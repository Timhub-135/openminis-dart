import 'attachment.dart';
import 'assistant_block.dart';
import 'roles.dart';
import 'token_usage.dart';

/// A single message in a session.
///
/// Ports `ChatMessage` / `RawMessage` semantics from `ChatModels.swift`. This
/// Dart version is immutable-ish and observable through a simple change
/// counter rather than Combine/SwiftUI `@Published`, keeping the core free of
/// any UI framework so the same object travels to Windows and Android.
class ChatMessage {
  final String id;
  final String sessionId;
  final ChatRole role;
  String content;

  /// Ordered content blocks for assistant turns (text + thinking + tool calls).
  final List<AssistantBlock> blocks = [];

  /// Error that terminated this assistant turn (null = no error).
  String? error;

  /// Number of mid-stream auto-retries that completed before this turn.
  int streamInterruptCount = 0;

  /// Accumulated token usage for this assistant turn.
  TokenUsage? usage;

  /// Structured metadata for user-attached files.
  List<AttachmentMeta> attachments = [];

  /// True when all tool calls completed and we await the model's next response.
  bool isAwaitingModelResponse = false;

  /// True when queued but not yet injected into the agent loop.
  bool isQueued = false;

  /// True when from the compacted-history zone (read-only).
  bool isCompactedHistory = false;

  /// sort_order of the FIRST raw message folded into this UI message.
  int? sourceSortOrder;

  /// sort_order of the LAST raw message folded into this UI message.
  int? lastSourceSortOrder;

  final DateTime timestamp;

  /// Monotonic change counter for the UI layer to subscribe to cheaply.
  int changeSeq = 0;

  ChatMessage({
    String? id,
    required this.sessionId,
    required this.role,
    this.content = '',
    DateTime? timestamp,
  })  : id = id ?? _genId(),
        timestamp = timestamp ?? DateTime.now();

  static String _genId() => 'm-${DateTime.now().microsecondsSinceEpoch}';

  bool get isInternalBridge {
    if (role != ChatRole.assistant) return false;
    if (bodyIsBridgeText(content)) return true;
    if (content.isEmpty &&
        blocks.length == 1 &&
        blocks[0].kind == AssistantBlockKind.text &&
        bodyIsBridgeText(blocks[0].content)) {
      return true;
    }
    return false;
  }

  /// Shared set of internal role-alternation bridge texts that must never
  /// render as a chat bubble (leak guard, ported from `#579`).
  static bool bodyIsBridgeText(String s) {
    const bridges = {'', 'assistant', '[assistant]', 'role-alternation'};
    return bridges.contains(s.trim().toLowerCase()) ||
        s.trim().isEmpty;
  }

  void bump() => changeSeq++;
}
