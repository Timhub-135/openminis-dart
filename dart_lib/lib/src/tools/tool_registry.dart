import 'tool.dart';

/// Registry that holds the tools available to the agent.
///
/// Ports the tool-discovery surface from the original. Tools can be registered
/// by the host app (native offloads on each platform) or dynamically added.
class ToolRegistry {
  final Map<String, Tool> _tools = {};
  final List<ToolRegistryListener> _listeners = [];

  void register(Tool tool) {
    _tools[tool.name] = tool;
    for (final l in _listeners) {
      l.onRegistered(tool);
    }
  }

  void registerAll(Iterable<Tool> tools) {
    for (final t in tools) {
      register(t);
    }
  }

  Tool? operator [](String name) => _tools[name];

  bool has(String name) => _tools.containsKey(name);

  List<Tool> get all => _tools.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  void addListener(ToolRegistryListener l) => _listeners.add(l);
  void removeListener(ToolRegistryListener l) => _listeners.remove(l);
}

abstract class ToolRegistryListener {
  void onRegistered(Tool tool);
}
