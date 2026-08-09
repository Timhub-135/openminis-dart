import '../models/chat_message.dart';
import '../models/roles.dart';
import '../providers/llm_client.dart';
import '../providers/llm_message.dart';

/// History compaction policy, porting the `<compaction>` / `ContextPolicy`
/// behaviour in the original that folds old turns behind a `compactDivider`
/// once a session grows past a token budget, so the LLM context stays lean.
class CompactionPolicy {
  /// Above this many raw messages we consider compacting.
  final int thresholdMessages;
  final int keepRecentMessages;

  const CompactionPolicy({
    this.thresholdMessages = 60,
    this.keepRecentMessages = 30,
  });

  /// Compute the split index such that the newest [keepRecentMessages] messages
  /// survive intact and older ones are candidates for a compact divider.
  int? compactCut(List<ChatMessage> ordered) {
    if (ordered.length < thresholdMessages) return null;
    final cut = ordered.length - keepRecentMessages;
    return cut < 2 ? null : cut;
  }
}

/// A pending compaction that folds a range of messages into a divider holding
/// an LLM-generated summary. The agent loop triggers the LLM summarisation; the
/// store does the fold.
class CompactionCandidate {
  final List<ChatMessage> folded;
  final int sourceSortOrder;
  final int lastSourceSortOrder;

  CompactionCandidate({
    required this.folded,
    required this.sourceSortOrder,
    required this.lastSourceSortOrder,
  });

  /// Build a divider message carrying the summary text.
  ChatMessage dividerFor(String sessionId, {required String summary}) {
    final d = ChatMessage(
      sessionId: sessionId,
      role: ChatRole.compactDivider,
      content: summary,
    );
    d.isCompactedHistory = true;
    d.sourceSortOrder = sourceSortOrder;
    d.lastSourceSortOrder = lastSourceSortOrder;
    return d;
  }

  /// Summarize the folded messages with an LLM (porting the original's
  /// LLM-driven compact summary). Falls back to a deterministic length+count
  /// line if no client/key is configured.
  Future<String> summarize(
    LlmClient client,
    LlmRequestConfig config,
  ) async {
    // Build a brief transcript for the LLM.
    final lines = folded.map((m) {
      final who = m.role == ChatRole.user ? '用户' : '助手';
      final c = m.content.trim();
      return c.isEmpty ? '' : '$who: ${_clip(c)}';
    }).where((s) => s.isNotEmpty).take(60).toList();
    if (lines.isEmpty) return '（压缩了 ${folded.length} 条消息，无文本可摘要）';

    if (config.hasKey && lines.isNotEmpty) {
      try {
        final out = StringBuffer();
        final prompt = '''
用3-4句话概括下面这段对话的讨论主题与结论，作为历史摘要：
${lines.join('\n')}
''';
        await for (final ev in client.complete(
          [LlmMessage.text('user', prompt)],
          config: config,
          tools: const [],
        )) {
          if (ev is TextDelta) out.write(ev.text);
        }
        final s = out.toString().trim();
        if (s.isNotEmpty) return s;
      } catch (_) {
        // fall through
      }
    }
    return '（摘要）讨论了 ${lines.length} 条要点，共 ${folded.length} 条消息被压缩至此。';
  }

  String _clip(String s) =>
      s.length > 120 ? '${s.substring(0, 120)}…' : s;
}
