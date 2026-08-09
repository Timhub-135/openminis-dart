import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openminis_core/openminis.dart' as core;

/// ---------------------------------------------------------------------------
/// OpenMinis · Dart — complete Web app server.
///
/// Serves the full agent as a LAN web app: an interactive three-panel UI that
/// fronts the real Dart core (store, agent loop, tools, sandbox, memory,
/// skills, sync). Streams agent output to the browser over Server-Sent Events
/// so thinking / tool calls / text land live.
///
/// Endpoints:
///   GET  /                       full web UI (server/web/index.html)
///   GET  /api/health             health
///   GET  /api/providers          configured providers + readiness
///   GET/POST /api/sessions       session list / create
///   DELETE /api/session/<id>     delete a session (sync tombstone)
///   GET   /api/session/<id>/messages
///   POST /api/chat               SSE stream: runs the AgentLoop, pushing
///                                user|thinking|text|tool_start|tool_end|
///                                usage|done|error events to the browser
///   GET  /api/tools              registered tools + availability
///   GET  /api/memory             memory notes + soul rules
///   GET  /api/sync/status        sync engine state
///   POST /api/sync/start         start cross-platform sync
/// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 8741 : 8741;
  final dataDir = args.length > 1
      ? args[1]
      : '${Directory.systemTemp.path}/openminis_web';
  final server = WebAppServer(port: port, dataDir: dataDir);
  await server.serve();
}

class WebAppServer {
  final int port;
  final String dataDir;

  late final core.ChatStore store;
  late final core.SoulStore souls;
  late final core.SkillStore skills;
  late final core.ToolRegistry tools;
  late final core.JsonFileStore jsonStore;
  core.MdFileStore? mdStore;
  core.MdWiki? wiki;
  late HttpServer server;
  late String deviceId;

  core.SyncEngine? _sync;
  bool _syncError = false;

  WebAppServer({required this.port, required this.dataDir});

  Future<void> serve() async {
    deviceId = 'web-${Platform.localHostname.isNotEmpty ? Platform.localHostname : 'host'}';
    _initState();

    server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    server.listen(_handle);
    server.idleTimeout = const Duration(minutes: 15);

    final lan = await _lanAddresses();
    print('───────────────────────────────────────────');
    print('  OpenMinis · Dart Web App');
    print('  local:   http://127.0.0.1:$port');
    print('  LAN:');
    for (final iface in lan) {
      print('     http://$iface:$port  (浏览器访问)');
    }
    print('  data:    $dataDir');
    print('───────────────────────────────────────────');
  }

  void _initState() {
    // The server is a native host; tell the web-safe PlatformInfo so tools
    // (e.g. browser_use, env lookup) take the native path.
    core.PlatformInfo.setPlatformInfo(
        os: Platform.operatingSystem, isWeb: false);
    jsonStore = core.JsonFileStore(Directory('$dataDir/store'));
    _await(jsonStore.init());
    store = core.ChatStore(jsonStore);

    // Real Markdown-file backend: every conversation is written as a `.md` and
    // an LLM wiki can distill it into a browsable knowledge base.
    mdStore = core.MdFileStore(Directory('$dataDir/markdown'));
    try {
      _await(mdStore!.init());
    } catch (_) {}
    souls = core.SoulStore();
    skills = core.SkillStore();
    tools = core.ToolRegistry();

    tools.registerAll(core.builtinTools());
    // Memory / file / browser tools (agent productivity).
    tools.registerAll(core.agentTools(
      core.AgentToolsDeps(souls: souls, fs: _DiskFs(root: '$dataDir/workspace')),
    ));

    // Linux shell sandbox: Docker on Windows/Linux, Termux on Android.
    final sandbox = core.SandboxFactory.create(
        hostMinisDir: Platform.operatingSystem == 'windows'
            ? '$dataDir/minis'
            : '$dataDir/bridge');
    tools.registerAll(core.sandboxTools(sandbox));
  }

