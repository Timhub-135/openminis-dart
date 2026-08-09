import 'package:flutter/material.dart';

import '../../services/wiki_api.dart';
import '../../theme.dart';
import '../widgets/minis_app_bar.dart';
import 'wiki_note_screen.dart';

/// Wiki index screen: browse the LLM-distilled knowledge wiki, grouped by tag.
/// Shows the `wiki/index.md` rendered from the real Markdown backend.
class WikiScreen extends StatefulWidget {
  final WikiApi api;
  const WikiScreen({super.key, required this.api});

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  String? _index;
  bool _loading = true;
  bool _building = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final idx = await widget.api.fetchIndex();
    if (!mounted) return;
    setState(() {
      _index = idx;
      _loading = false;
      if (idx == null) _error = '无法连接后端，或 wiki 尚未生成。';
    });
  }

  Future<void> _build() async {
    setState(() => _building = true);
    final msg = await widget.api.buildWiki();
    if (!mounted) return;
    setState(() => _building = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? '整理完成'), duration: const Duration(seconds: 2)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(
        title: 'Wiki · 知识库',
        actions: [
          IconButton(
            tooltip: '重新整理',
            icon: _building
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.smart_toy_outlined),
            onPressed: _building ? null : _build,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: MinisTheme.accent))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _WikiIndexView(indexMarkdown: _index!, onOpenNote: _openNote),
    );
  }

  void _openNote(String slug) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WikiNoteScreen(api: widget.api, slug: slug),
    ));
  }
}

/// Renders the index.md and makes each wiki-note link tappable.
class _WikiIndexView extends StatelessWidget {
  final String indexMarkdown;
  final ValueChanged<String> onOpenNote;
  const _WikiIndexView({required this.indexMarkdown, required this.onOpenNote});

  @override
  Widget build(BuildContext context) {
    final sections = _parseIndex(indexMarkdown);
    if (sections.isEmpty) {
      return const Center(
        child: Text('还没有 wiki。点右上角开始整理。',
            style: TextStyle(color: MinisTheme.textMuted)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text('由会话自动整理的 LLM 知识库（真实 Markdown 文件存储）',
              style: TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
        ),
        for (final sec in sections) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '# ${sec.tag}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: MinisTheme.accent),
            ),
          ),
          for (final n in sec.notes)
            _noteTile(context, n),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _noteTile(BuildContext context, _IndexNote n) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.description_outlined, color: MinisTheme.accent),
        title: Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: n.summary.isEmpty
            ? null
            : Text(n.summary, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: MinisTheme.textMuted),
        onTap: () => onOpenNote(n.slug),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48, color: MinisTheme.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: MinisTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('重试')),
          ]),
        ),
      );
}

// ---- index.md parser ------------------------------------------------------

class _IndexSection {
  final String tag;
  final List<_IndexNote> notes;
  _IndexSection(this.tag, this.notes);
}

class _IndexNote {
  final String title;
  final String slug;
  final String summary;
  _IndexNote(this.title, this.slug, this.summary);
}

List<_IndexSection> _parseIndex(String md) {
  final sections = <_IndexSection>[];
  _IndexSection? current;

  for (final line in md.split('\n')) {
    final tagMatch = RegExp(r'^##\s+`([^`]+)`').firstMatch(line);
    if (tagMatch != null) {
      current = _IndexSection(tagMatch.group(1)!, []);
      sections.add(current);
      continue;
    }
    if (current == null) continue;
    // - [title](slug.md) — summary
    final n = RegExp(r'^- \[([^\]]+)\]\(([^)]+)\.md\)\s*(?:—\s*(.*))?$').firstMatch(line.trim());
    if (n != null) {
      var summary = n.group(3)?.trim() ?? '';
      // The summary may repeat; keep first ~90 chars.
      if (summary.length > 90) summary = '${summary.substring(0, 90)}…';
      current.notes.add(_IndexNote(n.group(1)!, n.group(2)!, summary));
    }
  }
  return sections;
}
