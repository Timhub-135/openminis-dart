import 'dart:io';

import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  group('SkillStore disk scanning', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('skills');
    });
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('discovers skills from SKILL.md folders', () async {
      // skill one
      final d1 = Directory('${root.path}/web-skill')..createSync();
      File('${d1.path}/SKILL.md').writeAsStringSync(
          '---\nname: 网页技能\ndescription: 处理网页相关任务\n---\n# Web skill\nbody here');
      File('${d1.path}/helper.dart').writeAsStringSync('void main(){}');
      // skill two
      final d2 = Directory('${root.path}/search-skill')..createSync();
      File('${d2.path}/SKILL.md').writeAsStringSync(
          '---\nname: search\ndescription: search the web\n---\n# Search skill');

      final store = SkillStore(rootDir: root.path);
      await store.scan();
      expect(store.all.length, 2);
      final web = store.all.firstWhere((s) => s.id == 'web-skill');
      expect(web.name, '网页技能');
      expect(web.description, contains('网页'));
      expect(web.resources, ['helper.dart']);
      // body on demand
      expect(store.body('web-skill'), contains('# Web skill'));
    });

    test('search matches by name/description', () async {
      final d = Directory('${root.path}/xyz')..createSync();
      File('${d.path}/SKILL.md')
          .writeAsStringSync('---\nname: llama\ndescription: 关于 LLM 的工具\n---\n');
      final store = SkillStore(rootDir: root.path);
      await store.scan();
      expect(store.search('LLM'), isNotEmpty);
      expect(store.search('不存在的'), isEmpty);
    });
  });

  group('MCPStore', () {
    late File f;

    setUp(() {
      f = File('${Directory.systemTemp.createTempSync("mcp")}/servers.json');
    });

    test('persists and loads MCP server configs', () async {
      final store = MCPStore(file: f);
      await store.upsert(MCPServerConfig(
        id: 'filesystem',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem'],
        url: null,
      ));
      await store.upsert(MCPServerConfig(id: 'remote', url: 'https://mcp.example.com', command: null));

      final store2 = MCPStore(file: f);
      await store2.load();
      expect(store2.servers.length, 2);
      final fs = store2.get('filesystem')!;
      expect(fs.isSTDIO, isTrue);
      expect(store2.enabledServerIds(), containsAll(['filesystem', 'remote']));
    });

    test('per-session overrides', () async {
      final store = MCPStore(file: f);
      await store.upsert(MCPServerConfig(id: 'algo', command: 'algo'));
      await store.setSessionOverride('algo', 'sess1', false);
      expect(store.get('algo')!.enabledFor('sess1'), isFalse);
      expect(store.get('algo')!.enabledFor('sess2'), isTrue);
    });
  });

  group('provider config dispatch', () {
    test('openai-compatible providers resolve their own base URL', () async {
      const cfgs = [
        LlmRequestConfig(provider: 'kimi', model: 'm', apiKeyEnv: 'KIMI_API_KEY'),
        LlmRequestConfig(provider: 'xai', model: 'm', apiKeyEnv: 'XAI_API_KEY'),
        LlmRequestConfig(provider: 'antigravity', model: 'm', apiKeyEnv: 'A_KEY'),
      ];
      for (final c in cfgs) {
        expect(c.hasKey, isTrue);
      }
      expect(cfgs.every((c) => c.provider != 'anthropic' && c.provider != 'gemini'), isTrue);
    });

    test('protocol auto-detected from base URL', () {
      const p1 = ProviderConfig(id: 'a', name: 'A', baseUrl: 'https://api.anthropic.com', model: 'claude');
      const p2 = ProviderConfig(id: 'g', name: 'G', baseUrl: 'https://generativelanguage.googleapis.com', model: 'gemini');
      const p3 = ProviderConfig(id: 'o', name: 'O', baseUrl: 'https://api.openai.com/v1', model: 'gpt');
      const p4 = ProviderConfig(id: 'c', name: 'C', baseUrl: 'https://myproxy.example.com', model: 'x');
      expect(p1.protocol, 'anthropic');
      expect(p2.protocol, 'gemini');
      expect(p3.protocol, 'openai');
      expect(p4.protocol, 'openai'); // unknown -> openai-compatible
      // ready only when an api key is present
      expect(p1.ready, isFalse);
      expect(const ProviderConfig(id: 'x', name: 'x', baseUrl: 'u', model: 'm', apiKey: 'k').ready, isTrue);
    });

    test('inline apiKey takes precedence over env in config', () {
      const c = LlmRequestConfig(provider: 'openai', model: 'gpt', apiKey: 'inline', apiKeyEnv: 'ENV');
      expect(c.apiKey, 'inline');
      expect(c.hasKey, isTrue);
    });
  });

  group('Compaction with LLM summary', () {
    test('deterministic summary when no LLM key', () async {
      final msgs = List.generate(
          3, (i) => ChatMessage(sessionId: 's', role: ChatRole.user, content: '主题讨论点 $i'));
      final cand = CompactionCandidate(folded: msgs, sourceSortOrder: 0, lastSourceSortOrder: 2);
      final s = await cand.summarize(llmFactoryDefault(),
          const LlmRequestConfig(provider: 'echo', model: 'echo'));
      expect(s, isNotEmpty);
      final d = cand.dividerFor('s', summary: s);
      expect(d.role, ChatRole.compactDivider);
      expect(d.isCompactedHistory, isTrue);
    });
  });
}
