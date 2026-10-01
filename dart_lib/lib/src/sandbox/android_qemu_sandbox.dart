// R2 Android backend — a real QEMU/KVM-less virtual machine, not a chroot.
//
// Why this exists: OpenMinis' Android sandbox used to borrow Termux (and before
// that, PRoot). Both need something the device may not grant — Termux has to be
// installed and allow external apps, PRoot needs `ptrace` and the ability to
// exec a binary out of the app's *writable* data dir, which Android has denied
// since API 29 (W^X). This backend needs neither. It boots a small Alpine VM
// with its own kernel:
//
//   • QEMU (TCG) + kernel + initramfs + rootfs squashfs ship inside the APK.
//   • Executables live in the APK's native library dir — the one place a modern
//     app is still allowed to exec from.
//   • The guest mounts a sparse ext4 image as an overlay upper, so anything the
//     agent installs or writes survives reboots.
//   • Commands travel over the guest's virtio-console, driven by the
//     `minis-agent` script baked into the rootfs (see tools/ in the repo).
//
// Consequences worth knowing:
//   • Boot takes seconds, not milliseconds. `start()` is idempotent and usually
//     only pays that cost once per app run.
//   • TCG means roughly 1/5–1/20 of native speed; a VM beats no Linux at all,
//     and on devices with AVF/pKVM this backend has a faster sibling later.
//   • No root, no Termux, no ptrace, no user namespaces required.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'qemu_vm.dart';
import 'sandbox.dart';

/// Starts the VM process. Injectable for tests.
typedef VmProcessLauncher = Future<Process> Function(
  String executable,
  List<String> args,
  String workingDirectory,
  Map<String, String> environment,
);

/// Creates the console transport. Injectable for tests.
typedef VmTransportFactory = VmConsoleTransport Function(String socketPath);

class AndroidQemuSandbox implements Sandbox {
  AndroidQemuSandbox({
    required this.appDir,
    this.config = const VmConfig(),
    String? nativeLibraryDir,
    this.launcherName = 'libpodroid-launcher.so',
    this.qemuName = 'libqemu-system-aarch64.so',
    this.transportFactory,
    this.processLauncher,
    this.assetWait = const Duration(seconds: 90),
    this.bootTimeout = const Duration(seconds: 120),
    this.allowNonAndroid = false,
  }) : _nativeLibraryDirOverride = nativeLibraryDir;

  /// App data dir: Android `filesDir`. The VM payload lives in `<appDir>/vm`.
  final String appDir;

  final VmConfig config;
  final String launcherName;
  final String qemuName;
  final VmTransportFactory? transportFactory;
  final VmProcessLauncher? processLauncher;

  /// How long to wait for the APK payload to be unpacked (first run only).
  final Duration assetWait;

  /// How long to wait for the guest agent to announce itself.
  final Duration bootTimeout;

  /// Test/dev escape hatch: allow use on non-Android hosts.
  final bool allowNonAndroid;

  final String? _nativeLibraryDirOverride;

  late final VmPaths paths = VmPaths(appDir);

  Process? _process;
  VmConsoleClient? _console;
  Future<void>? _starting;
  bool _ready = false;
  String? _nativeLibraryDir;

  /// Last lines QEMU wrote to stderr — surfaced in failures.
  final List<String> qemuStderr = <String>[];

  @override
  bool get isAvailable => allowNonAndroid || Platform.isAndroid;

  /// The real native library dir resolved from the running process, or null.
  String? get nativeLibraryDir => _nativeLibraryDir;

  @override
  Future<void> start() {
    if (_ready) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    if (!isAvailable) {
      throw SandboxException(
          'AndroidQemuSandbox needs Android (or allowNonAndroid for tests).');
    }
    _nativeLibraryDir = _resolveNativeLibraryDir();
    Directory(paths.runDir).createSync(recursive: true);
    Directory(paths.shareDir).createSync(recursive: true);

    // The Kotlin VmAssetInstaller unpacks the APK payload and drops a marker;
    // on every launch after the first this is already satisfied.
    await _awaitPayload();
    _ensureStorageImage();

    // Attach to an already-running VM (e.g. after a Flutter hot restart)
    // instead of starting a second one.
    final transport = transportFactory?.call(paths.consoleSock) ??
        UnixSocketConsoleTransport(paths.consoleSock);
    final client = VmConsoleClient(transport);
    try {
      await transport.connect(timeout: const Duration(seconds: 2));
      await client.waitReady(timeout: const Duration(seconds: 5));
      _console = client;
      _ready = true;
      return;
    } catch (_) {
      await client.close().catchError((_) {});
    }

    await _launchQemu();

    final transport2 = transportFactory?.call(paths.consoleSock) ??
        UnixSocketConsoleTransport(paths.consoleSock);
    final client2 = VmConsoleClient(transport2);
    await transport2.connect(timeout: bootTimeout);
    await client2.waitReady(timeout: bootTimeout);
    _console = client2;
    _ready = true;
  }

