import 'minis_url.dart';

/// Structured metadata for a user-attached file (image, document, etc.).
///
/// Mirrors `AttachmentMeta` in `ChatModels.swift`.

class AttachmentMeta {
  /// Linux path, e.g. `/var/minis/attachments/uploads/photo.jpg`.
  final String path;
  final int size;
  final DateTime modified;

  const AttachmentMeta({
    required this.path,
    required this.size,
    required this.modified,
  });

  String get minisUrl => MinisUrl.fromLinuxPath(path);

  String get fileName {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  String get _ext => fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';

  bool get isImage =>
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(_ext);

  bool get isVideo =>
      const {'mp4', 'mov', 'm4v', 'avi', 'mkv'}.contains(_ext);

  Map<String, dynamic> toJson() =>
      {'path': path, 'size': size, 'modified': modified.toIso8601String()};

  factory AttachmentMeta.fromJson(Map<String, dynamic> j) => AttachmentMeta(
        path: j['path'] as String,
        size: j['size'] as int? ?? 0,
        modified:
            DateTime.tryParse(j['modified'] as String? ?? '') ?? DateTime.now(),
      );
}

/// A queued prompt waiting to enter the agent loop.
class QueuedPrompt {
  final String id;
  final String text;
  final List<AttachmentMeta> attachments;
  final DateTime timestamp;

  QueuedPrompt({
    String? id,
    required this.text,
    this.attachments = const [],
    DateTime? timestamp,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();
}
