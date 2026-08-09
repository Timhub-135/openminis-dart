import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Skills management: list installed skills with enable/disable.
class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final skills = app.skills.all;

    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '技能 (Skills)'),
      body: skills.isEmpty
          ? const Center(
              child: Text('暂无已安装技能', style: TextStyle(color: MinisTheme.textMuted)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: skills.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final s = skills[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MinisTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MinisTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_outlined, size: 20, color: MinisTheme.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(s.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
                          ],
                        ),
                      ),
                      Switch(
                        value: s.enabled,
                        activeTrackColor: MinisTheme.accent.withValues(alpha: 0.6),
                        onChanged: (v) {
                          app.skills.setEnabled(s.id, v);
                          setState(() {}); // repaint the toggle
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
