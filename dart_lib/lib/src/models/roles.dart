/// Role of a chat message.
///
/// Mirrors `ChatMessageRole` in `src/ios/Agent/Chat/ChatModels.swift`.
enum ChatRole {
  user,
  assistant,

  /// A visual separator showing where context was compacted.
  compactDivider,

  /// Ephemeral UI-only info message (not sent to LLM, not persisted).
  systemInfo;

  /// The wire/API role string sent to an LLM provider. Compaction dividers and
  /// system-info rows have no provider representation.
  String? get apiRole => switch (this) {
        ChatRole.user => 'user',
        ChatRole.assistant => 'assistant',
        _ => null,
      };

  /// Malformed/unknown string -> [ChatRole.user] like the original's default.
  static ChatRole fromWire(String? s) => switch (s) {
        'user' => ChatRole.user,
        'assistant' => ChatRole.assistant,
        'compactDivider' => ChatRole.compactDivider,
        'systemInfo' => ChatRole.systemInfo,
        _ => ChatRole.user,
      };
}
