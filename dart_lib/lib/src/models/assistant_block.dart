import 'dart:async';

/// Kinds of a content block within an assistant turn.
///
/// Mirrors the block surface in `src/ios/Agent/Chat/ChatModels.swift`:
/// text, thinking and tool calls.
enum AssistantBlockKind { text, thinking, toolCall }

/// Execution status of a tool block.
enum ToolBlockStatus { streaming, running, success, failed, cancelled }

/// A single block within an assistant turn.
///
/// The Dart port keeps the *adaptive flush throttle* from the original
/// `[T-thinking-stream-jank]` work: during SSE streaming, thinking deltas
/// append to a non-published buffer and the visible [content] is flushed on a
/// widening interval (0.3s → 0.6s → 1.0s as the buffer grows) so collapsed
/// thinking blocks don't repaint the Flutter tree per token.
class AssistantBlock {
  final String id;

  AssistantBlockKind get kind => _kind;
  AssistantBlockKind _kind;

  /// Visible content. For thinking blocks this is only updated on flush.
  String content;

  ToolBlockStatus? toolStatus;
  String? toolName;
  final Map<String, dynamic> toolArguments;

  /// O(1) change counter incremented on every thinking delta (diagnostics).
  int contentUpdateSeq = 0;

  final _flushController = StreamController<void>.broadcast();
  Stream<void> get onFlush => _flushController.stream;

  // Non-published buffer for streaming thinking content.
  String _thinkingBuffer = '';
  Timer? _pendingFlush;

  AssistantBlock({
    required this.id,
    required AssistantBlockKind kind,
    this.content = '',
    this.toolStatus,
    this.toolName,
    Map<String, dynamic>? toolArguments,
  })  : _kind = kind,
        toolArguments = toolArguments ?? const {};

  // ---- adaptive flush throttle (ported from [T-thinking-stream-jank]) ----

  /// Tiers: (max buffer length chars, flush interval seconds).
  static const List<(int, double)> thinkingFlushTiers = [
    (1000, 0.3),
    (3000, 0.6),
    (1 << 62, 1.0), // effectively infinite (JS-safe)
  ];

  /// Flush interval for a thinking buffer of [length] chars.
  static double thinkingFlushInterval(int length) {
    for (final tier in thinkingFlushTiers) {
      if (length < tier.$1) return tier.$2;
    }
    return thinkingFlushTiers.last.$2;
  }

  /// Append a thinking delta; buffers it and schedules an adaptive flush.
  void appendThinkingDelta(String delta) {
    _kind = AssistantBlockKind.thinking;
    _thinkingBuffer += delta;
    contentUpdateSeq++;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_pendingFlush != null) return;
    _pendingFlush = Timer(
      Duration(
        milliseconds: (thinkingFlushInterval(_thinkingBuffer.length) * 1000)
            .round(),
      ),
      flushThinkingBuffer,
    );
  }

  /// Flush the buffered thinking content into [content] and notify [onFlush].
  void flushThinkingBuffer() {
    _pendingFlush?.cancel();
    _pendingFlush = null;
    if (_thinkingBuffer.length > content.length) {
      content = _thinkingBuffer;
      if (!_flushController.isClosed) {
        _flushController.add(null);
      }
    }
  }

  /// Append streaming text content directly (text blocks).
  void appendText(String delta) {
    _kind = AssistantBlockKind.text;
    content += delta;
    if (!_flushController.isClosed) {
      _flushController.add(null);
    }
  }

  void dispose() {
    _pendingFlush?.cancel();
    _flushController.close();
  }

  bool get isThinking => _kind == AssistantBlockKind.thinking;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'content': content,
        'toolStatus': toolStatus?.name,
        'toolName': toolName,
        'toolArguments': toolArguments,
      };

  factory AssistantBlock.fromJson(Map<String, dynamic> j) => AssistantBlock(
        id: j['id'] as String? ?? _genId(),
        kind: AssistantBlockKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => AssistantBlockKind.text,
        ),
        content: j['content'] as String? ?? '',
        toolStatus: j['toolStatus'] == null
            ? null
            : ToolBlockStatus.values.firstWhere(
                (s) => s.name == j['toolStatus'],
                orElse: () => ToolBlockStatus.success),
        toolName: j['toolName'] as String?,
        toolArguments:
            (j['toolArguments'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  static String _genId() => 'blk-${DateTime.now().microsecondsSinceEpoch}';
}
