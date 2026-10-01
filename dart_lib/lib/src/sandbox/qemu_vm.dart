// R2 backend — QEMU system-mode VM plumbing (paths, argv, console protocol).
//
// Pure Dart on purpose: the Android sandbox in this package talks to the VM
// over a unix socket and a spawned process, so nothing here needs Flutter, a
// MethodChannel or the Android framework. The Flutter shell only has to say
// where the app's files dir is (`hostMinisDir`) and let the Kotlin
// `VmAssetInstaller` unpack the APK payload once.
//
// Layout inside the app data dir (filesDir on Android):
//
//   <appDir>/vm/vmlinuz-virt            guest kernel          (from APK assets)
//   <appDir>/vm/initrd.img              guest initramfs       (from APK assets)
//   <appDir>/vm/alpine-minis.squashfs   read-only guest root  (from APK assets)
//   <appDir>/vm/qemu/…                  QEMU data files (-L)
//   <appDir>/vm/storage.img             writable ext4 overlay (created here)
//   <appDir>/vm/run/*.sock              serial / console / QMP sockets
//   <appDir>/vm/share/                  virtio-9p share with the guest
//   <appDir>/vm/.ready                  written by the installer when done
//
// Executable pieces (QEMU, its launcher, libslirp) are *not* here — they live in
// the APK's native library dir, because that is the only place a modern Android
// app may exec a file from (targetSdk >= 29 W^X).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sandbox.dart';

/// Filesystem contract of the VM payload.
class VmPaths {
  /// App data dir (Android: `filesDir`).
  final String appDir;

  VmPaths(this.appDir);

  String get vmDir => '$appDir/vm';
  String get kernelPath => '$vmDir/vmlinuz-virt';
  String get initrdPath => '$vmDir/initrd.img';
  String get rootfsPath => '$vmDir/alpine-minis.squashfs';
  String get qemuDataDir => '$vmDir/qemu';
  String get storagePath => '$vmDir/storage.img';
  String get shareDir => '$vmDir/share';
  String get runDir => '$vmDir/run';
  String get readyMarker => '$vmDir/.ready';
  String get serialSock => '$runDir/serial.sock';
  String get consoleSock => '$runDir/console.sock';
  String get qmpSock => '$runDir/qmp.sock';

  /// Guest-side mount point of [shareDir] (virtio-9p, mount_tag=minis).
  static const String guestShareMount = '/mnt/minis';

  /// Marker file name the guest writes; lets the host prove the VM is ours.
  static const String releaseNote = '/etc/minis-vm-release';
}

/// Tunables for one VM.
class VmConfig {
  final int ramMb;
  final int cpus;

  /// Size of the writable ext4 image. Sparse — only written blocks cost space.
  final int storageMb;

  /// Expose [VmPaths.shareDir] to the guest over virtio-9p.
  final bool shareEnabled;

  /// Extra `hostfwd=tcp::HOST-:GUEST` rules on the slirp NIC.
  final List<String> hostFwd;

  /// Appended verbatim to the kernel command line.
  final List<String> kernelCmdlineExtra;

  /// Appended verbatim to the QEMU command line (last wins for -cpu/-accel).
  final List<String> extraQemuArgs;

  const VmConfig({
    this.ramMb = 2048,
    this.cpus = 4,
    this.storageMb = 8192,
    this.shareEnabled = true,
    this.hostFwd = const [],
    this.kernelCmdlineExtra = const [],
    this.extraQemuArgs = const [],
  });
}

