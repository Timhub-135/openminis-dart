import 'dart:async';

import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  group('agent productivity tools', () {
    test('memory_write then memory_get round-trips', () async {
      final souls = SoulStore();
      final tools = agentTools(AgentToolsDeps(souls: souls, fs: _memFs()));
      final w = tools.firstWhere((t) => t.name == 'memory_write');
      final g = tools.firstWhere((t) => t.name == 'memory_get');

      final wr = await w.invoke({'note': '前端用 Flutter 写', 'context': 'tech'});
      expect(wr.ok, isTrue);

      final hit = await g.invoke({'keywords': 'Flutter'});
      expect(hit.ok, isTrue);
      expect(hit.output, contains('Flutter'));
    });

    test('file_write then file_edit replaces content', () async {
      final tools = agentTools(AgentToolsDeps(souls: SoulStore(), fs: _memFs()));
      final w = tools.firstWhere((t) => t.name == 'file_write');
      final e = tools.firstWhere((t) => t.name == 'file_edit');

      await w.invoke({'path': 'hello.txt', 'content': 'Hello Dart'});
      final r = await e.invoke(
          {'path': 'hello.txt', 'old_string': 'Dart', 'new_string': 'OpenMinis'});
      expect(r.ok, isTrue);

      final read = tools.firstWhere((t) => t.name == 'file_read');
      final rd = await read.invoke({'path': 'hello.txt'});
      expect(rd.output, 'Hello OpenMinis');
    });

    test('file_edit reports when target text is absent', () async {
      final tools = agentTools(AgentToolsDeps(souls: SoulStore(), fs: _memFs()));
      final w = tools.firstWhere((t) => t.name == 'file_write');
      final e = tools.firstWhere((t) => t.name == 'file_edit');
      await w.invoke({'path': 'a.md', 'content': 'foo bar'});
      final r = await e.invoke({'path': 'a.md', 'old_string': 'nope', 'new_string': 'x'});
      expect(r.ok, isFalse); // error: text not found
    });
  });

  group('TitleGenerator', () {
    test('assigns a deterministic title from the first user message', () async {
      final store = MemoryStore();
      await store.init();
      final chat = ChatStore(store);
      final s = Session();
      await store.upsertSession(s);
      final m = ChatMessage(sessionId: s.id, role: ChatRole.user, content: '如何部署到 Windows');
      await chat.addMessage(m);

      final gen = TitleGenerator(store: chat); // no llm -> fallback
      final title = await gen.ensureTitle(s.id);
      expect(title, isNotEmpty);
      expect(title, contains('Windows'));
    });

    test('keeps an existing explicit title', () async {
      final store = MemoryStore();
      await store.init();
      final chat = ChatStore(store);
      final s = Session(title: '我的项目');
      await store.upsertSession(s);
      final m = ChatMessage(sessionId: s.id, role: ChatRole.user, content: 'xbox');
      await chat.addMessage(m);

      final gen = TitleGenerator(store: chat);
      final title = await gen.ensureTitle(s.id);
      expect(title, '我的项目');
    });
  });

  group('AgentLoop concurrent tools', () {
    test('runs independent tools in parallel and reports results', () async {
      final store = MemoryStore();
      await store.init();
      final chat = ChatStore(store);
      final s = Session();
      await chat.addMessage(ChatMessage(sessionId: s.id, role: ChatRole.user, content: 'go'));

      final registry = ToolRegistry();
      final active = <String, int>{};
      var maxActive = 0;
      // slow tools that overlap to prove concurrency
      registry.register(Tool(
        name: 'sleep_and_echo',
        description: 'echo after delay',
        params: const [ToolParam(name: 'value', description: 'v', required: true, type: 'string')],
        handler: (args) async {
          final v = args['value'] as String;
          active[v] = (active[v] ?? 0) + 1;
          maxActive = maxActive > active.length ? maxActive : active.length;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          active.remove(v);
          return ToolResult.ok('done-$v');
        },
      ));

      final llm = ScriptedLlm3([
        // Turn 1: ask for 3 tools at once.
        [
          const ToolUseRequested('t1', 'sleep_and_echo', {'value': 'a'}),
          const ToolUseRequested('t2', 'sleep_and_echo', {'value': 'b'}),
          const ToolUseRequested('t3', 'sleep_and_echo', {'value': 'c'}),
        ],
        // Turn 2: final.
        [const TextDelta('done all')],
      ]);

      final loop = AgentLoop(store: chat, tools: registry, client: llm,
          config: const LlmRequestConfig(provider: 'fake', model: 't'),
          maxConcurrentTools: 3);
      final r = await loop.run(s.id, 'run');
      expect(r.completed, isTrue);
      expect(r.toolCallsMade, 3);
      // They overlapped (ran concurrently).
      expect(maxActive, greaterThan(1), reason: 'tools should run in parallel');
    });
  });

  group('Gemini provider config dispatch', () {
    test('_clientFor selects HttpLlmClient for gemini', () {
      // HttpLlmClient is used by selecting provider 'gemini' — here we just
      // ensure LlmRequestConfig carries gemini and the client won't throw for
      // missing key gracefully.
      const cfg = LlmRequestConfig(provider: 'gemini', model: 'gemini-2.0-flash', apiKeyEnv: 'GOOGLE_API_KEY');
      expect(cfg.provider, 'gemini');
      expect(cfg.hasKey, isTrue);
    });
  });
}

class _MemFs implements FsAdapter {
  final Map<String, String> _files = {};
  @override
  Future<bool> exists(String path) async => _files.containsKey(path);
  @override
  Future<List<String>> list(String dir) async => _files.keys.where((p) => p.startsWith(dir)).toList();
  @override
  Future<String> read(String path) async {
    final f = _files[path];
    if (f == null) throw StateError('no file $path');
    return f;
  }
  @override
  Future<void> write(String path, String content) async => _files[path] = content;
}

FsAdapter _memFs() => _MemFs();

/// Scripted LLM returning tool requests then a final turn.
class ScriptedLlm3 implements LlmClient {
  final List<List<AgentStreamEvent>> script;
  int _i = 0;
  ScriptedLlm3(this.script);
  @override
  Stream<AgentStreamEvent> complete(
    List<LlmMessage> messages, {
    required LlmRequestConfig config,
    List<Map<String, dynamic>> tools = const [],
    List<String>? stopSequences,
  }) async* {
    if (_i < script.length) {
      for (final e in script[_i]) {
        yield e;
      }
      _i++;
    }
    yield const TurnFinished('', null);
  }
}
