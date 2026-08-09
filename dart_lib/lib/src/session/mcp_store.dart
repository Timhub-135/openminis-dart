import 'dart:convert';
import 'dart:io';

/// An MCP server configuration, mirroring `MCPServerConfig` in the original
/// `MCPStore.swift`. Supports STDIO (command+args+env) and HTTP (url+headers)
/// transports, and stores per-session enable/disable overrides.
class MCPServerConfig {
  /// The server name (key under `mcpServers`).
  final String id;
  String? note;
  bool enabled;
  // HTTP transport
  String? url;
  Map<String, String> headers;
  // STDIO transport
  String? command;
  List<String> args;
  Map<String, String> env;
  // per-server overrides for sessions
  final Map<String, bool> sessionOverrides;

  MCPServerConfig({
    required this.id,
    this.note,
    this.enabled = true,
    this.url,
    this.headers = const {},
    this.command,
    this.args = const [],
    this.env = const {},
    Map<String, bool>? sessionOverrides,
  }) : sessionOverrides = sessionOverrides ?? {};

  bool get isHTTP => !(url?.isEmpty ?? true);
  bool get isSTDIO => !(command?.isEmpty ?? true);

  String get transportSummary {
    if (isHTTP) return url ?? '';
    if (isSTDIO) return [command ?? '', ...args].join(' ');
    return '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (note != null) 'note': note,
        'enabled': enabled,
        if (url != null) 'url': url,
        if (headers.isNotEmpty) 'headers': headers,
        if (command != null) 'command': command,
        if (args.isNotEmpty) 'args': args,
        if (env.isNotEmpty) 'env': env,
        if (sessionOverrides.isNotEmpty) 'sessionOverrides': sessionOverrides,
      };

  factory MCPServerConfig.fromJson(Map<String, dynamic> j) => MCPServerConfig(
        id: j['id'] as String,
        note: j['note'] as String?,
        enabled: j['enabled'] as bool? ?? true,
        url: j['url'] as String?,
        headers: (j['headers'] as Map?)?.cast<String, String>() ?? {},
        command: j['command'] as String?,
        args: (j['args'] as List?)?.cast<String>() ?? [],
        env: (j['env'] as Map?)?.cast<String, String>() ?? {},
        sessionOverrides:
            (j['sessionOverrides'] as Map?)?.cast<String, bool>() ?? {},
      );

  /// Is this server enabled for a given session (with per-session override)?
  bool enabledFor(String sessionId) =>
      sessionOverrides[sessionId] ?? enabled;
}

/// Manages MCP server configurations, persisted as a `servers.json` (the
/// same Claude-Desktop compatible shape the original uses).
class MCPStore {
  final File file;
  final Map<String, MCPServerConfig> _servers = {};

  MCPStore({required this.file});

  /// Load servers from disk.
  Future<void> load() async {
    _servers.clear();
    if (!file.existsSync()) return;
    try {
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final srvs = map['mcpServers'] as Map? ?? map;
      for (final entry in srvs.entries) {
        final id = entry.key.toString();
        final cfg = MCPServerConfig.fromJson(
            (entry.value as Map).cast<String, dynamic>()..['id'] = id);
        _servers[id] = cfg;
      }
    } catch (_) {
      // start empty on corrupt file
    }
  }

  List<MCPServerConfig> get servers =>
      _servers.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  MCPServerConfig? get(String id) => _servers[id];

  Future<void> upsert(MCPServerConfig cfg) async {
    _servers[cfg.id] = cfg;
    await save();
  }

  Future<void> remove(String id) async {
    _servers.remove(id);
    await save();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final s = _servers[id];
    if (s != null) {
      s.enabled = enabled;
      await save();
    }
  }

  /// Enable/disable a server within one session (per-session override).
  Future<void> setSessionOverride(String serverId, String sessionId, bool enabled) async {
    final s = _servers[serverId];
    if (s != null) {
      s.sessionOverrides[sessionId] = enabled;
      await save();
    }
  }

  /// Names of servers enabled (globally or for [sessionId]).
  List<String> enabledServerIds([String? sessionId]) => _servers.values
      .where((s) => sessionId == null ? s.enabled : s.enabledFor(sessionId))
      .map((s) => s.id)
      .toList();

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    final obj = <String, dynamic>{
      'mcpServers': {
        for (final e in _servers.entries) e.key: e.value.toJson(),
      },
    };
    file.writeAsStringSync(jsonEncode(obj), flush: true);
  }
}
