import 'dart:io';

import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late MdFileStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mdstore_test');
    store = MdFileStore(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('persists a session + messages as real markdown files', () async {
    await store.init();

    final s = Session(title: '调研 Flutter 与 Web');
    await store.upsertSession(s);

    final user = ChatMessage(sessionId: s.id, role: ChatRole.user, content: 'Flutter web 怎么跑？');
    await store.upsertMessage(user);
    final asst = ChatMessage(sessionId: s.id, role: ChatRole.assistant, content: '用 flutter build web 即可');
    await store.upsertMessage(asst);

    // The session file exists and is markdown with front matter + transcript.
    final file = File(store.sessionFilePath(s.id));
    expect(file.existsSync(), isTrue);
    final text = file.readAsStringSync();
    expect(text, startsWith('---'));
    expect(text, contains('session: "${s.id}"'));
    expect(text, contains('## —— user'));
    expect(text, contains('## —— assistant'));
    expect(text, contains('Flutter web 怎么跑？'));
    expect(text, contains('用 flutter build web 即可'));

    // sessions/index.md exists.
    expect(File('${dir.path}/sessions/index.md').existsSync(), isTrue);

    // Reload a fresh store from the md files.
    final store2 = MdFileStore(dir);
    await store2.init();
    final sv2 = await store2.sessionById(s.id);
    final ms2 = await store2.messagesForSession(s.id);
    expect(sv2, isNotNull);
    expect(ms2, isNotEmpty);
  });

  test('reloads messages written by a prior instance', () async {
    final s1 = Session(title: '回读测试');
    await store.init();
    await store.upsertSession(s1);
    final m1 = ChatMessage(sessionId: s1.id, role: ChatRole.user, content: '第一条');
    await store.upsertMessage(m1);
    final m2 = ChatMessage(sessionId: s1.id, role: ChatRole.assistant, content: '第二条');
    await store.upsertMessage(m2);

    final store2 = MdFileStore(dir);
    await store2.init();
    final msgs = await store2.messagesForSession(s1.id);
    final contents = msgs.map((m) => m.content).toList();
    expect(contents, contains('第一条'));
    expect(contents, contains('第二条'));
  });

  test('MdWiki produces a note + index (deterministic fallback, no LLM key)',
      () async {
    await store.init();
    final s = Session(title: '了解 Docker');
    await store.upsertSession(s);
    final u = ChatMessage(sessionId: s.id, role: ChatRole.user, content: 'Docker 是啥');
    await store.upsertMessage(u);
    final a = ChatMessage(sessionId: s.id, role: ChatRole.assistant, content: 'Docker 是容器化工具');
    await store.upsertMessage(a);

    final wiki = MdWiki(store: store); // no llm -> deterministic
    final sess = await store.sessionById(s.id);
    final note = await wiki.noteFromSession(
        sess!, await store.messagesForSession(s.id));
    expect(note, isNotNull);
    expect(note!.title, isNotEmpty);
    expect(note.tags, isNotEmpty);

    // The wiki note file and index exist.
    final noteFile = File('${dir.path}/wiki/notes/${note.slug}.md');
    expect(noteFile.existsSync(), isTrue);
    final index = File('${dir.path}/wiki/index.md');
    expect(index.existsSync(), isTrue);
    expect(index.readAsStringSync(), contains('## `session`'));
  });

  test('writeWikiNote writes front-matter + body', () async {
    await store.init();
    await store.writeWikiNote('hello-note', {'title': 'Hello', 'tags': 'a,b'}, '# Body\nContent');
    final f = File('${dir.path}/wiki/notes/hello-note.md');
    expect(f.existsSync(), isTrue);
    final text = f.readAsStringSync();
    expect(text, contains('title: "Hello"'));
    expect(text, contains('tags: "a,b"'));
    expect(text, contains('# Body'));
  });
}
