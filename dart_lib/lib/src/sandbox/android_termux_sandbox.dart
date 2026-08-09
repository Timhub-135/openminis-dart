import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sandbox.dart';

/// Android implementation of [Sandbox] that runs commands **inside Termux**.
///
/// Why Termux (not PRoot / Docker on-device):
///   • Termux is a real Linux environment already on the phone (`$PREFIX`,
///     real shell, `pkg install` / `pip` usable) — the natural Linux shell for
///     an Android agent, with no root and no Docker daemon.
///
/// Why a file bridge:
///   • Android's `RUN_COMMAND` broadcast has **no synchronous return value**, so
///     we hand Termux a command stored in a file and have it write the result to
///     a **shared directory** that both this app and Termux can access. On
///     Android that means a *shared* location (e.g. `/sdcard/Download/.openminis`),
///     because the app and Termux have different Linux UIDs and cannot read each
///     other's private data dirs.
///
/// Flow (per command):
///   1. App writes `cmd_<id>.txt` containing the shell command (env prefix +
///       optional `cd workdir` + command).
///   2. App fires `com.termux.RUN_COMMAND` to
///      `com.termux/.app.RunCommandService`, asking it to run the installed
///      helper `run.sh <id> <result.json>`. Termux's bash reads the command,
///      executes it with stdout+stderr captured and the exit code recorded,
///      and writes a single JSON result file.
///   3. App polls for `<result>.json`, parses exitCode/stdout/stderr, deletes
///      the temp files, and returns a [SandboxResult].
///
/// Device prereqs:
///   • Termux installed; setting **"Allow external apps"** enabled.
///   • This app can write the shared bridge dir (storage permission).
class AndroidTermuxSandbox implements Sandbox {
  /// Shared bridge dir, e.g. `/sdcard/Download/.openminis`, readable/writable
  /// by both this app and Termux.
  final String bridgeDir;

  String get resultFileBase => 'openminis_result';

  int _requestCounter = 0;
  bool _ready = false;

  /// Result of the last `am` invocation (for diagnostics).
  ProcessResult _lastBroadcast =
      ProcessResult(-1, 0, '', '');

  /// Test seam: override this to skip the real `am` broadcast (runs inside the
  /// Dart VM with no Android). When set, [exec] uses it instead of [am].
  Future<void> Function(String id, String resultFile)? sendOverride;

  AndroidTermuxSandbox({required this.bridgeDir});

  @override
  bool get isAvailable => true; // probed on start()

  @override
  Future<void> start() async {
    if (_ready) return;
    final dir = Directory(bridgeDir);
    dir.createSync(recursive: true);
    _installHelper(dir); // idempotent
    _ready = true;
  }

  /// Install the one helper Termux executes; it turns a saved command file into
  /// a JSON result file with exit code + base64 stdout/stderr.
  void _installHelper(Directory dir) {
    final f = File('${dir.path}/run.sh');
    if (f.existsSync()) return; // already installed
    const bash = '/data/data/com.termux/files/usr/bin/bash';
    f.writeAsStringSync("""
#!/$bash
# openminis helper — invoked by the RUN_COMMAND broadcast:
#   run.sh <id> <result.json>
set +e
ID="\$1"
OUT="\$2"
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
CMD="\$DIR/cmd_\$ID.txt"

# Execute the saved command, capturing stdout+stderr and the exit code.
# NOTE: run inside a subshell `( ... )` so a command that calls `exit` or
# `return` never kills the helper itself.
CODE=0
if [ -f "\$CMD" ]; then
  ( . "\$CMD" ) >"\$OUT.out" 2>&1
  CODE=\$?
else
  echo "no cmd_\$ID.txt" >"\$OUT.out"
  CODE=2
fi

STDOUT_B64="\$(base64 -w0 <"\$OUT.out" 2>/dev/null || base64 <"\$OUT.out")"
printf '{"exitCode":%s,"stdout":"%s"}\\n' "\$CODE" "\$STDOUT_B64" > "\$OUT"
rm -f "\$CMD" "\$OUT.out"
""", flush: true);
    // Note: base64 in Termux's toybox accepts `-w0`; fallback without -w0.
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
    final id = (_requestCounter++).toString();
    final resultFile = '$bridgeDir/${resultFileBase}_$id.json';

    // Persist the command so Termux reads a file (no quoting through am).
    final envPrefix = _envPrefix(env);
    final script = workingDir != null
        ? 'cd "$workingDir"\n$envPrefix$command'
        : '$envPrefix$command';
    File('$bridgeDir/cmd_$id.txt').writeAsStringSync(script, flush: true);

    await _sendRunCommand(id, resultFile);

    // Poll for the JSON result.
    final deadline = DateTime.now().add(timeout ?? const Duration(seconds: 30));
    final outFile = File(resultFile);
    while (DateTime.now().isBefore(deadline)) {
      if (outFile.existsSync() && outFile.lengthSync() > 0) {
        try {
          final map = jsonDecode(outFile.readAsStringSync())
              as Map<String, dynamic>;
          outFile.deleteSync();
          final code = (map['exitCode'] as num).toInt();
          final stdout = _decodeB64(map['stdout']?.toString());
          return SandboxResult(code, stdout.trim());
        } catch (_) {
          // partial write — keep waiting a tick
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    // Timed out: the broadcast may have been denied (allow-external-apps off).
    return SandboxResult(
        _lastBroadcast.exitCode == 0 ? 1 : _lastBroadcast.exitCode,
        'Termux result timed out. Check Termux → Allow external apps and the '
        'bridge dir permission.\n${_lastBroadcast.stdout} ${_lastBroadcast.stderr}');
  }

  String _decodeB64(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(s));
    } catch (_) {
      return '';
    }
  }

  String _envPrefix(Map<String, String>? env) {
    if (env == null || env.isEmpty) return '';
    return env.entries.map((e) => 'export ${e.key}="${e.value}";\n').join();
  }

  Future<void> _sendRunCommand(String id, String resultFile) async {
    if (sendOverride != null) {
      await sendOverride!(id, resultFile);
      return;
    }
    try {
      _lastBroadcast = await Process.run('/system/bin/am', [
        'broadcast',
        '--user', '0',
        '-a', 'com.termux.RUN_COMMAND',
        '-n', 'com.termux/.app.RunCommandService',
        '--esa', 'com.executewrapper.EXTRA_ARGUMENTS',
        '$bridgeDir/run.sh', id, resultFile,
        '--ez', 'com.executewrapper.EXTRA_BACKGROUND', 'true',
      ]);
    } catch (e) {
      _lastBroadcast = ProcessResult(-1, 1, '', 'am broadcast failed: $e');
    }
  }

  @override
  Future<List<int>> readFile(String sandboxPath) async {
    final res = await exec('cat "$sandboxPath"');
    if (res.exitCode != 0) throw SandboxException('readFile: ${res.output}');
    return utf8.encode(res.output);
  }

  @override
  Future<void> writeFile(String sandboxPath, List<int> bytes) async {
    final b64 = base64Encode(bytes);
    final r = await exec(
        'mkdir -p "\$(dirname "$sandboxPath")"; '
        'printf %s "\$B64" | base64 -d > "$sandboxPath"',
        env: {'B64': b64});
    if (r.exitCode != 0) throw SandboxException('writeFile: ${r.output}');
  }

  @override
  Future<void> stop() async {
    _ready = false;
  }
}
