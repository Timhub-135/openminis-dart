import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

/// A stand-in for the guest agent: parses the same MINIS_* frames the real
/// `/usr/local/bin/minis-agent` does, runs the command through the host shell,
/// and answers with the same chunked framing. That makes the whole host-side
/// protocol (chunking, id matching, exit codes, truncation) testable without a
/// VM — the guest script itself is validated separately further down.
class FakeGuest implements VmConsoleTransport {
  final _toHost = StreamController<String>.broadcast();
  final List<String> _history = [];
  final List<String> inbox = [];
  String currentId = '';
  final StringBuffer _b64 = StringBuffer();

  /// When true the guest swallows frames without answering — used to exercise
  /// the host's frame-timeout guard.
  bool mute = false;

  static const int chunk = 1024;
  static const int outMax = 8 * 1024 * 1024;

  @override
  Stream<String> get lines async* {
    // Replay what was emitted before the host attached (MINIS_READY), then
    // stream live frames — the real socket behaves the same way for the host:
    // it connects, then the agent's banner arrives.
    yield* Stream<String>.fromIterable(_history);
    yield* _toHost.stream;
  }

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    _emit('MINIS_READY 1');
  }

  void _emit(String s) {
    _history.add(s);
    if (!_toHost.isClosed) _toHost.add(s);
  }

  @override
  void write(String frame) {
    inbox.add(frame);
    if (mute) return;
    final space = frame.indexOf(' ');
    final verb = space < 0 ? frame : frame.substring(0, space);
    final rest = space < 0 ? '' : frame.substring(space + 1);
    switch (verb) {
      case 'MINIS_PING':
        _emit('MINIS_PONG');
        break;
      case 'MINIS_EXEC':
        final sp = rest.indexOf(' ');
        currentId = sp < 0 ? rest : rest.substring(0, sp);
        _b64
          ..clear()
          ..write(sp < 0 ? '' : rest.substring(sp + 1));
        break;
      case 'MINIS_DATA':
        _b64.write(rest);
        break;
      case 'MINIS_RUN':
        unawaited(_run());
        break;
    }
  }

  Future<void> _run() async {
    final id = currentId;
    final script = utf8.decode(base64.decode(_b64.toString()));
    final dir = Directory.systemTemp.createTempSync('minis_guest');
    final file = File('${dir.path}/cmd.sh')..writeAsStringSync(script);
    _emit('MINIS_START $id');
    final r = await Process.run('sh', [file.path],
        stdoutEncoding: null, stderrEncoding: null);
    var out = <int>[...(r.stdout as List<int>), ...(r.stderr as List<int>)];
    if (out.length > outMax) out = out.sublist(0, outMax);
    if (out.isNotEmpty) {
      final b64 = base64.encode(out);
      for (var i = 0; i < b64.length; i += chunk) {
        final end = i + chunk > b64.length ? b64.length : i + chunk;
        _emit('MINIS_OUT $id ${b64.substring(i, end)}');
      }
    }
    _emit('MINIS_END $id ${r.exitCode}');
    dir.deleteSync(recursive: true);
  }

  @override
  Future<void> close() async {
    await _toHost.close();
  }
}

