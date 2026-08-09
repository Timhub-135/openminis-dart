import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../routes.dart';
import '../../services/share_intent_handler.dart';
import '../../theme.dart';
import '../chat/chat_view.dart';
import '../panels/chat_info_panel.dart';
import '../widgets/session_tile.dart';
import '../widgets/status_bar.dart';
import '../widgets/status_views.dart';

/// Home screen: responsive shell that hosts the session list and, on wide
/// (Windows) layouts, the active chat + right panel side by side.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedSessionId;
  bool _loading = true;
  List<Session> _sessions = [];
  String? _error;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
    // Auto-start a LAN sync hub in the background (best effort).
    final app = Provider.of<AppState>(context, listen: false);
    app.startSync(peerHost: '127.0.0.1', port: 8741).catchError((_) {});
    // If the app was launched via an Android Share intent, route it.
    _checkIncomingShare();
  }

  Future<void> _checkIncomingShare() async {
    try {
      final share = await ShareIntentHandler.consume();
      if (share != null && mounted) {
        Navigator.of(context).pushNamed(Routes.shareInbox, arguments: share);
      }
    } catch (_) {
      // ignore; not fatal
    }
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final app = Provider.of<AppState>(context, listen: false);
      final sessions = await app.sessions();
      if (!mounted) return;
      setState(() { _sessions = sessions; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _createSession() async {
    final app = Provider.of<AppState>(context, listen: false);
    final s = await app.ensureSession(null);
    _openSession(s.id);
  }

  Future<void> _deleteSession(Session s) async {
    final confirmed = await _confirmDelete(context, s);
    if (confirmed != true) return;
    final app = Provider.of<AppState>(context, listen: false);
    await app.deleteSession(s.id);
    if (_selectedSessionId == s.id) _selectedSessionId = null;
    await _reload();
  }

  void _openSession(String id) {
    setState(() => _selectedSessionId = id);
    // On narrow screens push the chat route; on wide screens show inline.
    final narrow = MediaQuery.of(context).size.width < 900;
    if (narrow) {
      Navigator.of(context).pushNamed(Routes.chat, arguments: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      body: Row(
        children: [
          // ---- Session sidebar / standalone list ----
          SizedBox(
            width: narrow ? 380 : 300,
            child: _buildSidebar(context),
          ),
          // ---- Right: chat + info panel (wide layout) ----
          if (!narrow)
            Expanded(
              child: _selectedSessionId == null
                  ? const _ChatPlaceholder()
                  : Row(
                      children: [
                        Expanded(
                          child: ChatScreenView(sessionId: _selectedSessionId),
                        ),
                        ChatInfoPanel(sessionId: _selectedSessionId),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    context.watch<AppState>(); // rebuild on AppState changes
    return Container(
      decoration: const BoxDecoration(
        color: MinisTheme.panel,
        border: Border(right: BorderSide(color: MinisTheme.border)),
      ),
      child: Column(
        children: [
          _buildBrandBar(context),
          _buildSearchRow(),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(
            child: _buildSessionList(),
          ),
          const Divider(height: 1),
          const _SidebarFooter(),
        ],
      ),
    );
  }

  Widget _buildBrandBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [MinisTheme.accent, MinisTheme.accentGreen],
              ),
            ),
            child: const Center(
              child: Text('M', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 10),
          const Text('OpenMinis',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          const StatusBar(),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() { _query = v; _searching = true; }),
              decoration: InputDecoration(
                hintText: '搜索会话…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                suffixIcon: _searching && _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() { _query = ''; _searching = false; }),
                      )
                    : null,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '新建会话',
            onPressed: _createSession,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    if (_loading) return const LoadingView(label: '加载会话…');
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _reload);
    }

    final filtered = _query.isEmpty
        ? _sessions
        : _sessions
            .where((s) => s.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    if (filtered.isEmpty) {
      if (_query.isNotEmpty) {
        return const Center(child: Text('无匹配会话', style: TextStyle(color: MinisTheme.textMuted)));
      }
      return EmptySessions(onCreate: _createSession);
    }

    return FutureBuilder<Map<String, int>>(
      future: _counts(),
      builder: (context, snap) {
        final counts = snap.data ?? const <String, int>{};
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (context, i) {
            final s = filtered[i];
            final selected = s.id == _selectedSessionId;
            return SessionTile(
              session: s,
              messageCount: counts[s.id] ?? 0,
              selected: selected,
              onTap: (sess) => _openSession(sess.id),
              onDelete: () => _deleteSession(s),
            );
          },
        );
      },
    );
  }

  Future<Map<String, int>> _counts() async {
    final app = Provider.of<AppState>(context, listen: false);
    final map = <String, int>{};
    for (final s in _sessions) {
      map[s.id] = (await app.store.messages(s.id)).length;
    }
    return map;
  }
}

class _ChatPlaceholder extends StatelessWidget {
  const _ChatPlaceholder();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: MinisTheme.textMuted),
          SizedBox(height: 16),
          Text('选择或新建一个会话开始对话', style: TextStyle(color: MinisTheme.textMuted, fontSize: 15)),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Row(
      children: [
        IconButton(
          tooltip: 'Wiki 知识库',
          icon: const Icon(Icons.menu_book_outlined),
          onPressed: () => Navigator.of(context).pushNamed(Routes.wiki),
        ),
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).pushNamed(Routes.settings),
        ),
        IconButton(
          tooltip: '关于',
          icon: const Icon(Icons.info_outline),
          onPressed: () => Navigator.of(context).pushNamed(Routes.about),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(app.deviceId,
              style: const TextStyle(fontSize: 10, color: MinisTheme.textMuted)),
        ),
      ],
    );
  }
}

Future<bool?> _confirmDelete(BuildContext context, Session s) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除会话'),
      content: Text('确定删除「${s.title.isEmpty ? '未命名会话' : s.title}」？此操作会同步到其他设备。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: MinisTheme.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
}
