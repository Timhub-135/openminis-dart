import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme.dart';

/// A compact status pill showing sync state and busy indicator.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final busy = app.busy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Busy / ready dot.
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: busy
                ? MinisTheme.accentBright
                : (app.syncError ? MinisTheme.danger : MinisTheme.accentGreen),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          busy ? '运行中…' : (app.syncError ? '同步异常' : '就绪'),
          style: TextStyle(
            fontSize: 11,
            color: busy ? MinisTheme.accentBright : (app.syncError ? MinisTheme.danger : MinisTheme.textMuted),
          ),
        ),
        const SizedBox(width: 12),
        Icon(
          app.sync != null ? Icons.sync : Icons.sync_disabled,
          size: 14,
          color: app.sync == null ? MinisTheme.textMuted : MinisTheme.accentGreen,
        ),
        const SizedBox(width: 3),
        if (app.sync != null)
          Text(app.syncMessage, style: const TextStyle(fontSize: 10, color: MinisTheme.textMuted)),
      ],
    );
  }
}
