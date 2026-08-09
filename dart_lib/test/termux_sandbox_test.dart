import 'dart:convert';
import 'dart:io';

import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidTermuxSandbox (Termux bridge, simulated)', () {
    late Directory bridge;

    setUp(() {
      bridge = Directory.systemTemp.createTempSync('openminis_bridge');
    });

    tearDown(() {
      if (bridge.existsSync()) bridge.deleteSync(recursive: true);
    });

    test('installs a bash-syntactically valid run.sh helper', () async {
      final sb = AndroidTermuxSandbox(bridgeDir: bridge.path);
      await sb.start();
      final helper = File('${bridge.path}/run.sh');
      expect(helper.existsSync(), isTrue);

      // Validate the generated bash script compiles.
      final r = await Process.run('bash', ['-n', helper.path]);
      expect(r.exitCode, 0, reason: 'run.sh has a bash syntax error:\n${r.stderr}');
    });

    test('full bridge round-trip: command -> Termux -> parsed result', () async {
      final sb = AndroidTermuxSandbox(bridgeDir: bridge.path);
      // Pretend to be Termux: read the command file, run run.sh via bash, which
      // writes the JSON result the app then parses.
      sb.sendOverride = (id, resultFile) async {
        final helper = File('${bridge.path}/run.sh');
        // The helper reads cmd_<id>.txt (written by exec) and produces result json.
        final r = await Process.run('bash', [helper.path, id, resultFile]);
        expect(r.exitCode, inInclusiveRange(0, 2),
            reason: 'run.sh failed:\n${r.stdout}\n${r.stderr}');
      };

      final res = await sb.exec('echo hello-termux');
      expect(res.exitCode, 0);
      expect(res.output.trim(), 'hello-termux');

      // No temp files left behind.
      expect(File('${bridge.path}/cmd_1.txt').existsSync(), isFalse);
    });

    test('exit codes propagate through the bridge', () async {
      final sb = AndroidTermuxSandbox(bridgeDir: bridge.path);
      sb.sendOverride = (id, resultFile) async {
        await Process.run('bash', [
          File('${bridge.path}/run.sh').path, id, resultFile,
        ]);
      };
      final res = await sb.exec('exit 7');
      expect(res.exitCode, 7);
    });

    test('writeFile round-trips binary via base64 env', () async {
      final sb = AndroidTermuxSandbox(bridgeDir: bridge.path);
      sb.sendOverride = (id, resultFile) async {
        await Process.run(
            'bash', [File('${bridge.path}/run.sh').path, id, resultFile]);
      };
      final payload = utf8.encode('hello ☺ 世界');
      await sb.writeFile('/tmp/t.txt', payload);
      final back = await sb.readFile('/tmp/t.txt');
      expect(utf8.decode(back), 'hello ☺ 世界');
    });
  });

  group('SandboxFactory platform selection', () {
    test('windows -> Docker Alpine', () {
      expect(
          SandboxFactory.create(hostMinisDir: '/d', os: 'windows'),
          isA<DockerAlpineSandbox>());
    });
    test('android -> Termux', () {
      expect(
          SandboxFactory.create(hostMinisDir: '/d', os: 'android'),
          isA<AndroidTermuxSandbox>());
    });
    test('ios -> unsupported', () {
      expect(
          SandboxFactory.create(hostMinisDir: '/d', os: 'ios').isAvailable,
          isFalse);
    });
  });
}
