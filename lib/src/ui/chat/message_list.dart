import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme.dart';
import 'assistant_bubble.dart';
import 'markdown_view.dart';
import 'thinking_block.dart';
import 'tool_chip.dart';
/// The scrollable message list for a chat: renders persisted messages plus a
/// live streaming assistant response driven by [AppState.streamEvents].
class MessageList extends StatefulWidget {
  final String sessionId;
  const MessageList({super.key, required this.sessionId});

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scroll = ScrollController();
  StreamSubscription<LiveEvent>? _sub;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  String? _error;

  // Live-turn state.
  bool _liveActive = false;
  String _liveText = '';
  String _liveThinking = '';
  final List<_LiveTool> _liveTools = [];
  bool _liveThinkingShown = false;
  int _liveTokIn = 0;
  int _liveTokOut = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<AppState>().streamEvents.listen(_onEvent);
  }

  @override
  void didUpdateWidget(MessageList old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId) {
      _liveReset();
      _load();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final msgs = await context.read<AppState>().store.messages(widget.sessionId);
      if (!mounted) return;
      setState(() { _messages = msgs; _loading = false; });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _liveReset() {
    _liveActive = false;
    _liveText = '';
    _liveThinking = '';
    _liveTools.clear();
    _liveThinkingShown = false;
  }

  void _onEvent(LiveEvent e) {
    if (!mounted) return;
    setState(() {
      _liveActive = true;
      switch (e) {
        case LiveText(:final delta):
          _liveText += delta;
        case LiveThinking(:final delta):
          _liveThinking += delta;
          _liveThinkingShown = true;
        case LiveToolStart(:final id, :final name):
          _liveTools.add(_LiveTool(id, name));
        case LiveToolEnd(:final id, :final ok, :final output):
          final t = _liveTools.where((t) => t.id == id).toList();
          if (t.isNotEmpty) {
            t.first.ok = ok;
            t.first.output = output;
            t.first.done = true;
          }
        case LiveUsage(:final input, :final output):
          _liveTokIn = input;
          _liveTokOut = output;
        case LiveTurnDone():
          _liveReset();
          _load();
      }
    });
    if (e is! LiveTurnDone) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: MinisTheme.accent));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: MinisTheme.danger)));
    }
    if (_messages.isEmpty && !_liveActive) {
      return const Center(
        child: Text('开始对话吧', style: TextStyle(color: MinisTheme.textMuted)),
      );
    }

    final itemCount = _messages.length + (_liveActive ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (i >= _messages.length) {
          return _liveBubble();
        }
        final m = _messages[i];
        return _messageRow(m);
      },
    );
  }

  Widget _messageRow(ChatMessage m) {
    switch (m.role) {
      case ChatRole.user:
        return _UserBubble(content: m.content, attachments: m.attachments);
      case ChatRole.assistant:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            child: AssistantBubble(message: m),
          ),
        );
      case ChatRole.compactDivider:
        return _CompactionDivider(summary: m.content);
      case ChatRole.systemInfo:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(m.content,
                style: const TextStyle(
                    color: MinisTheme.textMuted, fontSize: 12, fontStyle: FontStyle.italic)),
          ),
        );
    }
  }

  Widget _liveBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: MinisTheme.assistantBubble,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MinisTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_liveThinkingShown)
              ThinkingBlock(text: _liveThinking, done: false),
            if (_liveTools.isNotEmpty)
              Wrap(
                children: [
                  for (final t in _liveTools)
                    ToolChip(
                      name: t.name,
                      status: !t.done
                          ? ToolChipStatus.running
                          : (t.ok ? ToolChipStatus.success : ToolChipStatus.failed),
                      errorOutput: t.ok ? null : t.output,
                    ),
                ],
              ),
            if (_liveText.isNotEmpty)
              MarkdownView(data: _liveText),
            if (_liveText.isEmpty && _liveThinking.isEmpty && _liveTools.isEmpty)
              const Row(
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: MinisTheme.accent),
                  ),
                  SizedBox(width: 8),
                  Text('agent 正在思考…', style: TextStyle(fontSize: 13, color: MinisTheme.textMuted)),
                ],
              ),
            if (_liveTokIn > 0 || _liveTokOut > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '↥$_liveTokIn ↧$_liveTokOut tokens',
                  style: const TextStyle(fontSize: 10, color: MinisTheme.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveTool {
  final String id;
  final String name;
  bool done = false;
  bool ok = false;
  String output = '';
  _LiveTool(this.id, this.name);
}

class _UserBubble extends StatelessWidget {
  final String content;
  final List<AttachmentMeta> attachments;
  const _UserBubble({required this.content, this.attachments = const []});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: MinisTheme.userBubble,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final a in attachments)
                      Chip(
                        avatar: Icon(a.isImage ? Icons.image : Icons.insert_drive_file, size: 14),
                        label: Text(a.fileName, style: const TextStyle(fontSize: 10)),
                        backgroundColor: Colors.white10,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            Text(content, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _CompactionDivider extends StatelessWidget {
  final String summary;
  const _CompactionDivider({required this.summary});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MinisTheme.panel2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MinisTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.compress, size: 13, color: MinisTheme.textMuted),
                SizedBox(width: 4),
                Text('历史已压缩', style: TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
              ]),
              if (summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(summary,
                      style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted, fontStyle: FontStyle.italic)),
                ),
            ],
          ),
        ),
      );
}
