import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_settings_panels.dart';

void main() {
  group('DrawSettingsPanel', () {
    const settings = DrawSettings(strokeColor: Colors.red, strokeWidth: 5);

    Widget buildPanel({
      DrawSettings? initial,
      ValueChanged<DrawSettings>? onChanged,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: DrawSettingsPanel(
            settings: initial ?? settings,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('renders title and size label', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.text('Draw settings'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
    });

    testWidgets('renders color swatches and custom picker', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.byType(GestureDetector), findsNWidgets(7));
    });

    testWidgets('tapping color swatch calls onChanged with new color', (
      tester,
    ) async {
      DrawSettings? changed;
      await tester.pumpWidget(
        buildPanel(
          onChanged: (v) => changed = v,
        ),
      );

      await tester.tap(find.byType(GestureDetector).at(1));
      expect(changed, isNotNull);
      expect(changed!.strokeColor, isNot(settings.strokeColor));
    });

    testWidgets('slider change calls onChanged with new width', (tester) async {
      DrawSettings? changed;
      await tester.pumpWidget(
        buildPanel(
          onChanged: (v) => changed = v,
        ),
      );

      await tester.drag(find.byType(Slider), const Offset(20, 0));
      expect(changed, isNotNull);
      expect(changed!.strokeWidth, isNot(settings.strokeWidth));
    });

    testWidgets('custom color picker shows dialog when tapped', (tester) async {
      await tester.pumpWidget(buildPanel());
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pumpAndSettle();

      expect(find.text('Stroke color'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Stroke color'), findsNothing);
    });
  });

  group('ConnectSettingsPanel', () {
    const settings = ConnectSettings(
      geometry: BoardLinkGeometry.bezier,
      showArrow: true,
      color: Colors.blue,
    );

    Widget buildPanel({
      ConnectSettings? initial,
      ValueChanged<ConnectSettings>? onChanged,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: ConnectSettingsPanel(
            settings: initial ?? settings,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('renders title and arrow label', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Arrow'), findsOneWidget);
    });

    testWidgets('renders geometry buttons', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.text('Bézier'), findsOneWidget);
      expect(find.text('Line'), findsOneWidget);
      expect(find.text('Elbow'), findsOneWidget);
    });

    testWidgets('tapping geometry button calls onChanged', (tester) async {
      ConnectSettings? changed;
      await tester.pumpWidget(
        buildPanel(onChanged: (v) => changed = v),
      );

      await tester.tap(find.text('Line'));
      expect(changed, isNotNull);
      expect(changed!.geometry, BoardLinkGeometry.straight);
    });

    testWidgets('toggle switch changes showArrow', (tester) async {
      ConnectSettings? changed;
      await tester.pumpWidget(
        buildPanel(onChanged: (v) => changed = v),
      );

      await tester.tap(find.byType(Switch));
      expect(changed, isNotNull);
      expect(changed!.showArrow, isFalse);
    });

    testWidgets('tapping color swatch calls onChanged with new color', (
      tester,
    ) async {
      ConnectSettings? changed;
      await tester.pumpWidget(
        buildPanel(
          initial: const ConnectSettings(color: Colors.black),
          onChanged: (v) => changed = v,
        ),
      );

      await tester.tap(find.byType(GestureDetector).at(4));
      expect(changed, isNotNull);
    });

    testWidgets('renders custom paint preview', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
