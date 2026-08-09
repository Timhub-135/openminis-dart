/// Configuration for the cross-platform sync engine.
///
/// OpenMinis' original sync is iCloud-centric. This Dart rewrite introduces a
/// self-hostable sync transport so a Windows machine and an Android device can
/// share conversations, history and output without any third-party cloud:
///
///   • `lan`   — automatic peer discovery + direct HTTP/WS sync on the local
///               network (requires both devices online, same LAN).
///   • `hub`   — sync through a small relay server the user self-hosts (allows
///               cross-network round-trips; the relay never stores plaintext
///               when `encryptWithPassword` is set).
class SyncTransportMode {
  static const String lan = 'lan';
  static const String hub = 'hub';
}

class SyncConfig {
  /// Transport: `lan` or `hub`.
  final String mode;

  /// A device that speaks the sync protocol. When mode == 'lan' this is used
  /// to find peers on the subnet; when 'hub' it's the relay base URL.
  final String peerHost;

  /// Port/LAN hub port. Default mDNS-like advertisement port for OpenMinis.
  final int port;

  /// Sync interval in seconds for LAN polling/push; ignored in hub mode if the
  /// hub supports push.
  final int intervalSeconds;

  /// Password (optional). When set, message payloads are encrypted
  /// (AES-GCM via a runtime crypto adapter) so a shared relay can't read them.
  final String? encryptionPassword;

  /// If true, synced messages carry up/download state so attachment/output
  /// files are copied between devices too (not just their references).
  final bool syncBlobs;

  const SyncConfig({
    this.mode = SyncTransportMode.lan,
    this.peerHost = '127.0.0.1',
    this.port = 8741,
    this.intervalSeconds = 5,
    this.encryptionPassword,
    this.syncBlobs = true,
  });

  bool get isLan => mode == SyncTransportMode.lan;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'peerHost': peerHost,
        'port': port,
        'intervalSeconds': intervalSeconds,
        'syncBlobs': syncBlobs,
        'hasPassword': encryptionPassword != null,
      };
}
