/// Token usage for an assistant turn.
///
/// Mirrors `TokenUsage` in `src/ios/Agent/Chat/ChatModels.swift`. Uses `max`
/// rather than `+=` when folding an [LlmUsage] so providers that stream
/// *cumulative* usage on every SSE chunk don't inflate totals quadratically
/// (0 + 1 + 2 + ... + N ≈ N²/2).
class TokenUsage {
  int inputTokens;
  int outputTokens;
  int cacheCreationTokens;
  int cacheReadTokens;

  /// Context size of the latest API call (input + cache_read + cache_creation).
  int latestContextTokens;

  TokenUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
    this.latestContextTokens = 0,
  });

  /// Fold a single provider usage report into this cumulative usage.
  void add(int input, int output, {int? cacheRead, int? cacheCreation}) {
    inputTokens = _max(inputTokens, input);
    outputTokens = _max(outputTokens, output);
    cacheCreationTokens = cacheCreation ?? cacheCreationTokens;
    cacheReadTokens = cacheRead ?? cacheReadTokens;
    latestContextTokens =
        input + (cacheRead ?? 0) + (cacheCreation ?? 0);
  }

  static int _max(int a, int b) => a > b ? a : b;

  Map<String, dynamic> toJson() => {
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'cacheCreationTokens': cacheCreationTokens,
        'cacheReadTokens': cacheReadTokens,
        'latestContextTokens': latestContextTokens,
      };

  factory TokenUsage.fromJson(Map<String, dynamic> j) => TokenUsage(
        inputTokens: j['inputTokens'] as int? ?? 0,
        outputTokens: j['outputTokens'] as int? ?? 0,
        cacheCreationTokens: j['cacheCreationTokens'] as int? ?? 0,
        cacheReadTokens: j['cacheReadTokens'] as int? ?? 0,
        latestContextTokens: j['latestContextTokens'] as int? ?? 0,
      );

  @override
  String toString() =>
      'TokenUsage(i:$inputTokens o:$outputTokens c:$cacheCreationTokens r:$cacheReadTokens ctx:$latestContextTokens)';
}
