/// Tools exposed to the agent, ported from `AIChatViewModel+ToolDefinitions`.
library;

import 'dart:async';

/// JSON Schema-style argument descriptor for one tool parameter.
class ToolParam {
  final String name;
  final String description;
  final bool required;
  final String type; // string | integer | number | boolean | array | object | null
  final List<String>? enumValues;

  const ToolParam({
    required this.name,
    required this.description,
    this.required = false,
    this.type = 'string',
    this.enumValues,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'required': required,
        'type': type,
        if (enumValues != null) 'enum': enumValues,
      };
}

/// A tool invocation result returned by [Tool.invoke].
class ToolResult {
  final bool ok;
  final String output;

  /// True if this tool mutated shared state / a file and should mark the
  /// session dirty for cross-platform sync.
  final bool mutated;

  const ToolResult.ok(this.output, {this.mutated = false}) : ok = true;
  const ToolResult.fail(this.output, {this.mutated = false}) : ok = false;
}

/// Signature of a tool's raw invocation.
typedef ToolHandler = Future<ToolResult> Function(
    Map<String, dynamic> args);

/// A runnable tool.
class Tool {
  final String name;
  final String description;
  final List<ToolParam> params;
  final ToolHandler handler;

  /// The category/namespace, e.g. `linux_shell`, `browser`, `memory`, `sync`.
  final String category;

  const Tool({
    required this.name,
    required this.description,
    this.params = const [],
    required this.handler,
    this.category = 'core',
  });

  /// Render this tool in the provider-facing (Anthropic/OpenAI) `tools` list.
  Map<String, dynamic> toProviderJson() => {
        'name': name,
        'description': description,
        'input_schema': {
          'type': 'object',
          'properties': {
            for (final p in params) p.name: {
              'type': p.type,
              'description': p.description,
              if (p.enumValues != null) 'enum': p.enumValues,
            }
          },
          'required': [for (final p in params) if (p.required) p.name],
        },
      };

  Future<ToolResult> invoke(Map<String, dynamic> args) => handler(args);

  @override
  String toString() => 'Tool($name)';
}