/// Builds the QEMU argv (without argv[0]/argv[1] — see [buildLaunchedArgv]).
///
/// Kept a pure function so the whole launch contract is unit-testable without a
/// device: the guest layout (vda = writable overlay, vdb = read-only squashfs),
/// the console chardev the host protocol attaches to, and slirp networking are
/// all encoded here.
List<String> buildQemuArgv({
  required VmPaths paths,
  required VmConfig config,
  required String nativeLibraryDir,
}) {
  final tbMb = config.ramMb >= 2048 ? 512 : 256;
  final cmdline = <String>[
    'console=ttyAMA0',
    'mitigations=off', // TCG is not affected by speculative-execution attacks
    'tsc=reliable',
    ...config.kernelCmdlineExtra,
  ].join(' ');

  final args = <String>[
    '-M', 'virt,gic-version=3',
    '-cpu', 'max,pauth-impdef=on',
    '-accel', 'tcg,thread=multi,tb-size=$tbMb',
    '-m', '${config.ramMb}',
    '-smp', '${config.cpus}',
    '-kernel', paths.kernelPath,
    '-append', cmdline,
    '-initrd', paths.initrdPath,

    // vda — writable ext4; the initramfs formats it on first boot and stacks it
    // as the overlay upper, so `apk add` and anything the agent writes persist.
    '-object', 'iothread,id=iothread0',
    '-device', 'virtio-blk-pci,drive=drive1,num-queues=${config.cpus},iothread=iothread0',
    '-drive',
    'file=${paths.storagePath},if=none,id=drive1,format=raw,cache=writeback,'
        'aio=threads,discard=unmap,detect-zeroes=unmap',

    // vdb — the read-only Alpine squashfs shipped in the APK.
    '-object', 'iothread,id=iothread1',
    '-device', 'virtio-blk-pci,drive=drive2,num-queues=${config.cpus},iothread=iothread1',
    '-drive',
    'file=${paths.rootfsPath},if=none,id=drive2,format=raw,readonly=on,'
        'cache=writeback,aio=threads',
  ];

  if (config.shareEnabled) {
    args.addAll([
      '-fsdev', 'local,id=fsdev0,path=${paths.shareDir},security_model=none',
      '-device', 'virtio-9p-pci,fsdev=fsdev0,mount_tag=minis',
    ]);
  }

  final netdev = StringBuffer('user,id=net0,ipv6=off');
  for (final rule in config.hostFwd) {
    netdev.write(',hostfwd=$rule');
  }
  args.addAll([
    '-netdev', netdev.toString(),
    '-device', 'virtio-net-pci,netdev=net0,romfile=',
  ]);

  // ttyAMA0 carries kernel/init messages; hvc0 (below) carries the agent.
  args.addAll(['-serial', 'unix:${paths.serialSock},server,nowait']);

  // One virtio-console port: the guest's /usr/local/bin/minis-agent owns it and
  // the host speaks the MINIS_* protocol over it.
  args.addAll([
    '-device', 'virtio-serial-pci',
    '-chardev', 'socket,id=term0,path=${paths.consoleSock},server=on,wait=off',
    '-device', 'virtconsole,chardev=term0,name=org.minis.term',
  ]);

  args.addAll(['-display', 'none', '-qmp', 'unix:${paths.qmpSock},server,nowait']);
  args.addAll(['-L', paths.qemuDataDir]);
  args.addAll(config.extraQemuArgs);
  return args;
}

/// argv for the PDEATHSIG launcher: `launcher <qemu> <qemu args…>`.
///
/// Wrapping QEMU in the launcher (libpodroid-launcher.so, an APK native lib)
/// makes the kernel SIGKILL the VM when the Android app process dies — without
/// it, an uninstall/OOM leaves an orphaned VM eating RAM until reboot.
List<String> buildLaunchedArgv({
  required String launcherPath,
  required String qemuPath,
  required List<String> qemuArgs,
}) =>
    [launcherPath, qemuPath, ...qemuArgs];

/// Environment for the VM process: native lib dir first so `libslirp.so` (and
/// any future QEMU deps) resolve out of the APK's extracted libraries.
Map<String, String> buildVmEnvironment(String nativeLibraryDir) => {
      'LD_LIBRARY_PATH': nativeLibraryDir,
      'TMPDIR': '/tmp',
    };

// ───────────────────────────── console transport ─────────────────────────────

/// Byte transport for console frames. Injectable so the protocol can be tested
/// against a simulated guest instead of a real VM.
abstract class VmConsoleTransport {
  /// Establish the transport (for the real one: connect to the unix socket).
  Future<void> connect({Duration timeout = const Duration(seconds: 30)});

  /// Complete frame lines from the guest (newline-stripped).
  Stream<String> get lines;

  /// Send one frame (no trailing newline needed).
  void write(String frame);

  Future<void> close();
}

/// Real transport: QEMU's `-chardev socket` console port.
class UnixSocketConsoleTransport implements VmConsoleTransport {
  UnixSocketConsoleTransport(this.socketPath);

  final String socketPath;
  final _lines = StreamController<String>.broadcast();
  Socket? _socket;
  StreamSubscription<String>? _sub;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
          timeout: const Duration(seconds: 2),
        );
        _socket = socket;
        _sub = socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _lines.add,
              onError: _lines.addError,
              onDone: () => _lines.close(),
              cancelOnError: false,
            );
        return;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw SandboxConsoleError('console socket not ready: $socketPath ($lastError)');
  }

  @override
  void write(String frame) {
    final s = _socket;
    if (s == null) throw SandboxConsoleError('console not connected');
    s.write('$frame\n');
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    if (!_lines.isClosed) await _lines.close();
  }
}

class SandboxConsoleError implements Exception {
  final String message;
  SandboxConsoleError(this.message);
  @override
  String toString() => 'SandboxConsoleError: $message';
}

/// Talks the MINIS_* line protocol to the guest agent.
///
/// Commands are serialised (the console is a single ordered stream) and every
/// response is matched by id, so a stray echoed line can never be mistaken for
/// a result.
class VmConsoleClient {
  VmConsoleClient(this.transport, {this.frameTimeout = const Duration(seconds: 30)});

