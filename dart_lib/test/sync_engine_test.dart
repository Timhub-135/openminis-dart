import 'dart:async';

import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

/// A paired in-memory transport that lets two engines exchange batches,
/// mimicking a LAN or relayed sync without real sockets.
class _LoopbackTransport implements SyncTransport {
  final String deviceId;
  final _incoming = StreamController<SyncBatch>.broadcast();
  SyncBatch? lastPushed;
  SyncManifest? _peersManifest;
  final Map<String, int> _peersClock = {};

  _LoopbackTransport(this.deviceId);

  @override
  Stream<SyncBatch> get onIncoming => _incoming.stream;

  @override
  Future<void> start() async {}

  @override
  Future<SyncManifest> fetchManifest() async =>
      _peersManifest ??
      SyncManifest(deviceId: 'peer', clock: _peersClock);

  @override
  Future<SyncBatch> pull(Map<String, int> highwater, {String? cursor}) async {
    // In the paired model, pull returns what was pushed by the peer.
    final b = lastPushed;
    return b ?? SyncBatch(senderDeviceId: 'peer', manifest: _peersManifest ?? SyncManifest(deviceId: 'peer'));
  }

  @override
  Future<void> push(SyncBatch batch) async {
    lastPushed = batch;
  }

  /// The test harness delivers a batch as if received from the peer.
  void deliverPeerPush(SyncBatch batch) {
    _incoming.add(batch);
  }

  @override
  Future<void> stop() async {
    await _incoming.close();
  }
}

void main() {
  group('SyncEngine conflict resolution', () {
    test('pushes new sessions and messages from source to sink', () async {
      final payload = _makePayload(
        deviceId: 'src',
        sessions: [
          {
            'id': 's1',
            'title': 'Hello',
            'createdAt': '2026-08-01T00:00:00.000Z',
            'updatedAt': '2026-08-01T00:00:00.000Z',
            'revision': 1,
            'deleted': false,
          }
        ],
        messages: [
          _msg('m1', 's1', 'user', 'hi there'),
          _msg('m2', 's1', 'assistant', 'hello!'),
        ],
      );

      final sink = MemoryStore();
      final storage = _LoopbackTransport('sink');
      // Seed peer manifest so the sink knows the source has rev 1.
      storage._peersManifest = SyncManifest(deviceId: 'src', clock: {'s1': 1});

      final outcome = await SyncEngine(
        config: const SyncConfig(),
        transport: storage,
        store: ChatStore(sink),
        adapter: sink,
        deviceId: 'sink',
      ).applyBatch(payload);

      expect(outcome.messagesApplied, 2);
      expect(outcome.sessionsApplied, 1);
      final msgs = await sink.messagesForSession('s1');
      expect(msgs, hasLength(2));
      expect(msgs.first.content, 'hi there');
    });

    test('higher causal id wins on message conflict (deterministic)', () async {
      final store = MemoryStore();
      // Local message m1 at causal seq 10 (microseconds).
      final local = ChatMessage(
          id: 'm1', sessionId: 's1', role: ChatRole.user, content: 'local edit', timestamp: DateTime.fromMicrosecondsSinceEpoch(10));
      await store.upsertMessage(local);

      // Peer has a newer version of the same message (seq 99).
      final peerMsg = SyncMessage(
        id: 'm1',
        sessionId: 's1',
        causal: CausalId(deviceId: 'peer', seq: 99),
        role: 'user',
        content: 'peer edit',
        timestampMs: 99,
      );
      final payload = SyncBatch(
          senderDeviceId: 'peer',
          manifest: SyncManifest(deviceId: 'peer', clock: {'s1': 1}),
          messages: [peerMsg]);

      final outcome = await SyncEngine(
        config: const SyncConfig(),
        transport: _LoopbackTransport('me'),
        store: ChatStore(store),
        adapter: store,
        deviceId: 'me',
      ).applyBatch(payload);

      final after = await store.messageById('m1');
      // The peer edit (causal 99 > local 10) should have won.
      expect(after!.content, 'peer edit');
      expect(outcome.messagesConflictResolved, greaterThan(0));
    });

    test('older remote edit is discarded (local wins)', () async {
      final store = MemoryStore();
      final local = ChatMessage(
          id: 'm1', sessionId: 's1', role: ChatRole.user, content: 'local newer', timestamp: DateTime.fromMillisecondsSinceEpoch(500));
      await store.upsertMessage(local);

      final stale = SyncMessage(
        id: 'm1',
        sessionId: 's1',
        causal: CausalId(deviceId: 'peer', seq: 1),
        role: 'user',
        content: 'stale peer edit',
        timestampMs: 1,
      );
      final payload = SyncBatch(
        senderDeviceId: 'peer',
        manifest: SyncManifest(deviceId: 'peer', clock: {'s1': 2}),
        messages: [stale],
      );
      await SyncEngine(
        config: const SyncConfig(),
        transport: _LoopbackTransport('me'),
        store: ChatStore(store),
        adapter: store,
        deviceId: 'me',
      ).applyBatch(payload);

      final after = await store.messageById('m1');
      expect(after!.content, 'local newer');
    });
  });

  group('Manifest delta computation', () {
    test('sessionsNewerThan detects sessions we are behind on', () {
      final mine = SyncManifest(deviceId: 'a', clock: {'s1': 1, 's2': 5});
      final remote = SyncManifest(deviceId: 'b', clock: {'s1': 3, 's2': 5});
      final needed = mine.sessionsNewerThan(remote);
      expect(needed, {'s1'});
    });

    test('sessionsUnknownTo detects sessions we have that remote lacks', () {
      final mine = SyncManifest(deviceId: 'a', clock: {'s1': 1, 's9': 2});
      final remote = SyncManifest(deviceId: 'b', clock: {'s1': 1});
      expect(mine.sessionsUnknownTo(remote), {'s9'});
    });
  });

  group('CausalId ordering', () {
    test('orders by seq then deviceId', () {
      final a = CausalId(deviceId: 'dev-a', seq: 5);
      final b = CausalId(deviceId: 'dev-b', seq: 5);
      final c = CausalId(deviceId: 'dev-a', seq: 6);
      expect(a.isBefore(c), isTrue);
      // Same seq: deviceId breaks the tie deterministically.
      expect(a.isBefore(b), a.deviceId.compareTo(b.deviceId) < 0);
      expect(c.isBefore(a), isFalse);
    });
  });
}

SyncBatch _makePayload({
  required String deviceId,
  required List<Map<String, dynamic>> sessions,
  required List<SyncMessage> messages,
}) {
  return SyncBatch(
    senderDeviceId: deviceId,
    manifest: SyncManifest(deviceId: deviceId, clock: {
      for (final s in sessions) s['id'] as String: s['revision'] as int,
    }),
    sessions: {
      for (final s in sessions) s['id'] as String: s,
    },
    messages: messages,
  );
}

SyncMessage _msg(String id, String sessionId, String role, String content) =>
    SyncMessage(
      id: id,
      sessionId: sessionId,
      causal: CausalId(deviceId: 'peer', seq: id.hashCode),
      role: role,
      content: content,
      timestampMs: id.hashCode,
    );
