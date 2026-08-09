import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Agent persona / soul rules editor (GLOBAL.md style).
class SoulSettingsScreen extends StatefulWidget {
  const SoulSettingsScreen({super.key});

  @override
  State<SoulSettingsScreen> createState() => _SoulSettingsScreenState();
}

class _SoulSettingsScreenState extends State<SoulSettingsScreen> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: context.read<AppState>().souls.globalRules);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    context.read<AppState>().souls.setGlobalRules(_controller.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Soul 规则已保存'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(
        title: 'Agent 人格 (Soul)',
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '设置 agent 在每次对话中都遵循的全局规则/人格（等价于 GLOBAL.md）。',
                style: TextStyle(fontSize: 12, color: MinisTheme.textMuted),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 13, height: 1.6, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: '# Agent rules\n\n你是一个…\n',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
