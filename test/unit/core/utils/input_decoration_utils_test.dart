import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/utils/input_decoration_utils.dart';

void main() {
  group('appInputDecoration', () {
    late AppColorScheme colors;

    setUp(() {
      colors = AppThemePreset.neonPurple.theme.extension<AppColorScheme>()!;
    });

    test('returns InputDecoration with hint text', () {
      final decoration = appInputDecoration(colors: colors, hintText: 'Search');

      expect(decoration.hintText, 'Search');
      expect(decoration.hintStyle, isNotNull);
    });

    test('uses default border radius of 4', () {
      final decoration = appInputDecoration(colors: colors);
      final border = decoration.border as OutlineInputBorder;

      expect(border.borderRadius, BorderRadius.circular(4));
    });

    test('uses custom border radius when provided', () {
      final decoration = appInputDecoration(colors: colors, borderRadius: 12);
      final border = decoration.border as OutlineInputBorder;

      expect(border.borderRadius, BorderRadius.circular(12));
    });

    test('fills with surface color by default', () {
      final decoration = appInputDecoration(colors: colors);

      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, colors.surface);
    });

    test('uses custom fill color when provided', () {
      final decoration = appInputDecoration(
        colors: colors,
        fillColor: colors.surfaceElevated,
      );

      expect(decoration.fillColor, colors.surfaceElevated);
    });

    test('border and enabledBorder share same style', () {
      final decoration = appInputDecoration(colors: colors);

      expect(decoration.border, decoration.enabledBorder);
    });

    test('focused border uses primary color', () {
      final decoration = appInputDecoration(colors: colors);
      final focusedBorder = decoration.focusedBorder as OutlineInputBorder;

      expect(focusedBorder.borderSide.color, colors.primary);
    });

    test('custom focused border overrides default', () {
      final customFocused = OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.accentBlue),
      );
      final decoration = appInputDecoration(
        colors: colors,
        focusedBorder: customFocused,
      );

      expect(decoration.focusedBorder, customFocused);
    });

    test('uses custom border color', () {
      final decoration = appInputDecoration(
        colors: colors,
        borderColor: colors.accentRed,
      );
      final border = decoration.border as OutlineInputBorder;

      expect(border.borderSide.color, colors.accentRed);
    });

    test('uses custom content padding', () {
      final decoration = appInputDecoration(
        colors: colors,
        contentPadding: const EdgeInsets.all(16),
      );

      expect(decoration.contentPadding, const EdgeInsets.all(16));
    });

    test('uses default content padding', () {
      final decoration = appInputDecoration(colors: colors);

      expect(
        decoration.contentPadding,
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
    });

    test('uses custom border width', () {
      final decoration = appInputDecoration(
        colors: colors,
        borderWidth: 2,
      );
      final border = decoration.border as OutlineInputBorder;

      expect(border.borderSide.width, 2);
    });

    test('uses custom focus border width', () {
      final decoration = appInputDecoration(
        colors: colors,
        focusBorderWidth: 2,
      );
      final focusedBorder = decoration.focusedBorder as OutlineInputBorder;

      expect(focusedBorder.borderSide.width, 2);
    });

    test('isDense is true by default', () {
      final decoration = appInputDecoration(colors: colors);

      expect(decoration.isDense, isTrue);
    });

    test('uses custom hint font size', () {
      final decoration = appInputDecoration(
        colors: colors,
        hintText: 'Test',
        hintFontSize: 14,
      );

      expect(decoration.hintStyle!.fontSize, 14);
    });
  });
}
