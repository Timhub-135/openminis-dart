import 'dart:convert';

import 'package:http/http.dart' as http;

/// A wiki note as returned by the backend.
class WikiNoteSummary {
  final String slug;
  final String title;
  final List<String> tags;
  final String summary;
  const WikiNoteSummary({
    required this.slug,
    required this.title,
    required this.tags,
    required this.summary,
  });
}

/// Client for the OpenMinis wiki API (`/api/wiki*`).
///
/// The real Markdown backend (MdFileStore + MdWiki) runs on the local LAN
/// server; this client talks to it over HTTP so both the browser web app and
/// the desktop apps share the same wiki.
class WikiApi {
  /// Base URL of the backend, e.g. `http://127.0.0.1:8741`.
  final String baseUrl;
  final http.Client _client = http.Client();

  WikiApi({this.baseUrl = 'http://127.0.0.1:8741'});

  /// Fetch the wiki `index.md` (grouped-by-tag listing).
  Future<String?> fetchIndex() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/api/wiki'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final idx = d['index'];
      return idx is String ? idx : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch one wiki note's raw markdown.
  Future<String?> fetchNote(String slug) async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/api/wiki/note?slug=${Uri.encodeComponent(slug)}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final md = d['markdown'];
      return md is String ? md : null;
    } catch (_) {
      return null;
    }
  }

  /// Ask the backend to (re)build the wiki from all sessions.
  Future<String?> buildWiki() async {
    try {
      final r = await _client
          .post(Uri.parse('$baseUrl/api/wiki/build'))
          .timeout(const Duration(seconds: 240));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      return 'built ${d['built']}/${d['total']} · provider=${d['provider']}';
    } catch (e) {
      return '错误: $e';
    }
  }

  /// Distill just one session into a wiki note. Returns a human message.
  Future<String> distillSession(String sessionId) async {
    try {
      final r = await _client
          .post(Uri.parse('$baseUrl/api/wiki/session/$sessionId'))
          .timeout(const Duration(seconds: 120));
      if (r.statusCode != 200) {
        return '整理失败 (HTTP ${r.statusCode})';
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final built = (d['built'] as num?)?.toInt() ?? 0;
      final provider = d['provider'];
      return built > 0
          ? '已整理进 Wiki (provider: $provider)'
          : '会话为空，未整理';
    } catch (e) {
      return '错误: $e';
    }
  }
}
