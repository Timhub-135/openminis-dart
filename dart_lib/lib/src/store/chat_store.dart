import '../models/chat_message.dart';
import '../models/session.dart';
import 'persistence_adapter.dart';

/// High-level facade over the persistence layer, mirroring the role of the
/// original `ChatStore.swift`. Kept thin: all storage decisions live in the
/// [PersistenceAdapter] supplied by the host app.
class ChatStore {
  final PersistenceAdapter adapter;

  ChatStore(this.adapter);

  Future<void> init() => adapter.init();

  Future<Session> ensureSession([String? id]) async {
    if (id != null) {
      final existing = await adapter.sessionById(id);
      if (existing != null) return existing;
    }
    final s = Session();
    await adapter.upsertSession(s);
    return s;
  }

  Future<List<Session>> sessions() => adapter.allSessions();

  Future<List<ChatMessage>> messages(String sessionId, {int? limit}) =>
      adapter.messagesForSession(sessionId, limit: limit);

  Future<void> addMessage(ChatMessage m) async {
    final s = await adapter.sessionById(m.sessionId);
    if (s != null) {
      s.updatedAt = DateTime.now();
      s.dirty = true;
      s.revision++;
      await adapter.upsertSession(s);
    }
    await adapter.upsertMessage(m);
  }

  Future<void> deleteSession(String id) => adapter.markSessionDeleted(id);
}
