import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/assistant_block.dart';
import '../models/chat_message.dart';
import '../models/roles.dart';
import '../models/session.dart';

/// Abstract persistence for the core. Kept platform-agnostic so the same
/// engine runs on Windows and Android back-ends: a hosting app supplies
/// a [PersistenceAdapter] backed by whatever it prefers (SQLite, Hive, shared
/// files). This package ships a portable [JsonFileStore] that writes JSON to
/// a directory on disk, plus an in-memory store for tests.
abstract class PersistenceAdapter {
  Future<void> init();

  // Sessions
  Future<List<Session>> allSessions({bool includeDeleted = false});
  Future<Session?> sessionById(String id);
  Future<void> upsertSession(Session s);
  Future<void> markSessionDeleted(String id);

  // Messages
  Future<List<ChatMessage>> messagesForSession(
    String sessionId, {
    int? limit,
    int? afterSortOrder,
  });
  Future<ChatMessage?> messageById(String id);
  Future<void> upsertMessage(ChatMessage m);
  Future<void> deleteSessionMessages(String sessionId);
}

/// Portable JSON-file store. Persists sessions and messages as one JSON file
/// under [baseDir] (e.g. `.../openminis/data/`). Works unchanged on Windows
/// (`AppData`) and Android (app files dir) because it only needs an
/// [Directory], which both Flutter and pure Dart provide.
class JsonFileStore implements PersistenceAdapter {
  final Directory baseDir;
  File get _storeFile => File('${baseDir.path}/store.json');

  final Map<String, Session> _sessions = {};
  final Map<String, ChatMessage> _messagesById = {};
  final Map<String, List<String>> _bySession = {};
  bool _dirty = true;

  JsonFileStore(this.baseDir);

  @override
  Future<void> init() async {
    if (!baseDir.existsSync()) baseDir.createSync(recursive: true);
    if (_storeFile.existsSync()) {
      try {
        final obj =
            jsonDecode(_storeFile.readAsStringSync()) as Map<String, dynamic>;
        final sessions = obj['sessions'] as List? ?? [];
        final messages = obj['messages'] as List? ?? [];
        for (final s in sessions) {
          final sd = (s as Map).cast<String, dynamic>();
          final sess = Session(
            id: sd['id'] as String,
            title: sd['title'] as String? ?? '',
            createdAt: DateTime.tryParse(sd['createdAt'] as String? ?? '') ??
                DateTime.now(),
            updatedAt: DateTime.tryParse(sd['updatedAt'] as String? ?? '') ??
                DateTime.now(),
            lastModelProvider: sd['lastModelProvider'] as String?,
            payload: sd['payload'] as String?,
          );
          sess.deleted = sd['deleted'] as bool? ?? false;
          sess.revision = sd['revision'] as int? ?? 0;
          _sessions[sess.id] = sess;
        }
        for (final m in messages) {
          final md = (m as Map).cast<String, dynamic>();
          final msg = _messageFromJson(md);
          _messagesById[msg.id] = msg;
          (_bySession[msg.sessionId] ??= []).add(msg.id);
        }
      } catch (_) {
        // Start fresh if the file is corrupt.
      }
    }
    _dirty = false;
  }

  void _persist() {
    if (!_dirty) return;
    try {
      final sessions = _sessions.values
          .map((s) => {
                'id': s.id,
                'title': s.title,
                'createdAt': s.createdAt.toIso8601String(),
                'updatedAt': s.updatedAt.toIso8601String(),
                'lastModelProvider': s.lastModelProvider,
                'payload': s.payload,
                'deleted': s.deleted,
                'revision': s.revision,
              })
          .toList();
      final messages = _messagesById.values
          .map((m) => {
                'id': m.id,
                'sessionId': m.sessionId,
                'role': m.role.name,
                'content': m.content,
                'timestamp': m.timestamp.toIso8601String(),
                'blocks': m.blocks.map((b) => b.toJson()).toList(),
                'error': m.error,
                'sourceSortOrder': m.sourceSortOrder,
                'lastSourceSortOrder': m.lastSourceSortOrder,
              })
          .toList();
      _storeFile.parent.createSync(recursive: true);
      _storeFile.writeAsStringSync(
        jsonEncode({'sessions': sessions, 'messages': messages}),
        flush: true,
      );
    } catch (_) {
      // Ignore write errors in the portable store; subclasses may override.
    }
  }

