import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/sections/support_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('support_section_test_');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    SupportLogService.instance.clearMemoryLog();
  });

  tearDown(() {
    SupportLogService.instance.clearMemoryLog();
    if (home.existsSync()) home.deleteSync(recursive: true);
    PlatformDirs.reset();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: SingleChildScrollView(child: SupportSection()),
        ),
      ),
    );
    // Let AppLogger.logPath resolve.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders diagnostics card and empty event log', (tester) async {
    await pumpSection(tester);

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Copy logs'), findsOneWidget);
    expect(find.text('Recent support events'), findsOneWidget);
    expect(find.textContaining('(no support events captured)'), findsOneWidget);
    // App log path resolved under the temp home.
    expect(find.textContaining('logs/app.log'), findsOneWidget);
    // Web-only cache button stays hidden on desktop.
    expect(find.text('Clear page cache'), findsNothing);
  });

  testWidgets('shows recent support events and clears them', (tester) async {
    SupportLogService.instance.add('test', 'hello support event');
    await pumpSection(tester);

    expect(find.textContaining('hello support event'), findsOneWidget);

    await tester.tap(find.text('Clear recent'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('(no support events captured)'), findsOneWidget);
    expect(find.text('Recent support events cleared'), findsOneWidget);
  });
}
