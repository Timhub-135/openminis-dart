/// Request budget limiting how many tool turns / tokens an agent turn may use
/// before the loop yields. Ports the budget logic surfaced in
/// `AIChatViewModel+RequestBudget.swift`.
class RequestBudget {
  final int maxToolRounds;
  final int maxTotalToolCalls;
  final int maxOutputTokens;

  int toolRounds = 0;
  int toolCalls = 0;
  int outputTokensConsumed = 0;

  RequestBudget({
    this.maxToolRounds = 25,
    this.maxTotalToolCalls = 40,
    this.maxOutputTokens = 1 << 18, // 256k
  });

  bool get canContinue {
    if (toolRounds >= maxToolRounds) return false;
    if (toolCalls >= maxTotalToolCalls) return false;
    if (outputTokensConsumed >= maxOutputTokens) return false;
    return true;
  }

  /// Record one tool round (a full model response plus its tool executions).
  void recordToolRound() => toolRounds++;

  void recordToolCall() => toolCalls++;

  void recordOutputTokens(int n) => outputTokensConsumed += n;
}
