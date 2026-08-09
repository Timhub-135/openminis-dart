import '../models/chat_message.dart';
import '../models/roles.dart';
import '../models/assistant_block.dart';
import 'message_id.dart';

/// A serialized unit of conversation to transfer between devices.
///
/// Encodes the message model plus the sync bookkeeping (causal id / revision)
/// so each device can merge deterministically. Sent inside a `SyncBatch`.
class SyncMessage {
  /// Opaque device-unique id (the message's own id).
  final String id;

  /// Session this message belongs to.
  final String sessionId;

  /// The message's causal/lamport id, used for conflict ordering.
  final CausalId causal;

  final String role;
  final String content;
  final int timestampMs;
  final String? error;

  /// Serialized content blocks (text/thinking/tool).
  final List<Map<String, dynamic>> blocks;

  /// True if this is a tombstone (deletion) of a message.
  final bool deleted;

  const SyncMessage({
    required this.id,
    required this.sessionId,
    required this.causal,
    required this.role,
    required this.content,
    required this.timestampMs,
    this.error,
    this.blocks = const [],
    this.deleted = false,
  });

  /// Wrap a local [ChatMessage].
  factory SyncMessage.fromChatMessage(String deviceId, ChatMessage m) {
    final causal = CausalId(
      deviceId: deviceId,
      seq: m.timestamp.microsecondsSinceEpoch,
    );
    return SyncMessage(
      id: m.id,
      sessionId: m.sessionId,
      causal: causal,
      role: m.role.name,
      content: m.content,
      timestampMs: m.timestamp.millisecondsSinceEpoch,
      error: m.error,
      blocks: m.blocks.map((b) => b.toJson()).toList(),
    );
  }

  bool get isTombstone => deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'causal': causal.toJson(),
        'role': role,
        'content': content,
        'timestampMs': timestampMs,
        'error': error,
        'blocks': blocks,
        'deleted': deleted,
      };

  factory SyncMessage.fromJson(Map<String, dynamic> j) => SyncMessage(
        id: j['id'] as String,
        sessionId: j['sessionId'] as String,
        causal: CausalId.fromJson(
            (j['causal'] as Map?)?.cast<String, dynamic>() ?? {}),
        role: j['role'] as String? ?? 'user',
        content: j['content'] as String? ?? '',
        timestampMs: j['timestampMs'] as int? ?? 0,
        error: j['error'] as String?,
        blocks: (j['blocks'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        deleted: j['deleted'] as bool? ?? false,
      );

  ChatMessage toChatMessage() {
    final msg = ChatMessage(
      id: id,
      sessionId: sessionId,
      role: ChatRole.fromWire(role),
      content: content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    msg.error = error;
    for (final b in blocks) {
      msg.blocks
          .add(AssistantBlock.fromJson(b));
    }
    return msg;
  }
}
