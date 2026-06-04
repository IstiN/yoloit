import 'package:flutter/material.dart';

/// A compact colored badge showing a text label with a tinted
/// background and matching border.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.backgroundAlpha = 30,
    this.borderAlpha = 80,
    this.borderRadius = 6,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w500,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  final String label;
  final Color color;
  final int backgroundAlpha;
  final int borderAlpha;
  final double borderRadius;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withAlpha(backgroundAlpha),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: color.withAlpha(borderAlpha)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}
