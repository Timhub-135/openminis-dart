import 'package:openminis_core/openminis.dart';

/// Web bootstrap: no `dart:io` allowed. Uses an in-memory [MemoryStore]; for a
/// durable deployable web app this can be swapped for IndexedDB-backed
/// persistence without touching the UI.
class BootstrapData {
  final MemoryStore store;
  final String deviceId;
  final String storageRoot;
  final Object? dataDir;

  BootstrapData({
    required this.store,
    required this.deviceId,
    this.storageRoot = 'virtual',
    this.dataDir,
  });
}

/// Web: there is no app-support directory; return a virtual root.
Future<String> resolveAppDir() async => 'virtual';

/// Web: resolve a MemoryStore bootstrap.
Future<BootstrapData> resolvePlatformBootstrap({
  required String appDir,
  required String deviceId,
}) async {
  // Inform the web-safe PlatformInfo we're on the browser (no dart:io).
  PlatformInfo.setPlatformInfo(os: 'web', isWeb: true);
  // No dart:io sandbox on web: storageRoot stays empty so the Flutter layer
  // skips native sandbox tools entirely.
  return BootstrapData(
    store: MemoryStore(),
    deviceId: deviceId,
    storageRoot: '',
    dataDir: null,
  );
}

/// Default device id for the web build.
String defaultDeviceId() => 'web-browser';
