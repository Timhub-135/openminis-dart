import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// MCP (Model Context Protocol) integration management.
/// A MCP server entry: STDIO (command+args+env) or HTTP (url+headers).
class McpServerEntry {
  String id;
  bool enabled;
  String transport; // 'stdio' | 'http'
  String command;
  List<String> args;
  Map<String, String> env;
  String url;
  Map<String, String> headers;

  McpServerEntry({
    required this.id,
    this.enabled = true,
    this.transport = 'stdio',
    this.command = '',
    this.args = const [],
    this.env = const {},
    this.url = '',
    this.headers = const {},
  });

  String get summary {
    if (transport == 'http' && url.isNotEmpty) return url;
    return <String>[command, ...args].join(' ');
  }
}

/// MCP integration list + add stub. Full stdio process management lives in the
/// core; this UI manages the server configuration store (mirrors MCPStore).
class McpScreen extends StatefulWidget {
  const McpScreen({super.key});

  @override
  State<McpScreen> createState() => _McpScreenState();
}

class _McpScreenState extends State<McpScreen> {
  final List<McpServerEntry> _servers = [];
  final TextEditingController _name = TextEditingController();
  final TextEditingController _command = TextEditingController();
  final TextEditingController _url = TextEditingController();
  bool _http = false;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _url.dispose();
    super.dispose();
  }

  void _add() {
    final id = _name.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _servers.add(McpServerEntry(
        id: id,
        transport: _http ? 'http' : 'stdio',
        command: _command.text.trim(),
        url: _url.text.trim(),
      ));
      _name.clear();
      _command.clear();
      _url.clear();
      _http = false;
    });
  }

  void _importJson() {
    // In a full build this parses a Claude-Desktop mcpServers JSON. For the
    // scaffold it imports a couple of example entries.
    setState(() {
      _servers.clear();
      _servers.add(McpServerEntry(
          id: 'filesystem',
          command: 'npx',
          args: ['-y', '@modelcontextprotocol/server-filesystem', '/workspace']));
      _servers.add(McpServerEntry(
          id: 'memory-example',
          command: 'npx',
          args: ['-y', '@modelcontextprotocol/server-memory']));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(
        title: 'MCP 集成',
        actions: [
          TextButton.icon(
            onPressed: _importJson,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('导入示例'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Add form.
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MinisTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MinisTheme.border),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '名称', isDense: true),
                ),
                const SizedBox(height: 8),
                if (_http)
                  TextField(
                    controller: _url,
                    decoration: const InputDecoration(labelText: 'HTTP URL', isDense: true),
                  )
                else
                  TextField(
                    controller: _command,
                    decoration: const InputDecoration(labelText: '启动命令 (如 npx …)', isDense: true),
                  ),
                Row(
                  children: [
                    const Text('传输方式', style: TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
                    const SizedBox(width: 8),
                    FilterChip(label: const Text('STDIO', style: TextStyle(fontSize: 11)),
                        selected: !_http,
                        onSelected: (_) => setState(() => _http = false)),
                    const SizedBox(width: 6),
                    FilterChip(label: const Text('HTTP', style: TextStyle(fontSize: 11)),
                        selected: _http,
                        onSelected: (_) => setState(() => _http = true)),
                    const Spacer(),
                    FilledButton(onPressed: _add, child: const Text('添加')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('已配置 ${app.tools.all.length} 个内置工具 · MCP server 数:',
                  style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _servers.isEmpty
                ? const Center(child: Text('尚未添加 MCP server', style: TextStyle(color: MinisTheme.textMuted)))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _servers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final s = _servers[i];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: MinisTheme.panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: MinisTheme.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.api, size: 18,
                                color: s.enabled ? MinisTheme.accentGreen : MinisTheme.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.id, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(s.summary,
                                      style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
                                ],
                              ),
                            ),
                            Switch(
                              value: s.enabled,
                              activeTrackColor: MinisTheme.accent.withValues(alpha: 0.6),
                              onChanged: (v) => setState(() => s.enabled = v),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
