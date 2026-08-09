import '../tools/tool_registry.dart';

/// Preflight validation run before an agent turn accepts tool calls, mirroring
/// `AIChatViewModel+ToolPreflight.swift`'s concern of catching bad arguments
/// before they reach native/platform handlers.
class ToolPreflight {
  final ToolRegistry registry;

  ToolPreflight(this.registry);

  /// Validate [name]/[args] against the registered tool's parameter schema.
  /// Returns null on success, or a user-friendly error string.
  String? validate(String name, Map<String, dynamic> args) {
    final tool = registry[name];
    if (tool == null) {
      return 'Unknown tool: "$name"';
    }
    for (final p in tool.params) {
      if (p.required && !args.containsKey(p.name)) {
        return 'Tool "$name" is missing required argument "${p.name}"';
      }
      if (args.containsKey(p.name) && !_typeMatches(p.type, args[p.name])) {
        return 'Tool "$name" argument "${p.name}" must be $p.type';
      }
    }
    return null;
  }

  bool _typeMatches(String type, Object? value) {
    switch (type) {
      case 'string':
        return value is String;
      case 'integer':
        return value is int;
      case 'number':
        return value is num;
      case 'boolean':
        return value is bool;
      case 'array':
        return value is List;
      case 'object':
        return value is Map;
      case 'null':
        return value == null;
      default:
        return true;
    }
  }
}
