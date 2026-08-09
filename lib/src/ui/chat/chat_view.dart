import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../services/wiki_api.dart';
import '../../theme.dart';
import '../widgets/status_bar.dart';
import 'chat_input_bar.dart';
import 'message_list.dart';

/// Base URL of the local OpenMinis backend (the real Markdown store).
const _backendBase = 'http://127.0.0.1:8741';

/// The main chat screen body, reusable both as a pushed route (mobile) and an
/// inline panel (Windows wide layout). Takes [sessionId]; if null, prompts the
/// user to pick/create one inline.
class ChatScreenView extends StatefulWidget {
  final String? sessionId;
  final VoidCallback? onTitleTap;
  const ChatScreenView({super.key, this.sessionId, this.onTitleTap});

  @override
  State<ChatScreenView> createState() => _ChatScreenViewState();
}

class _ChatScreenViewState extends State<ChatScreenView> {
  String? _sessionId;
  bool _busy = false;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    if (_sessionId != null) _loadTitle();
  }

  @override
  void didUpdateWidget(ChatScreenView old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId && widget.sessionId != null) {
      _sessionId = widget.sessionId;
      _title = '';
      _loadTitle();
    }
  }

  void _loadTitle() {
    _loadTitleAsync();
  }

  Future<void> _loadTitleAsync() async {
    final app = context.read<AppState>();
    final id = _sessionId;
    if (id == null) return;
    final s = await app.store.adapter.sessionById(id);
    if (!mounted) return;
    setState(() {
      _title = s?.title.isEmpty ?? true ? '未命名会话' : s!.title;
    });
  }

  Future<void> _send(String text) async {
    var id = _sessionId;
    if (id == null) {
      final app = context.read<AppState>();
      final s = await app.ensureSession(null);
      id = s.id;
      if (mounted) setState(() => _sessionId = id);
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().send(id, text);
      _loadTitle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')), 
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickProvider() async {
    final app = context.read<AppState>();
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MinisTheme.panel,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('选择 provider', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final p in app.providerOptions)
              ListTile(
                leading: Icon(
                  p.ready ? Icons.check_circle : Icons.circle_outlined,
                  color: p.ready ? MinisTheme.accentGreen : MinisTheme.textMuted,
                ),
                title: Text(p.name),
                subtitle: Text(
                  '${p.protocol}${p.ready ? ' · 已配置' : ' · 无 key'}',
                  style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted),
                ),
                trailing: app.providerId == p.id ? const Icon(Icons.check, size: 18) : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
          ],
        ),
      ),
    );
    if (value != null) {
      context.read<AppState>().setProvider(value);
    }
  }

  /// Top-bar button to distill the current session into a wiki note.
  Widget _wikiButton(BuildContext context) {
    return IconButton(
      tooltip: '整理此会话进 Wiki',
      icon: const Icon(Icons.menu_book_outlined, size: 18),
      onPressed: () => _distillToWiki(context),
    );
  }

  Future<void> _distillToWiki(BuildContext context) async {
    final id = _sessionId;
    if (id == null) return;
    // Confirm, then call the backend to distill just this session.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('整理进 Wiki'),
        content: const Text('把这个会话的内容用 LLM 蒸馏成一条知识笔记，加入 Wiki 知识库？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('整理')),
        ],
      ),
    );
    if (confirmed != true) return;

    final api = WikiApi(baseUrl: _backendBase);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在整理…'), duration: Duration(seconds: 2)),
    );
    final msg = await api.distillSession(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final providerLabel = app.providerOptions
        .where((p) => p.id == app.providerId)
        .toList()
        .isEmpty
        ? 'auto'
        : app.providerOptions.firstWhere((p) => p.id == app.providerId).name;

    return Column(
      children: [
        // Top bar.
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: MinisTheme.panel,
            border: Border(bottom: BorderSide(color: MinisTheme.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onTitleTap,
                  child: Text(
                    _sessionId == null ? '选择会话' : _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              // Model/provider picker.
              InkWell(
                onTap: _pickProvider,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MinisTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt, size: 13, color: MinisTheme.accent),
                      const SizedBox(width: 4),
                      Text(providerLabel, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const StatusBar(),
              if (_sessionId != null) ...[
                const SizedBox(width: 6),
                _wikiButton(context),
              ],
            ],
          ),
        ),
        // Message list.
        Expanded(
          child: _sessionId == null
              ? _NoSession(onPick: _ensureSession)
              : MessageList(sessionId: _sessionId!),
        ),
        // Input bar.
        ChatInputBar(busy: _busy, onSubmit: _send),
      ],
    );
  }

  Future<void> _ensureSession() async {
    final app = context.read<AppState>();
    final s = await app.ensureSession(null);
    if (mounted) setState(() => _sessionId = s.id);
    _loadTitle();
  }
}

class _NoSession extends StatelessWidget {
  final VoidCallback onPick;
  const _NoSession({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_comment_outlined, size: 52, color: MinisTheme.textMuted),
          const SizedBox(height: 12),
          const Text('还没有激活的会话', style: TextStyle(color: MinisTheme.textMuted)),
          const SizedBox(height: 14),
          FilledButton(onPressed: onPick, child: const Text('新建会话')),
        ],
      ),
    );
  }
}
