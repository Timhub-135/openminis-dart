import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart';
import 'package:provider/provider.dart';

// Conditional bootstrap: native uses JsonFileStore + path_provider; web uses
// MemoryStore. Both expose resolveAppDir / resolvePlatformBootstrap /
// defaultDeviceId.
import 'src/storage_bootstrap_io.dart'
    if (dart.library.js_interop) 'src/storage_bootstrap_web.dart';

import 'src/app_state.dart';
import 'src/routes.dart';
import 'src/theme.dart';
import 'src/ui/screens/home_screen.dart';
import 'src/ui/screens/chat_screen.dart';
import 'src/services/wiki_api.dart';
import 'src/ui/screens/share_inbox_screen.dart';
import 'src/ui/screens/wiki_screen.dart';
import 'src/ui/screens/settings/settings_screen.dart';
import 'src/ui/screens/settings/providers_screen.dart';
import 'src/ui/screens/settings/model_groups_screen.dart';
import 'src/ui/screens/settings/sync_settings_screen.dart';
import 'src/ui/screens/settings/soul_settings_screen.dart';
import 'src/ui/screens/settings/skills_screen.dart';
import 'src/ui/screens/settings/memory_screen.dart';
import 'src/ui/screens/settings/mcp_screen.dart';
import 'src/ui/screens/settings/environ_screen.dart';
import 'src/ui/screens/settings/mounted_folders_screen.dart';
import 'src/ui/screens/settings/storage_screen.dart';
import 'src/ui/screens/settings/about_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Platform-agnostic storage: resolve the app dir and a JsonFileStore or a
  // MemoryStore depending on the target (web vs native).
  final appDir = await resolveAppDir();
  final deviceId = defaultDeviceId();
  final boot = await resolvePlatformBootstrap(
    appDir: appDir,
    deviceId: deviceId,
  );

  final chatStore = ChatStore(boot.store as PersistenceAdapter);
  final state = await AppState.bootstrap(
    adapter: boot.store as PersistenceAdapter,
    chatStore: chatStore,
    deviceId: deviceId,
    storageRoot: boot.storageRoot,
    llm: llmFactoryDefault(),
    modelConfig: const LlmRequestConfig(provider: 'echo', model: 'echo'),
  );

  runApp(MinisApp(state: state));
}

final _backendBase = 'http://127.0.0.1:8741';

class MinisApp extends StatelessWidget {
  final AppState state;
  const MinisApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: 'OpenMinis',
        debugShowCheckedModeBanner: false,
        theme: MinisTheme.dark,
        initialRoute: Routes.home,
        routes: {
          Routes.home: (_) => const HomeScreen(),
          Routes.chat: (_) => const ChatScreen(),
          Routes.wiki: (_) => WikiScreen(api: WikiApi(baseUrl: _backendBase)),
          Routes.shareInbox: (ctx) {
            final args = ModalRoute.of(ctx)?.settings.arguments;
            final share = args is PendingShare ? args : null;
            if (share == null) {
              // No share payload: fall back to home.
              return const HomeScreen();
            }
            return ShareInboxScreen(share: share);
          },
          Routes.settings: (_) => const SettingsScreen(),
          Routes.providers: (_) => const ProvidersScreen(),
          Routes.modelGroups: (_) => const ModelGroupsScreen(),
          Routes.syncSettings: (_) => const SyncSettingsScreen(),
          Routes.soulSettings: (_) => const SoulSettingsScreen(),
          Routes.skills: (_) => const SkillsScreen(),
          Routes.memory: (_) => const MemoryScreen(),
          Routes.mcp: (_) => const McpScreen(),
          Routes.environments: (_) => const EnvScreen(),
          Routes.mountedFolders: (_) => const MountedFoldersScreen(),
          Routes.storage: (_) => const StorageScreen(),
          Routes.about: (_) => const AboutScreen(),
        },
      ),
    );
  }
}
