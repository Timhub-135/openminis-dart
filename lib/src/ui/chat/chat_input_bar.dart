import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart';

import '../../theme.dart';

/// The chat input bar: attachment button, multi-line text field, send button.
/// Grows with content (Shift+Enter = newline, Enter = send).
class ChatInputBar extends StatefulWidget {
  final bool busy;
  final ValueChanged<String> onSubmit;
  final ValueChanged<List<AttachmentMeta>>? onAttach;

  const ChatInputBar({
    super.key,
    required this.busy,
    required this.onSubmit,
    this.onAttach,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final _attachmentItems = <AttachEntry>[];

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: MinisTheme.panel,
        border: Border(top: BorderSide(color: MinisTheme.border)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachmentItems.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < _attachmentItems.length; i++)
                    InputChip(
                      label: Text(_attachmentItems[i].name,
                          style: const TextStyle(fontSize: 11)),
                      onDeleted: () => setState(() => _attachmentItems.removeAt(i)),
                      deleteIconColor: MinisTheme.textMuted,
                    ),
                ],
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '添加附件',
                  icon: const Icon(Icons.attach_file),
                  onPressed: widget.onAttach == null ? null : _pickAttach,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 14),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: '给 agent 发消息…',
                      hintStyle: const TextStyle(color: MinisTheme.textMuted),
                      suffixIcon: _controller.text.isNotEmpty
                          ? TextButton(
                              onPressed: _send,
                              child: const Text('发送', style: TextStyle(fontSize: 12)),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                widget.busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: MinisTheme.accent),
                        ),
                      )
                    : IconButton.filled(
                        tooltip: '发送',
                        onPressed: _canSend ? _send : null,
                        icon: const Icon(Icons.send),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSend =>
      _controller.text.trim().isNotEmpty && !widget.busy;

  void _pickAttach() {
    // Real file/photo picking requires package:file_picker / image_picker.
    // This scaffold shells out: for now just notify parent with empty list.
    widget.onAttach?.call(const []);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('附件选择器需要 file_picker 插件，当前为占位。'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class AttachEntry {
  final String name;
  final AttachmentMeta? meta;
  const AttachEntry(this.name, [this.meta]);
}
