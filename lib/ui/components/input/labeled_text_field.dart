import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Standard outlined text field with an optional label used across
/// settings screens and editor dialogs.
///
/// Replaces repeated inline `TextField` + `InputDecoration` blocks that
/// configure the same `OutlineInputBorder` styling.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.minLines,
    this.maxLines = 1,
    this.obscureText = false,
    this.autofocus = false,
    this.borderRadius = 8,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 8,
    ),
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? minLines;
  final int? maxLines;
  final bool obscureText;
  final bool autofocus;
  final double borderRadius;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Text(
            label!,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 11,
            ),
          ),
        if (label != null) const SizedBox(height: 4),
        TextField(
          controller: controller,
          autofocus: autofocus,
          obscureText: obscureText,
          minLines: minLines,
          maxLines: maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: TextStyle(
            color: onSurface,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          decoration: outlineInputDecoration(
            colors: colors,
            hintText: hint,
            borderRadius: borderRadius,
            contentPadding: contentPadding,
          ),
        ),
      ],
    );
  }
}

/// Returns the standard outline [InputDecoration] used throughout the app.
InputDecoration outlineInputDecoration({
  required AppColorScheme colors,
  String? hintText,
  String? labelText,
  TextStyle? hintStyle,
  TextStyle? labelStyle,
  double borderRadius = 8,
  EdgeInsetsGeometry? contentPadding,
  bool isDense = true,
  Color? fillColor,
  bool filled = false,
  bool focused = true,
  Widget? prefixIcon,
  BoxConstraints? prefixIconConstraints,
  Widget? suffixIcon,
  BoxConstraints? suffixIconConstraints,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(borderRadius),
    borderSide: BorderSide(color: colors.border),
  );
  return InputDecoration(
    isDense: isDense,
    hintText: hintText,
    labelText: labelText,
    hintStyle: hintStyle ?? TextStyle(color: colors.textMuted, fontSize: 12),
    labelStyle: labelStyle,
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    filled: filled,
    fillColor: fillColor,
    prefixIcon: prefixIcon,
    prefixIconConstraints: prefixIconConstraints,
    suffixIcon: suffixIcon,
    suffixIconConstraints: suffixIconConstraints,
    border: border,
    enabledBorder: border,
    focusedBorder: focused
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: BorderSide(color: colors.primary),
          )
        : null,
  );
}
