/// A conversation session.
///
/// Ports the session concept from `src/ios/Agent/Session/` and
/// `ChatStore.swift`. A session groups messages, owns a generated title, and
/// carries a sync state so conversations can be reconciled across Windows and
/// Android devices (see `sync/`).
class Session {
  final String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;
  String? lastModelProvider;

  /// Optional v1 opaque payload kept for parity with the original (e.g. LLM
  /// prompt settings, fork lineage). Serialized as JSON text.
  String? payload;

  /// Sync-aware dirty flag: when true, this session has local changes not yet
  /// pushed to peer devices (Windows <-> Android).
  bool dirty = false;

  /// Tombstoned (deleted); kept so deletions propagate through sync.
  bool deleted = false;

  /// Highest known revision counter used by the sync engine (see SyncManifest).
  int revision = 0;

  Session({
    String? id,
    this.title = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastModelProvider,
    this.payload,
  })  : id = id ?? _genId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static String _genId() => 's-${DateTime.now().microsecondsSinceEpoch}';

  Session copy() => Session(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastModelProvider: lastModelProvider,
        payload: payload,
      );

  @override
  bool operator ==(Object other) =>
      other is Session && other.id == id && other.updatedAt == updatedAt;

  @override
  int get hashCode => id.hashCode;
}
