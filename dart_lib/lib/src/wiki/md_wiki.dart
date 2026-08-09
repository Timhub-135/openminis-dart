import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/chat_message.dart';
import '../models/roles.dart';
import '../models/session.dart';
import '../providers/llm_client.dart';
import '../providers/llm_message.dart';
import '../tools/tool_registry.dart';
import 'md_file_store.dart';

/// A distilled wiki note produced from a conversation.
class WikiNote {
  final String slug;
  final String title;
  final String summary;
  final List<String> tags;
  final String body; // markdown
  final String sourceSessionId;

  WikiNote({
    required this.slug,
    required this.title,
    required this.summary,
    required this.tags,
    required this.body,
    required this.sourceSessionId,
  });
}

/// LLM-powered wiki organizer.
///
/// Turns raw conversation transcripts (stored as Markdown by [MdFileStore])
/// into a structured knowledge wiki:
///
///   * it asks an [LlmClient] to produce a short title, a summary, and tags
///     for a conversation (or a deterministic fallback if no client / key);
///   * it writes a noted `wiki/notes/<slug>.md` (front-matter + body);
///   * it maintains `wiki/index.md` — a top-level browse index of all notes,
///     grouped by tag, with cross-reference links back to the transcripts.
class MdWiki {
  final MdFileStore store;
  final LlmClient? llm;
  final LlmRequestConfig? config;
  final ToolRegistry? tools;

  MdWiki({required this.store, this.llm, this.config, this.tools});

  /// Generate a wiki note from one session. Returns null if empty.
  Future<WikiNote?> noteFromSession(Session s, List<ChatMessage> msgs) async {
    if (msgs.isEmpty || msgs.every((m) => m.role == ChatRole.user && m.content.isEmpty)) {
      return null;
    }
    final slug = _slugFromTitle(s.title.isEmpty ? 'session-${s.id.substring(0, 8)}' : s.title, s.id);
    final transcript = store.sessionMarkdown(s.id);
    if (transcript.isEmpty) return null;

    print('[wiki] distilling session ${s.id} -> $slug');
    final meta = await _summarize(transcript, s);

    final body = StringBuffer()
      ..writeln('# ${meta.title}')
      ..writeln()
      ..writeln(meta.summary)
      ..writeln()
      ..writeln('## Tags')
      ..writeln()
      ..writeln(meta.tags.map((t) => '`$t`').join(' '))
      ..writeln()
      ..writeln('## 会话原文')
      ..writeln()
      ..writeln('> 来自会话: [${s.title.isEmpty ? '未命名会话' : s.title}]'
          '(${_relSessionPath(s.id)})')
      ..writeln()
      ..writeln(_codeBlock(transcript));

    final note = WikiNote(
      slug: slug,
      title: meta.title,
      summary: meta.summary,
      tags: meta.tags,
      body: body.toString(),
      sourceSessionId: s.id,
    );
    await _storeNote(note);
    _rewriteIndex();
    return note;
  }

  Future<_Meta> _summarize(String transcript, Session s) async {
    // Try real LLM if a client + config are available and configured.
    if (llm != null && config != null && config!.hasKey) {
      try {
        final reply = await _askLlm(transcript, s);
        final parsed = _parseMeta(reply);
        if (parsed != null) return parsed;
      } catch (e) {
        print('[wiki] LLM summarization failed, falling back: $e');
      }
    }
    // Deterministic fallback: derive title/tags from the first user message.
    return _fallbackMeta(transcript, s);
  }

  Future<String> _askLlm(String transcript, Session s) async {
    final prompt = '''
你是一个知识整理助手。请把下面的会话整理成一段 Wiki 笔记，只输出 JSON，不要其他文字：
{"title":"简短标题","summary":"2-4句要点","tags":["标签1","标签2","标签3"]}

会话开始：
$transcript
''';
    final client = llm!;
    final out = StringBuffer();
    await for (final ev in client.complete(
      [LlmMessage.text('user', prompt)],
      config: config!,
      tools: const [],
    )) {
      if (ev is TextDelta) out.write(ev.text);
      if (ev is TurnFinished) out.write(ev.content);
    }
    return out.toString();
  }

  _Meta? _parseMeta(String reply) {
    final open = reply.indexOf('{');
    final close = reply.lastIndexOf('}');
    if (open < 0 || close <= open) return null;
    try {
      final map = (jsonDecode(reply.substring(open, close + 1)) as Map)
          .cast<String, dynamic>();
      final title = map['title']?.toString() ?? '未命名';
      final summary = map['summary']?.toString() ?? '';
      final tags = (map['tags'] as List?)?.map((t) => t.toString()).toList() ?? [];
      return _Meta(title: title, summary: summary, tags: tags);
    } catch (_) {
      return null;
    }
  }

