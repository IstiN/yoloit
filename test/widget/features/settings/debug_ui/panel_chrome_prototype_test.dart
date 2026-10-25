import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/debug_ui/sections/panel_chrome_prototype.dart';

void main() {
  testWidgets('prototype builds selected, unselected, and locked mock panels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(body: PanelChromePrototype()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Chart'), findsOneWidget);
    expect(find.text('Board notes'), findsOneWidget);
    expect(find.text('Terminal agent'), findsOneWidget);
    expect(find.text('Panel body placeholder'), findsWidgets);
    expect(find.text('Content toolbar — primary + hover overflow'), findsOneWidget);
  });
}