  @override
  Future<void> upsertSession(Session s) async {
    _sessions[s.id] = s;
    _dirty = true;
    _persist();
  }

  @override
  Future<Session?> sessionById(String id) async =>
      _sessions[id]?.copy();

  @override
  Future<List<Session>> allSessions({bool includeDeleted = false}) async =>
      _sessions.values
          .where((s) => includeDeleted || !s.deleted)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> markSessionDeleted(String id) async {
    final s = _sessions[id];
    if (s != null) {
      s.deleted = true;
      _dirty = true;
      _persist();
    }
  }

  @override
  Future<void> upsertMessage(ChatMessage m) async {
    _messagesById[m.id] = m;
    (_bySession[m.sessionId] ??= []);
    if (!_bySession[m.sessionId]!.contains(m.id)) {
      _bySession[m.sessionId]!.add(m.id);
    }
    _dirty = true;
    _persist();
  }

  @override
  Future<ChatMessage?> messageById(String id) async => _messagesById[id];

  @override
  Future<List<ChatMessage>> messagesForSession(
    String sessionId, {
    int? limit,
    int? afterSortOrder,
  }) async {
    final ids = _bySession[sessionId] ?? const <String>[];
    final msgs = ids.map((i) => _messagesById[i]!).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (limit != null && msgs.length > limit) {
      return msgs.sublist(msgs.length - limit);
    }
    return msgs;
  }

  @override
  Future<void> deleteSessionMessages(String sessionId) async {
    for (final id in _bySession[sessionId] ?? const <String>[]) {
      _messagesById.remove(id);
    }
    _bySession.remove(sessionId);
    _dirty = true;
    _persist();
  }

  ChatMessage _messageFromJson(Map<String, dynamic> j) {
    final msg = ChatMessage(
      id: j['id'] as String?,
      sessionId: j['sessionId'] as String,
      role: ChatRole.fromWire(j['role'] as String?),
      content: j['content'] as String? ?? '',
      timestamp:
          DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
    msg.error = j['error'] as String?;
    msg.sourceSortOrder = j['sourceSortOrder'] as int?;
    msg.lastSourceSortOrder = j['lastSourceSortOrder'] as int?;
    final blks = (j['blocks'] as List? ?? []);
    for (final b in blks) {
      msg.blocks.add(AssistantBlock.fromJson((b as Map).cast<String, dynamic>()));
    }
    return msg;
  }
}

/// In-memory store used by unit tests.
class MemoryStore implements PersistenceAdapter {
  final Map<String, Session> sessions = {};
  final Map<String, ChatMessage> messages = {};
  final Map<String, List<String>> order = {};

  @override
  Future<void> init() async {}

  @override
  Future<List<Session>> allSessions({bool includeDeleted = false}) async =>
      sessions.values
          .where((s) => includeDeleted || !s.deleted)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<Session?> sessionById(String id) async => sessions[id];

  @override
  Future<void> upsertSession(Session s) async => sessions[s.id] = s;

  @override
  Future<void> markSessionDeleted(String id) async {
    final s = sessions[id];
    if (s != null) s.deleted = true;
  }

  @override
  Future<void> upsertMessage(ChatMessage m) async {
    messages[m.id] = m;
    (order[m.sessionId] ??= []);
    if (!order[m.sessionId]!.contains(m.id)) order[m.sessionId]!.add(m.id);
  }

  @override
  Future<ChatMessage?> messageById(String id) async => messages[id];

  @override
  Future<List<ChatMessage>> messagesForSession(
    String sessionId, {
    int? limit,
    int? afterSortOrder,
  }) async {
    final msgs = (order[sessionId] ?? [])
        .map((i) => messages[i]!)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (limit != null && msgs.length > limit) {
      return msgs.sublist(msgs.length - limit);
    }
    return msgs;
  }

  @override
  Future<void> deleteSessionMessages(String sessionId) async {
    for (final id in order[sessionId] ?? const <String>[]) {
      messages.remove(id);
    }
    order.remove(sessionId);
  }
}
