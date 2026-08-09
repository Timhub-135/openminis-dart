import 'package:flutter/material.dart';
import '../../theme.dart';

/// Status of a tool call shown as a pill.
enum ToolChipStatus { streaming, running, success, failed }

/// A pill showing a tool invocation and its live status.
class ToolChip extends StatelessWidget {
  final String name;
  final ToolChipStatus status;
  final String? errorOutput;
  const ToolChip({
    super.key,
    required this.name,
    required this.status,
    this.errorOutput,
  });

  Color get _color => switch (status) {
        ToolChipStatus.streaming => MinisTheme.textMuted,
        ToolChipStatus.running => MinisTheme.accent,
        ToolChipStatus.success => MinisTheme.accentGreen,
        ToolChipStatus.failed => MinisTheme.danger,
      };

  IconData get _icon => switch (status) {
        ToolChipStatus.streaming => Icons.more_horiz,
        ToolChipStatus.running => Icons.sync,
        ToolChipStatus.success => Icons.check_circle_outline,
        ToolChipStatus.failed => Icons.error_outline,
      };

  bool get _spin => status == ToolChipStatus.running || status == ToolChipStatus.streaming;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      margin: const EdgeInsets.only(right: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: MinisTheme.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_spin)
            SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: _color),
            )
          else
            Icon(_icon, size: 13, color: _color),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(fontSize: 11, color: _color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );

    if (status == ToolChipStatus.failed && errorOutput != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chip,
          Text(
            errorOutput!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: MinisTheme.danger),
          ),
        ],
      );
    }
    return chip;
  }
}
