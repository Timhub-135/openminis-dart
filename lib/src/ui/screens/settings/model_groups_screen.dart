import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart' show ProviderConfig;
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Model groups / agent-loop slot configuration.
/// A simplified view of the original AgentLoopModelsView: shows the
/// provider picker per role slot (main, planning, tools) as a conceptual map.
class ModelGroupsScreen extends StatelessWidget {
  const ModelGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '模型分组'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _slotCard(
            context,
            '主模型 (Main)',
            '处理日常对话与主推理',
            app.providerId,
            (id) => app.setProvider(id),
            app.providerOptions,
          ),
          const SizedBox(height: 10),
          // Planning & tools share the same provider in this scaffold.
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MinisTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MinisTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('规划 / 工具 (Planning/Tools)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('当前复用「主模型」的 provider。完整实现可将不同 slot 绑定不同模型。',
                    style: TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
                const SizedBox(height: 10),
                const Chip(
                  avatar: Icon(Icons.link, size: 14),
                  label: Text('跟随主模型', style: TextStyle(fontSize: 11)),
                  backgroundColor: MinisTheme.panel2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotCard(BuildContext context, String title, String desc,
      String current, ValueChanged<String> onSelect, List<ProviderConfig> options) {
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
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
          const SizedBox(height: 10),
          // Only pass an initialValue that exists in the item list, otherwise
          // DropdownButtonFormField throws and the page renders broken.
          DropdownButtonFormField<String>(
            initialValue: options.any((p) => p.id == current)
                ? current
                : (options.isNotEmpty ? options.first.id : 'echo'),
            decoration: InputDecoration(
              labelText: '当前 Provider',
              labelStyle: const TextStyle(fontSize: 12, color: MinisTheme.textMuted),
            ),
            items: [
              for (final p in options)
                DropdownMenuItem(
                  value: p.id,
                  child: Text('${p.name} (${p.protocol})',
                      style: const TextStyle(fontSize: 13)),
                ),
            ],
            onChanged: (v) { if (v != null) onSelect(v); },
          ),
        ],
      ),
    );
  }
}
