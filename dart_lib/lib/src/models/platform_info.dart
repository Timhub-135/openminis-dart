/// Cross-platform "current OS" info that avoids `dart:io` so the core can
/// compile for the web.
///
/// The host (Flutter native vs web) sets the values at startup via
/// [setPlatformInfo]. Defaults are web-safe; on the browser there is no
/// `dart:io` so any native branch is skipped.
class PlatformInfo {
  static String _os = 'web';
  static bool _web = true;

  /// Current OS name: 'windows' | 'linux' | 'android' | 'web' | 'ios'.
  static String get operatingSystem => _os;

  /// True when running in a browser build (no dart:io).
  static bool get isWeb => _web;

  /// True when a native dart:io host is present.
  static bool get isNative => !_web;

  /// The environment value for a key, or null. Web returns null (no env).
  static String? environment(String key) => _web ? null : _envValue(key);

  // Native env map injected by the host (only meaningful on native).
  static String? Function(String key)? _envProvider;
  static String? _envValue(String key) => _envProvider?.call(key);

  /// Set by the host at bootstrap.
  static void setPlatformInfo({required String os, required bool isWeb}) {
    _os = os;
    _web = isWeb;
  }

  /// Provide a native environment lookup (called on native targets only).
  static void setEnvProvider(String? Function(String key) provider) {
    _envProvider = provider;
  }
}
