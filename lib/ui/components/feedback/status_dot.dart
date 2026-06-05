import 'package:flutter/material.dart';

/// Small circular status indicator with optional glow shadow.
///
/// Used in mind-map cards (agent, session, run) and anywhere a
/// compact live/idle/error dot is needed.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.glowAlpha = 180,
    this.blurRadius = 8,
    this.isActive = true,
  });

  final Color color;
  final double size;
  final int glowAlpha;
  final double blurRadius;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow:
            isActive
                ? [
                  BoxShadow(
                    color: color.withAlpha(glowAlpha),
                    blurRadius: blurRadius,
                  ),
                ]
                : const [],
      ),
    );
  }
}
