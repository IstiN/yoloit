import 'package:flutter/material.dart';

/// Emphasised label text (fontSize 12–13, textSecondary or onSurface).
///
/// Replaces repeated settings boilerplate:
/// ```dart
/// Text('...', style: TextStyle(
///   color: Theme.of(context).colorScheme.onSurface,
///   fontSize: 13,
///   fontWeight: FontWeight.w600,
/// ))
/// ```
class Label extends StatelessWidget {
  const Label(
    this.data, {
    super.key,
    this.fontSize = 13,
    this.fontWeight = FontWeight.w600,
    this.color,
    this.overflow,
    this.maxLines,
    this.textAlign,
  });

  final String data;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
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
        color: color ?? Theme.of(context).colorScheme.onSurface,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
  }
}
