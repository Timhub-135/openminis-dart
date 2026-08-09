import 'package:flutter/material.dart';
import 'package:openminis_core/openminis.dart' show ProviderConfig;
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../widgets/minis_app_bar.dart';

/// Provider management, simplified: just add a custom provider by giving an
/// API base URL and an API key. The protocol is auto-detected from the base.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _model = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _add() {
    final name = _name.text.trim();
    final base = _baseUrl.text.trim();
    final key = _apiKey.text.trim();
    if (name.isEmpty || base.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称、API Base 和 API Key 都是必填')),
      );
      return;
    }
    final app = context.read<AppState>();
    app.addProvider(ProviderConfig(
      id: 'p-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      baseUrl: base,
      apiKey: key,
      model: _model.text.trim().isEmpty ? 'default' : _model.text.trim(),
    ));
    _name.clear();
    _baseUrl.clear();
    _apiKey.clear();
    _model.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加 provider 并设为当前使用')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final providers = app.providerOptions.where((p) => p.id != 'echo').toList();

    return Scaffold(
      backgroundColor: MinisTheme.bg,
      appBar: MinisAppBar(title: 'Provider 管理'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '只需填 API Base URL 和 API Key。协议自动识别：'
              '含 anthropic 用 Anthropic，含 generativelanguage 用 Gemini，其余走 OpenAI 兼容。',
              style: TextStyle(fontSize: 12, color: MinisTheme.textMuted, height: 1.5),
            ),
          ),
          // Add form
          Container(
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
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: 'https://api.openai.com/v1',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(
                    labelText: '模型（可选，默认 default）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKey,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('添加'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('已配置 (${providers.length})',
              style: const TextStyle(fontSize: 12, color: MinisTheme.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (providers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('还没有自定义 provider。用上面的表单添加一个。',
                    style: TextStyle(color: MinisTheme.textMuted)),
              ),
            )
          else
            for (final p in providers) _providerCard(context, app, p),
        ],
      ),
    );
  }

  Widget _providerCard(BuildContext context, AppState app, ProviderConfig p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MinisTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: app.providerId == p.id ? MinisTheme.accent : MinisTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            p.ready ? Icons.check_circle : Icons.error_outline,
            color: p.ready ? MinisTheme.accentGreen : MinisTheme.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${p.protocol} · ${p.model}',
                    style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
                Text(p.baseUrl,
                    style: const TextStyle(fontSize: 11, color: MinisTheme.textMuted)),
              ],
            ),
          ),
          ChoiceChip(
            label: Text(app.providerId == p.id ? '使用中' : '选用'),
            selected: app.providerId == p.id,
            onSelected: (_) => app.setProvider(p.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => app.removeProvider(p.id),
          ),
        ],
      ),
    );
  }
}