  _Meta _fallbackMeta(String transcript, Session s) {
    // Derive: title = first non-empty user line; summary = deterministic.
    String title = s.title.isEmpty ? '会话整理' : s.title;
    final firstUser = transcript
        .split('\n')
        .where((l) => l.startsWith('## —— user'))
        .toList();
    if (firstUser.isNotEmpty) {
      final i = transcript.indexOf(firstUser.first);
      final rest = transcript.substring(i + firstUser.first.length);
      // Skip blank lines between the header and the message body.
      final firstBodyLine = rest.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (firstBodyLine.isNotEmpty) {
        final line = firstBodyLine.first.replaceAll('#', '').replaceAll('>', '').trim();
        if (line.isNotEmpty && line.length > 2) {
          title = line.length > 40 ? '${line.substring(0, 40)}…' : line;
        }
      }
    }
    final summary = '该会话包含 '
        '${RegExp(r'user ·').allMatches(transcript).length} 条用户消息与 '
        '${RegExp(r'assistant ·').allMatches(transcript).length} 条助手回复。'
        '（未配置 LLM 摘要，此为确定性降级。）';
    final tags = ['session', s.lastModelProvider ?? 'general'];
    return _Meta(title: title, summary: summary, tags: tags);
  }

  Future<void> _storeNote(WikiNote note) async {
    await store.writeWikiNote(note.slug, {
      'title': note.title,
      'summary': note.summary,
      'tags': note.tags.join(','),
      'session': note.sourceSessionId,
      'generated': DateTime.now().toIso8601String(),
    }, note.body);
  }

  void _rewriteIndex() {
    Directory('${store.root.path}/wiki').createSync(recursive: true);
    final notes = _listNotes();
    final byTag = <String, List<_NoteEntry>>{};
    for (final n in notes) {
      for (final t in n.tags) {
        (byTag[t] ??= []).add(n);
      }
    }
    final buf = StringBuffer()
      ..writeln('---')
      ..writeln('title: "OpenMinis Knowledge Wiki"')
      ..writeln('generated: ${DateTime.now().toIso8601String()}')
      ..writeln('---')
      ..writeln()
      ..writeln('# Wiki')
      ..writeln()
      ..writeln('由会话自动整理的 LLM 知识库。')
      ..writeln();

    final tagsSorted = byTag.keys.toList()..sort();
    for (final tag in tagsSorted) {
      buf.writeln('## `$tag`');
      buf.writeln();
      for (final e in byTag[tag]!) {
        buf.writeln('- [${e.title}](${e.slug}.md) — ${e.summary}');
      }
      buf.writeln();
    }
    if (notes.isEmpty) {
      buf.writeln('（还没有整理任何笔记。去聊几个会话，然后触发整理。）');
    }
    File('${store.root.path}/wiki/index.md').writeAsStringSync(buf.toString(), flush: true);
  }

  List<_NoteEntry> _listNotes() {
    final dir = Directory('${store.root.path}/wiki/notes');
    if (!dir.existsSync()) return [];
    final out = <_NoteEntry>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.md')) continue;
      final text = f.readAsStringSync();
      final slug = f.path.split('/').last.replaceAll('.md', '');
      String title = slug;
      List<String> tags = [];
      String summary = '';
      if (text.startsWith('---\n')) {
        final end = text.indexOf('\n---\n', 4);
        if (end > 0) {
          for (final line in text.substring(4, end).split('\n')) {
            final i = line.indexOf(':');
            if (i <= 0) continue;
            final k = line.substring(0, i).trim();
            var v = line.substring(i + 1).trim().replaceAll('"', '');
            if (k == 'title') {
              title = v;
            } else if (k == 'tags') {
              tags = v.split(',').where((x) => x.isNotEmpty).toList();
            } else if (k == 'summary') {
              summary = v;
            }
          }
        }
      }
      out.add(_NoteEntry(slug: slug, title: title, tags: tags, summary: summary));
    }
    out.sort((a, b) => a.title.compareTo(b.title));
    return out;
  }

  String _slugFromTitle(String title, String sessionId) {
    final slug = title.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-').replaceAll(RegExp(r'-+'), '-');
    // Use the last 8 chars of the id to keep slugs unique per session.
    final shortId = sessionId.length > 8
        ? sessionId.substring(sessionId.length - 8)
        : sessionId;
    return slug.isEmpty ? 'note-$shortId' : '$slug-$shortId';
  }

  String _relSessionPath(String id) => '../sessions/${_safe(id)}.md';
  String _safe(String id) => id.replaceAll(':', '_').replaceAll('/', '_');

  String _codeBlock(String s) {
    // Clip really long transcripts for note bodies.
    final clipped = s.length > 6000 ? '${s.substring(0, 6000)}\n…(截断)' : s;
    return '```markdown\n$clipped\n```';
  }
}

class _Meta {
  final String title;
  final String summary;
  final List<String> tags;
  _Meta({required this.title, required this.summary, required this.tags});
}

class _NoteEntry {
  final String slug;
  final String title;
  final List<String> tags;
  final String summary;
  _NoteEntry({required this.slug, required this.title, required this.tags, required this.summary});
}
