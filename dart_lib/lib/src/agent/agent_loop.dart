import 'dart:async';

import '../models/assistant_block.dart';
import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/roles.dart';
import '../models/token_usage.dart';
import '../providers/llm_client.dart';
import '../providers/llm_message.dart';
import '../providers/llm_usage.dart';
import '../store/chat_store.dart';
import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import 'compaction.dart';
import 'request_budget.dart';
import 'tool_preflight.dart';

/// Outcome of a single agent turn run by [AgentLoop.run].
class AgentTurnResult {
  final bool completed;
  final String content;
  final TokenUsage usage;
  final int toolCallsMade;
  final List<String> errors;

  AgentTurnResult({
    required this.completed,
    this.content = '',
    TokenUsage? usage,
    this.toolCallsMade = 0,
    this.errors = const [],
  }) : usage = usage ?? TokenUsage();

  bool get hadError => errors.isNotEmpty;
}

/// Receives streaming progress so the UI can render deltas live.
abstract class AgentTurnListener {
  void onText(String delta);
  void onThinking(String delta);
  void onToolStart(String blockId, String name, Map<String, dynamic> args);
  void onToolEnd(String blockId, bool ok, String output);
  void onUsage(LlmUsage usage);
  void onState({required bool awaitingModel});
}

/// The agent loop. Ports the core of `AIChatViewModel`:
///   1. Take user request, build provider messages from stored history.
///   2. Stream the model response; collect text/thinking + tool calls.
///   3. Preflight + run tools, feed results back, continue until the model
///      stops asking for tools or the budget is exhausted.
///   4. Persist the resulting messages; mark the session dirty for sync.
class AgentLoop {
  final ChatStore store;
  final ToolRegistry tools;
  final LlmClient client;
  final LlmRequestConfig config;
  final RequestBudget budget;
  final CompactionPolicy compaction;

  /// Max simultaneous in-flight tool executions per turn (mirrors the original
  /// ConcurrentTools ceiling — beyond this the sandbox/shells start to contend).
  final int maxConcurrentTools;

  /// Max auto-retries for a mid-stream failure before giving up (Fallback).
  final int maxStreamRetries;

  AgentTurnListener? listener;

  AgentLoop({
    required this.store,
    required this.tools,
    required this.client,
    required this.config,
    RequestBudget? budget,
    CompactionPolicy? compaction,
    this.maxConcurrentTools = 4,
    this.maxStreamRetries = 2,
    this.listener,
  })  : budget = budget ?? RequestBudget(),
        compaction = compaction ?? const CompactionPolicy();

  /// Run one complete agent turn for [prompt] in [sessionId].
  Future<AgentTurnResult> run(
    String sessionId,
    String prompt, {
    List<AttachmentMeta> attachments = const [],
  }) async {
    // Load recent history (respecting a sensible window).
    final history = await store.messages(sessionId, limit: 40);
    final contextMessages = history
        .where((m) =>
            m.role == ChatRole.user || m.role == ChatRole.assistant)
        .toList();

    // Append the user's prompt as a message we will persist.
    final userMsg = ChatMessage(
      sessionId: sessionId,
      role: ChatRole.user,
      content: prompt,
    );
    userMsg.attachments = attachments;
    await store.addMessage(userMsg);

    // Build the provider request: history + tools metadata.
    final llmMessages = <LlmMessage>[];
    for (final m in contextMessages) {
      if (m.role == ChatRole.user) {
        llmMessages.add(LlmMessage.text('user', m.content));
      } else if (m.role == ChatRole.assistant) {
        llmMessages.add(LlmMessage.text('assistant', m.content));
      }
    }
    llmMessages.add(LlmMessage.text('user', prompt));

    final toolDefs = tools.all.map((t) => t.toProviderJson()).toList();

    // The assistant message accumulates blocks and is persisted at the end.
    final assistantMsg = ChatMessage(
      sessionId: sessionId,
      role: ChatRole.assistant,
      content: '',
    );
    final textBlock = AssistantBlock(
      id: 'b-${DateTime.now().microsecondsSinceEpoch}',
      kind: AssistantBlockKind.text,
      content: '',
    );
    assistantMsg.blocks.add(textBlock);

    final usageAgg = TokenUsage();
    var toolCallsMade = 0;
    final errors = <String>[];

    listener?.onState(awaitingModel: true);

    // Run model <-> tool turns until the model stops requesting tools.
    while (budget.canContinue) {
      final turn = _streamOneTurn(sessionId, llmMessages, toolDefs,
          assistantMsg, textBlock, usageAgg, errors);
      final requestedTools = await turn;
      toolCallsMade += requestedTools.length;

      if (requestedTools.isEmpty) {
        break; // Model gave a final textual answer.
      }
      if (!budget.canContinue) {
        errors.add('Tool limit reached; turn truncated.');
        break;
      }

      // Execute the requested tools. Independent calls run IN PARALLEL up to
      // [maxConcurrentTools] at a time (ConcurrentTools); order of tool results
      // is preserved so the model sees a deterministic transcript.
      final results = await _runTools(requestedTools, errors);
      for (final r in results) {
        budget.recordToolCall();
        llmMessages.add(LlmMessage(
          role: 'user',
          content: [LlmContentBlock.toolResult(id: r.call.id, text: r.output)],
        ));
      }
      budget.recordToolRound();
    }

    // Persist assistant response + update session; mark dirty for sync.
    assistantMsg.usage = usageAgg;
    assistantMsg.content = textBlock.content;
    if (errors.isNotEmpty) {
      assistantMsg.error = errors.first;
    }
    textBlock.flushThinkingBuffer();
    await store.addMessage(assistantMsg);

    listener?.onState(awaitingModel: false);

    return AgentTurnResult(
      completed: errors.isEmpty,
      content: assistantMsg.content,
      usage: usageAgg,
      toolCallsMade: toolCallsMade,
      errors: errors,
    );
  }

