import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Mounted folders management: bind external host folders into the agent's
/// `/var/minis/mounts/` space (Windows: any accessible directory; Android:
/// shared storage). This is the UI for the `mounts` authority.
class MountedFoldersScreen extends StatefulWidget {
  const MountedFoldersScreen({super.key});

  @override
  State<MountedFoldersScreen> createState() => _MountedFoldersScreenState();
}

class _MountedFoldersScreenState extends State<MountedFoldersScreen> {
  final List<_MountEntry> _mounts = [];
  final TextEditingController _path = TextEditingController();
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _path.dispose();
    _name.dispose();
    super.dispose();
  }

  void _add() {
    final p = _path.text.trim();
    final n = _name.text.trim();
    if (p.isEmpty) return;
    setState(() => _mounts.add(_MountEntry(name: n.isEmpty ? p : n, path: p)));
    _path.clear();
    _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '挂载文件夹'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MinisTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MinisTheme.border),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '名称 (可选)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _path,
                  decoration: const InputDecoration(
                    labelText: '本机路径 (Windows: D:\\\\data…)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_link),
                    label: const Text('挂载'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('已挂载目录会映射到 agent 的 minis://mounts/<名称>',
              style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
          const SizedBox(height: 8),
          if (_mounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('暂无挂载', style: TextStyle(color: MinisTheme.textMuted))),
            )
          else
            for (final m in _mounts)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: MinisTheme.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MinisTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder, size: 16, color: MinisTheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          Text('minis://mounts/${m.name} → ${m.path}',
                              style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _mounts.remove(m)),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 12),
          Text('设备: ${app.deviceId}',
              style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
        ],
      ),
    );
  }
}

class _MountEntry {
  final String name;
  final String path;
  _MountEntry({required this.name, required this.path});
}
