import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart';

import '../../theme.dart';

/// A single session row in the session list.
class SessionTile extends StatelessWidget {
  final Session session;
  final int messageCount;
  final bool selected;
  final ValueChanged<Session> onTap;
  final VoidCallback onDelete;

  const SessionTile({
    super.key,
    required this.session,
    required this.messageCount,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = session.title.isEmpty ? '未命名会话' : session.title;
    return Material(
      color: selected ? MinisTheme.panel2 : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(session),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? MinisTheme.accent : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$messageCount 条消息 · ${_relative(session.updatedAt)}'
                      '${session.lastModelProvider != null ? ' · ${session.lastModelProvider}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: MinisTheme.textMuted,
                tooltip: '删除',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return t.year.toString();
  }
}

/// Empty state shown when there are no sessions yet.
class EmptySessions extends StatelessWidget {
  final VoidCallback onCreate;
  const EmptySessions({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: MinisTheme.textMuted),
          const SizedBox(height: 16),
          const Text('还没有会话', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          const Text('开始和你的 agent 对话吧',
              style: TextStyle(color: MinisTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('新建会话'),
          ),
        ],
      ),
    );
  }
}
