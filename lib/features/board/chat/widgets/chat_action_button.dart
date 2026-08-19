import 'package:flutter/material.dart';

/// Compact circular action button used in the chat input bar.
class ChatActionButton extends StatelessWidget {
  const ChatActionButton({
    required this.icon,
    this.onTap,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;
  final String? tooltip;

  static const double _size = 28;
  static const double _radius = 14;
  static final BorderRadius _borderRadius = BorderRadius.circular(_radius);
  static const EdgeInsets _margin = EdgeInsets.only(bottom: 2);

  Widget get _button {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _size,
        height: _size,
        margin: _margin,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: _borderRadius,
        ),
        child: Icon(icon, size: iconSize ?? 14, color: iconColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: _button);
    }
    return _button;
  }
}
