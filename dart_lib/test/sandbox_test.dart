import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  group('Sandbox tools (Docker Alpine back-end)', () {
    test('factory picks DockerAlpineSandbox for windows', () {
      final s = SandboxFactory.create(hostMinisDir: '/tmp/minis2026', os: 'windows');
      expect(s, isA<DockerAlpineSandbox>());
      expect(s.isAvailable, isTrue);
    });

    test('factory refuses iOS explicitly', () {
      final s = SandboxFactory.create(hostMinisDir: '/tmp/minis2026', os: 'ios');
      expect(s.isAvailable, isFalse);
    });
  });

  group('agent-facing shell tools', () {
    test('linux_sh runs a command through FakeSandbox', () async {
      final sandbox = FakeSandbox();
      final tools = sandboxTools(sandbox);
      final sh = tools.firstWhere((t) => t.name == 'linux_sh');

      final res = await sh.invoke({'command': 'echo hello'});
      expect(res.ok, isTrue);
      expect(res.output.trim(), 'hello');
    });

    test('linux_sh reports non-zero exits as failures', () async {
      final sandbox = FakeSandbox();
      final sh = sandboxTools(sandbox).firstWhere((t) => t.name == 'linux_sh');

      final res = await sh.invoke({'command': 'not_a_real_cmd'});
      expect(res.ok, isFalse);
      expect(res.output, contains('exit 127'));
    });

    test('sandbox_write and sandbox_read round-trip a file', () async {
      final sandbox = FakeSandbox();
      final tools = sandboxTools(sandbox);
      final write = tools.firstWhere((t) => t.name == 'sandbox_write');
      final read = tools.firstWhere((t) => t.name == 'sandbox_read');

      await write.invoke({'path': '/var/minis/workspace/hello.txt', 'content': 'hi'});
      final res = await read.invoke({'path': '/var/minis/workspace/hello.txt'});
      expect(res.ok, isTrue);
      expect(res.output, 'hi');
    });
  });
}
