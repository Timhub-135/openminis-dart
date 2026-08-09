import 'dart:async';
import 'dart:collection';

import '../models/session.dart';
import '../store/chat_store.dart';
import '../store/persistence_adapter.dart';
import 'message_id.dart';
import 'sync_config.dart';
import 'sync_manifest.dart';
import 'sync_message.dart';
import 'sync_peer.dart';

/// Result of applying a batch of remote changes.
class SyncOutcome {
  final int sessionsApplied;
  final int messagesApplied;
  final int messagesConflictResolved;
  final bool upToDate;

  const SyncOutcome({
    this.sessionsApplied = 0,
    this.messagesApplied = 0,
    this.messagesConflictResolved = 0,
    required this.upToDate,
  });
}

/// A change event emitted by the engine so the UI can refresh.
sealed class SyncEvent {
  const SyncEvent();
}

class SyncStarted extends SyncEvent {
  final String deviceId;
  const SyncStarted(this.deviceId);
}

class SyncCompleted extends SyncEvent {
  final SyncOutcome outcome;
  const SyncCompleted(this.outcome);
}

class SyncPeersChanged extends SyncEvent {
  final int peerCount;
  const SyncPeersChanged(this.peerCount);
}

class SyncError extends SyncEvent {
  final Object error;
  const SyncError(this.error);
}

/// Cross-platform conversation / history / output sync engine.
///
/// This is the feature OpenMinis' iCloud-centric sync didn't offer for
/// Windows+Android. It reconciles two replicas (a Windows host and an Android
/// device) using:
///
///   • **Revision high-water marks** per session to compute a minimal delta.
///   • **CausalId ordering** for deterministic conflict resolution when two
///     devices edited the same message (last-write-wins by causal order).
///   • **Tombstones** so deletions propagate (not just new content).
///
/// The engine is transport-agnostic: the host app injects a [SyncTransport]
/// (LAN peer or self-hosted relay). This class is fully unit-testable.
class SyncEngine {
  final SyncConfig config;
  final SyncTransport transport;
  final ChatStore store;
  final PersistenceAdapter adapter;

  final String deviceId;
  final _updates = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get updates => _updates.stream;

  final List<SyncEvent> _lastEvents = [];
  List<SyncEvent> get lastEvents => List.unmodifiable(_lastEvents);

  SyncEngine({
    required this.config,
    required this.transport,
    required this.store,
    required this.adapter,
    required this.deviceId,
  });

  Future<void> init() async {
    await transport.start();
    _updates.add(SyncStarted(deviceId));
    _watchIncoming();
  }

  void _watchIncoming() {
    transport.onIncoming.listen((batch) async {
      if (batch.senderDeviceId == deviceId) return; // self echo
      final outcome = await applyBatch(batch);
      _updates.add(SyncCompleted(outcome));
    });
  }

  /// One full reconciliation pass: pull peer's manifest, compute deltas, apply.
  Future<SyncOutcome> reconcile() async {
    try {
      final remoteManifest = await transport.fetchManifest();

      // Build our local manifest.
      final localSessions =
          await adapter.allSessions(includeDeleted: true);
      final localManifest =
          SyncManifest.fromSessions(deviceId, localSessions);

      // Compute sessions this device is missing/behind on.
      final needed = remoteManifest.sessionsNewerThan(localManifest);

      SyncBatch remoteBatch;
      if (needed.isNotEmpty) {
        final highwater = <String, int>{};
        for (final id in needed) {
          highwater[id] = localManifest.clock[id] ?? 0;
        }
        remoteBatch =
            await transport.pull(highwater, cursor: localManifest.deviceId);
      } else {
        remoteBatch = SyncBatch(
          senderDeviceId: remoteManifest.deviceId,
          manifest: remoteManifest,
        );
      }

      var outcome = await applyBatch(remoteBatch);

      // Push back anything we have that the peer is missing.
      final weKnow = localManifest.sessionsUnknownTo(remoteManifest);
      if (weKnow.isNotEmpty) {
        final sessions = <String, Map<String, dynamic>>{};
        final messages = <SyncMessage>[];
        for (final id in weKnow) {
          final s = localSessions.firstWhere((x) => x.id == id);
          sessions[id] = _sessionToJson(s);
          final msgs =
              await adapter.messagesForSession(id);
          messages.addAll(msgs.map((m) => SyncMessage.fromChatMessage(deviceId, m)));
        }
        final pushBatch = SyncBatch(
          senderDeviceId: deviceId,
          manifest: localManifest,
          sessions: sessions,
          messages: messages,
        );
        await transport.push(pushBatch);
      }

      _updates.add(SyncCompleted(outcome));
      return outcome;
    } catch (e) {
      _updates.add(SyncError(e));
      rethrow;
    }
  }

