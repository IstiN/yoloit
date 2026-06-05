import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class SessionBarButton extends StatelessWidget {
  const SessionBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: colors.textSecondary),
        ),
      ),
    );
  }
}
