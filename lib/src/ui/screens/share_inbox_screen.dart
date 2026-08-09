import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart' show PendingShare, Session, ShareInbox;
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../widgets/minis_app_bar.dart';

/// The screen shown when a share from another device/app arrives. Lets the user
/// route the shared content into an existing conversation or start a new one.
class ShareInboxScreen extends StatefulWidget {
  final PendingShare share;
  const ShareInboxScreen({super.key, required this.share});

  @override
  State<ShareInboxScreen> createState() => _ShareInboxScreenState();
}

class _ShareInboxScreenState extends State<ShareInboxScreen> {
  List<Session> _sessions = [];
  String? _targetSessionId; // null = create a new session
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final sessions = await app.sessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _targetSessionId = null; // default to a new conversation
      _loading = false;
    });
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final s = await ShareInbox.routeIntoSession(
        app.store,
        share: widget.share,
        sessionId: _targetSessionId,
      );
      // Optionally run the agent on the shared prompt (if a real LLM is set).
      if (app.providerId != 'echo') {
        await app.send(s.id, widget.share.fullText);
      }
      if (!mounted) return;
      final title = s.title.isEmpty ? '新建会话' : s.title;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已分享进会话「$title」')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: const MinisAppBar(title: '分享到会话'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: MinisTheme.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('分享内容'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MinisTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MinisTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final it in widget.share.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                it.isFile ? Icons.attach_file : Icons.notes,
                                size: 15,
                                color: MinisTheme.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: SelectableText(it.displayText,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section('发送到'),
                RadioGroup<String?>(
                  groupValue: _targetSessionId,
                  onChanged: (v) => setState(() => _targetSessionId = v),
                  child: Column(
                    children: [
                      const RadioListTile<String?>(
                        dense: true,
                        title: Text('➕ 新对话'),
                        value: null,
                      ),
                      if (_sessions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Text('（还没有历史会话）',
                              style: TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
                        )
                      else
                        for (final s in _sessions.take(20))
                          RadioListTile<String?>(
                            dense: true,
                            title: Text(
                              s.title.isEmpty ? '未命名会话' : s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            secondary: const Icon(Icons.forum_outlined, size: 18),
                            value: s.id,
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: Text(_targetSessionId == null ? '新建对话并发送' : '发送到所选会话'),
                ),
              ],
            ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text(
          t,
          style: const TextStyle(
              fontSize: 12, color: MinisTheme.textMuted,
              fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      );
}
