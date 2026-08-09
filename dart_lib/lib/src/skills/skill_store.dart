import 'dart:io';

/// A skill: a folder with a `SKILL.md` file plus optional resources.
///
/// Ports `SkillStore.swift`. Metadata (name/description) stays in context so
/// the model can match triggers cheaply; the full body and bundled resources
/// load only when the skill is actually invoked, keeping context lean.
class Skill {
  final String id;
  final String name;
  final String description;

  /// Full markdown body, loaded on demand (not always in memory).
  final String bodyMarkdown;

  /// Bundled resources (relative paths within the skill folder).
  final List<String> resources;

  /// The on-disk directory holding this skill (for loading resources).
  final String? dir;

  /// Whether this skill is active/available for triggering.
  bool enabled;

  Skill({
    required this.id,
    required this.name,
    required this.description,
    this.bodyMarkdown = '',
    this.resources = const [],
    this.dir,
    this.enabled = true,
  });
}

/// [SkillStore] that discovers skills from a directory on disk.
///
/// Layout expected (compatible with the OpenMinis/Miniskills convention):
///
///   <skillsRoot>/
///     <skill-name>/
///       SKILL.md            ← front-matter (name/description) + instructions
///       scripts/…           ← resources (loaded only when invoked)
///
/// Front-matter is parsed from `SKILL.md`:
///   ---
///   name: my-skill
///   description: one-line trigger hint
///   ---
///
/// The full body is kept in memory only for enabled/matched skills; [body(s)]
/// reads the file from disk on demand.
class SkillStore {
  final String? rootDir;
  final Map<String, Skill> _skills = {};

  SkillStore({this.rootDir});

  /// Scan [rootDir] for skill folders and index their metadata.
  Future<void> scan() async {
    _skills.clear();
    final root = rootDir;
    if (root == null || !Directory(root).existsSync()) return;
    for (final d in Directory(root).listSync().whereType<Directory>()) {
      final f = File('${d.path}/SKILL.md');
      if (!f.existsSync()) continue;
      try {
        final skill = _parseSkill(f);
        _skills[skill.id] = skill;
      } catch (_) {
        // skip malformed skill folder
      }
    }
  }

  Skill _parseSkill(File skillMd) {
    final text = skillMd.readAsStringSync();
    final id = skillMd.parent.path.split('/').last;
    var name = id;
    var description = '';
    // Extract minimal front-matter for name/description.
    if (text.startsWith('---\n')) {
      final end = text.indexOf('\n---\n', 4);
      if (end > 0) {
        for (final line in text.substring(4, end).split('\n')) {
          final i = line.indexOf(':');
          if (i <= 0) continue;
          final k = line.substring(0, i).trim();
          var v = line.substring(i + 1).trim().replaceAll('"', '').trim();
          if (k == 'name') {
            name = v.isEmpty ? name : v;
          } else if (k == 'description') {
            description = v;
          }
        }
      }
    }
    // Discover bundled resources (files besides SKILL.md).
    final resources = <String>[];
    for (final f in skillMd.parent.listSync()) {
      if (f is File && f.path != skillMd.path) {
        resources.add(f.path.split('/').last);
      }
    }
    return Skill(
      id: id,
      name: name,
      description: description,
      bodyMarkdown: text,
      resources: resources,
      dir: skillMd.parent.path,
    );
  }

  List<Skill> get all => _skills.values
      .where((s) => s.enabled)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Skill? operator [](String id) => enabledOnly(id);

  Skill? enabledOnly(String id) {
    final s = _skills[id];
    return (s != null && s.enabled) ? s : null;
  }

  void put(Skill s) => _skills[s.id] = s;

  void putAll(Iterable<Skill> skills) => skills.forEach(put);

  void remove(String id) => _skills.remove(id);

  void setEnabled(String id, bool enabled) {
    final s = _skills[id];
    if (s != null) s.enabled = enabled;
  }

  /// The full skill instructions (loaded from disk if it was discovered).
  String body(String id) {
    final s = _skills[id];
    if (s == null) return '';
    if (s.bodyMarkdown.isNotEmpty) return s.bodyMarkdown;
    final dir = s.dir;
    if (dir == null) return '';
    final f = File('$dir/SKILL.md');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  /// Match skills whose description/name contains any [keywords] (case-insensitive).
  List<Skill> search(String keywords) {
    final q = keywords.toLowerCase();
    return all
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.description.toLowerCase().contains(q))
        .toList();
  }
}
