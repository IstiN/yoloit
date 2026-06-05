import 'package:flutter/material.dart';

/// A compact 28×28 icon button for panel header toolbars.
class PanelHeaderIconButton extends StatelessWidget {
  const PanelHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        splashRadius: 14,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
