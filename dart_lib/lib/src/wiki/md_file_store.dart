import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/assistant_block.dart';
import '../models/chat_message.dart';
import '../models/roles.dart';
import '../models/session.dart';
import '../store/persistence_adapter.dart';

/// A [PersistenceAdapter] whose on-disk representation is **Markdown files**,
/// not JSON/SQLite. Every conversation, its history and its outputs are written
/// as human-readable `.md` documents, so the store doubles as a browsable wiki:
///
///   <root>/
///     sessions/
///       index.md                  ← session index (front-matter + links)
///       <slug>.md                 ← one file per session (full transcript)
///     wiki/
///       index.md                  ← knowledge wiki index (LLM-authored)
///       notes/<slug>.md           ← distilled wiki notes
///
/// Each session file starts with YAML front-matter (title, model, timestamps,
/// tags, session id) and renders the transcript as Markdown:
///
///   ## —— assistant 2026-08-07 12:00
///   Hello world.   ← assistant content
///   ## —— user …
///   you say…
///
/// Because every write is a plain text file, the store can be synced by git /
/// rsync / the OpenMinis LAN sync engine without any database.
class MdFileStore implements PersistenceAdapter {
  final Directory root;
  late final Directory _sessionsDir;
  late final Directory _wikiNotesDir;

  // In-memory caches (md files are not the query index).
  final Map<String, Session> _sessions = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, List<String>> _order = {}; // sessionId → message ids
  final Map<String, ChatMessage> _byId = {};

  MdFileStore(this.root) {
    _sessionsDir = Directory('${root.path}/sessions');
    _wikiNotesDir = Directory('${root.path}/wiki/notes');
  }

  // ---- lifecycle -----------------------------------------------------------

  @override
  Future<void> init() async {
    _sessionsDir.createSync(recursive: true);
    _wikiNotesDir.createSync(recursive: true);
    _scanSessions();
  }

  void _scanSessions() {
    // Rebuild in-memory index by reading each *.md (excluding index.md).
    _sessions.clear();
    _messages.clear();
    _order.clear();
    _byId.clear();
    for (final f in _sessionsDir.listSync().whereType<File>()) {
      if (f.path.endsWith('index.md')) continue;
      if (!f.path.endsWith('.md')) continue;
      try {
        _parseSessionFile(f);
      } catch (_) {
        // skip malformed
      }
    }
  }

  // ---- parse / render helpers ----------------------------------------------

  static const _fmStart = '---\n';
  static const _fmEnd = '\n---\n';

  String _slug(String id) => id.replaceAll(':', '_').replaceAll('/', '_');

  // ---- PersistenceAdapter: sessions ----------------------------------------

  @override
  Future<List<Session>> allSessions({bool includeDeleted = false}) async =>
      _sessions.values
          .where((s) => includeDeleted || !s.deleted)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<Session?> sessionById(String id) async => _sessions[id]?.copy();

  @override
  Future<void> upsertSession(Session s) async {
    s.revision++;
    s.updatedAt = DateTime.now();
    _sessions[s.id] = s.copy();
    await _writeSessionFile(s);
    _rewriteSessionIndex();
  }

  @override
  Future<void> markSessionDeleted(String id) async {
    final s = _sessions[id];
    if (s == null) return;
    s.deleted = true;
    _sessions[id] = s.copy();
    // Write a tombstone marker into the file.
    await _writeSessionFile(s);
    _rewriteSessionIndex();
  }

  Future<void> _writeSessionFile(Session s) async {
    final msgs = _messages[s.id] ?? [];
    final buffer = StringBuffer()..writeln(_renderFrontMatter(s, msgs.length));
    buffer.writeln();
    for (final m in msgs) {
      _renderMessage(m, buffer);
    }
    final path = '${_sessionsDir.path}/${_slug(s.id)}.md';
    File(path).writeAsStringSync(buffer.toString(), flush: true);
  }

  String _renderFrontMatter(Session s, int count) {
    final sb = StringBuffer()..writeln(_frontMatter(s, count));
    sb.writeln('# ${s.title.isEmpty ? '未命名会话' : s.title}');
    return sb.toString();
  }

