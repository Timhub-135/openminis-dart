import 'dart:io';

import '../models/platform_info.dart';
import 'android_qemu_sandbox.dart';
import 'android_termux_sandbox.dart';
import 'qemu_vm.dart';
import 'sandbox.dart';
import 'windows_docker_sandbox.dart';

/// Which Android implementation to build.
enum AndroidSandboxBackend {
  /// **R2 (default)** — boot the QEMU/Alpine VM that ships inside the APK.
  /// Needs no Termux, no PRoot, no ptrace, no user namespaces, no root.
  qemu,

  /// Legacy — run commands inside an installed Termux via `RUN_COMMAND`.
  /// Kept for devices where the VM cannot run (and for the sim tests).
  termux,
}

/// Builds the right sandbox for the current platform.
///
///   • **Windows**  → [DockerAlpineSandbox] (Docker + Alpine).
///   • **Android**  → [AndroidQemuSandbox] (R2): a real VM with its own kernel,
///                    launched from the APK's native library dir, driven over
///                    the guest's virtio-console.
///   • **Android (legacy)** → [AndroidTermuxSandbox]: the old Termux bridge.
class SandboxFactory {
  /// Creates the default sandbox for the current OS.
  ///
  /// [hostMinisDir] is the real on-disk location of `/var/minis` for the
  /// current device (the app data dir; on Android that is `filesDir`, where the
  /// VM payload is unpacked). [os] defaults to [PlatformInfo.operatingSystem]
  /// so the web build (where `dart:io` is unavailable) is kept safe.
  static Sandbox create({
    required String hostMinisDir,
    String? os,
    AndroidSandboxBackend androidBackend = AndroidSandboxBackend.qemu,
    VmConfig vmConfig = const VmConfig(),
  }) {
    final target = os ?? PlatformInfo.operatingSystem;
    switch (target) {
      case 'windows':
      case 'linux':
        // Linux desktop uses the same Docker/Alpine approach for parity.
        return DockerAlpineSandbox(hostMinisDir: hostMinisDir);
      case 'android':
        switch (androidBackend) {
          case AndroidSandboxBackend.qemu:
            return AndroidQemuSandbox(appDir: hostMinisDir, config: vmConfig);
          case AndroidSandboxBackend.termux:
            return AndroidTermuxSandbox(bridgeDir: hostMinisDir);
        }
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
