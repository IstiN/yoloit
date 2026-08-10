import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/settings/ui/widgets/theme_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    home = Directory.systemTemp.createTempSync('theme_selector_test_');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    // Reset the singleton to a clean preset state before each test.
    await ThemeManager.instance.load();
  });

  tearDown(() {
    BoardFilePicker.debugPickDirectoryOverride = null;
    if (home.existsSync()) home.deleteSync(recursive: true);
    PlatformDirs.reset();
  });

  Future<void> pumpSelector(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: SingleChildScrollView(child: ThemeSelector()),
        ),
      ),
    );
    await tester.pump();
  }

  /// Real-async poll until [condition] holds (use inside tester.runAsync).
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    while (!condition() && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    await tester.pump();
  }

  testWidgets('save preset persists a custom theme', (tester) async {
    await pumpSelector(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Save Preset'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Default name derives from the active preset.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Neon Purple Custom');

      await tester.enterText(find.byType(TextField), 'My Preset');
      await tester.tap(find.text('Save'));
      await tester.pump();

      // _savePreset waits 350ms for the dialog exit animation, then writes.
      await waitFor(
        tester,
        () => ThemeManager.instance.customThemes.isNotEmpty,
      );
    });

    final custom = ThemeManager.instance.customThemes.single;
    expect(custom.name, 'My Preset');
    expect(ThemeManager.instance.activeCustomThemeId, custom.id);

    final persisted = File(
      p.join(home.path, '.config', 'yoloit', 'themes', '${custom.id}.json'),
    );
    expect(persisted.existsSync(), isTrue);
    expect(persisted.readAsStringSync(), contains('"name": "My Preset"'));
  });

  testWidgets('cancelling the preset dialog saves nothing', (tester) async {
    await pumpSelector(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Save Preset'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });

    expect(ThemeManager.instance.customThemes, isEmpty);
  });

  testWidgets('export writes the current theme JSON to the picked folder', (
    tester,
  ) async {
    final exportDir = Directory(p.join(home.path, 'export'))..createSync();
    BoardFilePicker.debugPickDirectoryOverride = () async => exportDir.path;

    await pumpSelector(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Export'));
      await waitFor(tester, () {
        final f = File(p.join(exportDir.path, 'neon_purple_theme.json'));
        return f.existsSync() && f.readAsStringSync().isNotEmpty;
      });
    });

    final exported = File(p.join(exportDir.path, 'neon_purple_theme.json'));
    expect(exported.readAsStringSync(), contains('"name": "Neon Purple"'));
    expect(find.textContaining('Theme exported to'), findsOneWidget);
  });

  testWidgets('cancelling the folder picker exports nothing', (tester) async {
    BoardFilePicker.debugPickDirectoryOverride = () async => null;

    await pumpSelector(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Export'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    expect(find.textContaining('Theme exported to'), findsNothing);
  });
}
