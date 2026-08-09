import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// About screen: version, device, attribution.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: '关于'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [MinisTheme.accent, MinisTheme.accentGreen],
                ),
              ),
              child: const Center(
                child: Text('M', style: TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: Text('OpenMinis', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          const Center(child: Text('Dart × Flutter 重写 · Windows + Android', style: TextStyle(fontSize: 12, color: MinisTheme.textMuted))),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MinisTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MinisTheme.border),
            ),
            child: Column(
              children: [
                _row('设备', app.deviceId),
                _row('版本', '0.1.0'),
                _row('许可', 'GPL v3'),
                _row('核心', 'openminis_core (dart_lib)'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'OpenMinis 是开源的私有 AI agent：自带模型、Linux 沙盒、技能与记忆、跨平台同步。'
            '本重写版保留核心能力，并以 Docker+Alpine（Windows）与 Termux（Android）提供 Linux shell。',
            style: TextStyle(fontSize: 12, color: MinisTheme.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(k, style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
