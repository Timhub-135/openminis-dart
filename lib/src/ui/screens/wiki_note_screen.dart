import 'package:flutter/material.dart';

import '../../services/wiki_api.dart';
import '../../theme.dart';
import '../widgets/minis_app_bar.dart';
import '../chat/markdown_view.dart';

/// Displays a single wiki note's full markdown (title, tags, body).
class WikiNoteScreen extends StatefulWidget {
  final WikiApi api;
  final String slug;
  const WikiNoteScreen({super.key, required this.api, required this.slug});

  @override
  State<WikiNoteScreen> createState() => _WikiNoteScreenState();
}

class _WikiNoteScreenState extends State<WikiNoteScreen> {
  String? _md;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final md = await widget.api.fetchNote(widget.slug);
    if (!mounted) return;
    setState(() { _md = md; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: 'Wiki 笔记'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: MinisTheme.accent))
          : _md == null
              ? const Center(child: Text('笔记不存在', style: TextStyle(color: MinisTheme.textMuted)))
              : _NoteBody(markdown: _md!),
    );
  }
}

class _NoteBody extends StatelessWidget {
  final String markdown;
  const _NoteBody({required this.markdown});

  @override
  Widget build(BuildContext context) {
    final parsed = _parseNote(markdown);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(parsed.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        if (parsed.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (final t in parsed.tags)
                Chip(
                  label: Text(t, style: const TextStyle(fontSize: 11)),
                  backgroundColor: MinisTheme.panel2,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Divider(color: MinisTheme.border),
        const SizedBox(height: 10),
        // Render the note body (post-front-matter markdown).
        MarkdownView(data: parsed.body, baseStyle: const TextStyle(fontSize: 14, height: 1.7)),
        const SizedBox(height: 20),
      ],
    );
  }

  _ParsedNote _parseNote(String full) {
    String title = '笔记';
    final tags = <String>[];
    String body = full;
    if (full.startsWith('---\n')) {
      final end = full.indexOf('\n---\n', 4);
      if (end > 0) {
        final fm = full.substring(4, end);
        for (final line in fm.split('\n')) {
          final i = line.indexOf(':');
          if (i <= 0) continue;
          final k = line.substring(0, i).trim();
          var v = line.substring(i + 1).trim().replaceAll('"', '');
          if (k == 'title') {
            title = v;
          } else if (k == 'tags') {
            tags.addAll(v.split(',').where((x) => x.isNotEmpty));
          }
        }
        body = full.substring(end + 6);
      }
    }
    return _ParsedNote(title: title, tags: tags, body: body);
  }
}

class _ParsedNote {
  final String title;
  final List<String> tags;
  final String body;
  _ParsedNote({required this.title, required this.tags, required this.body});
}
