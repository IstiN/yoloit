import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A compact text+icon button used in panel toolbars.
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: colors.textSecondary),
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: colors.textSecondary),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
