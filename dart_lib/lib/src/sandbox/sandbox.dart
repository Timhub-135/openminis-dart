/// A Linux shell sandbox that the agent can work in — the heart of OpenMinis.
///
/// Original semantics: "a full Linux shell running on your device". The
/// upstream used iSH on iOS and PRoot on Android; this rewrite targets
/// Windows + Android, using **Docker + Alpine on Windows**:
///
///   • **Windows**  → a **Docker Alpine** container (the standard way to get a
///     real Linux shell on Windows).
///   • **Android**  → PRoot / a native chroot-backed sandbox.
///
/// The interface below is platform-agnostic so the agent loop never touches
/// Docker or PRoot directly. Implementations are supplied per platform.
abstract class Sandbox {
  /// Whether the sandbox is currently available/startable on this device.
  bool get isAvailable;

  /// Start the sandbox (e.g. start the Alpine container). Idempotent.
  Future<void> start();

  /// Run a command in the sandbox, streaming stdout/stderr lines.
  ///
  /// [workingDir] is a path inside the sandbox; [env] are extra env vars.
  Stream<SandboxOutput> run(
    String command, {
    String? workingDir,
    Map<String, String>? env,
  });

  /// Run a command and wait for it to finish, returning exit code + combined
  /// output (stdout and stderr merged). Convenience over [run].
  Future<SandboxResult> exec(
    String command, {
    String? workingDir,
    Map<String, String>? env,
    Duration? timeout,
  });

  /// Read a file from inside the sandbox as bytes.
  Future<List<int>> readFile(String sandboxPath);

  /// Write bytes to a file inside the sandbox (creating dirs as needed).
  Future<void> writeFile(String sandboxPath, List<int> bytes);

  /// Stop the sandbox. Idempotent.
  Future<void> stop();
}

/// One line/frame of sandbox output.
class SandboxOutput {
  final bool isStdout; // false = stderr
  final String text;
  const SandboxOutput(this.isStdout, this.text);
}

/// Full command result.
class SandboxResult {
  final int exitCode;
  final String output;
  const SandboxResult(this.exitCode, this.output);

  bool get ok => exitCode == 0;
}

/// Exception type for sandbox operations.
class SandboxException implements Exception {
  final String message;
  final Object? cause;
  SandboxException(this.message, [this.cause]);
  @override
  String toString() => 'SandboxException: $message';
}
