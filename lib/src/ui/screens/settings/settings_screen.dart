import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../../routes.dart';
import '../../widgets/minis_app_bar.dart';

/// Main settings screen: grouped list of all configuration areas.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '设置'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _section('Provider & 模型', [
            _tile(context, Icons.extension, 'Provider 管理', Routes.providers,
                'Anthropic / OpenAI / OpenRouter'),
            _tile(context, Icons.tune, '模型分组', Routes.modelGroups,
                'Agent 循环各 slot 的模型'),
          ]),
          _section('Agent', [
            _tile(context, Icons.psychology, 'Agent 人格 (Soul)', Routes.soulSettings,
                '全局规则 / GLOBAL.md'),
            _tile(context, Icons.memory, '记忆管理', Routes.memory,
                '持久记忆条目'),
            _tile(context, Icons.bookmark_border, '技能 (Skills)', Routes.skills,
                '已安装技能 · 启用状态'),
            _tile(context, Icons.api, 'MCP 集成', Routes.mcp,
                'Model Context Protocol servers'),
          ]),
          _section('同步', [
            _tile(context, Icons.sync, '跨平台同步', Routes.syncSettings,
                _syncSubtitle(app)),
          ]),
          _section('环境', [
            _tile(context, Icons.key, '环境变量', Routes.environments,
                'API keys 等（脱敏）'),
            _tile(context, Icons.folder_open, '挂载文件夹', Routes.mountedFolders,
                '外部目录 → /var/minis/mounts'),
            _tile(context, Icons.storage, '存储管理', Routes.storage,
                '数据目录 · 清理缓存'),
          ]),
          _section('关于', [
            _tile(context, Icons.info, '关于 OpenMinis', Routes.about,
                app.deviceId),
          ]),
        ],
      ),
    );
  }

  String _syncSubtitle(AppState app) {
    if (app.syncMessage == 'idle') return '尚未启动';
    return app.syncError ? '异常：${app.syncMessage}' : app.syncMessage;
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(
            title,
            style: const TextStyle(
                fontSize: 12, color: MinisTheme.textMuted,
                fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: MinisTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MinisTheme.border),
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }

  ListTile _tile(BuildContext context, IconData icon, String title, String route, String? sub) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: MinisTheme.textMuted),
      onTap: () => Navigator.of(context).pushNamed(route),
    );
  }
}
