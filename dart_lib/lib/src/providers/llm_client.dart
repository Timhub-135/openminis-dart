import 'llm_message.dart';
import 'sse_stream.dart';

/// Configuration describing a provider endpoint for a request.
///
/// Providers supported by the original: Anthropic, OpenAI, Gemini, Kimi, xAI,
/// OpenRouter, Antigravity ("antigravity"), custom OpenAI-compatible.
class LlmRequestConfig {
  /// Normalized provider key, e.g. `anthropic`, `openai`, `gemini`, `kimi`,
  /// `xai`, `openrouter`, `custom`.
  final String provider;
  final String model;

  /// Name of the environment variable holding the API key.
  final String apiKeyEnv;

  /// Inline API key (user-provided). Preferred over [apiKeyEnv] when set.
  final String apiKey;

  final String baseUrl;
  final int maxTokens;
  final bool stream;
  final double temperature;
  final bool supportsThinking;

  const LlmRequestConfig({
    required this.provider,
    required this.model,
    this.apiKeyEnv = '',
    this.apiKey = '',
    this.baseUrl = '',
    this.maxTokens = 4096,
    this.stream = true,
    this.temperature = 0.7,
    this.supportsThinking = true,
  });

  bool get hasKey => apiKey.isNotEmpty || apiKeyEnv.isNotEmpty;
}

/// A provider-agnostic LLM client.
///
/// Implementations translate an [LlmRequest] (normalized message list) into the
/// provider's wire format and stream back normalized [AgentStreamEvent]s.
abstract class LlmClient {
  Stream<AgentStreamEvent> complete(List<LlmMessage> messages, {
    required LlmRequestConfig config,
    List<Map<String, dynamic>> tools = const [],
    List<String>? stopSequences,
  });
}

/// Transport-level detail helper for SSE-based providers.
abstract class SseClient implements LlmClient {
  /// Parse provider SSE frames into normalized [AgentStreamEvent]s.
  Stream<AgentStreamEvent> parseSse(Stream<(String?, String)> events, LlmRequestConfig config);
}

extension SseParsing on SseClient {
  Stream<AgentStreamEvent> fromUtf8Bytes(
    Stream<List<int>> bytes,
    LlmRequestConfig config,
  ) {
    return parseSse(SseStream.parse(bytes), config);
  }
}