  // ---- HTTP routing --------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    // CORS: allow the Flutter web app (on a different port) to call this API.
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS');
    req.response.headers.set('Access-Control-Allow-Headers', 'content-type');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }
    final path = req.uri.path;
    try {
      if (path == '/' || path == '/index.html') {
        await _serveWebUi(req);
        return;
      }
      if (path == '/api/health') { _json(req, {'ok': true, 'deviceId': deviceId}); return; }
      if (path == '/api/providers') { await _serveProviders(req); return; }
      if (path == '/api/tools') { await _serveTools(req); return; }
      if (path == '/api/memory') { await _serveMemory(req); return; }
      if (path == '/api/sync/status') { _serveSyncStatus(req); return; }
      if (path == '/api/sync/start' && req.method == 'POST') { await _startSync(req); return; }
      if (path == '/api/sessions') {
        if (req.method == 'GET') { await _serveSessions(req); return; }
        if (req.method == 'POST') { await _createSession(req); return; }
      }
      if (path.startsWith('/api/session/')) {
        final segs = path.split('/'); // /api/session/<id>/...
        if (segs.length == 5 && segs[4] == 'messages') { await _serveMessages(req, segs[3]); return; }
        if (segs.length == 4 && req.method == 'DELETE') { await _deleteSession(req, segs[3]); return; }
      }
      if (path == '/api/chat' && req.method == 'POST') { await _serveChat(req); return; }
      if (path == '/api/wiki' && req.method == 'GET') { await _serveWiki(req); return; }
      if (path == '/api/wiki/build' && req.method == 'POST') { await _serveWikiBuild(req); return; }
      if (path.startsWith('/api/wiki/session/') && req.method == 'POST') {
        final segs = path.split('/'); // /api/wiki/session/<id>
        if (segs.length == 5) { await _serveWikiSession(req, segs[4]); return; }
      }
      if (path == '/api/wiki/note' && req.method == 'GET') { await _serveWikiNote(req); return; }

      _json(req, {'error': 'not found'}, 404);
    } catch (e, st) {
      try { _json(req, {'error': '$e', 'stack': '$st'}, 500); } catch (_) {}
    }
  }

  // ---- static UI -----------------------------------------------------------

  Future<void> _serveWebUi(HttpRequest req) async {
    final file = File('${dirOfScript().path}/index.html');
    var html = '';
    if (file.existsSync()) {
      html = file.readAsStringSync();
    } else {
      html = await _bootstrapWebUi();
    }
    html = html.replaceFirst('id="deviceId">web · dart</small>',
        'id="deviceId">$deviceId</small>');
    req.response.headers.contentType = ContentType.html;
    req.response.write(html);
    await req.response.close();
  }

  Future<String> _bootstrapWebUi() async {
    // Fallback if web/index.html is missing: a minimal but functional UI.
    return '<!doctype html><html lang="zh"><meta charset="utf-8">'
        '<title>OpenMinis</title><body style="background:#0c1018;color:#e8ecf3;font-family:sans-serif">'
        '<h2>OpenMinis · $deviceId</h2>'
        '<p>web/index.html 未找到。完整界面在 server/web/index.html。</p></body></html>';
  }

  Directory dirOfScript() {
    var d = Directory.current;
    for (var i = 0; i < 4; i++) {
      final candidate = Directory('${d.path}/web');
      if (candidate.existsSync()) return candidate;
      d = d.parent;
    }
    return Directory.current;
  }

  // ---- REST ----------------------------------------------------------------

  void _json(HttpRequest req, Object body, [int status = 200]) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    req.response.close();
  }

  Future<Map<String, dynamic>?> _readBody(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    if (body.isEmpty) return {};
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _serveSessions(HttpRequest req) async {
    final sessions = await store.sessions();
    _json(req, {
      'sessions': [
        for (final s in sessions)
          {
            'id': s.id,
            'title': s.title.isEmpty ? '未命名会话' : s.title,
            'messageCount': (await store.messages(s.id)).length,
            'updatedAt': s.updatedAt.toIso8601String(),
          }
      ],
    });
  }

  Future<void> _createSession(HttpRequest req) async {
    final s = await store.ensureSession(null);
    _json(req, {'session': {'id': s.id, 'title': s.title}}, 201);
  }

  Future<void> _deleteSession(HttpRequest req, String id) async {
    await store.deleteSession(id);
    _backlinkDeleteSync();
    _json(req, {'ok': true});
  }

  Future<void> _serveMessages(HttpRequest req, String id) async {
    final msgs = await store.messages(id);
    _json(req, {
      'messages': [
        for (final m in msgs)
          {
            'id': m.id,
            'role': m.role.name,
            'content': m.content,
            'meta':
                m.role == core.ChatRole.compactDivider ? '历史已压缩（摘要）' : null,
          }
      ],
    });
  }

  Future<void> _serveTools(HttpRequest req) async {
    _json(req, {
      'tools': [
        for (final t in tools.all)
          {
            'name': t.name,
            'category': t.category,
            'description': t.description,
            'available': true,
          }
      ],
    });
  }

  Future<void> _serveMemory(HttpRequest req) async {
    _json(req, {
      'rules': souls.globalRules,
      'notes': souls.memory.take(40).map((m) => m.text).toList(),
    });
  }

  void _serveSyncStatus(HttpRequest req) {
    _json(req, {
      'deviceId': deviceId,
      'enabled': _sync != null,
      'error': _syncError,
      'message': _sync == null
          ? '未启动'
          : (_syncError ? '异常' : '运行中（LAN :8742）'),
    });
  }

  Future<void> _startSync(HttpRequest req) async {
    if (_sync != null) { _json(req, {'ok': true, 'message': '已在运行'}); return; }
    final transport = core.LanSyncTransport(
        baseUrl: 'http://127.0.0.1:8742', deviceId: deviceId);
    _sync = core.SyncEngine(
      config: const core.SyncConfig(mode: core.SyncTransportMode.lan, port: 8742),
      transport: transport,
      store: store,
      adapter: jsonStore,
      deviceId: deviceId,
    );
    _sync!.updates.listen((e) {
      if (e is core.SyncError) {
        _syncError = true;
      } else if (e is core.SyncCompleted) {
        _syncError = false;
      }
    });
    // Try to also serve as the hub on :8742 (best effort).
    unawaited(_serveHub());
    await _sync!.init();
    _json(req, {'ok': true, 'message': '同步已启动（LAN :8742）'});
  }

  Future<void> _serveHub() async {
    try {
      final t = _sync!.transport as core.LanSyncTransport;
      await t.serve(port: 8742);
    } catch (_) {}
  }

  void _backlinkDeleteSync() {
    final s = _sync;
    if (s != null) unawaited(s.reconcile());
  }

  Future<void> _serveProviders(HttpRequest req) async {
    final defs = [
      ('anthropic', 'anthropic', 'ANTHROPIC_API_KEY', 'Claude'),
      ('openai', 'openai', 'OPENAI_API_KEY', 'GPT'),
      ('gemini', 'gemini', 'GOOGLE_API_KEY', 'Gemini'),
      ('openrouter', 'openrouter', 'OPENROUTER_API_KEY', 'OpenRouter'),
      ('kimi', 'kimi', 'KIMI_API_KEY', 'Kimi'),
      ('xai', 'xai', 'XAI_API_KEY', 'xAI'),
      ('antigravity', 'antigravity', 'ANTIGRAVITY_API_KEY', 'Antigravity'),
    ];
    _json(req, {
      'providers': [
        for (final (id, _, keyEnv, label) in defs)
          {
            'id': id,
            'label': label,
            'ready': core.SecretResolver.has(keyEnv),
          }
      ],
    });
  }

  // ---- chat (SSE) ----------------------------------------------------------

  Future<void> _serveChat(HttpRequest req) async {
    final body = await _readBody(req);
    final text = (body?['text'] as String? ?? '').trim();
    if (text.isEmpty) { _json(req, {'error': 'text required'}, 400); return; }

    final session = await store.ensureSession(body?['sessionId'] as String?);

    final provider = (body?['provider'] as String?) ?? 'auto';
    final client = _pickClient(provider);
    final config = _pickConfig(provider);

    req.response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
    req.response.headers.set('Cache-Control', 'no-cache');
    req.response.headers.set('Connection', 'keep-alive');
    req.response.statusCode = 200;
    final sink = _makeSse(req.response);

    _sse(sink, 'user', {'sessionId': session.id});

    final loop = core.AgentLoop(
      store: store,
      tools: tools,
      client: client,
      config: config,
      listener: _listenerToSse(sink),
    );
    try {
      final snippet = text.length > 20 ? text.substring(0, 20) : text;
      print('[chat] running turn: "$snippet"');
      final result = await loop.run(session.id, text);
      print('[chat] turn done, writing done event');
      _mirrorToMarkdown(session.id);
      // Auto-title the session (deterministic fallback when no real LLM).
      try {
        final tg = core.TitleGenerator(
          store: store,
          llm: _pickClient(_firstReadyProvider()),
          config: _pickConfig(_firstReadyProvider()),
        );
        await tg.ensureTitle(session.id);
      } catch (_) {}
      _sse(sink, 'done', {
        'ok': result.completed,
        'errors': result.errors,
        'usage': result.usage.toJson(),
      });
    } catch (e) {
      print('[chat] error: $e');
      _sse(sink, 'error', {'error': '$e'});
    } finally {
      await sink.close();
    }
  }

  /// Mirror a session + its messages into the Markdown-file backend so every
  /// conversation is persisted as a human-readable `.md` (the "real md store").
  Future<void> _mirrorToMarkdown(String sessionId) async {
    final md = mdStore;
    if (md == null) return;
    final s = await store.adapter.sessionById(sessionId);
    final msgs = await store.messages(sessionId);
    if (s == null) return;
    try {
      await md.upsertSession(s);
      for (final m in msgs) {
        await md.upsertMessage(m);
      }
    } catch (e) {
      print('[wiki] mirror to markdown failed: $e');
    }
  }

  _SseSink _makeSse(HttpResponse resp) => _SseSink(resp);

  void _sse(_SseSink sink, String event, Map<String, dynamic> data) {
    sink.write(event, data);
  }

  core.AgentTurnListener _listenerToSse(_SseSink sink) {
    return _SseListener(sink);
  }

  core.LlmClient _pickClient(String provider) {
    switch (provider) {
      case 'anthropic':
      case 'openai':
      case 'openrouter':
        return core.HttpLlmClient();
      default:
        return core.llmFactoryDefault(); // EchoLlm fallback
    }
  }

  core.LlmRequestConfig _pickConfig(String provider) {
    switch (provider) {
      case 'anthropic':
        return const core.LlmRequestConfig(
            provider: 'anthropic', model: 'claude-sonnet-4-5', apiKeyEnv: 'ANTHROPIC_API_KEY');
      case 'gemini':
        return const core.LlmRequestConfig(
            provider: 'gemini', model: 'gemini-2.0-flash', apiKeyEnv: 'GOOGLE_API_KEY');
      case 'openai':
        return const core.LlmRequestConfig(
            provider: 'openai', model: 'gpt-4o-mini', apiKeyEnv: 'OPENAI_API_KEY');
      case 'openrouter':
        return const core.LlmRequestConfig(
            provider: 'openrouter', model: 'openrouter/auto', apiKeyEnv: 'OPENROUTER_API_KEY');
      case 'kimi':
        return const core.LlmRequestConfig(
            provider: 'kimi', model: 'moonshot-v1-8k', apiKeyEnv: 'KIMI_API_KEY');
      case 'xai':
        return const core.LlmRequestConfig(
            provider: 'xai', model: 'grok-beta', apiKeyEnv: 'XAI_API_KEY');
      case 'antigravity':
        return const core.LlmRequestConfig(
            provider: 'antigravity', model: 'antigravity-base', apiKeyEnv: 'ANTIGRAVITY_API_KEY');
      default:
        return const core.LlmRequestConfig(provider: 'echo', model: 'echo');
    }
  }

  // ---- infra ---------------------------------------------------------------

  Future<List<String>> _lanAddresses() async {
    final out = <String>[];
    try {
      final interfaces = await NetworkInterface.list();
      for (final i in interfaces) {
        out.addAll(i.addresses
            .where((a) => !a.isLoopback)
            .map((a) => a.address));
      }
    } catch (_) {}
    return out.isEmpty ? ['<detect-ip>'] : out;
  }

  void _await(Future<void> f) {}

  // ---- Wiki (Markdown knowledge base) -------------------------------------

  Future<void> _serveWiki(HttpRequest req) async {
    final md = mdStore;
    if (md == null) { _json(req, {'error': 'md store unavailable'}, 500); return; }
    final index = File('${md.root.path}/wiki/index.md');
    _json(req, {
      'index': index.existsSync() ? index.readAsStringSync() : null,
    });
  }

  Future<void> _serveWikiNote(HttpRequest req) async {
    final md = mdStore;
    if (md == null) { _json(req, {'error': 'md store unavailable'}, 500); return; }
    final slug = req.uri.queryParameters['slug'] ?? '';
    if (slug.isEmpty) { _json(req, {'error': 'slug required'}, 400); return; }
    final f = File('${md.root.path}/wiki/notes/$slug.md');
    _json(req, {
      'slug': slug,
      'markdown': f.existsSync() ? f.readAsStringSync() : null,
    });
  }

  Future<void> _serveWikiBuild(HttpRequest req) async {
    final md = mdStore;
    if (md == null) { _json(req, {'error': 'md store unavailable'}, 500); return; }

    _ensureWiki(md);
    final sessions = await store.sessions();
    var built = 0;
    for (final s in sessions) {
      final msgs = await store.messages(s.id);
      final note = await wiki!.noteFromSession(s, msgs);
      if (note != null) built++;
    }
    _json(req, {'built': built, 'total': sessions.length, 'provider': _wikiProvider});
  }

  /// Distill just one session into a wiki note.
  Future<void> _serveWikiSession(HttpRequest req, String sessionId) async {
    final md = mdStore;
    if (md == null) { _json(req, {'error': 'md store unavailable'}, 500); return; }

    final s = await store.adapter.sessionById(sessionId);
    if (s == null) { _json(req, {'error': 'session not found'}, 404); return; }
    _ensureWiki(md);
    final msgs = await store.messages(sessionId);
    final note = await wiki!.noteFromSession(s, msgs);
    _json(req, {
      'built': note != null ? 1 : 0,
      'notes': note?.slug,
      'provider': _wikiProvider,
    });
  }

  String _wikiProvider = 'echo';

  void _ensureWiki(core.MdFileStore md) {
    if (wiki != null) return;
    final providerId = _firstReadyProvider();
    _wikiProvider = providerId;
    wiki = core.MdWiki(
      store: md,
      llm: _pickClient(providerId),
      config: _pickConfig(providerId),
    );
  }

  /// First provider that currently has a configured API key, else 'echo'.
  String _firstReadyProvider() {
    const map = [
      ('anthropic', 'ANTHROPIC_API_KEY'),
      ('openai', 'OPENAI_API_KEY'),
      ('openrouter', 'OPENROUTER_API_KEY'),
      ('gemini', 'GOOGLE_API_KEY'),
      ('kimi', 'KIMI_API_KEY'),
      ('xai', 'XAI_API_KEY'),
      ('antigravity', 'ANTIGRAVITY_API_KEY'),
    ];
    for (final (id, key) in map) {
      if (core.SecretResolver.has(key)) return id;
    }
    return 'echo';
  }

}

