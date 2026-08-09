import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  group('SSE parser', () {
    test('parses event frames with data fields', () async {
      const body = 'event: message\ndata: {"a":1}\n\n'
          'event: done\ndata: {"b":2}\n\n';
      final events = await SseStream.parseString(body).toList();
      expect(events, hasLength(2));
      expect(events[0].$1, 'message');
      expect(events[0].$2, '{"a":1}');
      expect(events[1].$1, 'done');
      expect(events[1].$2, '{"b":2}');
    });

    test('handles multi-line data, comments and CRLF', () async {
      const body = ': keepalive\r\n'
          'event: message\r\n'
          'data: line1\r\n'
          'data: line2\r\n'
          '\r\n';
      final events = await SseStream.parseString(body).toList();
      expect(events, hasLength(1));
      expect(events.single.$2, 'line1\nline2');
    });

    test('yields data without an event name when no event field present',
        () async {
      const body = 'data: lone\n\n';
      final events = await SseStream.parseString(body).toList();
      expect(events.single.$1, isNull);
      expect(events.single.$2, 'lone');
    });

    test('chunked/split across byte boundaries', () async {
      // Split mid-line to exercise buffering.
      final stream = Stream.fromIterable([
        'event: m\nda'.codeUnits,
        'ta: hello\n\n'.codeUnits,
        'event: m\ndata: w'.codeUnits,
        'orld\n\n'.codeUnits,
      ]);
      final events = await SseStream.parse(stream).toList();
      expect(events, hasLength(2));
      expect(events[0].$2, 'hello');
      expect(events[1].$2, 'world');
    });

    test('flushes trailing data without closing blank line', () async {
      const body = 'data: trailing';
      final events = await SseStream.parseString(body).toList();
      expect(events.single.$2, 'trailing');
    });
  });

  group('TokenUsage folds with max() to avoid cumulative inflation', () {
    test('cumulative usage per chunk stays at max, not N²/2', () {
      final usage = TokenUsage();
      // Provider emits cumulative input token counts each chunk (1,2,...,100).
      for (var i = 1; i <= 100; i++) {
        usage.add(i, i * 2);
      }
      expect(usage.inputTokens, 100); // max, not 5050
      expect(usage.outputTokens, 200);
      expect(usage.latestContextTokens, 100);
    });

    test('single-shot usage applies directly', () {
      final usage = TokenUsage();
      usage.add(10, 25, cacheRead: 5, cacheCreation: 3);
      expect(usage.inputTokens, 10);
      expect(usage.outputTokens, 25);
      expect(usage.cacheReadTokens, 5);
      expect(usage.cacheCreationTokens, 3);
      expect(usage.latestContextTokens, 18);
    });
  });

  group('AssistantBlock adaptive thinking flush', () {
    test('thinking interval grows with buffer length', () {
      expect(AssistantBlock.thinkingFlushInterval(100), 0.3);
      expect(AssistantBlock.thinkingFlushInterval(1500), 0.6);
      expect(AssistantBlock.thinkingFlushInterval(10000), 1.0);
    });

    test('buffered thinking only lands on content after a flush', () {
      final b = AssistantBlock(
        id: 'b1',
        kind: AssistantBlockKind.thinking,
        content: '',
      );
      b.appendThinkingDelta('hel');
      b.appendThinkingDelta('lo');
      // Not yet flushed synchronously.
      expect(b.content, '');
      expect(b.contentUpdateSeq, 2);
      b.flushThinkingBuffer();
      expect(b.content, 'hello');
      expect(b.isThinking, isTrue);
      b.dispose();
    });

    test('text deltas append immediately', () {
      final b = AssistantBlock(
        id: 'b2',
        kind: AssistantBlockKind.text,
        content: '',
      );
      b.appendText('a');
      b.appendText('b');
      expect(b.content, 'ab');
      expect(b.kind, AssistantBlockKind.text);
      b.dispose();
    });
  });

  group('MinisUrl', () {
    test('derives minis:// from /var/minis path with percent-encoding', () {
      final url = MinisUrl.fromLinuxPath('/var/minis/attachments/照片/猫.jpg');
      expect(url.startsWith('minis://attachments/'), isTrue);
      expect(url, isNot(contains(' ')));
      expect(url, isNot(contains('猫'))); // encoded
    });

    test('round-trips through parse', () {
      final url = 'minis://workspace/reports/q1%20v2.md';
      final parsed = MinisUrl.parse(url)!;
      expect(parsed.authority, 'workspace');
      expect(parsed.path, 'reports/q1 v2.md');
      expect(parsed.full, url);
    });

    test('resolves on disk against a platform root', () {
      final disk = MinisUrl.resolveOnDisk(
          'minis://shared/project/data.csv', '/home/user/.openminis');
      expect(disk, '/home/user/.openminis/shared/project/data.csv');
    });
  });
}
