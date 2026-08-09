import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  group('ShareInbox', () {
    test('builds a PendingShare from share extras', () {
      final share = ShareInbox.fromShareExtras(
        sharedText: 'Hello from another device',
        sharedUrl: 'https://example.com',
      );
      expect(share.items, hasLength(2));
      expect(share.items[0].isText, isTrue);
      expect(share.preview, contains('Hello'));
      expect(share.fullText, contains('https://example.com'));
    });

    test('routeIntoSession creates a new session when sessionId is null',
        () async {
      final store = MemoryStore();
      await store.init();
      final chat = ChatStore(store);
      final share = ShareInbox.fromShareExtras(sharedText: '我的分享内容');

      final session =
          await ShareInbox.routeIntoSession(chat, share: share, sessionId: null);
      expect(session.id, isNotEmpty);

      final msgs = await chat.messages(session.id);
      expect(msgs, hasLength(1));
      expect(msgs.first.role, ChatRole.user);
      expect(msgs.first.content, '我的分享内容');
    });

    test('routeIntoSession appends into an existing session', () async {
      final store = MemoryStore();
      await store.init();
      final chat = ChatStore(store);
      final s = Session(title: '已有对话');
      await store.upsertSession(s);
      final share = ShareInbox.fromShareExtras(sharedText: '加入这个对话');

      final routed =
          await ShareInbox.routeIntoSession(chat, share: share, sessionId: s.id);
      expect(routed.id, s.id);
      final msgs = await chat.messages(s.id);
      expect(msgs, hasLength(1));
      expect(msgs.first.content, '加入这个对话');
    });

    test('file items become attachments', () async {
      final store = MemoryStore();
      await store.init();
      final chat = ChatStore(store);
      final share = ShareInbox.fromShareExtras(sharedFilePaths: ['/tmp/a.png']);
      final session =
          await ShareInbox.routeIntoSession(chat, share: share, sessionId: null);
      final msgs = await chat.messages(session.id);
      expect(msgs.first.attachments, isNotEmpty);
      expect(msgs.first.attachments.first.path, '/tmp/a.png');
    });
  });
}