/// Server-sent events writer. Serializes writes and awaits each flush so
/// chunks are actually transmitted to the incremental HTTP client (probe-verified:
/// `await resp.flush()` is what commits an SSE chunk in dart:io).
class _SseSink {
  final HttpResponse _resp;
  bool _closed = false;
  Future<void> _tail = Future.value();
  _SseSink(this._resp);

  void write(String event, Map<String, dynamic> data) {
    if (_closed) return;
    final buf = StringBuffer()
      ..writeln('event: $event')
      ..writeln('data: ${jsonEncode(data)}')
      ..writeln('');
    // Append + flush on the event loop, serialized so ordering holds.
    _tail = _tail.then((_) async {
      try {
        _resp.write(buf.toString());
        await _resp.flush();
      } catch (_) {}
    });
  }

  /// Wait for all enqueued writes to flush.
  Future<void> drain() => _tail;

  Future<void> close() async {
    if (_closed) return;
    await drain();
    _closed = true;
    try {
      await _resp.close();
    } catch (_) {}
  }
}

/// Bridges AgentLoop streaming events to SSE frames.
class _SseListener implements core.AgentTurnListener {
  final _SseSink sink;
  _SseListener(this.sink);

  @override
  void onText(String delta) => sink.write('text', {'text': delta});

