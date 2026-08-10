import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';

/// Exercises [_ShapePalette.build] via the [createShapePaletteForTest] seam.
/// The palette is never instantiated in production (the editor dialog builds
/// ChoiceChips directly), so without this seam the widget and its tool
/// buttons are unreachable.
void main() {
  late AppColorScheme colors;

  /// Builds a [MaterialApp] wired with [AppThemePreset.neonPurple] so that
  /// [createShapePaletteForTest] receives a real [AppColorScheme] from
  /// `context.appColors`.
  Future<void> pumpPalette(
    WidgetTester tester, {
    required String selectedShape,
    required Color selectedColor,
    required String textHAlign,
    required String textVAlign,
    required String textOrientation,
    ValueChanged<Map<String, dynamic>>? onUpdate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              colors = context.appColors;
              return createShapePaletteForTest(
                selectedShape: selectedShape,
                selectedColor: selectedColor,
                textHAlign: textHAlign,
                textVAlign: textVAlign,
                textOrientation: textOrientation,
                colors: colors,
                onUpdate: onUpdate ?? (_) {},
              );
            },
          ),
        ),
      ),
    );
  }

  group('_ShapePalette.build', () {
    testWidgets('renders all shape option labels', (tester) async {
      await pumpPalette(
        tester,
        selectedShape: 'rectangle',
        selectedColor: const Color(0xFF93C5FD),
        textHAlign: 'center',
        textVAlign: 'center',
        textOrientation: 'horizontal',
      );

      // Shape glyphs rendered via _ShapeOption.label.
      for (final glyph in ['▭', '○', '◇', '△', '⬡', '▢']) {
        expect(find.text(glyph), findsOneWidget);
      }
    });

    testWidgets('renders all alignment / orientation tool buttons', (
      tester,
    ) async {
      await pumpPalette(
        tester,
        selectedShape: 'circle',
        selectedColor: const Color(0xFFA78BFA),
        textHAlign: 'left',
        textVAlign: 'top',
        textOrientation: 'vertical',
      );

      // _TextToolButton labels: L C R T M B H V
      for (final label in ['L', 'C', 'R', 'T', 'M', 'B', 'H', 'V']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('tapping a shape option fires onUpdate with shape key', (
      tester,
    ) async {
      final updates = <Map<String, dynamic>>[];
      await pumpPalette(
        tester,
        selectedShape: 'rectangle',
        selectedColor: const Color(0xFF93C5FD),
        textHAlign: 'center',
        textVAlign: 'center',
        textOrientation: 'horizontal',
        onUpdate: updates.add,
      );

      // Circle is the 2nd shape option glyph.
      await tester.tap(find.text('○'));
      await tester.pump();

      expect(updates, [
        {'shape': 'circle'},
      ]);
    });

    testWidgets('tapping a color swatch sets strokeColor and textColor', (
      tester,
    ) async {
      final updates = <Map<String, dynamic>>[];
      await pumpPalette(
        tester,
        selectedShape: 'rectangle',
        selectedColor: const Color(0xFF93C5FD),
        textHAlign: 'center',
        textVAlign: 'center',
        textOrientation: 'horizontal',
        onUpdate: updates.add,
      );

      // First color swatch in _colorOptions is #93C5FD.
      await tester.tap(find.byTooltip('Color #93C5FD'));
      await tester.pump();

      expect(updates, [
        {'strokeColor': '#93C5FD', 'textColor': '#93C5FD'},
      ]);
    });

    testWidgets('tapping text alignment buttons fires expected updates', (
      tester,
    ) async {
      final updates = <Map<String, dynamic>>[];
      await pumpPalette(
        tester,
        selectedShape: 'rectangle',
        selectedColor: const Color(0xFF93C5FD),
        textHAlign: 'center',
        textVAlign: 'center',
        textOrientation: 'horizontal',
        onUpdate: updates.add,
      );

      await tester.tap(find.byTooltip('Text right'));
      await tester.pump();
      await tester.tap(find.byTooltip('Text bottom'));
      await tester.pump();
      await tester.tap(find.byTooltip('Vertical text'));
      await tester.pump();

      expect(updates, [
        {'textHAlign': 'right'},
        {'textVAlign': 'bottom'},
        {'textOrientation': 'vertical'},
      ]);
    });

    testWidgets('selected shape option uses highlight colour', (tester) async {
      await pumpPalette(
        tester,
        selectedShape: 'diamond',
        selectedColor: const Color(0xFF000000),
        textHAlign: 'center',
        textVAlign: 'center',
        textOrientation: 'horizontal',
      );

      // The diamond glyph container should have a non-transparent background
      // (selected), while the circle glyph should be transparent (unselected).
      final diamondContainer = tester.widget<Container>(
        find.ancestor(of: find.text('◇'), matching: find.byType(Container)).first,
      );
      final circleContainer = tester.widget<Container>(
        find.ancestor(of: find.text('○'), matching: find.byType(Container)).first,
      );

      final diamondBg = diamondContainer.decoration as BoxDecoration;
      final circleBg = circleContainer.decoration as BoxDecoration;

      expect(diamondBg.color, isNot(Colors.transparent));
      expect(circleBg.color, Colors.transparent);
    });
  });
}
