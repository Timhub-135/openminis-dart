import 'package:flutter/material.dart';
import '../../theme.dart';

/// Collapsible "thinking" block shown for an assistant's reasoning content.
/// Starts collapsed; taps to expand/collapse. When streaming, shows a pulsing
/// indicator until [done] is true.
class ThinkingBlock extends StatefulWidget {
  final String text;
  final bool done;
  const ThinkingBlock({super.key, required this.text, required this.done});

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      decoration: BoxDecoration(
        color: MinisTheme.panel2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: Colors.white24, width: 3)),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: _expanded ? _expandedBody() : collapsedHeader(),
        ),
      ),
    );
  }

  Widget collapsedHeader() {
    return Row(
      children: [
        const Icon(Icons.psychology_outlined, size: 15, color: MinisTheme.textMuted),
        const SizedBox(width: 6),
        if (!widget.done)
          const SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: MinisTheme.accent),
          )
        else
          const Icon(Icons.check_circle_outline, size: 14, color: MinisTheme.accentGreen),
        const SizedBox(width: 6),
        Text(
          widget.done ? '思考 · ${widget.text.length} 字' : '正在思考…',
          style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted),
        ),
        const Spacer(),
        const Icon(Icons.expand_more, size: 16, color: MinisTheme.textMuted),
      ],
    );
  }

  Widget _expandedBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.psychology_outlined, size: 15, color: MinisTheme.textMuted),
            const SizedBox(width: 6),
            Text(widget.done ? '思考过程' : '正在思考…', style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
            const Spacer(),
            const Icon(Icons.expand_less, size: 16, color: MinisTheme.textMuted),
          ],
        ),
        const SizedBox(height: 6),
        SelectableText(
          widget.text.isEmpty ? '(暂无内容)' : widget.text,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: MinisTheme.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