  final VmConsoleTransport transport;

  /// How long to wait for *any* frame of a command before giving up.
  Duration frameTimeout;

  final _ready = Completer<void>();
  StreamSubscription<String>? _sub;
  _PendingCommand? _pending;
  int _seq = 0;
  Future<void> _chain = Future<void>.value();
  final List<String> _stderr = <String>[];

  /// Frames the guest emitted that no command was waiting for (diagnostics).
  final List<String> recentFrames = <String>[];

  bool get isReady => _ready.isCompleted;

  /// Attach to the stream and wait for the agent's `MINIS_READY` banner.
  Future<void> waitReady({Duration timeout = const Duration(seconds: 60)}) async {
    _sub ??= transport.lines.listen(_onFrame, onError: _onError, onDone: _onDone);
    await _ready.future.timeout(
      timeout,
      onTimeout: () => throw SandboxConsoleError(
          'guest agent did not become ready in ${timeout.inSeconds}s'
          '${_stderr.isEmpty ? '' : ' (${_stderr.last})'}'),
    );
  }

  void _onFrame(String line) {
    final l = line.trim();
    if (l.isEmpty) return;
    if (recentFrames.length > 64) recentFrames.removeAt(0);
    recentFrames.add(l);

    if (l.startsWith('MINIS_READY')) {
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    if (l.startsWith('MINIS_PONG')) return;

    final parts = l.split(' ');
    final kind = parts.isNotEmpty ? parts[0] : '';
    if (parts.length < 2) return;
    final id = parts[1];

    final pending = _pending;
    if (pending == null || pending.id != id) return; // stale frame: ignore

    switch (kind) {
      case 'MINIS_START':
        pending.startedAt = DateTime.now();
        break;
      case 'MINIS_OUT':
        if (parts.length >= 3) pending.addChunk(parts[2]);
        break;
      case 'MINIS_END':
        final code = parts.length >= 3 ? int.tryParse(parts[2]) ?? -1 : -1;
        _pending = null;
        if (!pending.completer.isCompleted) {
          pending.completer.complete(SandboxResult(code, pending.output));
        }
        break;
      case 'MINIS_ERR':
        final why = parts.length >= 3 ? parts.sublist(2).join(' ') : 'error';
        _pending = null;
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(SandboxConsoleError('guest agent: $why'));
        }
        break;
      default:
        break;
    }
  }

  void _onError(Object e) {
    _failPending(SandboxConsoleError('console error: $e'));
  }

  void _onDone() {
    _failPending(SandboxConsoleError('console closed'));
    if (!_ready.isCompleted) {
      _ready.completeError(SandboxConsoleError('console closed before ready'));
    }
  }

  void _failPending(Object error) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error);
    }
  }

  /// Run [script] in the guest; returns exit code + combined output.
  Future<SandboxResult> execute(String script, {Duration? timeout}) {
    final result = _chain.then((_) => _executeLocked(script, timeout: timeout));
    // Keep the chain alive even when a command fails.
    _chain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<SandboxResult> _executeLocked(String script, {Duration? timeout}) async {
    if (!isReady) {
      await waitReady();
    }
    final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}';
    final pending = _PendingCommand(id);
    _pending = pending;

    final b64 = base64.encode(utf8.encode(script));
    final chunks = <String>[];
    for (var i = 0; i < b64.length; i += _chunkSize) {
      chunks.add(b64.substring(
          i, i + _chunkSize > b64.length ? b64.length : i + _chunkSize));
    }
    if (chunks.isEmpty) chunks.add('');

    transport.write('MINIS_EXEC $id ${chunks.first}');
    for (final chunk in chunks.skip(1)) {
      transport.write('MINIS_DATA $chunk');
    }
    transport.write('MINIS_RUN');

    final guard = timeout == null ? frameTimeout : timeout + const Duration(seconds: 10);
    try {
      return await pending.completer.future.timeout(guard);
    } on TimeoutException {
      _pending = null;
      throw SandboxConsoleError(
          'command timed out after ${guard.inSeconds}s (id=$id)');
    }
  }

  static const int _chunkSize = 1024; // base64 chars; tty MAX_CANON is 4096

  Future<bool> ping() async {
    if (!isReady) return false;
    try {
      await execute('true', timeout: const Duration(seconds: 15));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await transport.close();
  }
}

class _PendingCommand {
  _PendingCommand(this.id);
  final String id;
  final completer = Completer<SandboxResult>();
  final _bytes = <int>[];
  DateTime? startedAt;

  void addChunk(String b64Chunk) {
    try {
      _bytes.addAll(base64.decode(b64Chunk));
    } catch (_) {
      // A corrupted chunk should not abort the command; keep what we have.
    }
  }

  String get output => utf8.decode(_bytes, allowMalformed: true);
}
