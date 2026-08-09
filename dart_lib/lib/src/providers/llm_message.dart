import 'llm_usage.dart';

/// One turn in a conversation sent to a provider. Content is a list of blocks
/// (text or tool_use / tool_result), matching the Anthropic-style tool protocol
/// the original normalises all providers onto.
class LlmMessage {
  final String role; // user | assistant
  final List<LlmContentBlock> content;
  final Map<String, dynamic>? metadata;

  const LlmMessage({required this.role, this.content = const [], this.metadata});

  static LlmMessage text(String role, String text, {Map<String, dynamic>? metadata}) =>
      LlmMessage(role: role, content: [LlmContentBlock.text(text)], metadata: metadata);
}

class LlmContentBlock {
  final String type; // text | thinking | tool_use | tool_result
  final String? text;
  final String? id;
  final String? toolName;
  final dynamic input; // JSON-serialisable for tool_use / tool_result
  const LlmContentBlock.text(this.text)
      : type = 'text',
        id = null,
        toolName = null,
        input = null;
  const LlmContentBlock.toolUse({required this.id, required this.toolName, this.input})
      : type = 'tool_use',
        text = null;
  const LlmContentBlock.toolResult({required this.id, this.input, this.text = ''})
      : type = 'tool_result',
        toolName = null;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (text != null) 'text': text,
        if (id != null) 'id': id,
        if (toolName != null) 'name': toolName,
        if (input != null) 'input': input,
      };
}

/// A streamed event during an SSE agent turn.
sealed class AgentStreamEvent {
  const AgentStreamEvent();
}

/// A text delta for the assistant message body.
class TextDelta extends AgentStreamEvent {
  final String text;
  const TextDelta(this.text);
}

/// A thinking delta.
class ThinkingDelta extends AgentStreamEvent {
  final String thinking;
  const ThinkingDelta(this.thinking);
}

/// The model requested a tool call.
class ToolUseRequested extends AgentStreamEvent {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  const ToolUseRequested(this.id, this.name, this.input);
}

/// Streaming usage snapshot (may be cumulative; the agent folds via max()).
class UsageDelta extends AgentStreamEvent {
  final LlmUsage usage;
  const UsageDelta(this.usage);
}

/// The assistant message / turn finished; contains final content and usage.
class TurnFinished extends AgentStreamEvent {
  final String content;
  final LlmUsage? usage;
  const TurnFinished(this.content, this.usage);
}

/// A transport or provider-level error.
class StreamError extends AgentStreamEvent {
  final Object error;
  final bool retryable;
  const StreamError(this.error, {this.retryable = false});
}
