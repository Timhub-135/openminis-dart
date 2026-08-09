import 'dart:async';

import '../models/roles.dart';
import '../providers/llm_client.dart';
import '../providers/llm_message.dart';
import '../store/chat_store.dart';

/// Generates a concise, human-readable session title from an opening prompt.
///
/// Ports the essence of `AIChatViewModel+TitleGeneration.swift`: after a
/// session has a user message, it asks the LLM for a short title, falling back
/// to a deterministic truncation when no model / key is configured (so the
/// feature still works offline).
class TitleGenerator {
  final ChatStore store;
  final LlmClient? llm;
  final LlmRequestConfig? config;
  final int maxTitleLength;

  TitleGenerator({
    required this.store,
    this.llm,
    this.config,
    this.maxTitleLength = 30,
  });

  /// Generate and apply a title for [sessionId] if it doesn't already have one.
  /// Returns the new title (or existing one).
  Future<String> ensureTitle(String sessionId) async {
    final s = await store.adapter.sessionById(sessionId);
    if (s == null) return '';
    if (s.title.isNotEmpty && s.title != '未命名会话') return s.title;

    // Find the first non-empty user message to base the title on.
    final msgs = await store.messages(sessionId);
    final firstUser = msgs
        .where((m) => m.role == ChatRole.user && m.content.trim().isNotEmpty)
        .toList();
    final base = firstUser.isEmpty ? '' : firstUser.first.content.trim();

    String title;
    if (llm != null && config != null && config!.hasKey && base.isNotEmpty) {
      title = (await _askLlm(base)).trim();
    } else {
      title = _fallback(base);
    }
    if (title.isEmpty) title = '未命名会话';
    if (title.length > maxTitleLength) {
      title = '${title.substring(0, maxTitleLength)}…';
    }
    s.title = title;
    await store.adapter.upsertSession(s);
    return title;
  }

  Future<String> _askLlm(String prompt) async {
    try {
      final out = StringBuffer();
      await for (final ev in llm!.complete(
        [
          LlmMessage.text(
              'user', '用不超过15个字给下面的会话起一个标题，只输出标题本身：\n$prompt'),
        ],
        config: config!,
        tools: const [],
      )) {
        if (ev is TextDelta) out.write(ev.text);
      }
      return out.toString().replaceAll('\n', ' ').trim();
    } catch (_) {
      return _fallback(prompt);
    }
  }

  String _fallback(String base) {
    if (base.isEmpty) return '未命名会话';
    final t = base.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return t.length > maxTitleLength ? t.substring(0, maxTitleLength) : t;
  }
}
