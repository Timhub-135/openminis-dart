/// Support for the LAN web server and headless demos.
///
/// Provides:
///   • a tiny self-contained HTML chat UI ([webChatIndex]);
///   • a default [LlmClient] factory ([llmFactoryDefault]) that answers
///     deterministically so the LAN service is demonstrably alive even when no
///     real API key is configured.
library server_support;

import 'src/providers/llm_client.dart';
import 'src/providers/llm_message.dart';

/// A deterministic LLM client used when no provider API key is configured. It
/// returns a short echo-style answer so a browser hitting the LAN server sees
/// real conversational output without network access to a model provider.
class EchoLlm implements LlmClient {
  @override
  Stream<AgentStreamEvent> complete(
    List<LlmMessage> messages, {
    required LlmRequestConfig config,
    List<Map<String, dynamic>> tools = const [],
    List<String>? stopSequences,
  }) async* {
    final userText = _lastUserText(messages);
    final reply = userText.isEmpty
        ? '[echo] （收到空消息）'
        : '[echo] 我收到： "$userText"（未配置真实 provider，这是默认回显。）';
    for (final chunk in _chunks(reply)) {
      yield TextDelta(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
    yield TurnFinished(reply, null);
  }

  String _lastUserText(List<LlmMessage> messages) {
    for (final m in messages.reversed) {
      if (m.role != 'user') continue;
      final texts = m.content
          .where((b) => b.type == 'text' && b.text != null)
          .map((b) => b.text!)
          .join();
      if (texts.isNotEmpty) return texts;
    }
    return '';
  }

  Iterable<String> _chunks(String s) {
    // Stream 3-char chunks so the UI renders a progressive response.
    const size = 3;
    final out = <String>[];
    for (var i = 0; i < s.length; i += size) {
      out.add(s.substring(i, i + size > s.length ? s.length : i + size));
    }
    return out;
  }
}

/// Default `LlmClient` built when no API key is configured.
LlmClient llmFactoryDefault() => EchoLlm();