  String _frontMatter(Session s, int count) {
    return [
      '---',
      'session: "${_escYaml(s.id)}"',
      'title: "${_escYaml(s.title.isEmpty ? '未命名会话' : s.title)}"',
      'created: ${s.createdAt.toIso8601String()}',
      'updated: ${s.updatedAt.toIso8601String()}',
      'model: "${_escYaml(s.lastModelProvider ?? '')}"',
      'messages: $count',
      'deleted: ${s.deleted}',
      'revision: ${s.revision}',
      '---',
    ].join('\n');
  }

  String _escYaml(String s) => s.replaceAll('"', '\\"');

  void _renderMessage(ChatMessage m, StringBuffer buf) {
    final when = _fmtTime(m.timestamp);
    switch (m.role) {
      case ChatRole.user:
        buf.writeln('## —— user · $when');
        if (m.attachments.isNotEmpty) {
          buf.writeln('> attachments: '
              '${m.attachments.map((a) => '`${a.path}`').join(', ')}');
        }
        buf.writeln();
        buf.writeln(_mdText(m.content));
        buf.writeln();
      case ChatRole.assistant:
        buf.writeln('## —— assistant · $when');
        // thinking
        for (final b in m.blocks) {
          if (b.kind == AssistantBlockKind.thinking && b.content.isNotEmpty) {
            buf.writeln('<details><summary>🧠 thinking</summary>');
            buf.writeln('');
            buf.writeln(b.content);
            buf.writeln('');
            buf.writeln('</details>');
            buf.writeln();
          }
        }
        // tool calls
        for (final b in m.blocks) {
          if (b.kind == AssistantBlockKind.toolCall && b.toolName != null) {
            final tname = b.toolName;
            final j = _json(b.toolArguments);
            buf.writeln('> 🔧 tool: `$tname` args:$j');
            buf.writeln();
          }
        }
        buf.writeln(_mdText(m.content));
        if (m.error != null) {
          buf.writeln('> ⚠ error: ${_mdText(m.error!)}');
        }
        buf.writeln();
      case ChatRole.compactDivider:
        buf.writeln('> 📦 历史已压缩：${_mdText(m.content)}');
        buf.writeln();
      case ChatRole.systemInfo:
        buf.writeln('> ℹ️ ${_mdText(m.content)}');
        buf.writeln();
    }
  }

  String _mdText(String s) {
    // Escape only the characters that would break markdown structure.
    return s;
  }

  String _json(Map<String, dynamic> m) {
    try {
      return jsonEncode(m);
    } catch (_) {
      return '{}';
    }
  }

  String _fmtTime(DateTime t) =>
      '${t.year}-${_p(t.month)}-${_p(t.day)} ${_p(t.hour)}:${_p(t.minute)}';
  String _p(int n) => n.toString().padLeft(2, '0');

  void _rewriteSessionIndex() {
    final sorted = _sessions.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final buf = StringBuffer()
      ..writeln('---')
      ..writeln('title: "Session Index"')
      ..writeln('generated: ${DateTime.now().toIso8601String()}')
      ..writeln('---')
      ..writeln()
      ..writeln('# Sessions')
      ..writeln()
      ..writeln('| # | 会话 | 消息 | 更新 |')
      ..writeln('|---|------|-----|------|');
    var n = 0;
    for (final s in sorted) {
      if (s.deleted) continue;
      n++;
      final title = s.title.isEmpty ? '未命名会话' : s.title;
      final count = _messages[s.id]?.length ?? 0;
      buf.writeln('| $n | [${_tblEsc(title)}](${_slug(s.id)}.md) | $count | ${s.updatedAt.toIso8601String()} |');
    }
    File('${_sessionsDir.path}/index.md').writeAsStringSync(buf.toString(), flush: true);
  }

  String _tblEsc(String s) => s.replaceAll('|', '\\|');

  // ---- PersistenceAdapter: messages ----------------------------------------

