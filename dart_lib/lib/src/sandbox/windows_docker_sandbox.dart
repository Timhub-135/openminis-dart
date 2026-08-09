import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sandbox.dart';

/// Windows implementation of [Sandbox] backed by **Docker + Alpine Linux**.
///
/// Strategy:
///   • `docker run` an Alpine image once with a named container and a bind
///     mount of the app's data dir, started detached (`sleep infinity`).
///   • Shell into it with `docker exec` for commands and `docker exec cat` /
///     stdin `tee` for file transfer.
///
/// Being image/container based it's reproducible across Windows machines and
/// needs no WSL. The agent's persisted pieces live under the mounted directory
/// (not an ephemeral overlay) so they survive container restarts.
class DockerAlpineSandbox implements Sandbox {
  final String image;
  final String containerName;

  /// On the host: where `/var/minis` maps (the app's data dir).
  final String hostMinisDir;

  /// Container path mounted to [hostMinisDir].
  final String containerMinisPath = '/var/minis';

  bool _started = false;

  DockerAlpineSandbox({
    this.image = 'alpine:3.21',
    this.containerName = 'openminis-sandbox',
    required this.hostMinisDir,
  });

  @override
  bool get isAvailable => true; // Docker presence is probed on start()

  @override
  Future<void> start() async {
    if (_started) return;
    final inspect = await _run('docker', ['container', 'inspect', containerName]);
    if (inspect.exitCode != 0) {
      // Container doesn't exist yet — create + start it detached.
      Directory(hostMinisDir).createSync(recursive: true);
      final run = await _run('docker', [
        'run', '-d', '--name', containerName,
        '-v', '$hostMinisDir:$containerMinisPath',
        '--entrypoint', '/bin/sh',
        image, '-c', 'sleep infinity',
      ]);
      if (run.exitCode != 0) {
        throw SandboxException(
            'Failed to start Docker Alpine container: ${run.stderr}');
      }
    } else {
      await _run('docker', ['container', 'start', containerName]);
    }
    _started = true;
  }

  @override
  Stream<SandboxOutput> run(String command,
      {String? workingDir, Map<String, String>? env}) async* {
    await _ensureRunning();
    final script = workingDir != null
        ? 'cd "$workingDir" && ${_envPrefix(env)} $command'
        : '${_envPrefix(env)} $command';
    final process = await Process.start(
        'docker', ['exec', '-i', containerName, '/bin/sh', '-c', script]);

    // Relay stdout and stderr onto a single output stream.
    final sink = StreamController<SandboxOutput>(sync: true);
    process.stdout.transform(utf8.decoder).listen(
        (t) => sink.add(SandboxOutput(true, t)),
        onError: (Object e) => sink.addError(e));
    process.stderr.transform(utf8.decoder).listen(
        (t) => sink.add(SandboxOutput(false, t)),
        onError: (Object e) => sink.addError(e));
    await process.exitCode;
    await sink.close();
    yield* sink.stream;
  }

  @override
  Future<SandboxResult> exec(String command,
      {String? workingDir, Map<String, String>? env, Duration? timeout}) async {
    await _ensureRunning();
    final script = workingDir != null
        ? 'cd "$workingDir" && ${_envPrefix(env)} $command'
        : '${_envPrefix(env)} $command';
    final result = await _run('docker',
        ['exec', containerName, '/bin/sh', '-c', script]);
    return SandboxResult(result.exitCode,
        '${result.stdout ?? ''}\n${result.stderr ?? ''}'.trim());
  }

  @override
  Future<List<int>> readFile(String sandboxPath) async {
    await _ensureRunning();
    final result = await _run(
        'docker', ['exec', containerName, '/bin/sh', '-c', 'cat "\$1"', '_', sandboxPath]);
    if (result.exitCode != 0) {
      throw SandboxException('readFile($sandboxPath) failed: ${result.stderr}');
    }
    return utf8.encode(result.stdout?.toString() ?? '');
  }

  @override
  Future<void> writeFile(String sandboxPath, List<int> bytes) async {
    await _ensureRunning();
    final mkdir = await _run('docker',
        ['exec', containerName, '/bin/sh', '-c', 'mkdir -p "\$(dirname "\$1")"', '_', sandboxPath]);
    if (mkdir.exitCode != 0) {
      throw SandboxException('mkdir failed: ${mkdir.stderr}');
    }
    final process = await Process.start('docker',
        ['exec', '-i', containerName, '/bin/sh', '-c', 'cat > "\$1"', '_', sandboxPath]);
    process.stdin.add(bytes);
    await process.stdin.close();
    await process.exitCode;
  }

  @override
  Future<void> stop() async {
    if (_started) {
      await _run('docker', ['container', 'stop', '--time', '5', containerName]);
      _started = false;
    }
  }

  Future<void> _ensureRunning() async {
    await start();
    // Verify the container is actually running; if not, (re)start it.
    final r = await _run(
        'docker', ['container', 'inspect', '-f', '{{.State.Running}}', containerName]);
    final running = (r.stdout?.toString() ?? '').trim() == 'true';
    if (!running) {
      await _run('docker', ['container', 'start', containerName]);
    }
  }

  String _envPrefix(Map<String, String>? env) {
    if (env == null || env.isEmpty) return '';
    return env.entries.map((e) => '${e.key}="${e.value}"').join(' ');
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> args,
  ) async {
    return Process.run(executable, args);
  }
}
