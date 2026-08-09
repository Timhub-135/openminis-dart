/// Causal/lamport identifiers for cross-device ordering.
///
/// A [CausalId] is `(deviceId, seq)` where seq is a device-local monotonic
/// counter (we seed it from wall-clock microseconds and bump it on edits). Two
/// ids are totally ordered lexicographically by (seq, deviceId); ties broken by
/// deviceId make the order deterministic across replicas with no central
/// authority. This underpins the sync engine's merge rule.
class CausalId implements Comparable<CausalId> {
  final String deviceId;
  final int seq;

  const CausalId({required this.deviceId, required this.seq});

  /// Produce the next id after this one on the same device.
  CausalId bump() => CausalId(deviceId: deviceId, seq: seq + 1);

  @override
  int compareTo(CausalId other) {
    final bySeq = seq.compareTo(other.seq);
    if (bySeq != 0) return bySeq;
    return deviceId.compareTo(other.deviceId);
  }

  bool isBefore(CausalId other) => compareTo(other) < 0;

  bool get isValid => seq > 0;

  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'seq': seq};

  factory CausalId.fromJson(Map<String, dynamic> j) => CausalId(
        deviceId: j['deviceId'] as String? ?? 'unknown',
        seq: j['seq'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is CausalId &&
      other.deviceId == deviceId &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(deviceId, seq);

  @override
  String toString() => '$deviceId@$seq';
}
