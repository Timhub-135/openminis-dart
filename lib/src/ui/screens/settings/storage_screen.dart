import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Storage management: shows data-store info and (in a real build) lets the
/// user clear caches. Read-only summary here since the sandbox/per-platform
/// data dir is owned by the host.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    const sessionCount = '—';

    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '存储管理'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card('数据存储', Icons.storage, [
            ('持久化方式', 'JSON Store (openminis_core)'),
            ('会话数', sessionCount),
            ('同步引擎', app.sync != null ? (app.syncError ? '异常' : '运行中') : '未启动'),
          ]),
          const SizedBox(height: 12),
          _card('说明', Icons.info_outline, [
            ('消息/会话', '跨平台可同步 (Windows ⇄ Android)'),
            ('附件 & 输出', '走 minis:// 工作区，物理位置由主机平台决定'),
            ('清理', '升级版可提供「清空消息历史」按钮'),
          ]),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('清空会话历史（待实现）'),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, IconData icon, List<(String, String)> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MinisTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MinisTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: MinisTheme.accent),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(k, style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
                  ),
                  Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
