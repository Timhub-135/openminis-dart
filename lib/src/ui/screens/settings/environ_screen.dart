import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart' show SecretResolver;

import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Environment variables management. Values are masked; new entries can be
/// added. Real secret values are stored at the platform layer / injected by
/// the host; this screen only tracks which keys are set.
class EnvScreen extends StatefulWidget {
  const EnvScreen({super.key});

  @override
  State<EnvScreen> createState() => _EnvScreenState();
}

class _EnvScreenState extends State<EnvScreen> {
  final List<String> _keys = [];
  final TextEditingController _newKey = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Show the known provider keys and whether they're configured.
    const known = ['ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'OPENROUTER_API_KEY'];
    for (final k in known) {
      if (SecretResolver.has(k)) _keys.add('$k=••••••');
    }
    if (_keys.isEmpty) _keys.addAll(known.map((k) => '$k=(未设置)'));
  }

  @override
  void dispose() {
    _newKey.dispose();
    super.dispose();
  }

  void _add() {
    final k = _newKey.text.trim().toUpperCase();
    if (k.isEmpty) return;
    setState(() {
      if (_keys.contains(k) || _keys.where((e) => e.startsWith(k)).isNotEmpty) return;
      _keys.add('$k=(待设置, 保存后写入 env)');
      _newKey.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '环境变量'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MinisTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MinisTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('API keys 等敏感值只在写入时可见，读取时一律脱敏。',
                    style: TextStyle(fontSize: 12, color: MinisTheme.textMuted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newKey,
                        decoration: const InputDecoration(
                            hintText: '新增变量名，如 MY_APP_KEY', isDense: true),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('已配置条目 (${_keys.length})',
              style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final k in _keys)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MinisTheme.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MinisTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.key, size: 15, color: MinisTheme.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(k,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
                  Text(k.contains('未设置') ? '未设置' : '已配置',
                      style: TextStyle(
                          fontSize: 11,
                          color: k.contains('未设置') ? MinisTheme.textMuted : MinisTheme.accentGreen)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