  /// Runs a batch of tool calls. Preflight-validates each; independent calls
  /// execute concurrently in chunks of [maxConcurrentTools], preserving order.
  Future<List<_ToolOutcome>> _runTools(
    List<_ToolCall> calls,
    List<String> errors,
  ) async {
    final results = <_ToolOutcome>[];
    final outcomes = List<_ToolOutcome?>.filled(calls.length, null);

    Future<void> runOne(int i) async {
      final call = calls[i];
      final preflight =
          ToolPreflight(tools).validate(call.name, call.input);
      if (preflight != null) {
        errors.add(preflight);
        outcomes[i] =
            _ToolOutcome(call, '工具参数错误: $preflight');
        return;
      }
      final tool = tools[call.name];
      if (tool == null) {
        errors.add('未知工具: ${call.name}');
        outcomes[i] = _ToolOutcome(call, '未知工具: ${call.name}');
        return;
      }
      listener?.onToolStart(call.id, call.name, call.input);
      ToolResult result;
      try {
        result = await tool.invoke(call.input);
      } catch (e) {
        result = ToolResult.fail('工具执行异常: $e');
      }
      listener?.onToolEnd(call.id, result.ok, result.output);
      outcomes[i] = _ToolOutcome(call, result.output);
    }

    // Run in concurrency-limited batches, preserving original order.
    for (var start = 0; start < calls.length; start += maxConcurrentTools) {
      final batch = <Future<void>>[];
      final end = (start + maxConcurrentTools) < calls.length
          ? start + maxConcurrentTools
          : calls.length;
      for (var i = start; i < end; i++) {
        batch.add(runOne(i));
      }
      await Future.wait(batch);
    }

    for (final o in outcomes) {
      if (o != null) results.add(o);
    }
    return results;
  }

  /// Stream one model response. Returns the list of tool requests, if any.
  ///
  /// Applies Fallback: if the transport fails mid-stream with a retryable error
  /// (e.g. a dropped SSE connection), it re-requests up to [maxStreamRetries]
  /// times so an interrupted turn can still complete.
  Future<List<_ToolCall>> _streamOneTurn(
    String sessionId,
    List<LlmMessage> llmMessages,
    List<Map<String, dynamic>> toolDefs,
    ChatMessage assistantMsg,
    AssistantBlock textBlock,
    TokenUsage usageAgg,
    List<String> errors,
  ) async {
    final calls = <_ToolCall>[];
    // Baseline text already present before this turn's stream (from prior turns
    // in the same assistant message). On retry we restore to this so the model's
    // regenerated stream doesn't duplicate.
    final baselineText = textBlock.content;
    int attempts = 0;

    while (true) {
      var hadRetryableError = false;
      var sawStreamError = false;
      var sawAnyContent = false;
      textBlock.content = baselineText;
      final stream = client.complete(
        llmMessages,
        config: config,
        tools: toolDefs,
      );

      await for (final ev in stream) {
        switch (ev) {
          case TextDelta():
            textBlock.appendText(ev.text);
            listener?.onText(ev.text);
            sawAnyContent = true;
          case ThinkingDelta():
            listener?.onThinking(ev.thinking);
            textBlock.appendThinkingDelta(ev.thinking);
          case ToolUseRequested():
            calls.add(_ToolCall(ev.id, ev.name, ev.input));
            textBlock.toolName = ev.name;
            textBlock.toolStatus = ToolBlockStatus.running;
          case UsageDelta():
            usageAgg.add(ev.usage.inputTokens, ev.usage.outputTokens,
                cacheRead: ev.usage.cacheReadInputTokens,
                cacheCreation: ev.usage.cacheCreationInputTokens);
            listener?.onUsage(ev.usage);
          case TurnFinished():
            textBlock.flushThinkingBuffer();
          case StreamError():
            sawStreamError = true;
            hadRetryableError = ev.retryable;
            errors.add(ev.error.toString());
        }
      }

      if (!sawStreamError) break; // clean completion
      if (!hadRetryableError || attempts >= maxStreamRetries) break; // give up
      if (!sawAnyContent) {
        // Nothing useful arrived; retry the request directly.
        attempts++;
        continue;
      }
      attempts++;
    }
    return calls;
  }
}

class _ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  _ToolCall(this.id, this.name, this.input);
}

class _ToolOutcome {
  final _ToolCall call;
  final String output;
  _ToolOutcome(this.call, this.output);
}
