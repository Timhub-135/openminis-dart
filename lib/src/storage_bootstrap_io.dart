import 'dart:io';

import 'package:openminis_core/openminis.dart';
import 'package:path_provider/path_provider.dart';

/// Native (VM) storage bootstrap. Uses the platform's app-support directory
/// via path_provider so messages/sessions persist across launches.
class BootstrapData {
  final JsonFileStore store;
  final String deviceId;
  final String storageRoot;
  final Directory dataDir;

  BootstrapData({
    required this.store,
    required this.deviceId,
    required this.storageRoot,
    required this.dataDir,
  });
}

/// Resolve the native app-support directory.
Future<String> resolveAppDir() async {
  try {
    final base = await getApplicationSupportDirectory();
    base.createSync(recursive: true);
    return base.path;
  } catch (_) {
    // Fallback (e.g. headless): a temp dir under the system temp.
    final tmp = Directory.systemTemp.createTempSync('openminis_native');
    return tmp.path;
  }
}

/// Resolve a native BootstrapData from an existing app dir.
Future<BootstrapData> resolvePlatformBootstrap({
  required String appDir,
  required String deviceId,
}) async {
  // Inform the web-safe PlatformInfo the real OS (dart:io is available here).
  PlatformInfo.setPlatformInfo(
    os: Platform.operatingSystem,
    isWeb: false,
  );
  PlatformInfo.setEnvProvider((k) => Platform.environment[k]);
  final dataDir = Directory(appDir);
  dataDir.createSync(recursive: true);
  final store = JsonFileStore(Directory('${dataDir.path}/openminis'));
  await store.init();
  return BootstrapData(
    store: store,
    deviceId: deviceId,
    storageRoot: dataDir.path,
    dataDir: dataDir,
  );
}

/// Default device id for native platforms.
String defaultDeviceId() {
  final host = Platform.localHostname.isNotEmpty ? Platform.localHostname : 'device';
  return '${Platform.operatingSystem}-$host';
}
