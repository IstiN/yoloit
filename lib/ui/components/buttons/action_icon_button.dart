import 'package:flutter/material.dart';

/// Compact icon-only button used in dialog lists.
class ActionIconButton extends StatelessWidget {
  const ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}
