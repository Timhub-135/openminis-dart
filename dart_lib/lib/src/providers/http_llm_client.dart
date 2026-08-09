import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'llm_client.dart';
import 'llm_message.dart';
import 'llm_usage.dart';
import 'provider_factory.dart';
import 'sse_stream.dart';

/// A real HTTP `LlmClient` speaking the two dominant wire formats:
///
///   • **Anthropic Messages API**  (`https://api.anthropic.com/v1/messages`)
///   • **OpenAI Chat Completions** (`https://api.openai.com/v1/chat/completions`)
///     plus any OpenAI-compatible endpoint (OpenRouter, Kimi, xAI, custom…).
///
/// It streams via [SseStream] and normalizes both protocols onto the shared
/// [AgentStreamEvent] vocabulary the AgentLoop understands, so the web/Flutter
/// UI drives the exact same turn logic whether the back-end is Anthropic,
/// OpenAI or a local model.
class HttpLlmClient implements LlmClient {
  final HttpClient _http;

  HttpLlmClient({HttpClient? http}) : _http = http ?? HttpClient();

  static const _timeout = Duration(seconds: 120);

  @override
  Stream<AgentStreamEvent> complete(
    List<LlmMessage> messages, {
    required LlmRequestConfig config,
    List<Map<String, dynamic>> tools = const [],
    List<String>? stopSequences,
  }) async* {
    final key = config.apiKey.isNotEmpty
        ? config.apiKey
        : (config.apiKeyEnv.isNotEmpty
            ? SecretResolver.lookup(config.apiKeyEnv)
            : null);
    if (key == null) {
      yield StreamError(StateError('No API key for "${config.provider}". '
          'Add it via SecretResolver.seed().'));
      return;
    }

    switch (config.provider) {
      case 'anthropic':
        yield* _completeAnthropic(messages, config, key, tools, stopSequences);
      case 'gemini':
        yield* _completeGemini(messages, config, key, tools, stopSequences);
      default:
        yield* _completeOpenAi(messages, config, key, tools, stopSequences);
    }
  }

  // ---- Anthropic ----------------------------------------------------------

