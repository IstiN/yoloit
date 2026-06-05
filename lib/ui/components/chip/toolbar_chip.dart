import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A compact pill-shaped chip with an icon and label, used in toolbars.
class ToolbarChip extends StatelessWidget {
  const ToolbarChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: context.appColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: context.appColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
