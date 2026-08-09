import 'dart:async';

import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

/// A scripted fake LLM: plays back a sequence of turns. Each turn returns a
/// list of events; the fake pauses between turns until the agent feeds tool
/// results back.
class ScriptedLlm implements LlmClient {
  /// Each element is one model turn: a list of tool requests to emit, and the
  /// final text. When tools is non-empty the fake emits ToolUseRequested for
  /// each then ends; the agent loop feeds results and calls again.
  final List<List<AgentStreamEvent>> script;
  int _call = 0;

  ScriptedLlm(this.script);

  @override
  Stream<AgentStreamEvent> complete(
    List<LlmMessage> messages, {
    required LlmRequestConfig config,
    List<Map<String, dynamic>> tools = const [],
    List<String>? stopSequences,
  }) async* {
    if (_call >= script.length) {
      yield const TextDelta('(end of script)');
      yield const TurnFinished('(end of script)', null);
      return;
    }
    final evs = script[_call++];
    final textBuf = StringBuffer();
    for (final e in evs) {
      if (e is TextDelta) textBuf.write(e.text);
      yield e;
    }
    yield TurnFinished(textBuf.toString(), null);
  }
}

void main() {
  group('AgentLoop', () {
    test('runs a tool-calling turn end to end and persists messages', () async {
      final store = MemoryStore();
      final chatStore = ChatStore(store);
      final session = Session();
      await store.upsertSession(session);

      final registry = ToolRegistry();
      registry.register(Tool(
        name: 'add',
        description: 'add two ints',
        params: const [
          ToolParam(name: 'a', description: 'left', required: true, type: 'integer'),
          ToolParam(name: 'b', description: 'right', required: true, type: 'integer'),
        ],
        handler: (args) async {
          final sum = (args['a'] as int) + (args['b'] as int);
          return ToolResult.ok('sum=$sum');
        },
      ));

      final llm = ScriptedLlm([
        // Turn 1: request the tool (no stray text).
        [
          const ToolUseRequested('t1', 'add', {'a': 2, 'b': 3}),
        ],
        // Turn 2: final answer referencing the tool result.
        [const TextDelta('2+3=5')],
      ]);

      final sentToolCalls = <String>[];
      final loop = AgentLoop(
        store: chatStore,
        tools: registry,
        client: llm,
        config: const LlmRequestConfig(provider: 'fake', model: 'test'),
        listener: _recordingListener(sentToolCalls),
      );

      final result = await loop.run(session.id, 'what is 2+3?');

      expect(result.completed, isTrue);
      expect(result.content, '2+3=5');
      expect(result.toolCallsMade, 1);
      expect(sentToolCalls, ['add']);

      // Two messages persisted: user prompt + assistant response.
      final msgs = await store.messagesForSession(session.id);
      expect(msgs, hasLength(2));
      expect(msgs[0].role, ChatRole.user);
      expect(msgs[1].role, ChatRole.assistant);
    });

    test('preflight rejects a tool call missing a required argument', () async {
      final registry = ToolRegistry();
      registry.register(Tool(
        name: 'div',
        description: 'divide',
        params: const [
          ToolParam(name: 'denominator', description: 'd', required: true, type: 'number'),
        ],
        handler: (args) async => ToolResult.ok('ok'),
      ));

      final preflight = ToolPreflight(registry);
      expect(preflight.validate('div', {}), contains('missing required'));
      expect(preflight.validate('div', {'denominator': 2}), isNull);
      expect(preflight.validate('nope', {}), contains('Unknown tool'));
    });

    test('request budget caps runaway tool loops', () {
      final budget = RequestBudget(maxToolRounds: 2, maxTotalToolCalls: 3);
      expect(budget.canContinue, isTrue);
      budget.recordToolRound();
      budget.recordToolRound();
      expect(budget.canContinue, isFalse); // runs exhausted
    });
  });

  group('CompactionPolicy', () {
    test('no compaction below threshold', () {
      final msgs = List.generate(20, (_) => ChatMessage(
          sessionId: 's', role: ChatRole.user, content: 'x'));
      final cut = const CompactionPolicy(
              thresholdMessages: 60, keepRecentMessages: 30)
          .compactCut(msgs);
      expect(cut, isNull);
    });

    test('cuts old messages above threshold', () {
      final msgs = List.generate(80, (_) => ChatMessage(
          sessionId: 's', role: ChatRole.user, content: 'x'));
      final cut = const CompactionPolicy(
              thresholdMessages: 60, keepRecentMessages: 30)
          .compactCut(msgs);
      expect(cut, 50);
    });

    test('divider carries a summary and sort-order anchors', () {
      final base = List.generate(5, (i) => ChatMessage(
          sessionId: 's', role: ChatRole.user, content: 'm$i'));
      base[0].sourceSortOrder = 0;
      base[4].sourceSortOrder = 4;
      final cand = CompactionCandidate(
          folded: base, sourceSortOrder: 0, lastSourceSortOrder: 4);
      final divider = cand.dividerFor('s', summary: 'summary text');
      expect(divider.role, ChatRole.compactDivider);
      expect(divider.content, 'summary text');
      expect(divider.isCompactedHistory, isTrue);
      expect(divider.sourceSortOrder, 0);
      expect(divider.lastSourceSortOrder, 4);
    });
  });
}

AgentTurnListener _recordingListener(List<String> calls) =>
    _RecordingListener(calls);

class _RecordingListener implements AgentTurnListener {
  final List<String> calls;
  _RecordingListener(this.calls);

  @override
  void onText(String delta) {}

  @override
  void onThinking(String delta) {}

  @override
  void onToolEnd(String blockId, bool ok, String output) {}

  @override
  void onToolStart(String blockId, String name, Map<String, dynamic> args) {
    calls.add(name);
  }

  @override
  void onUsage(LlmUsage usage) {}

  @override
  void onState({required bool awaitingModel}) {}
}
