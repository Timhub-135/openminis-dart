import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Cross-platform sync settings (Windows ⇄ Android).
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await context.read<AppState>().startSync(
        mode: SyncTransportMode.lan,
        peerHost: '127.0.0.1',
        port: 8741,
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _syncNow() async {
    await context.read<AppState>().syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final running = app.sync != null;

    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '跨平台同步'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MinisTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MinisTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      running ? Icons.sync : Icons.sync_disabled,
                      color: running
                          ? (app.syncError ? MinisTheme.danger : MinisTheme.accentGreen)
                          : MinisTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      running ? '同步引擎：${app.syncError ? "异常" : "运行中"}' : '同步引擎：未启动',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '模式: LAN · 本机: ${app.deviceId}',
                  style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted),
                ),
                if (running)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(app.syncMessage,
                        style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
                  ),
                const SizedBox(height: 16),
                Text(
                  '同步会话、历史记录与输出到局域网另一台设备（Windows ⇄ Android）。'
                  '使用 CausalId 因果序做确定性冲突消解，删除会作为墓碑传播。',
                  style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: running || _starting ? null : _start,
            icon: _starting ? const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.play_arrow),
            label: Text(running ? '已启动 (局域网 :8741)' : '启动局域网同步'),
          ),
          if (running) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: app.syncError ? _start : _syncNow,
              icon: const Icon(Icons.refresh),
              label: const Text('立即同步一次'),
            ),
          ],
        ],
      ),
    );
  }
}
