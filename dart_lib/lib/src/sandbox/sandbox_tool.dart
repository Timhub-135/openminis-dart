import '../tools/tool.dart';
import 'sandbox.dart';

/// Turns a [Sandbox] into one or more [Tool]s the agent can invoke, mirroring
/// the original's `linux_shell` tool category.
///
/// Registers:
///   • `linux_sh`      — run an arbitrary shell command in the sandbox.
///   • `sandbox_read`  — read a file from the sandbox.
///   • `sandbox_write` — write a file to the sandbox.
List<Tool> sandboxTools(Sandbox sandbox) {
  return [
    Tool(
      name: 'linux_sh',
      description: 'Run a shell command in the device Linux sandbox (Docker Alpine).',
      params: const [
        ToolParam(name: 'command', description: 'Shell command to run', required: true, type: 'string'),
        ToolParam(name: 'working_dir', description: 'Optional directory inside the sandbox', required: false, type: 'string'),
      ],
      category: 'linux_shell',
      handler: (args) async {
        if (!sandbox.isAvailable) {
          return const ToolResult.fail('Linux sandbox is not available on this device.');
        }
        final command = args['command'] as String? ?? '';
        if (command.isEmpty) {
          return const ToolResult.fail('Empty command.');
        }
        try {
          final res = await sandbox.exec(command,
              workingDir: args['working_dir'] as String?);
          return res.ok
              ? ToolResult.ok(res.output, mutated: true)
              : ToolResult.fail(
                  'exit ${res.exitCode}\n${res.output}', mutated: true);
        } catch (e) {
          return ToolResult.fail('sandbox error: $e');
        }
      },
    ),
    Tool(
      name: 'sandbox_read',
      description: 'Read a file located inside the Linux sandbox.',
      params: const [
        ToolParam(name: 'path', description: 'File path inside the sandbox', required: true, type: 'string'),
      ],
      category: 'linux_shell',
      handler: (args) async {
        try {
          final bytes = await sandbox.readFile(args['path'] as String? ?? '');
          return ToolResult.ok(String.fromCharCodes(bytes));
        } catch (e) {
          return ToolResult.fail('read failed: $e');
        }
      },
    ),
    Tool(
      name: 'sandbox_write',
      description: 'Write content to a file inside the Linux sandbox.',
      params: const [
        ToolParam(name: 'path', description: 'File path inside the sandbox', required: true, type: 'string'),
        ToolParam(name: 'content', description: 'File content', required: true, type: 'string'),
      ],
      category: 'linux_shell',
      handler: (args) async {
        try {
          await sandbox.writeFile(args['path'] as String? ?? '',
              (args['content'] as String? ?? '').codeUnits);
          return const ToolResult.ok('written', mutated: true);
        } catch (e) {
          return ToolResult.fail('write failed: $e');
        }
      },
    ),
  ];
}

/// In-memory [Sandbox] fake for tests and for running the agent loop headlessly
/// without Docker. Implements a toy command language so shell invocations return
/// deterministic output.
class FakeSandbox implements Sandbox {
  final Map<String, List<int>> files = {};

  @override
  bool get isAvailable => true;

  @override
  Future<void> start() async {}

  @override
  Future<SandboxResult> exec(String command,
      {String? workingDir, Map<String, String>? env, Duration? timeout}) async {
    // Minimal command support for tests: echo / cat.
    final trimmed = command.trim();
    if (trimmed.startsWith('echo ')) {
      final text = trimmed.substring(5).replaceAll('"', '');
      return SandboxResult(0, text);
    }
    if (trimmed.startsWith('cat ')) {
      final path = trimmed.substring(4).trim();
      final f = files[path];
      if (f == null) return SandboxResult(1, 'cat: $path: No such file');
      return SandboxResult(0, String.fromCharCodes(f));
    }
    if (trimmed.startsWith('mkdir ')) return SandboxResult(0, '');
    if (trimmed == 'true') return SandboxResult(0, '');
    return SandboxResult(127, 'command not found: $trimmed');
  }

  @override
  Stream<SandboxOutput> run(String command,
          {String? workingDir, Map<String, String>? env}) async* {
    final res = await exec(command, workingDir: workingDir, env: env);
    if (res.output.isNotEmpty) yield SandboxOutput(true, res.output);
  }

  @override
  Future<List<int>> readFile(String sandboxPath) async {
    final f = files[sandboxPath];
    if (f == null) throw SandboxException('No such file: $sandboxPath');
    return f;
  }

  @override
  Future<void> writeFile(String sandboxPath, List<int> bytes) async {
    files[sandboxPath] = bytes;
  }

  @override
  Future<void> stop() async {}
}
