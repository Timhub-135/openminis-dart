/// A user-configured provider: only an API base URL and an API key are needed.
/// The wire protocol (Anthropic / Gemini / OpenAI-compatible) is auto-detected
/// from the base URL. `echo` is the built-in local fallback (no network).
class ProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;

  const ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
  });

  /// The normalized protocol key derived from the base URL.
  String get protocol {
    if (baseUrl.contains('anthropic')) return 'anthropic';
    if (baseUrl.contains('generativelanguage')) return 'gemini';
    return 'openai'; // everything else is OpenAI-compatible
  }

  bool get ready => apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> j) => ProviderConfig(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        baseUrl: j['baseUrl'] as String? ?? '',
        model: j['model'] as String? ?? '',
      );
}
