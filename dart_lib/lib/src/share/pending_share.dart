import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/roles.dart';
import '../models/session.dart';
import '../store/chat_store.dart';

/// A single item shared into OpenMinis (text, URL, an image/file path).
///
/// Mirrors the original `ShareExtension/PendingShare.Item`:
/// kind is either `text` (inline text/URL) or `file` (a copied attachment).
class SharedItem {
  final String kind; // 'text' | 'file'
  final String value; // text content, or the file path for file kinds
  final String? fileName;

  const SharedItem({required this.kind, required this.value, this.fileName});

  bool get isText => kind == 'text';
  bool get isFile => kind == 'file';

  /// The message text a user sees / agent gets.
  String get displayText => isText ? value : '[附件] ${fileName ?? value}';

  Map<String, dynamic> toJson() =>
      {'kind': kind, 'value': value, if (fileName != null) 'fileName': fileName};

  factory SharedItem.fromJson(Map<String, dynamic> j) => SharedItem(
        kind: j['kind'] as String? ?? 'text',
        value: j['value'] as String? ?? '',
        fileName: j['fileName'] as String?,
      );
}

/// A share that arrived into the app, waiting for the user to route it into a
/// conversation. Mirrors the original `PendingShare` (content cached, consumed
/// later by a screen that lets you pick or create a session).
class PendingShare {
  final String id;
  final List<SharedItem> items;
  final DateTime timestamp;

  PendingShare({String? id, required this.items, DateTime? timestamp})
      : id = id ?? 'sh-${DateTime.now().microsecondsSinceEpoch}',
        timestamp = timestamp ?? DateTime.now();

  String get preview {
    if (items.isEmpty) return '';
    final first = items.first.displayText;
    return first.length > 80 ? '${first.substring(0, 80)}…' : first;
  }

  String get fullText => items.map((i) => i.displayText).join('\n');

  Map<String, dynamic> toJson() => {
        'id': id,
        'items': items.map((i) => i.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
      };

  factory PendingShare.fromJson(Map<String, dynamic> j) => PendingShare(
        id: j['id'] as String?,
        items: (j['items'] as List? ?? [])
            .map((m) => SharedItem.fromJson((m as Map).cast<String, dynamic>()))
            .toList(),
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Builds a [PendingShare] from raw shared payloads (text, url, filePath...).
class ShareInbox {
  /// Create a pending share from common Android `ACTION_SEND` extras.
  static PendingShare fromShareExtras({
    String? sharedText,
    String? sharedSubject,
    String? sharedUrl,
    List<String>? sharedFilePaths,
  }) {
    final items = <SharedItem>[];
    if (sharedText != null && sharedText.isNotEmpty) {
      items.add(SharedItem(kind: 'text', value: sharedText));
    }
    if (sharedUrl != null && sharedUrl.isNotEmpty) {
      items.add(SharedItem(kind: 'text', value: sharedUrl));
    }
    for (final p in sharedFilePaths ?? const <String>[]) {
      if (p.isNotEmpty) {
        items.add(SharedItem(
          kind: 'file',
          value: p,
          fileName: p.split('/').last,
        ));
      }
    }
    return PendingShare(items: items);
  }

  /// Route a pending share into a conversation: send its text as a user message
  /// in [sessionId]. Creates the session if [sessionId] is null.
  ///
  /// Returns the session the share was routed into. Requires a pre-configured
  /// LLM (a real client) to actually run the agent; without one, the message is
  /// still persisted and the session returned.
  static Future<Session> routeIntoSession(
    ChatStore store, {
    required PendingShare share,
    required String? sessionId,
  }) async {
    final session = await store.ensureSession(sessionId);
    final text = share.fullText;
    final attachments = share.items
        .where((i) => i.isFile)
        .map((i) => AttachmentMeta(
              path: i.value,
              size: 0,
              modified: DateTime.now(),
            ))
        .toList();
    final msg = ChatMessage(
      sessionId: session.id,
      role: ChatRole.user,
      content: text,
    );
    msg.attachments = attachments;
    await store.addMessage(msg);
    return session;
  }
}
