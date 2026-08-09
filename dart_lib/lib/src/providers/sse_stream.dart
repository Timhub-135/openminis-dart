import 'dart:async';
import 'dart:convert';

/// A Server-Sent Events stream parser.
///
/// The original streams Anthropic/OpenAI/SG responses and normalises the
/// wrapped `event:` frames. This Dart port is transport-agnostic: it parses a
/// byte stream into `(eventName, dataJsonString)` tuples; provider wrappers then
/// convert `data` JSON into the events in `llm_message.dart`.
class SseStream {
  /// Parse a byte stream as SSE. Emits `(eventName, data)` where a final blank
  /// line with no event name still yields a `(null, data)` event (the
  /// default-event case some providers use).
  ///
  /// [cancelSignal] closes the output early if any of its events arrive while
  /// the stream is still open.
  static Stream<(String?, String)> parse(
    Stream<List<int>> bytes, {
    Stream<void>? cancelSignal,
  }) {
    final merged = StreamController<(String?, String)>();
    var isActive = true;

    // Broker: forward the transformed stream; surf finish.
    StreamSubscription<(String?, String)>? sub;
    sub = bytes.transform(const _SseTransformer()).listen(
          (e) {
            if (isActive) merged.add(e);
          },
          onError: (Object e, StackTrace st) {
            if (isActive) merged.addError(e, st);
          },
          onDone: () {
            isActive = false;
            if (!merged.isClosed) merged.close();
          },
        );

    cancelSignal?.listen((_) {
      if (isActive) {
        isActive = false;
        sub?.cancel();
        if (!merged.isClosed) merged.close();
      }
    });

    return merged.stream;
  }

  /// Convenience for tests and non-HTTP sources.
  static Stream<(String?, String)> parseString(String body) =>
      parse(Stream.value(utf8.encode(body)));
}

class _SseTransformer
    extends StreamTransformerBase<List<int>, (String?, String)> {
  const _SseTransformer();

  @override
  Stream<(String?, String)> bind(Stream<List<int>> stream) async* {
    final buffer = StringBuffer();
    String? currentEvent;
    final currentData = StringBuffer(); // reuse; cleared via clear()

    await for (final chunk in stream) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));
      final text = buffer.toString();
      buffer.clear();
      var idx = 0;
      for (;;) {
        final nl = _findLineEnd(text, idx);
        if (nl == null) break;
        final line = text.substring(idx, nl.start);
        idx = nl.end;
        if (line.isEmpty) {
          // Dispatch the accumulated event.
          if (currentEvent != null || currentData.isNotEmpty) {
            yield (currentEvent, currentData.toString());
          }
          currentEvent = null;
          currentData.clear();
        } else if (line.startsWith(':')) {
          // Comment / keep-alive line.
          continue;
        } else {
          final colon = line.indexOf(':');
          final field = colon < 0 ? line : line.substring(0, colon);
          final value = colon < 0
              ? ''
              : line.substring(colon + 1).replaceFirst(RegExp(r'^ '), '');
          if (field == 'event') {
            currentEvent = value;
          } else if (field == 'data') {
            if (currentData.isNotEmpty) currentData.writeln();
            currentData.write(value);
          }
        }
      }
      // Preserve a trailing partial line for the next chunk.
      if (idx < text.length) {
        buffer.write(text.substring(idx));
      }
    }

    // ---- end of stream: flush any residual state ----

    // A final partial line that never ended with a newline (e.g. 'data: x' with
    // no closing \n) is still a valid line per the SSE spec; parse it inline.
    if (buffer.isNotEmpty) {
      final line = buffer.toString();
      buffer.clear();
      if (line.startsWith(':')) {
        // comment — ignore
      } else {
        final colon = line.indexOf(':');
        final field = colon < 0 ? line : line.substring(0, colon);
        final value = colon < 0
            ? ''
            : line.substring(colon + 1).replaceFirst(RegExp(r'^ '), '');
        if (field == 'event') {
          currentEvent = value;
        } else if (field == 'data') {
          if (currentData.isNotEmpty) currentData.writeln();
          currentData.write(value);
        }
      }
    }
    // Flush a final data block whose event frame was never closed by a blank
    // line (e.g. the server stream just ended).
    if (currentEvent != null || currentData.isNotEmpty) {
      yield (currentEvent, currentData.toString());
    }
  }

  static _LineEnd? _findLineEnd(String s, int start) {
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x0D) {
        // \r or \r\n
        if (i + 1 < s.length && s.codeUnitAt(i + 1) == 0x0A) {
          return _LineEnd(i, i + 2);
        }
        return _LineEnd(i, i + 1);
      }
      if (c == 0x0A) {
        return _LineEnd(i, i + 1);
      }
    }
    return null;
  }
}

class _LineEnd {
  final int start;
  final int end;
  const _LineEnd(this.start, this.end);
}