  /// Apply a remote batch to local state, resolving conflicts deterministically.
  Future<SyncOutcome> applyBatch(SyncBatch batch) async {
    var sessionsApplied = 0;
    var messagesApplied = 0;
    var conflicts = 0;

    // Apply session snapshots first (create missing / update metadata).
    for (final entry in batch.sessions.entries) {
      final remoteSession = _sessionFromJson(entry.value);
      final local = await adapter.sessionById(remoteSession.id);
      if (local == null ||
          remoteSession.revision > (local.revision)) {
        await adapter.upsertSession(remoteSession);
        sessionsApplied++;
      } else if (remoteSession.revision == local.revision &&
          local.updatedAt.isBefore(remoteSession.updatedAt)) {
        // Last-write-wins on equal revision via updatedAt.
        await adapter.upsertSession(remoteSession);
        sessionsApplied++;
      }
    }

    // Apply tombstoned sessions (deletions).
    for (final entry in batch.manifest.tombstones.entries) {
      final local = await adapter.sessionById(entry.key);
      if (local != null && local.revision < entry.value) {
        await adapter.markSessionDeleted(entry.key);
      }
    }

    // Apply messages with causal-order last-write-wins.
    final pending = SplayTreeMap<CausalId, SyncMessage>();
    for (final m in batch.messages) {
      pending[m.causal] = m;
    }
    for (final m in pending.values) {
      final localMsg = await adapter.messageById(m.id);
      if (localMsg == null) {
        await adapter.upsertMessage(m.toChatMessage());
        messagesApplied++;
      } else {
        // Conflict: same message id on both replicas. Deterministic resolution:
        // higher causal id wins. Count as resolved.
        final localCausal = CausalId(
          deviceId: deviceId,
          seq: localMsg.timestamp.microsecondsSinceEpoch,
        );
        if (m.causal.isBefore(localCausal)) {
          // Remote is older; keep local.
          conflicts++;
        } else if (localCausal.isBefore(m.causal)) {
          await adapter.upsertMessage(m.toChatMessage());
          messagesApplied++;
          conflicts++;
        } else {
          // identical — keep.
        }
      }
    }

    // Bump session updatedAt where messages arrived so the UI order updates.
    for (final m in batch.messages) {
      final local = await adapter.sessionById(m.sessionId);
      if (local != null && !local.deleted) {
        local.dirty = false;
        local.revision = _max(local.revision, batch.manifest.clock[m.sessionId] ?? 0);
        await adapter.upsertSession(local);
      }
    }

    return SyncOutcome(
      sessionsApplied: sessionsApplied,
      messagesApplied: messagesApplied,
      messagesConflictResolved: conflicts,
      upToDate: batch.messages.isEmpty && batch.sessions.isEmpty,
    );
  }

  int _max(int a, int b) => a > b ? a : b;

  Map<String, dynamic> _sessionToJson(Session s) => {
        'id': s.id,
        'title': s.title,
        'createdAt': s.createdAt.toIso8601String(),
        'updatedAt': s.updatedAt.toIso8601String(),
        'lastModelProvider': s.lastModelProvider,
        'payload': s.payload,
        'deleted': s.deleted,
        'revision': s.revision,
      };

  Session _sessionFromJson(Map<String, dynamic> j) {
    final s = Session(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      lastModelProvider: j['lastModelProvider'] as String?,
      payload: j['payload'] as String?,
    );
    s.deleted = j['deleted'] as bool? ?? false;
    s.revision = j['revision'] as int? ?? 0;
    return s;
  }

  Future<void> dispose() async {
    await transport.stop();
    await _updates.close();
  }
}
