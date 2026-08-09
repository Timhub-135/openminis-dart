import 'dart:convert';
import 'dart:io';

import '../models/platform_info.dart';
import '../skills/soul_store.dart';
import 'tool.dart';

/// A minimal filesystem abstraction used by the file tools so the same tools
/// work on the browser (no `dart:io`) and native (real disk).
abstract class FsAdapter {
  Future<String> read(String path);
  Future<void> write(String path, String content);
  Future<bool> exists(String path);
  Future<List<String>> list(String dir);
}

/// Dependencies the "production" agent tools need. The host injects these so
/// the core stays transport- and platform-agnostic.
class AgentToolsDeps {
  final SoulStore souls;
  final FsAdapter fs;
  final String workspaceRoot; // maps to /var/minis/workspace
  const AgentToolsDeps({
    required this.souls,
    required this.fs,
    this.workspaceRoot = '',
  });
}

/// Builds the agent's productivity tools, mirroring the original
/// `+MemoryTools` / `+FileTools`:
///
///   • `memory_write` — store a persistent note (SoulStore).
///   • `memory_get`   — read notes / soul rules matching keywords.
///   • `file_read`    — read a text file.
///   • `file_write`   — write a text file.
///   • `file_edit`    — find-and-replace in an existing file (preserves the
///                      rest, like the original).
///   • `read_image`   — report image path + byte size (visual decoding is left
///                      to the model / a platform offload).
List<Tool> agentTools(AgentToolsDeps deps) {
  return [
    Tool(
      name: 'browser_use',
      description: 'Fetch a URL and extract readable text + links (lightweight browser tool).',
      params: const [
        ToolParam(name: 'url', description: 'The URL to fetch', required: true, type: 'string'),
        ToolParam(name: 'max_chars', description: 'Limit returned text length', required: false, type: 'integer'),
      ],
      category: 'browser',
      handler: (args) async {
        final url = (args['url'] as String? ?? '').trim();
        if (url.isEmpty) return const ToolResult.fail('url 不能为空');
        final maxChars = (args['max_chars'] as num?)?.toInt() ?? 3000;
        try {
          return ToolResult.ok(await BrowserAgent.fetchReadable(url, maxChars: maxChars));
        } catch (e) {
          return ToolResult.fail('抓取失败: $e');
        }
      },
    ),
    Tool(
      name: 'memory_write',
      description: 'Store a persistent note in long-term memory (survives sessions).',
      params: const [
        ToolParam(name: 'note', description: 'The fact/knowledge to remember', required: true),
        ToolParam(name: 'context', description: 'Optional short context label', required: false),
      ],
      category: 'memory',
      handler: (args) async {
        final note = (args['note'] as String? ?? '').trim();
        if (note.isEmpty) return const ToolResult.fail('note 不能为空');
        deps.souls.add(note, context: args['context'] as String?);
        return ToolResult.ok('已记住：$note', mutated: true);
      },
    ),
    Tool(
      name: 'memory_get',
      description: 'Find persistent memory notes whose content contains the given keywords.',
      params: const [
        ToolParam(name: 'keywords', description: 'Space-separated keywords to match', required: true),
      ],
      category: 'memory',
      handler: (args) async {
        final kw = (args['keywords'] as String? ?? '').trim();
        if (kw.isEmpty) return const ToolResult.fail('keywords 不能为空');
        final hits = deps.souls.search(kw);
        if (hits.isEmpty) return ToolResult.ok('(无匹配的记忆条目)');
        return ToolResult.ok(hits.join('\n'));
      },
    ),
    Tool(
      name: 'file_read',
      description: 'Read a UTF-8 text file from the workspace.',
      params: const [
        ToolParam(name: 'path', description: 'Path (relative to workspace root)', required: true),
      ],
      category: 'files',
      handler: (args) async {
        final p = (args['path'] as String? ?? '');
        if (p.isEmpty) return const ToolResult.fail('path 不能为空');
        try {
          return ToolResult.ok(await deps.fs.read(deps.workspaceRoot.isEmpty ? p : '${deps.workspaceRoot}/$p'));
        } catch (e) {
          return ToolResult.fail('读取失败: $e');
        }
      },
    ),
    Tool(
      name: 'file_write',
      description: 'Write UTF-8 content to a file in the workspace (creates/overwrites).',
      params: const [
        ToolParam(name: 'path', description: 'Path (relative to workspace root)', required: true),
        ToolParam(name: 'content', description: 'File content', required: true),
      ],
      category: 'files',
      handler: (args) async {
        final p = (args['path'] as String? ?? '');
        final c = (args['content'] as String? ?? '');
        if (p.isEmpty) return const ToolResult.fail('path 不能为空');
        try {
          await deps.fs.write(deps.workspaceRoot.isEmpty ? p : '${deps.workspaceRoot}/$p', c);
          return ToolResult.ok('已写入 $p', mutated: true);
        } catch (e) {
          return ToolResult.fail('写入失败: $e');
        }
      },
    ),
    Tool(
      name: 'file_edit',
      description: 'Replace an exact substring in an existing file (find-and-replace).',
      params: const [
        ToolParam(name: 'path', description: 'Path (relative to workspace root)', required: true),
        ToolParam(name: 'old_string', description: 'Exact text to find', required: true),
        ToolParam(name: 'new_string', description: 'Replacement text', required: true),
      ],
      category: 'files',
      handler: (args) async {
        final p = (args['path'] as String? ?? '');
        final oldS = (args['old_string'] as String? ?? '');
        final newS = (args['new_string'] as String? ?? '');
        if (p.isEmpty || oldS.isEmpty) return const ToolResult.fail('path 和 old_string 不能为空');
        final path = deps.workspaceRoot.isEmpty ? p : '${deps.workspaceRoot}/$p';
        try {
          final content = await deps.fs.read(path);
          final count = oldS.allMatches(content).length;
          if (count == 0) return ToolResult.fail('未找到要替换的文本，文件未改动');
          final updated = content.replaceFirst(oldS, newS); // one edit per call, like the original
          await deps.fs.write(path, updated);
          return ToolResult.ok('已替换 $count 处中的 1 处（其余请再次调用）', mutated: true);
        } catch (e) {
          return ToolResult.fail('编辑失败: $e');
        }
      },
    ),
    Tool(
      name: 'read_image',
      description: 'Report the size/path of an image so the model can reason about it.',
      params: const [
        ToolParam(name: 'path', description: 'Image path', required: true),
      ],
      category: 'media',
      handler: (args) async {
        final p = (args['path'] as String? ?? '');
        if (p.isEmpty) return const ToolResult.fail('path 不能为空');
        try {
          final content = await deps.fs.read(p); // bytes as latin-1 string
          return ToolResult.ok('图像: $p · ${content.length} bytes (如需视觉解码请在支持多模态的模型/host 中使用)');
        } catch (e) {
          return ToolResult.fail('读取图像失败: $e');
        }
      },
    ),
  ];
}

