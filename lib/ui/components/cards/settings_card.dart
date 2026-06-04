import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Standard card container used in Settings screens.
///
/// Provides consistent surface elevation, border radius, border, and padding.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.borderColor,
    this.borderRadius = 10,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final Color? borderColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? colors.border),
      ),
      child: child,
    );
  }
}