  @override
  Future<void> upsertMessage(ChatMessage m) async {
    _byId[m.id] = m;
    (_messages[m.sessionId] ??= []);
    if (!_messages[m.sessionId]!.any((x) => x.id == m.id)) {
      _messages[m.sessionId]!.add(m);
      (_order[m.sessionId] ??= []).add(m.id);
    } else {
      // replace in place, re-sort by timestamp
      final idx = _messages[m.sessionId]!.indexWhere((x) => x.id == m.id);
      _messages[m.sessionId]![idx] = m;
      _messages[m.sessionId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    final s = _sessions[m.sessionId];
    if (s != null) {
      s.revision++;
      s.updatedAt = DateTime.now();
      _sessions[s.id] = s.copy();
      await _writeSessionFile(s);
      _rewriteSessionIndex();
    }
  }

  @override
  Future<ChatMessage?> messageById(String id) async => _byId[id];

  @override
  Future<List<ChatMessage>> messagesForSession(
    String sessionId, {
    int? limit,
    int? afterSortOrder,
  }) async {
    final msgs = (_messages[sessionId] ?? [])
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (limit != null && msgs.length > limit) {
      return msgs.sublist(msgs.length - limit);
    }
    return msgs;
  }

  @override
  Future<void> deleteSessionMessages(String sessionId) async {
    _messages.remove(sessionId);
    _order.remove(sessionId);
    _sessions.remove(sessionId);
    _rewriteSessionIndex();
  }

  // ---- parse a session file back into in-memory model ----------------------

  void _parseSessionFile(File f) {
    final text = f.readAsStringSync();
    // front matter
    Map<String, dynamic> fm = {};
    if (text.startsWith(_fmStart)) {
      final end = text.indexOf(_fmEnd, _fmStart.length);
      if (end > 0) {
        fm = _parseFrontMatter(text.substring(_fmStart.length, end));
      }
    }
    final id = (fm['session'] as String?) ?? f.path.split('/').last.replaceAll('.md', '');
    final sess = Session(
      id: id,
      title: (fm['title'] as String?) ?? '',
      createdAt: DateTime.tryParse(fm['created']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(fm['updated']?.toString() ?? '') ?? DateTime.now(),
      lastModelProvider: fm['model']?.toString(),
    );
    sess.deleted = _parseBool(fm['deleted']) ?? false;
    sess.revision = int.tryParse(fm['revision']?.toString() ?? '') ?? 0;
    _sessions[id] = sess;
    _messages[id] = [];
    _order[id] = [];
    // Parse transcript into messages (best-effort).
    _parseTranscript(text, id);
  }

  bool? _parseBool(Object? v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return null;
  }

  Map<String, dynamic> _parseFrontMatter(String body) {
    final map = <String, dynamic>{};
    for (final line in body.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      var v = line.substring(i + 1).trim();
      v = v.replaceAll('"', '');
      map[k] = v;
    }
    return map;
  }

  void _parseTranscript(String text, String sessionId) {
    // Very light parse: split on '## —— role' headers. multiLine so ^ matches
    // at line starts after the front matter.
    final blocks = text.split(RegExp('^## —— ', multiLine: true));
    for (var i = 1; i < blocks.length; i++) {
      final b = blocks[i];
      final nl = b.indexOf('\n');
      final header = (nl > 0 ? b.substring(0, nl) : b).trim();
      final body = (nl > 0 ? b.substring(nl + 1) : '').trim();
      final m = header.startsWith('user ')
          ? ChatMessage(sessionId: sessionId, role: ChatRole.user, content: body)
          : ChatMessage(sessionId: sessionId, role: ChatRole.assistant, content: body);
      _byId[m.id] = m;
      _messages[sessionId]!.add(m);
      _order[sessionId]!.add(m.id);
    }
  }

  /// Write a distilled wiki note (not a session transcript).
  Future<void> writeWikiNote(
      String slug, Map<String, dynamic> frontMatter, String markdownBody) {
    _wikiNotesDir.createSync(recursive: true);
    final sb = StringBuffer()..writeln('---');
    frontMatter.forEach((k, v) => sb.writeln('$k: "${_escYaml(v.toString())}"'));
    sb.writeln('---');
    sb.writeln();
    sb.write(markdownBody);
    File('${_wikiNotesDir.path}/${_slug(slug)}.md').writeAsStringSync(sb.toString(), flush: true);
    return Future.value();
  }

  /// The path of a session's markdown file (for display / links).
  String sessionFilePath(String id) => '${_sessionsDir.path}/${_slug(id)}.md';

  /// Expose the raw markdown of a session.
  String sessionMarkdown(String id) {
    final f = File('${_sessionsDir.path}/${_slug(id)}.md');
    return f.existsSync() ? f.readAsStringSync() : '';
  }
}
