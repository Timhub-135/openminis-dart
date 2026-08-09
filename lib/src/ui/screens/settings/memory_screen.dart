import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Persistent memory management: view soul memory notes.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final notes = app.souls.memory;
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '记忆管理'),
      body: notes.isEmpty
          ? const Center(
              child: Text('暂无记忆条目', style: TextStyle(color: MinisTheme.textMuted)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = notes[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notes, size: 18, color: MinisTheme.textMuted),
                  title: Text(n.text, style: const TextStyle(fontSize: 13)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      n.context ?? _time(n.timestamp),
                      style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _time(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
