import '../models/platform_info.dart';
import 'tool.dart';

/// A small, dependency-light set of built-in tools. Full platform offloads
/// (shell, browser, device APIs) are registered by the host Flutter app per
/// platform; these are the ones that are identical on Windows and Android.
/// Implemented without `dart:io` so the core compiles for the web too.
List<Tool> builtinTools() {
  return [
    // Informational tool: tells the agent where real filesystem operations go.
    Tool(
      name: 'filesystem_root',
      description: 'Resolve the platform-local root that maps to /var/minis.',
      params: const [
        ToolParam(name: 'authority', description: 'minis:// authority folder', required: true),
      ],
      category: 'core',
      handler: (args) async {
        final auth = args['authority']?.toString() ?? '';
        // The concrete root is injected at runtime by the host; this is the
        // portable fallback.
        final root = PlatformInfo.environment('MINIS_ROOT') ?? '.minis';
        return ToolResult.ok('$root/$auth (resolved on ${PlatformInfo.operatingSystem})');
      },
    ),
  ];
}
