import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme.dart';

/// Right-hand info panel (Windows wide layout): a tabbed view showing the
/// active session's tools, memory, and sync state.
class ChatInfoPanel extends StatefulWidget {
  final String? sessionId;
  const ChatInfoPanel({super.key, this.sessionId});

  @override
  State<ChatInfoPanel> createState() => _ChatInfoPanelState();
}

class _ChatInfoPanelState extends State<ChatInfoPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: MinisTheme.panel,
        border: Border(left: BorderSide(color: MinisTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              '会话信息',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: .5,
                color: MinisTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // KPIs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              children: [
                _kpi('工具', app.tools.all.length.toString()),
                const SizedBox(width: 10),
                _kpi('同步', app.sync != null ? '开' : '关'),
                const SizedBox(width: 10),
                _kpi('状态', app.busy ? '忙' : '闲'),
              ],
            ),
          ),
          const Divider(height: 1),
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _tabBtn(0, '工具', Icons.construction),
                _tabBtn(1, '记忆', Icons.memory),
                _tabBtn(2, '同步', Icons.sync),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(app)),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontSize: 10, color: MinisTheme.textMuted)),
      ],
    );
  }

  Widget _tabBtn(int idx, String label, IconData icon) {
    final on = _tab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = idx),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: on ? MinisTheme.panel2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: on ? MinisTheme.accent : MinisTheme.textMuted),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10, color: on ? MinisTheme.accent : MinisTheme.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(AppState app) {
    switch (_tab) {
      case 0:
        return _toolsTab(app);
      case 1:
        return _memoryTab(app);
      default:
        return _syncTab(app);
    }
  }

  Widget _toolsTab(AppState app) {
    final tools = app.tools.all;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final t in tools)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MinisTheme.panel2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.handyman_outlined, size: 15, color: MinisTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(t.category,
                          style: const TextStyle(fontSize: 10, color: MinisTheme.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_outline, size: 14, color: MinisTheme.accentGreen),
              ],
            ),
          ),
      ],
    );
  }

  Widget _memoryTab(AppState app) {
    final notes = app.souls.memory;
    if (notes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('暂无持久记忆', style: TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: notes.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('· ${notes[i].text}',
            style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
      ),
    );
  }

  Widget _syncTab(AppState app) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(app.sync != null ? Icons.sync : Icons.sync_disabled,
                size: 16,
                color: app.sync != null
                    ? (app.syncError ? MinisTheme.danger : MinisTheme.accentGreen)
                    : MinisTheme.textMuted),
            const SizedBox(width: 8),
            Text(app.sync != null ? 'LAN 同步: ${app.syncError ? "异常" : "运行中"}' : 'LAN 同步: 未启动',
                style: const TextStyle(fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          Text('会话、历史与输出在两台设备间同步（Windows ⇄ Android）。',
              style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted, height: 1.5)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: app.sync == null
                ? () => app.startSync(peerHost: '127.0.0.1', port: 8741)
                : null,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('启动同步'),
          ),
        ],
      ),
    );
  }
}
