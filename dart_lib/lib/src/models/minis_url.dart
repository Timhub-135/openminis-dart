/// The `minis://` URL scheme used throughout the original app.
///
/// Mirrors `MinisURLPathDecoding.swift` and the URL derivation in
/// `AttachmentMeta.minisURL`. A `minis://` URL is app-internal (NOT a web URL)
/// and maps onto paths under `/var/minis/` on a platform where the sandbox
/// lives. In this Dart rewrite the scheme is resolved through a platform
/// adapter, so Windows and Android can both serve the same URL space.
class MinisUrl {
  static const String prefix = 'minis://';

  /// The root of the app's writable space, e.g. `/var/minis`.
  static const String rootPrefix = '/var/minis/';

  /// The `minis://` authority segment maps one-to-one onto the sub-folder
  /// under `/var/minis/`. Known authorities:
  ///   attachments, workspace, offloads, browser, shared, memory, skills, mounts
  final String authority;
  final String path;

  /// The exact original URL string if this was produced by [parse] (so
  /// percent-encoding survives round-trip). When built programmatically this is
  /// reconstructed.
  final String? _original;

  const MinisUrl._(this.authority, this.path, [this._original]);

  String get full => _original ?? '$_prefixRaw$authority/$path';

  static const String _prefixRaw = 'minis://';

  /// Derive a `minis://` URL from a Linux path under `/var/minis/`.
  /// Non-ASCII characters are percent-encoded so Markdown/HTML render cleanly.
  static String fromLinuxPath(String linuxPath) {
    if (linuxPath.startsWith(prefix)) return linuxPath;
    if (!linuxPath.startsWith(rootPrefix)) return linuxPath;
    final rel = linuxPath.substring(rootPrefix.length);
    final segs =
        rel.split('/').map((s) => Uri.encodeComponent(s)).join('/');
    return '$prefix$segs';
  }

  /// Build a URL directly from an authority + path (path already relative).
  static String url(String authority, String relPath) {
    final segs = relPath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return '$prefix$authority/$segs';
  }

  /// Parse a `minis://` URL back into (authority, decoded path segments).
  /// Preserves the original encoding via [full].
  static MinisUrl? parse(String url) {
    if (!url.startsWith(prefix)) return null;
    var rest = url.substring(prefix.length);
    rest = rest.replaceAll(RegExp(r'^//+'), '');
    final slash = rest.indexOf('/');
    final authority = slash < 0 ? rest : rest.substring(0, slash);
    final rel = slash < 0
        ? ''
        : rest
            .substring(slash + 1)
            .split('/')
            .map(Uri.decodeComponent)
            .join('/');
    return MinisUrl._(authority, rel, url);
  }

  /// Map a parsed URL to a real filesystem location via a root prefix.
  /// [platformRoot] is where the pseudo-root `/var/minis` actually lives on
  /// the current OS (e.g. the app's data/home dir on Windows, app files on
  /// Android). Returns null if the authority is unknown.
  static String? resolveOnDisk(String url, String platformRoot) {
    final p = parse(url);
    if (p == null) return null;
    return '$platformRoot/${p.authority}/${p.path}';
  }

  @override
  String toString() => full;

  String maybeEncode(String authority, String path) => full;
}