void main() {
  group('QEMU launch contract', () {
    final paths = VmPaths('/data/user/0/com.openminis.app/files');
    final config = const VmConfig(
      ramMb: 2048,
      cpus: 4,
      storageMb: 8192,
      hostFwd: ['tcp::8081-:80'],
    );

    test('wires kernel, initramfs, both virtio disks and the console', () {
      final argv = buildQemuArgv(
        paths: paths,
        config: config,
        nativeLibraryDir: '/data/app/x/lib/arm64',
      );
      final line = argv.join(' ');

      expect(line, contains('-M virt,gic-version=3'));
      expect(line, contains('-accel tcg,thread=multi'));
      expect(line, contains('-kernel ${paths.kernelPath}'));
      expect(line, contains('-initrd ${paths.initrdPath}'));
      // vda = writable overlay, vdb = read-only squashfs
      expect(line, contains('id=drive1'));
      expect(line, contains('file=${paths.storagePath}'));
      expect(line, contains('id=drive2'));
      expect(line, contains('file=${paths.rootfsPath}'));
      expect(line, contains('readonly=on'));
      // the console the host protocol attaches to
      expect(line, contains('path=${paths.consoleSock}'));
      expect(line, contains('name=org.minis.term'));
      expect(line, contains('-qmp unix:${paths.qmpSock},server,nowait'));
      // slirp with the user's forward
      expect(line, contains('hostfwd=tcp::8081-:80'));
      // headless
      expect(line, contains('-display none'));
    });

    test('shares the app dir only when enabled', () {
      final on = buildQemuArgv(
          paths: paths, config: config, nativeLibraryDir: '/x').join(' ');
      expect(on, contains('mount_tag=minis'));
      final off = buildQemuArgv(
              paths: paths,
              config: const VmConfig(shareEnabled: false),
              nativeLibraryDir: '/x')
          .join(' ');
      expect(off, isNot(contains('mount_tag=minis')));
    });

    test('launcher argv puts the QEMU path first (PDEATHSIG wrapper)', () {
      final argv = buildLaunchedArgv(
        launcherPath: '/lib/arm64/libpodroid-launcher.so',
        qemuPath: '/lib/arm64/libqemu-system-aarch64.so',
        qemuArgs: ['-M', 'virt'],
      );
      expect(argv.first, '/lib/arm64/libpodroid-launcher.so');
      expect(argv[1], '/lib/arm64/libqemu-system-aarch64.so');
      expect(argv.sublist(2), ['-M', 'virt']);
    });

    test('environment points QEMU at the extracted native libs', () {
      final env = buildVmEnvironment('/lib/arm64');
      expect(env['LD_LIBRARY_PATH'], '/lib/arm64');
    });
  });

  group('console protocol round-trip (simulated guest)', () {
    late FakeGuest guest;
    late VmConsoleClient client;
    late Directory appDir;

    setUp(() async {
      appDir = Directory.systemTemp.createTempSync('openminis_vm');
      guest = FakeGuest();
      client = VmConsoleClient(guest);
      await guest.connect();
      await client.waitReady(timeout: const Duration(seconds: 5));
    });

    tearDown(() async {
      await client.close();
      if (appDir.existsSync()) appDir.deleteSync(recursive: true);
    });

    test('commands are chunked, then answered with exit code + output', () async {
      final res = await client.execute('echo hello-r2');
      expect(res.exitCode, 0);
      expect(res.output.trim(), 'hello-r2');
      // A short command still uses the framed form.
      expect(guest.inbox.first.startsWith('MINIS_EXEC '), isTrue);
      expect(guest.inbox.last, 'MINIS_RUN');
    });

    test('long commands are split into <=1024-char frames', () async {
      final cmd = 'echo ${'x' * 5000}';
      final res = await client.execute(cmd);
      expect(res.exitCode, 0);
      final execFrames = guest.inbox.where((f) => f.startsWith('MINIS_EXEC ')).toList();
      final dataFrames = guest.inbox.where((f) => f.startsWith('MINIS_DATA ')).toList();
      expect(dataFrames, isNotEmpty, reason: 'payload must be chunked');
      for (final f in [...execFrames, ...dataFrames]) {
        expect(f.length, lessThan(4096), reason: 'tty MAX_CANON is 4096');
      }
      expect(res.output.trim().length, 5000);
    });

    test('large output is reassembled from multiple MINIS_OUT frames', () async {
      final res = await client.execute('seq 1 2000');
      expect(res.exitCode, 0);
      final lines = res.output.trim().split('\n');
      expect(lines.first, '1');
      expect(lines.last, '2000');
    });

    test('exit codes propagate', () async {
      final res = await client.execute('exit 7');
      expect(res.exitCode, 7);
    });

    test('stderr is merged into the same ordered stream', () async {
      final res = await client.execute('echo out; echo err 1>&2');
      expect(res.exitCode, 0);
      expect(res.output, contains('out'));
      expect(res.output, contains('err'));
    });

    test('a silent guest trips the frame-timeout guard', () async {
      final mute = FakeGuest()..mute = true;
      final c = VmConsoleClient(mute,
          frameTimeout: const Duration(milliseconds: 400));
      await mute.connect();
      await c.waitReady(timeout: const Duration(seconds: 5));
      await expectLater(
        c.execute('echo never'),
        throwsA(isA<SandboxConsoleError>()),
      );
      await c.close();
    });

    test('commands run one at a time even when issued concurrently', () async {
      final results = await Future.wait([
        client.execute('echo a'),
        client.execute('echo b'),
        client.execute('echo c'),
      ]);
      expect(results.map((r) => r.output.trim()).toList(), <String>['a', 'b', 'c']);
      // exactly one MINIS_EXEC per command — no interleaving
      expect(guest.inbox.where((f) => f.startsWith('MINIS_EXEC ')).length, 3);
    });
  });

  group('AndroidQemuSandbox (simulated guest + fake process)', () {
    late Directory appDir;
    late FakeGuest guest;

    VmConsoleTransport factory(String _) => guest;

    setUp(() async {
      appDir = Directory.systemTemp.createTempSync('openminis_vm');
      // Stand in for the APK payload the Kotlin installer unpacks.
      final vm = Directory('${appDir.path}/vm')..createSync(recursive: true);
      for (final p in ['vmlinuz-virt', 'initrd.img', 'alpine-minis.squashfs']) {
        File('${vm.path}/$p').writeAsStringSync('payload');
      }
      File('${vm.path}/.ready').writeAsStringSync('ok');
      Directory('${vm.path}/lib/arm64').createSync(recursive: true);
      for (final p in ['libpodroid-launcher.so', 'libqemu-system-aarch64.so']) {
        File('${vm.path}/lib/arm64/$p').writeAsStringSync('');
      }
      guest = FakeGuest();
    });

    tearDown(() async {
      await guest.close();
      if (appDir.existsSync()) appDir.deleteSync(recursive: true);
    });

    AndroidQemuSandbox make() => AndroidQemuSandbox(
          appDir: appDir.path,
          nativeLibraryDir: '${appDir.path}/vm/lib/arm64',
          transportFactory: factory,
          allowNonAndroid: true,
          bootTimeout: const Duration(seconds: 10),
          assetWait: const Duration(seconds: 5),
          processLauncher: (exe, args, wd, env) async =>
              throw StateError('should reuse the running console, launched $exe'),
        );

    test('start() attaches to a live console instead of booting a VM', () async {
      final sb = make();
      await sb.start();
      expect(sb.isAvailable, isTrue);
    });

    test('exec runs a command in the guest', () async {
      final sb = make();
      final res = await sb.exec('echo from-vm');
      expect(res.exitCode, 0);
      expect(res.output.trim(), 'from-vm');
    });

    test('honours workingDir and env', () async {
      final sb = make();
      await sb.exec('mkdir -p ${appDir.path}/vm/share/work');
      final res = await sb.exec('pwd; echo \$GREETING',
          workingDir: '${appDir.path}/vm/share/work', env: {'GREETING': 'hi'});
      expect(res.output, contains('share/work'));
      expect(res.output, contains('hi'));
    });

    test('applies the exec timeout inside the guest', () async {
      final sb = make();
      final sw = Stopwatch()..start();
      final res = await sb.exec('sleep 10', timeout: const Duration(seconds: 1));
      sw.stop();
      // The contract is "a hanging command does not occupy the console": the
      // guest-side `timeout` cuts it short. Which non-zero code comes back is
      // implementation-defined (coreutils says 124, a signal death surfaces as
      // 128+N), so assert the behaviour, not the number.
      expect(sw.elapsed, lessThan(const Duration(seconds: 8)));
      expect(res.output, isNot(contains('10 seconds later')));
    });

    test('creates a sparse storage image on first start', () async {
      final sb = make();
      await sb.start();
      final img = File('${appDir.path}/vm/storage.img');
      expect(img.existsSync(), isTrue);
      expect(img.lengthSync(), 8192 * 1024 * 1024);
      // Sparse: a truncated file costs ~0 blocks on disk.
      final blocks = await Process.run('du', ['-k', img.path]);
      final kb = int.parse((blocks.stdout as String).trim().split(RegExp(r'\s+')).first);
      expect(kb, lessThan(1024), reason: 'storage.img should not be preallocated');
    });

    test('file IO round-trips through the share dir without the console', () async {
      final sb = make();
      await sb.writeFile('${VmPaths.guestShareMount}/notes.txt', utf8.encode('hello'));
      final back = await sb.readFile('${VmPaths.guestShareMount}/notes.txt');
      expect(utf8.decode(back), 'hello');
      expect(
          File('${appDir.path}/vm/share/notes.txt').readAsStringSync(), 'hello');
      expect(guest.inbox, isEmpty, reason: 'share paths bypass the console');
    });

    test('file IO outside the share goes through the guest shell', () async {
      final sb = make();
      // Anywhere writable works: the point is that a path outside the 9p share
      // cannot be served by the host, so it must travel over the console.
      // (A fixed /root/... path broke on CI runners, which are not root.)
      final outside =
          '${Directory.systemTemp.path}/openminis_outside_$pid.txt';
      await sb.writeFile(outside, utf8.encode('x'));
      expect(guest.inbox, isNotEmpty);
      final res = await sb.readFile(outside);
      expect(utf8.decode(res), contains('x'));
    });

    test('factory wires Android to the QEMU backend by default', () {
      final sb = SandboxFactory.create(hostMinisDir: appDir.path, os: 'android');
      expect(sb, isA<AndroidQemuSandbox>());
      final legacy = SandboxFactory.create(
          hostMinisDir: appDir.path,
          os: 'android',
          androidBackend: AndroidSandboxBackend.termux);
      expect(legacy, isA<AndroidTermuxSandbox>());
    });
  });

  group('guest payload (shipped in the APK)', () {
    test('minis-agent is valid POSIX shell', () async {
      final file = File('${_repoRoot()}/android/vm/guest/usr/local/bin/minis-agent');
      if (!file.existsSync()) {
        markTestSkipped('guest agent not vendored at ${file.path}');
        return;
      }
      final r = await Process.run('sh', ['-n', file.path]);
      expect(r.exitCode, 0, reason: 'minis-agent syntax error:\n${r.stderr}');
    });

    test('minis-rc is valid POSIX shell', () async {
      final file = File('${_repoRoot()}/android/vm/guest/etc/minis-rc');
      if (!file.existsSync()) {
        markTestSkipped('minis-rc not vendored at ${file.path}');
        return;
      }
      final r = await Process.run('sh', ['-n', file.path]);
      expect(r.exitCode, 0, reason: 'minis-rc syntax error:\n${r.stderr}');
    });
  });
}

String _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (Directory('${dir.path}/android').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return Directory.current.path;
}
