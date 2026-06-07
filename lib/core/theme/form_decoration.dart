import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Returns a standard [InputDecoration] with an outlined border used
/// throughout the app for text fields inside dialogs and forms.
///
/// The default padding is `EdgeInsets.symmetric(horizontal: 10, vertical: 8)`.
InputDecoration outlineInputDecoration(
  AppColorScheme colors, {
  String? hintText,
  TextStyle? hintStyle,
  String? labelText,
  TextStyle? labelStyle,
  EdgeInsetsGeometry? contentPadding,
  bool isDense = true,
  Color? fillColor,
  bool filled = false,
  bool focused = true,
  Widget? prefixIcon,
  BoxConstraints? prefixIconConstraints,
  Widget? suffixIcon,
  BoxConstraints? suffixIconConstraints,
}) => InputDecoration(
  isDense: isDense,
  hintText: hintText,
  hintStyle: hintStyle,
  labelText: labelText,
  labelStyle: labelStyle,
  contentPadding: contentPadding ??
      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  filled: filled,
  fillColor: fillColor,
  prefixIcon: prefixIcon,
  prefixIconConstraints: prefixIconConstraints,
  suffixIcon: suffixIcon,
  suffixIconConstraints: suffixIconConstraints,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: colors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: colors.border),
  ),
  focusedBorder: focused
      ? OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colors.primary),
        )
      : null,
);
