/// Persistent agent persona/memory, porting `SoulStore.swift`.
///
/// A "soul" is a body of persistent instructions/memory that colors every turn
/// without being reloaded per skill. This lightweight store keeps the active
/// soul plus a write-ahead of memory notes that cross sessions.
class SoulStore {
  /// The active soul's system-role instructions (GLOBAL.md-style).
  String _globalRules = '';

  /// Persistent memory notes, newest first.
  final List<MemoryNote> _memory = [];

  String get globalRules => _globalRules;

  void setGlobalRules(String rules) => _globalRules = rules;

  List<MemoryNote> get memory => List.unmodifiable(_memory);

  void add(String note, {String? context}) {
    _memory.insert(0, MemoryNote(note, context: context));
    if (_memory.length > 500) {
      _memory.removeRange(500, _memory.length);
    }
  }

  /// Search memory + global rules for entries containing all [keywords].
  List<String> search(String keywords) {
    final kws = keywords.toLowerCase().split(' ');
    bool match(String s) {
      final low = s.toLowerCase();
      return kws.every(low.contains);
    }

    final results = <String>[];
    if (kws.isNotEmpty && match(_globalRules)) {
      results.add(globalRules);
    }
    for (final n in _memory) {
      if (match(n.text)) results.add('${n.text}${n.context != null ? ' (${n.context})' : ''}');
    }
    return results;
  }
}

class MemoryNote {
  final String text;
  final String? context;
  final DateTime timestamp;
  MemoryNote(this.text, {this.context, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}
