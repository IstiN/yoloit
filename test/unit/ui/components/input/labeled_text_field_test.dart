import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/ui/components/input/labeled_text_field.dart';

void main() {
  group('outlineInputDecoration', () {
    late AppColorScheme colors;

    setUp(() {
      colors = AppThemePreset.neonPurple.theme.extension<AppColorScheme>()!;
    });

    testWidgets('returns InputDecoration with hint text', (tester) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        hintText: 'Enter value',
      );

      expect(decoration.hintText, 'Enter value');
      expect(decoration.hintStyle, isNotNull);
    });

    testWidgets('returns InputDecoration with label text', (tester) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        labelText: 'Label',
      );

      expect(decoration.labelText, 'Label');
    });

    testWidgets('applies prefixIcon when provided', (tester) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        prefixIcon: const Icon(Icons.search),
      );

      expect(decoration.prefixIcon, isA<Icon>());
    });

    testWidgets('applies suffixIcon when provided', (tester) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        suffixIcon: const Icon(Icons.clear),
      );

      expect(decoration.suffixIcon, isA<Icon>());
    });

    testWidgets('filled mode sets filled and fillColor', (tester) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        filled: true,
        fillColor: colors.surface,
      );

      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, colors.surface);
    });

    testWidgets('default border uses border color', (tester) async {
      final decoration = outlineInputDecoration(colors: colors);
      final border = decoration.enabledBorder as OutlineInputBorder;

      expect(border.borderSide.color, colors.border);
    });

    testWidgets('focused border uses primary color', (tester) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        focused: true,
      );
      final border = decoration.focusedBorder as OutlineInputBorder;

      expect(border.borderSide.color, colors.primary);
    });

    testWidgets('focused false leaves focusedBorder null', (
      tester,
    ) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        focused: false,
      );

      expect(decoration.focusedBorder, isNull);
    });

    testWidgets('applies custom borderRadius', (tester) async {
      final decoration = outlineInputDecoration(
        colors: colors,
        borderRadius: 12,
      );
      final border = decoration.enabledBorder as OutlineInputBorder;

      expect(border.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('default contentPadding is compact', (tester) async {
      final decoration = outlineInputDecoration(colors: colors);

      expect(
        decoration.contentPadding,
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
    });

    testWidgets('isDense is true by default', (tester) async {
      final decoration = outlineInputDecoration(colors: colors);

      expect(decoration.isDense, isTrue);
    });
  });
}
