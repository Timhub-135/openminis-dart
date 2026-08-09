import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart';

import '../../theme.dart';
import 'markdown_view.dart';
import 'thinking_block.dart';
import 'tool_chip.dart';

/// Renders an assistant message bubble: optional thinking block, tool-call
/// chips, and the markdown-rendered body.
class AssistantBubble extends StatelessWidget {
  final ChatMessage message;
  const AssistantBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final blocks = message.blocks;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: MinisTheme.assistantBubble,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        border: Border.all(color: MinisTheme.border),
      ),
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thinking blocks (from stored blocks, if any).
          for (final b in blocks)
            if (b.kind == AssistantBlockKind.thinking && b.content.isNotEmpty)
              ThinkingBlock(text: b.content, done: true),
          // Tool calls.
          if (_toolCalls.isNotEmpty)
            Wrap(
              children: [
                for (final b in _toolCalls)
                  ToolChip(name: b.toolName ?? 'tool', status: ToolChipStatus.success),
              ],
            ),
          // Body.
          if (message.content.isNotEmpty)
            MarkdownView(data: message.content)
          else if (blocks.isEmpty)
            const Text('(空)', style: TextStyle(color: MinisTheme.textMuted, fontSize: 12)),
          // Error.
          if (message.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '⚠ ${message.error}',
                style: const TextStyle(color: MinisTheme.danger, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  List<AssistantBlock> get _toolCalls =>
      message.blocks.where((b) => b.kind == AssistantBlockKind.toolCall).toList();
}