  @override
  void onThinking(String delta) => sink.write('thinking', {'text': delta});

  @override
  void onToolStart(String blockId, String name, Map<String, dynamic> args) =>
      sink.write('tool_start', {'id': blockId, 'name': name});

  @override
  void onToolEnd(String blockId, bool ok, String output) =>
      sink.write('tool_end', {'id': blockId, 'ok': ok, 'output': output});

  @override
  void onUsage(core.LlmUsage usage) => sink.write('usage', {
        'input': usage.inputTokens,
        'output': usage.outputTokens,
      });

  @override
  void onState({required bool awaitingModel}) {}
}

/// A real-disk `FsAdapter` for the agent's file tools (native).
class _DiskFs implements core.FsAdapter {
  final String root;
  _DiskFs({required this.root});

  String _p(String path) => path.startsWith('/') ? path : '$root/$path';

  @override
  Future<bool> exists(String path) async => File(_p(path)).existsSync();

  @override
  Future<List<String>> list(String dir) async {
    final d = Directory(_p(dir));
    if (!d.existsSync()) return const [];
    return d.listSync().map((e) => e.path.split('/').last).toList();
  }

  @override
  Future<String> read(String path) async => File(_p(path)).readAsStringSync();

  @override
  Future<void> write(String path, String content) async {
    final f = File(_p(path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content, flush: true);
  }
}
