import 'dart:io';

import '../models/platform_info.dart';
import 'android_termux_sandbox.dart';
import 'sandbox.dart';
import 'windows_docker_sandbox.dart';

/// Builds the right sandbox for the current platform.
///
///   • **Windows**  → [DockerAlpineSandbox] (Docker + Alpine).
///   • **Android**  → [AndroidTermuxSandbox]: runs commands inside the installed
///                    Termux shell (no root / PRoot / Docker needed), using a
///                    shared bridge directory + `com.termux.RUN_COMMAND`.
class SandboxFactory {
  /// Creates the default sandbox for the current OS.
  ///
  /// [hostMinisDir] is the real on-disk location of `/var/minis` for the
  /// current device (e.g. the app data dir on Windows; on Android it's the
  /// bridge dir used by Termux). [os] defaults to [PlatformInfo.operatingSystem]
  /// so the web build (where `dart:io` is unavailable) is kept safe.
  static Sandbox create({
    required String hostMinisDir,
    String? os,
  }) {
    final target = os ?? PlatformInfo.operatingSystem;
    switch (target) {
      case 'windows':
      case 'linux':
        // Linux desktop uses the same Docker/Alpine approach for parity.
        return DockerAlpineSandbox(hostMinisDir: hostMinisDir);
      case 'android':
        // If the phone has Termux, run commands inside it. The bridge dir is
        // where both this app and Termux can write (shared storage).
        return AndroidTermuxSandbox(bridgeDir: hostMinisDir);
      default:
        // web / iOS / unknown: no on-device linux shell available.
        return UnsupportedSandbox(
            'Sandbox not available on "$target". Targets: windows, android.',
            hostMinisDir: hostMinisDir);
    }
  }

  /// Probe whether Docker is installed on this machine.
  static Future<bool> dockerAvailable() async {
    try {
      final r = await Process.run(
          'docker', ['version', '--format', '{{.Server.Version}}']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// A sandbox that always refuses — used to surface "not wired yet" clearly.
class UnsupportedSandbox implements Sandbox {
  final String message;
  final String hostMinisDir;
  UnsupportedSandbox(this.message, {required this.hostMinisDir});

  @override
  bool get isAvailable => false;

  @override
  Future<SandboxResult> exec(String command,
          {String? workingDir, Map<String, String>? env, Duration? timeout}) async {
    throw SandboxException(message);
  }

  @override
  Future<List<int>> readFile(String sandboxPath) async =>
      throw SandboxException(message);

  @override
  Stream<SandboxOutput> run(String command,
          {String? workingDir, Map<String, String>? env}) async* {
    throw SandboxException(message);
  }

  @override
  Future<void> start() async => throw SandboxException(message);

  @override
  Future<void> stop() async {}

  @override
  Future<void> writeFile(String sandboxPath, List<int> bytes) async =>
      throw SandboxException(message);
}
