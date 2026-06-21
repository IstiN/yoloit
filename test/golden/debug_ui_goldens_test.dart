import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/ui/debug_ui/debug_ui_shell.dart';

const _darkBg = Color(0xFF0D1117);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _darkBg,
        extensions: [AppColorScheme.fromAccent(const Color(0xFF7C6BFF))],
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  group('Debug UI golden tests', () {
    testWidgets('DebugUIShell — Plectrum section', (tester) async {
      await _pump(tester, const DebugUIShell());
      await _golden(tester, 'debug_ui_plectrum');
    });

    testWidgets('DebugUIShell — Voice Overlay section', (tester) async {
      await _pump(tester, const DebugUIShell());
      await tester.tap(find.text('Voice Overlay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _golden(tester, 'debug_ui_voice_overlay');
    });

    testWidgets('DebugUIShell — Typography section', (tester) async {
      await _pump(tester, const DebugUIShell());
      await tester.tap(find.text('Typography'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _golden(tester, 'debug_ui_typography');
    });

    testWidgets('DebugUIShell — Colors section', (tester) async {
      await _pump(tester, const DebugUIShell());
      await tester.tap(find.text('Colors'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _golden(tester, 'debug_ui_colors');
    });

    testWidgets('DebugUIShell — Components section', (tester) async {
      await _pump(tester, const DebugUIShell());
      await tester.tap(find.text('Components'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _golden(tester, 'debug_ui_components');
    });

    testWidgets('DebugUIShell — Panel Chrome Prototype section', (tester) async {
      await _pump(tester, const DebugUIShell());
      await tester.tap(find.text('Panel Chrome Prototype'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _golden(tester, 'debug_ui_panel_chrome_prototype');
    });
  });
}
