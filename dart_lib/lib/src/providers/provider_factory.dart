import '../models/platform_info.dart';

/// Resolves API keys by environment-variable name, without ever echoing the
/// value into logs. The host app (Flutter) seeds [overrides] from its own
/// secure keychain per platform at startup.
///
/// Web-safe: uses [PlatformInfo] (no `dart:io`) so reads are harmless on the
/// browser — secrets seeded by the host come from [seed], or from env on
/// native.
class SecretResolver {
  SecretResolver._();

  /// name -> secret value. Never logged; core code reads via [lookup].
  static final Map<String, String> _overrides = {};

  /// Seed secrets from the host (Flutter) layer at startup.
  static void seed(Map<String, String> secrets) {
    _overrides.addAll(secrets);
  }

  /// True if [name] is set.
  static bool has(String name) {
    if (_overrides.containsKey(name)) return true;
    return _platformEnv(name) != null;
  }

  /// Resolve [name] to its value, if set.
  static String? lookup(String name) {
    if (_overrides.containsKey(name)) return _overrides[name];
    try {
      return _platformEnv(name);
    } catch (_) {
      return null;
    }
  }

  static String? _platformEnv(String name) => PlatformInfo.environment(name);
}

/// Builds prefix-keyed resolver: strips a prefix before lookup.
class PrefixedSecretResolver {
  final String prefix;
  const PrefixedSecretResolver(this.prefix);

  String? resolve(String envName) {
    final bare = envName.startsWith(prefix)
        ? envName.substring(prefix.length)
        : envName;
    return SecretResolver.lookup(bare) ?? SecretResolver.lookup(envName);
  }
}
