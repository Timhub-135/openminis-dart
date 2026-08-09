import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openminis_core/openminis.dart';

/// A live streaming-event for the active agent turn, surfaced to the chat UI.
/// The chat screen listens to [AppState.streamEvents] and renders each event.
sealed class LiveEvent {
  const LiveEvent();
}

class LiveText extends LiveEvent {
  final String delta;
  const LiveText(this.delta);
}

class LiveThinking extends LiveEvent {
  final String delta;
  const LiveThinking(this.delta);
}

class LiveToolStart extends LiveEvent {
  final String id;
  final String name;
  final Map<String, dynamic> args;
  const LiveToolStart(this.id, this.name, this.args);
}

class LiveToolEnd extends LiveEvent {
  final String id;
  final bool ok;
  final String output;
  const LiveToolEnd(this.id, this.ok, this.output);
}

class LiveUsage extends LiveEvent {
  final int input;
  final int output;
  const LiveUsage(this.input, this.output);
}

class LiveTurnDone extends LiveEvent {
  const LiveTurnDone();
}

/// Live events / provider management.
///
/// A user-configured provider (`core.ProviderConfig`) needs only an API base URL
/// and an API key; the wire protocol auto-detects from the base. `echo` is the
/// built-in local fallback (no network).


/// Application-wide state: storage, tool registry, agent loop, sync engine.
/// This is the single bridge between the pure-Dart core and the Flutter UI on
/// Windows and Android.
class AppState extends ChangeNotifier {
  final ChatStore store;
  final ToolRegistry tools;
  final SoulStore souls;
  final SkillStore skills;
  final String deviceId;

  SyncEngine? _sync;
  SyncEngine? get sync => _sync;

  LlmClient? _llm;
  LlmRequestConfig? _modelConfig;
  late final RequestBudget baseBudget;
  PersistenceAdapter? _adapter;

  bool _syncError = false;
  String _syncMessage = 'idle';
  bool get syncError => _syncError;
  String get syncMessage => _syncMessage;

  /// Whether an agent turn is currently running.
  bool _busy = false;
  bool get busy => _busy;

  /// Currently selected provider.
  String _providerId = 'echo';
  String get providerId => _providerId;

  /// In-progress assistant text (kept for compat: chat can also use the stream).
  final ValueNotifier<String> liveAssistantText = ValueNotifier('');

  /// Broadcast stream of live agent events for the chat UI.
  final _eventController = StreamController<LiveEvent>.broadcast();
  Stream<LiveEvent> get streamEvents => _eventController.stream;

  /// Provider registry for the UI (static definitions).
  /// User-configured providers, by id (excluding the built-in `echo`).
  final Map<String, ProviderConfig> _providers = {};

  /// All selectable providers, including the built-in `echo` fallback.
  List<ProviderConfig> get providerOptions => [
        const ProviderConfig(id: 'echo', name: '本地回显', baseUrl: '', model: 'echo'),
        ..._providers.values,
      ];

  /// Add or replace a custom provider (only base + key needed).
  void addProvider(ProviderConfig p, {bool select = true}) {
    _providers[p.id] = p;
    if (select) setProvider(p.id);
    notifyListeners();
  }

  void removeProvider(String id) {
    _providers.remove(id);
    if (_providerId == id) {
      _providerId = 'echo';
      _llm = llmFactoryDefault();
      _modelConfig = const LlmRequestConfig(provider: 'echo', model: 'echo');
    }
    notifyListeners();
  }

  AppState({
    required this.store,
    required this.tools,
    required this.souls,
    required this.skills,
    required this.deviceId,
  }) {
    baseBudget = RequestBudget(maxToolRounds: 25, maxTotalToolCalls: 40);
    // Mark ready providers based on resolved env keys.
  }

  /// Build a ready AppState. Platform-agnostic: the caller supplies a
  /// [PersistenceAdapter] (JsonFileStore on native, MemoryStore on web) and a
  /// storage-root string used for the sandbox/minis workspace.
  static Future<AppState> bootstrap({
    required PersistenceAdapter adapter,
    required ChatStore chatStore,
    required String deviceId,
    String storageRoot = '',
    LlmClient? llm,
    LlmRequestConfig? modelConfig,
  }) async {
    await adapter.init();
    final souls = SoulStore();
    final tools = ToolRegistry();
    tools.registerAll(builtinTools());
    tools.registerAll(agentTools(AgentToolsDeps(souls: souls, fs: _simpleFs(storageRoot))));

    // Register the Linux shell sandbox (Docker-Alpine on Windows, Termux on
    // Android). On web the host dir is a virtual root.
    if (storageRoot.isNotEmpty) {
      final sandbox = SandboxFactory.create(hostMinisDir: storageRoot);
      tools.registerAll(sandboxTools(sandbox));
    }

    final state = AppState(
      store: chatStore,
      tools: tools,
      souls: souls,
      skills: SkillStore(),
      deviceId: deviceId,
    );
    state._llm = llm;
    state._modelConfig = modelConfig;
    state._adapter = adapter;
    return state;
  }