  Stream<AgentStreamEvent> _completeAnthropic(
    List<LlmMessage> messages,
    LlmRequestConfig config,
    String key,
    List<Map<String, dynamic>> tools,
    List<String>? stopSequences,
  ) async* {
    final url = '${(config.baseUrl.isEmpty
            ? 'https://api.anthropic.com'
            : config.baseUrl)}/v1/messages';

    final body = <String, dynamic>{
      'model': config.model,
      'max_tokens': config.maxTokens,
      'stream': true,
      'messages': [
        for (final m in messages)
          {'role': m.role, 'content': [for (final b in m.content) b.toJson()]},
      ],
      if (tools.isNotEmpty) 'tools': tools,
      if (stopSequences != null && stopSequences.isNotEmpty)
        'stop_sequences': stopSequences,
    };

    final req = await _http.postUrl(Uri.parse(url));
    req.headers
      ..contentType = ContentType.json
      ..set('x-api-key', key)
      ..set('anthropic-version', '2023-06-01')
      ..set('accept', 'text/event-stream');
    req.write(jsonEncode(body));

    final resp = await req.close().timeout(_timeout);
    if (resp.statusCode >= 400) {
      final err = await utf8.decoder.bind(resp).join();
      yield StreamError(HttpException('Anthropic ${resp.statusCode}: $err'),
          retryable: resp.statusCode >= 500);
      return;
    }

    final textBuf = StringBuffer();
    final events = SseStream.parse(resp, cancelSignal: null);
    await for (final (name, data) in events) {
      if (name != 'message' && !data.contains('"type"')) continue;
      final Map<String, dynamic> frame;
      try {
        frame = (jsonDecode(data) as Map).cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      final type = frame['type'] as String?;
      switch (type) {
        case 'content_block_delta':
          final delta = frame['delta'] as Map?;
          final dType = delta?['type'] as String?;
          if (dType == 'text_delta') {
            final t = (delta?['text'] as String?) ?? '';
            textBuf.write(t);
            yield TextDelta(t);
          } else if (dType == 'thinking_delta' ||
              dType == 'signature_delta') {
            final t = (delta?['thinking'] as String?) ?? '';
            if (t.isNotEmpty) yield ThinkingDelta(t);
          }
        case 'content_block_start':
          final block = frame['content_block'] as Map?;
          if (block?['type'] == 'tool_use') {
            yield ToolUseRequested(
              (block?['id'] as String?) ?? '',
              (block?['name'] as String?) ?? '',
              (block?['input'] as Map?)?.cast<String, dynamic>() ?? const {},
            );
          }
        case 'message_delta':
          final usage = frame['usage'] as Map?;
          if (usage != null) {
            yield UsageDelta(LlmUsage(
              inputTokens: usage['input_tokens'] as int? ?? 0,
              outputTokens: usage['output_tokens'] as int? ?? 0,
              cacheReadInputTokens:
                  usage['cache_read_input_tokens'] as int?,
              cacheCreationInputTokens:
                  usage['cache_creation_input_tokens'] as int?,
            ));
          }
        case 'message_stop':
          yield TurnFinished(textBuf.toString(), null);
        default:
          break;
      }
    }
    if (textBuf.isNotEmpty) {
      // Guard against a stream that ended without message_stop.
      yield TurnFinished(textBuf.toString(), null);
    }
  }

  // ---- OpenAI / compatible ------------------------------------------------

  Stream<AgentStreamEvent> _completeOpenAi(
    List<LlmMessage> messages,
    LlmRequestConfig config,
    String key,
    List<Map<String, dynamic>> tools,
    List<String>? stopSequences,
  ) async* {
    // OpenAI-compatible providers share the Chat Completions wire format; only
    // the endpoint differs. Kimi / xAI / Antigravity use their own base URLs.
    final base = config.baseUrl.isEmpty
        ? _openAiBase(config.provider)
        : (config.baseUrl.endsWith('/v1')
            ? config.baseUrl
            : '${config.baseUrl}/v1');
    final url = '$base/chat/completions';

    final body = <String, dynamic>{
      'model': config.model,
      'stream': true,
      // OpenAI-compatible tools use openai function schema; we adapt.
      'tools': _toOpenAiTools(tools),
      'messages': [
        for (final m in messages) {
          'role': m.role,
          'content': [
            for (final b in m.content)
              b.type == 'text' ? b.text ?? '' : b.toJson(),
          ].join(''),
        },
      ],
      if (stopSequences != null && stopSequences.isNotEmpty)
        'stop': stopSequences,
    };

    final req = await _http.postUrl(Uri.parse(url));
    req.headers
      ..contentType = ContentType.json
      ..set('Authorization', 'Bearer $key')
      ..set('accept', 'text/event-stream');
    req.write(jsonEncode(body));

    final resp = await req.close().timeout(_timeout);
    if (resp.statusCode >= 400) {
      final err = await utf8.decoder.bind(resp).join();
      yield StreamError(HttpException('OpenAI ${resp.statusCode}: $err'),
          retryable: resp.statusCode >= 500);
      return;
    }

    final textBuf = StringBuffer();
    await for (final (_, data) in SseStream.parse(resp)) {
      if (data.trim() == '[DONE]') break;
      final Map<String, dynamic> frame;
      try {
        frame = (jsonDecode(data) as Map).cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      final choice = ((frame['choices'] as List?) ?? [])
          .isEmpty
          ? null
          : ((frame['choices'] as List).first as Map).cast<String, dynamic>();
      if (choice == null) continue;

      final delta = choice['delta'] as Map?;
      final content = delta?['content'] as String?;
      if (content != null && content.isNotEmpty) {
        textBuf.write(content);
        yield TextDelta(content);
      }
      final toolCalls = delta?['tool_calls'] as List?;
      if (toolCalls != null) {
        for (final tc in toolCalls) {
          final t = (tc as Map).cast<String, dynamic>();
          final fn = (t['function'] as Map?)?.cast<String, dynamic>();
          final id = (t['id'] as String?) ?? '';
          final name = (fn?['name'] as String?) ?? '';
          final argStr = (fn?['arguments'] as String?) ?? '';
          Map<String, dynamic> args = const {};
          if (argStr.isNotEmpty) {
            try {
              args = (jsonDecode(argStr) as Map).cast<String, dynamic>();
            } catch (_) {
              args = {'_raw': argStr};
            }
          }
          if (name.isNotEmpty && id.isNotEmpty) {
            yield ToolUseRequested(id, name, args);
          }
        }
      }
      final usage = frame['usage'] as Map?;
      if (usage != null) {
        yield UsageDelta(LlmUsage(
          inputTokens: usage['prompt_tokens'] as int? ?? 0,
          outputTokens: usage['completion_tokens'] as int? ?? 0,
        ));
      }
    }
    yield TurnFinished(textBuf.toString(), null);
  }

  // ---- Gemini (streamGenerateContent) --------------------------------------

  Stream<AgentStreamEvent> _completeGemini(
    List<LlmMessage> messages,
    LlmRequestConfig config,
    String key,
    List<Map<String, dynamic>> tools,
    List<String>? stopSequences,
  ) async* {
    final base = config.baseUrl.isEmpty
        ? 'https://generativelanguage.googleapis.com/v1beta'
        : config.baseUrl;
    final url = '$base/models/${config.model}:streamGenerateContent?alt=sse&key=$key';

    // Convert normalized messages to Gemini's contents format.
    final contents = <Map<String, dynamic>>[];
    for (final m in messages) {
      final parts = <Map<String, dynamic>>[];
      for (final b in m.content) {
        if (b.type == 'text' && b.text != null && b.text!.isNotEmpty) {
          parts.add({'text': b.text});
        }
      }
      if (parts.isEmpty && m.role == 'user') parts.add({'text': ''});
      // Gemini pairs consecutive turns; assistant role maps to 'model'.
      contents.add(<String, dynamic>{
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': parts,
      });
    }

    final body = <String, dynamic>{
      'contents': contents,
      if (tools.isNotEmpty) 'tools': [_toGeminiTools(tools)],
      'generationConfig': {
        'temperature': config.temperature,
        'maxOutputTokens': config.maxTokens,
        if (stopSequences != null && stopSequences.isNotEmpty)
          'stopSequences': stopSequences,
      },
    };

    final req = await _http.postUrl(Uri.parse(url));
    req.headers
      ..contentType = ContentType.json
      ..set('accept', 'text/event-stream');
    req.write(jsonEncode(body));

    final resp = await req.close().timeout(_timeout);
    if (resp.statusCode >= 400) {
      final err = await utf8.decoder.bind(resp).join();
      yield StreamError(
          HttpException('Gemini ${resp.statusCode}: $err'),
          retryable: resp.statusCode >= 500);
      return;
    }

    final textBuf = StringBuffer();
    await for (final (_, data) in SseStream.parse(resp)) {
      final Map<String, dynamic> frame;
      try {
        frame = (jsonDecode(data) as Map).cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      final candidates = frame['candidates'] as List? ?? [];
      if (candidates.isEmpty) continue;
      final parts = ((candidates.first as Map)['content'] as Map?)?['parts'] as List? ?? [];
      for (final p in parts) {
        if (p is! Map) continue;
        final block = p;
        final t = block['text'];
        if (t is String && t.isNotEmpty) {
          textBuf.write(t);
          yield TextDelta(t);
        }
        final fnCall = block['functionCall'];
        if (fnCall is Map) {
          yield ToolUseRequested(
            (fnCall['id'] as String?) ??
                'g-${DateTime.now().microsecondsSinceEpoch}',
            (fnCall['name'] as String?) ?? '',
            (fnCall['args'] as Map?)?.cast<String, dynamic>() ??
                const {},
          );
        }
      }
      final usage = frame['usageMetadata'] as Map?;
      if (usage != null) {
        yield UsageDelta(LlmUsage(
          inputTokens:
              (usage['promptTokenCount'] as num?)?.toInt() ?? 0,
          outputTokens:
              ((usage['candidatesTokenCount'] as num?) ?? (usage['outputTokenCount'] as num?))
                      ?.toInt() ??
                  0,
        ));
      }
    }
    yield TurnFinished(textBuf.toString(), null);
  }

  /// Default `/v1` base URL for each OpenAI-compatible provider.
  String _openAiBase(String provider) {
    switch (provider) {
      case 'kimi':
        return 'https://api.moonshot.cn/v1';
      case 'xai':
        return 'https://api.x.ai/v1';
      case 'antigravity':
        return 'https://api.antigravity.ai/v1';
      case 'openrouter':
        return 'https://openrouter.ai/api/v1';
      default:
        return 'https://api.openai.com/v1';
    }
  }

  Map<String, dynamic> _toGeminiTools(List<Map<String, dynamic>> tools) {
    // Convert Anthropic-style tools into Gemini functionDeclarations.
    return <String, dynamic>{
      'functionDeclarations': [
        for (final t in tools)
          <String, dynamic>{
            'name': t['name'],
            'description': t['description'] ?? '',
            'parameters': t['input_schema'] ??
                <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{},
                },
          }
      ],
    };
  }

  List<Map<String, dynamic>> _toOpenAiTools(List<Map<String, dynamic>> tools) {
    // Accept Anthropic-style tool json and republish under OpenAI function
    // schema (name/description/parameters).
    return [
      for (final t in tools)
        <String, dynamic>{
          'type': 'function',
          'function': {
            'name': t['name'],
            'description': t['description'] ?? '',
            'parameters': t['input_schema'] ??
                <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{},
                },
          },
        },
    ];
  }
}
