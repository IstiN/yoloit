import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Builds the standard filled [InputDecoration] used throughout the app.
///
/// Provides consistent borders, padding, and focus styling.  Override
/// individual parameters when a specific screen needs a deviation.
InputDecoration appInputDecoration({
  required AppColorScheme colors,
  String? hintText,
  double hintFontSize = 12,
  double borderRadius = 4,
  double borderWidth = 1,
  double focusBorderWidth = 1,
  Color? fillColor,
  Color? borderColor,
  EdgeInsets contentPadding = const EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 8,
  ),
  bool isDense = true,
  InputBorder? border,
  InputBorder? enabledBorder,
  InputBorder? focusedBorder,
}) {
  final effectiveBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(borderRadius),
    borderSide: BorderSide(
      color: borderColor ?? colors.border,
      width: borderWidth,
    ),
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: colors.textMuted, fontSize: hintFontSize),
    filled: true,
    fillColor: fillColor ?? colors.surface,
    border: border ?? effectiveBorder,
    enabledBorder: enabledBorder ?? effectiveBorder,
    focusedBorder: focusedBorder ?? OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(color: colors.primary, width: focusBorderWidth),
    ),
    contentPadding: contentPadding,
    isDense: isDense,
  );
}
