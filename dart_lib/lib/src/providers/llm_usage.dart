/// Provider-neutral usage report.
///
/// Mirrors the `LLMUsage` type in the original provider layer.
class LlmUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheReadInputTokens;
  final int? cacheCreationInputTokens;

  const LlmUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadInputTokens,
    this.cacheCreationInputTokens,
  });

  Map<String, dynamic> toJson() => {
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        if (cacheReadInputTokens != null)
          'cacheReadInputTokens': cacheReadInputTokens,
        if (cacheCreationInputTokens != null)
          'cacheCreationInputTokens': cacheCreationInputTokens,
      };
}
