import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Small muted caption text (fontSize 11, textMuted).
///
/// Replaces the repeated boilerplate:
/// ```dart
/// Text('...', style: TextStyle(color: context.appColors.textMuted, fontSize: 11))
/// ```
class Caption extends StatelessWidget {
  const Caption(
    this.data, {
    super.key,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w400,
    this.letterSpacing,
    this.overflow,
    this.maxLines,
    this.textAlign,
  });

  final String data;
  final double fontSize;
  final FontWeight fontWeight;
  final double? letterSpacing;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        color: context.appColors.textMuted,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
      ),
    );
  }
}
