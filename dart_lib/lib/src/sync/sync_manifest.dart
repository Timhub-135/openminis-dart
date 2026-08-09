import '../models/session.dart';

/// The sync manifest exchanged during a reconciliation handshake.
///
/// Each device advertises the highest [Session.revision] it has seen for every
/// session (plus tombstones for deletes). The peer returns the delta: sessions
/// here with a lower revision than its own local revision are missing updates.
///
/// Model:
///   Manifest = { deviceId, clock: { sessionId: highwaterRevision } }
class SyncManifest {
  final String deviceId;
  /// sessionId -> highwater revision known to this device.
  final Map<String, int> clock;
  /// sessionIds that were tombstones (deleted) locally with a revision.
  final Map<String, int> tombstones;

  const SyncManifest({
    required this.deviceId,
    this.clock = const {},
    this.tombstones = const {},
  });

  /// Built from a list of local sessions.
  factory SyncManifest.fromSessions(String deviceId, List<Session> sessions) {
    final clock = <String, int>{};
    final tombstones = <String, int>{};
    for (final s in sessions) {
      if (s.deleted) {
        tombstones[s.id] = s.revision;
      } else {
        clock[s.id] = s.revision;
      }
    }
    return SyncManifest(deviceId: deviceId, clock: clock, tombstones: tombstones);
  }

  /// The set of session ids for which [remote] knows a higher revision than
  /// this manifest (i.e. updates we are missing).
  Set<String> sessionsNewerThan(SyncManifest remote) {
    return remote.clock.keys
        .where((id) => (clock[id] ?? 0) < (remote.clock[id] ?? 0))
        .toSet();
  }

  /// Session ids that this device knows but the remote doesn't at all.
  Set<String> sessionsUnknownTo(SyncManifest remote) => clock.keys
      .where((id) => !remote.clock.containsKey(id))
      .toSet();

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'clock': clock,
        'tombstones': tombstones,
      };

  factory SyncManifest.fromJson(Map<String, dynamic> j) => SyncManifest(
        deviceId: j['deviceId'] as String? ?? 'unknown',
        clock: (j['clock'] as Map?)?.cast<String, int>() ?? {},
        tombstones: (j['tombstones'] as Map?)?.cast<String, int>() ?? {},
      );
}
