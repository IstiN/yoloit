import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Bold section title (fontSize 13–14, textPrimary, semibold).
///
/// Replaces repeated `_SectionHeader` inline usage and other section headers.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.data, {
    super.key,
    this.fontSize = 13,
    this.fontWeight = FontWeight.w600,
    this.letterSpacing = 0.1,
    this.overflow,
    this.maxLines,
  });

  final String data;
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final TextOverflow? overflow;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        color: context.appColors.textPrimary,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
      ),
    );
  }
}