  /// Start the cross-platform sync engine.
  Future<void> startSync({String mode = SyncTransportMode.lan, String peerHost = '127.0.0.1', int port = 8741}) async {
    if (_sync != null) return;
    final config = SyncConfig(mode: mode, peerHost: peerHost, port: port);
    final transport =
        LanSyncTransport(baseUrl: 'http://$peerHost:$port', deviceId: deviceId);
    _sync = SyncEngine(
      config: config,
      transport: transport,
      store: store,
      adapter: _adapter!,
      deviceId: deviceId,
    );
    _sync!.updates.listen((e) {
      _syncMessage = switch (e) {
        SyncError() => 'sync error',
        SyncCompleted() =>
          'synced ${e.outcome.messagesApplied} new, ${e.outcome.sessionsApplied} sessions',
        SyncStarted() => 'sync started',
        _ => _syncMessage,
      };
      _syncError = e is SyncError;
      notifyListeners();
    });
    await _sync!.init();
    notifyListeners();
  }

  /// Kick off a reconciliation pass now.
  Future<void> syncNow() async {
    final s = _sync;
    if (s == null) return;
    await s.reconcile();
  }

  /// Set the active provider by id.
  void setProvider(String id) {
    _providerId = id;
    _llm = _clientFor(id);
    _modelConfig = _configFor(id);
    notifyListeners();
  }

  LlmClient _clientFor(String id) {
    if (id == 'echo') return llmFactoryDefault();
    return HttpLlmClient(); // protocol auto-detected from baseUrl in config
  }

  LlmRequestConfig _configFor(String id) {
    if (id == 'echo') {
      return const LlmRequestConfig(provider: 'echo', model: 'echo');
    }
    final p = _providers[id];
    if (p == null) return const LlmRequestConfig(provider: 'echo', model: 'echo');
    // Build a config for the auto-detected protocol. baseUrl is passed through;
    // the client resolves the provider endpoint from it. The key is embedded
    // (not via an env name) since the user supplied it directly.
    return LlmRequestConfig(
      provider: p.protocol,
      model: p.model,
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
    );
  }

  /// List of sessions (sorted by activity).
  Future<List<Session>> sessions() => store.sessions();

  /// Ensure a session exists, creating one if [id] is null.
  Future<Session> ensureSession([String? id]) => store.ensureSession(id);

  /// Delete a session (marks sync tombstone).
  Future<void> deleteSession(String id) => store.deleteSession(id);

  /// Send a user prompt through the agent loop in [sessionId].
  Future<ChatMessage?> send(
    String sessionId,
    String text, {
    List<AttachmentMeta> attachments = const [],
  }) async {
    final client = _llm ?? _clientFor(_providerId);
    final cfg = _modelConfig ?? _configFor(_providerId);
    _busy = true;
    notifyListeners();
    liveAssistantText.value = '';
    final loop = AgentLoop(
      store: store,
      tools: tools,
      client: client,
      config: cfg,
      budget: baseBudget,
      listener: _streamListener,
    );
    try {
      await loop.run(sessionId, text, attachments: attachments);
      _eventController.add(const LiveTurnDone());
    } finally {
      _busy = false;
      notifyListeners();
      if (_sync != null) {
        unawaited(_sync!.reconcile());
      }
    }
    return null;
  }

  void _onText(String delta) {
    liveAssistantText.value = liveAssistantText.value + delta;
    _eventController.add(LiveText(delta));
  }

  AgentTurnListener get _streamListener => _UiListener(this);

  @override
  void dispose() {
    liveAssistantText.dispose();
    _eventController.close();
    super.dispose();
  }
}

class _UiListener implements AgentTurnListener {
  final AppState state;
  _UiListener(this.state);
  @override
  void onText(String delta) => state._onText(delta);

  @override
  void onThinking(String delta) =>
      state._eventController.add(LiveThinking(delta));

  @override
  void onToolEnd(String blockId, bool ok, String output) =>
      state._eventController.add(LiveToolEnd(blockId, ok, output));

  @override
  void onToolStart(String blockId, String name, Map<String, dynamic> args) =>
      state._eventController.add(LiveToolStart(blockId, name, args));

  @override
  void onUsage(LlmUsage usage) =>
      state._eventController.add(LiveUsage(usage.inputTokens, usage.outputTokens));

  @override
  void onState({required bool awaitingModel}) {}
}

/// A web-safe in-memory [FsAdapter] so the file tools are never platform-bound.
/// On native, a real-disk adapter can be injected by the host for persistence.
class _MemoryFs implements FsAdapter {
  final Map<String, String> _files = {};

  _MemoryFs();

  @override
  Future<String> read(String path) async {
    final f = _files[path];
    if (f == null) throw StateError('No such file: $path');
    return f;
  }

  @override
  Future<void> write(String path, String content) async {
    _files[path] = content;
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(path);

  @override
  Future<List<String>> list(String dir) async =>
      _files.keys.where((p) => p.startsWith(dir)).toList();
}

FsAdapter _simpleFs(String root) => _MemoryFs();