  Future<void> _awaitPayload() async {
    final marker = File(paths.readyMarker);
    final required = [
      paths.kernelPath,
      paths.initrdPath,
      paths.rootfsPath,
    ];
    final deadline = DateTime.now().add(assetWait);
    while (DateTime.now().isBefore(deadline)) {
      if (marker.existsSync() && required.every((p) => File(p).existsSync())) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final missing = required.where((p) => !File(p).existsSync()).toList();
    throw SandboxException(
        'VM payload not unpacked in ${paths.vmDir} (marker=${marker.existsSync()}'
        '${missing.isEmpty ? '' : ', missing: ${missing.join(", ")}'}). '
        'The APK assets are unpacked by VmAssetInstaller on app start.');
  }

  void _ensureStorageImage() {
    final f = File(paths.storagePath);
    final want = config.storageMb * 1024 * 1024;
    if (f.existsSync() && f.lengthSync() == want) return;
    f.parent.createSync(recursive: true);
    final raf = f.openSync(mode: FileMode.writeOnly);
    try {
      // ftruncate => sparse file: on first boot the guest sees all zeros and
      // mkfs.ext4's it; only blocks actually written afterwards take space.
      raf.truncateSync(want);
    } finally {
      raf.closeSync();
    }
  }

  Future<void> _launchQemu() async {
    final libDir = _nativeLibraryDir!;
    final launcher = '$libDir/$launcherName';
    final qemu = '$libDir/$qemuName';
    if (!File(qemu).existsSync()) {
      throw SandboxException(
          'QEMU binary not found at $qemu — the APK was built without the VM '
          'native libraries (jniLibs/arm64-v8a).');
    }
    final args = buildQemuArgv(
      paths: paths,
      config: config,
      nativeLibraryDir: libDir,
    );
    final argv = buildLaunchedArgv(
      launcherPath: launcher,
      qemuPath: qemu,
      qemuArgs: args,
    );
    final env = buildVmEnvironment(libDir);

    final launcherExists = File(launcher).existsSync();
    final start = processLauncher ??
        (exe, a, wd, e) => Process.start(
              exe,
              a,
              workingDirectory: wd,
              environment: e,
              includeParentEnvironment: true,
            );

    final proc = launcherExists
        ? await start(launcher, argv, paths.vmDir, env)
        : await start(qemu, args, paths.vmDir, env);
    _process = proc;
    _drainStderr(proc);
  }

  void _drainStderr(Process proc) {
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      if (qemuStderr.length > 200) qemuStderr.removeAt(0);
      qemuStderr.add(line.trim());
    }, onError: (_) {}, cancelOnError: false);
    // stdout is redirected to /dev/null by QEMU itself (-display none, no
    // stdio monitor), but drain it anyway so a full pipe can never block.
    proc.stdout.listen((_) {}, onError: (_) {}, cancelOnError: false);
    unawaited(proc.exitCode.then((code) {
      _ready = false;
    }, onError: (_) {}));
  }

  /// `/proc/self/maps` lists every mapped .so, including the app's own native
  /// libraries — the first line under `/lib/<abi>/` names the exact directory
  /// Android extracted our APK libs into. Android apps can read their own maps.
  String _resolveNativeLibraryDir() {
    final override = _nativeLibraryDirOverride;
    if (override != null) return override;
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      for (final line in const LineSplitter().convert(maps)) {
        if (!line.contains('/lib/')) continue;
        final path = line.split(' ').last.trim();
        final idx = path.indexOf('/lib/');
        if (idx <= 0) continue;
        final dir = path.substring(0, idx);
        if (Directory('$dir/lib').existsSync()) return '$dir/lib';
      }
    } catch (_) {
      // fall through
    }
    throw SandboxException(
        'could not resolve nativeLibraryDir from /proc/self/maps');
  }

  @override
  Stream<SandboxOutput> run(String command,
      {String? workingDir, Map<String, String>? env}) async* {
    final res = await exec(command, workingDir: workingDir, env: env);
    if (res.output.isNotEmpty) yield SandboxOutput(true, res.output);
  }

  @override
  Future<SandboxResult> exec(String command,
      {String? workingDir, Map<String, String>? env, Duration? timeout}) async {
    await start();
    final console = _console;
    if (console == null) throw SandboxException('console not connected');

    final script = _wrap(command, workingDir: workingDir, env: env, timeout: timeout);
    final res = await console.execute(script, timeout: timeout);
    if (res.exitCode == -1 && res.output.isEmpty && !console.isReady) {
      return SandboxResult(-1, 'guest agent went away mid-command');
    }
    return res;
  }

  /// Builds the script the guest shell runs: optional `cd`, exported env, the
  /// command itself, and an optional hard timeout so a hanging command cannot
  /// occupy the single console forever.
  String _wrap(String command,
      {String? workingDir, Map<String, String>? env, Duration? timeout}) {
    final buf = StringBuffer();
    if (timeout != null) {
      final secs = timeout.inSeconds <= 0 ? 1 : timeout.inSeconds;
      buf.writeln('timeout -k 5 ${secs}s sh -c ${_quote(command)}');
    } else {
      buf.writeln(command);
    }
    final header = StringBuffer();
    if (workingDir != null && workingDir.isNotEmpty) {
      header.writeln('cd ${_quote(workingDir)} || exit 66');
    }
    if (env != null) {
      for (final e in env.entries) {
        header.writeln('export ${e.key}=${_quote(e.value)}');
      }
    }
    return '${header.toString()}$buf';
  }

  static String _quote(String s) => "'${s.replaceAll("'", r"'\''")}'";

  @override
  Future<List<int>> readFile(String sandboxPath) async {
    final shared = _sharedHostPath(sandboxPath);
    if (shared != null) {
      final f = File(shared);
      if (!f.existsSync()) throw SandboxException('no such file: $sandboxPath');
      return f.readAsBytes();
    }
    final res = await exec('base64 -w0 < ${_quote(sandboxPath)}');
    if (res.exitCode != 0) throw SandboxException('readFile: ${res.output}');
    return base64.decode(res.output.replaceAll(RegExp(r'\s'), ''));
  }

  @override
  Future<void> writeFile(String sandboxPath, List<int> bytes) async {
    final shared = _sharedHostPath(sandboxPath);
    if (shared != null) {
      final f = File(shared);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes, flush: true);
      return;
    }
    final b64 = base64.encode(bytes);
    final res = await exec(
      'mkdir -p "\$(dirname ${_quote(sandboxPath)})" && '
      'printf %s "\$MINIS_B64" | base64 -d > ${_quote(sandboxPath)}',
      env: {'MINIS_B64': b64},
    );
    if (res.exitCode != 0) throw SandboxException('writeFile: ${res.output}');
  }

  /// Maps a guest path under the 9p share to its host path, so large files
  /// bypass the console entirely. Returns null for paths outside the share.
  String? _sharedHostPath(String sandboxPath) {
    if (!config.shareEnabled) return null;
    const prefix = VmPaths.guestShareMount;
    if (sandboxPath == prefix || sandboxPath.startsWith('$prefix/')) {
      final rel = sandboxPath.substring(prefix.length);
      return '${paths.shareDir}$rel';
    }
    return null;
  }

  @override
  Future<void> stop() async {
    final proc = _process;
    _starting = null;
    if (_ready) {
      try {
        await _qmpQuit(const Duration(seconds: 5));
      } catch (_) {
        // fall through to SIGKILL
      }
    }
    try {
      await _console?.close();
    } catch (_) {}
    _console = null;
    _ready = false;

    if (proc != null) {
      try {
        await proc.exitCode.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {
        proc.kill(ProcessSignal.sigkill);
      }
      _process = null;
    }
    for (final sock in [paths.serialSock, paths.consoleSock, paths.qmpSock]) {
      final f = File(sock);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Asks QEMU to shut the guest down cleanly (flushes the ext4 overlay)
  /// instead of pulling the plug.
  Future<void> _qmpQuit(Duration timeout) async {
    final socket = await Socket.connect(
      InternetAddress(paths.qmpSock, type: InternetAddressType.unix),
      0,
      timeout: timeout,
    );
    final done = Completer<void>();
    final buffer = StringBuffer();
    late StreamSubscription<String> sub;
    sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      buffer.writeln(line);
      if (line.contains('"QMP"')) {
        socket.write('{"execute":"qmp_capabilities"}\n');
        socket.write('{"execute":"quit"}\n');
      }
      if (line.contains('"return"') && !done.isCompleted) {
        // qmp_capabilities answered; quit already sent.
      }
      if (line.contains('"event"')) {}
    }, onError: (_) {}, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(timeout);
    } catch (_) {
      // timeout — caller falls back to SIGKILL
    } finally {
      await sub.cancel();
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  /// Diagnostic summary for the UI / the agent.
  Future<String> status() async {
    final buf = StringBuffer();
    buf.writeln('backend: qemu-system-aarch64 (TCG)');
    buf.writeln('vmDir: ${paths.vmDir}');
    buf.writeln('nativeLibraryDir: ${_nativeLibraryDir ?? "-"}');
    buf.writeln('ready: $_ready');
    if (_ready) {
      try {
        final r = await exec('cat ${VmPaths.releaseNote}; uname -a');
        buf.writeln(r.output.trim());
      } catch (e) {
        buf.writeln('probe failed: $e');
      }
    }
    if (qemuStderr.isNotEmpty) {
      buf.writeln('qemu stderr tail: ${qemuStderr.last}');
    }
    return buf.toString();
  }
}