/// A minimal "browser" tool implementation: fetches a URL over HTTP(S) and
/// strips HTML tags into readable text + extracts links. This is a pragmatic
/// stand-in for full browser automation (which needs an external browser). It
/// works on native (dart:io) and reports unavailable on the web.
class BrowserAgent {
  static const _timeout = Duration(seconds: 20);

  static Future<String> fetchReadable(String url, {int maxChars = 3000}) async {
    if (PlatformInfo.isWeb) {
      return '(browser_use 在 web 端不可用——请在本机/桌面端使用抓取工具。)';
    }
    final http = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await http.getUrl(Uri.parse(url));
      req.headers.set('accept', 'text/html,application/xhtml+xml');
      req.headers.set('user-agent', 'OpenMinisAgent/0.1');
      final resp = await req.close().timeout(_timeout);
      final bytes = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final html = utf8.decode(bytes, allowMalformed: true);
      return _strip(html, maxChars);
    } finally {
      http.close(force: true);
    }
  }

  static String _strip(String html, int maxChars) {
    final titleMatch =
        RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html);
    final title = titleMatch?.group(1)?.trim() ?? '';
    final links = <String>[];
    for (final m in RegExp(r'<a\s[^>]*href="([^"]+)"[^>]*>(.*?)</a>', caseSensitive: false)
        .allMatches(html)) {
      final href = m.group(1) ?? '';
      final text = _tags(m.group(2) ?? '').trim();
      if (href.isNotEmpty && text.isNotEmpty && links.length < 20) {
        links.add('$text -> $href');
      }
    }
    var body = html
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
    body = _tags(body);
    body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.length > maxChars) body = '${body.substring(0, maxChars)}…';
    final buf = StringBuffer();
    if (title.isNotEmpty) buf.writeln('# $title');
    if (body.isNotEmpty) buf.writeln(body);
    if (links.isNotEmpty) {
      buf.writeln();
      buf.writeln('## 链接');
      links.forEach(buf.writeln);
    }
    return buf.toString().trim();
  }

  static String _tags(String s) => s.replaceAll(RegExp(r'<[^>]+>'), ' ');
}
