import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A rounded container that frames a Mermaid diagram (loading, error or rendered).
class MermaidPreviewFrame extends StatelessWidget {
  const MermaidPreviewFrame({
    super.key,
    required this.height,
    required this.colors,
    required this.child,
    this.borderColor,
    this.backgroundColor,
  });

  final double height;
  final AppColorScheme colors;
  final Widget child;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? colors.border),
      ),
      child: child,
    );
  }
}
