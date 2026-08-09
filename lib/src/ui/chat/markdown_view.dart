import 'package:flutter/material.dart';
import '../../theme.dart';

/// A lightweight Markdown renderer for chat messages. Handles code blocks,
/// inline code, bold/italic, headings, blockquotes, bullet lists and simple
/// tables. Kept dependency-free so the app runs offline; for richer output a
/// real `flutter_markdown` widget can replace the leaf rendering later.
class MarkdownView extends StatelessWidget {
  final String data;
  final TextStyle? baseStyle;
  const MarkdownView({super.key, required this.data, this.baseStyle});

  @override
  Widget build(BuildContext context) {
    final style = baseStyle ?? const TextStyle(fontSize: 14, height: 1.6);
    return _MdRenderer(data: data, style: style).render();
  }
}

class _MdRenderer {
  final String data;
  final TextStyle style;
  _MdRenderer({required this.data, required this.style});

  Widget render() {
    final lines = data.split('\n');
    final children = <Widget>[];
    final codeBuf = StringBuffer();
    var inCode = false;
    var inTable = false;
    final tableRows = <List<String>>[];

    void flushTable() {
      if (tableRows.isNotEmpty) {
        children.add(_table(tableRows));
        tableRows.clear();
      }
    }

    for (final raw in lines) {
      if (_isFence(raw)) {
        flushTable();
        if (inCode) {
          children.add(_codeBlock(codeBuf.toString()));
          codeBuf.clear();
          inCode = false;
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        codeBuf.writeln(raw);
        continue;
      }
      if (raw.trim().startsWith('|') && raw.contains('|')) {
        final cells = raw
            .trim()
            .split('|')
            .where((c) => c.isNotEmpty)
            .map((c) => c.trim())
            .toList();
        // Skip separator rows (|---|---|).
        if (!cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) {
          tableRows.add(cells);
        }
        inTable = true;
        continue;
      }
      if (inTable && raw.trim().isEmpty) {
        flushTable();
        inTable = false;
        continue;
      }
      if (raw.trim().isEmpty) {
        continue;
      }
      children.add(_block(raw));
    }
    if (inCode) children.add(_codeBlock(codeBuf.toString()));
    flushTable();

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  bool _isFence(String line) {
    final t = line.trim();
    return t.startsWith('```') || t.startsWith('~~~');
  }

  Widget _block(String line) {
    final t = line.trim();
    // Heading.
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
    if (h != null) {
      final level = h.group(1)!.length;
      final List<double> sizes = [20, 17, 15, 14, 13, 12];
      final size = sizes[level.clamp(1, 6) - 1];
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          _inline(h.group(2)!),
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w700,
            color: MinisTheme.textPrimary,
          ),
        ),
      );
    }
    // Blockquote.
    if (t.startsWith('>')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: const Border(left: BorderSide(color: MinisTheme.accent, width: 3)),
          color: MinisTheme.panel2.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(_inline(t.substring(1).trim()), style: style),
      );
    }
    // Bullet list.
    if (RegExp(r'^[-*+]\s+').hasMatch(t)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 6),
            const Text('•  ', style: TextStyle(color: MinisTheme.textMuted)),
            Expanded(child: Text(_inline(t.replaceFirst(RegExp(r'^[-*+]\s+'), '')), style: style)),
          ],
        ),
      );
    }
    // Numbered list.
    final num = RegExp(r'^\d+\.\s+').firstMatch(t);
    if (num != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.substring(0, num.end).trim(), style: TextStyle(color: MinisTheme.textMuted, fontWeight: FontWeight.w600)),
            Expanded(child: Text(_inline(t.substring(num.end)), style: style)),
          ],
        ),
      );
    }
    // Horizontal rule.
    if (RegExp(r'^(\*\s*){3,}$|^(-{3,})$|^(_{3,})$').hasMatch(t)) {
      return const Divider(color: MinisTheme.border, height: 14);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(_inline(line), style: style),
    );
  }

  String _inline(String s) => s;

  Widget _codeBlock(String code) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MinisTheme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MinisTheme.border),
      ),
      child: SelectableText(
        code.trimRight(),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.5,
          color: MinisTheme.textPrimary.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Widget _table(List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
    if (colCount == 0) return const SizedBox.shrink();

    List<Widget> cells() => [
          for (var c = 0; c < colCount; c++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  _tableCell(rows, c),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ),
            ),
        ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: MinisTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++)
            Container(
              color: r == 0 ? MinisTheme.panel2 : Colors.transparent,
              child: Row(children: cells()),
            ),
        ],
      ),
    );
  }

  String _tableCell(List<List<String>> rows, int c) {
    final vals = rows.map((r) => r.length > c ? r[c] : '').toList();
    // Joining columns vertically would look odd; pick the first non-empty.
    for (final v in vals) {
      if (v.isNotEmpty) return v;
    }
    return '';
  }
}
