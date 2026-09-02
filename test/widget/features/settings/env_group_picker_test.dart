import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('env_group_picker_test_');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: tmpDir.path));
  });

  tearDown(() {
    PlatformDirs.reset();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Future<void> seedGroup() => GlobalEnvGroupsService.instance.saveAll([
    const GlobalEnvGroup(
      id: 'seeded',
      name: 'Seeded',
      values: {'SEED_KEY': 'seed_val'},
    ),
  ]);

  Future<void> pumpApp(WidgetTester tester) async {
    // The picker dialog is up to 620px tall; give it room so the bottom
    // button row ('New Group' / 'Save & Select') is on-screen and tappable.
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () {
                    showEnvGroupPickerDialog(context, initialSelected: const []);
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
  }

  Future<void> openPicker(WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    // Wait for the real async _load() to finish (spinner disappears).
    for (var i = 0; i < 20; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    expect(find.text('Select Env Groups'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  /// Waits until [finder] matches (real async I/O inside runAsync).
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    await tester.pump();
  }

  /// Waits until [finder] no longer matches (real async I/O in runAsync).
  Future<void> waitForGone(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20; i++) {
      if (finder.evaluate().isEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    await tester.pump();
  }

  Finder fieldByHint(String hint) => find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.hintText == hint,
  );

  group('EnvGroupPickerDialog._saveNewGroup', () {
    testWidgets('does nothing when no key/value pairs are filled in', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedGroup();
        await openPicker(tester);

        await tester.tap(find.text('New Group'));
        await tester.pump();
        expect(find.text('New Env Group'), findsOneWidget);

        await tester.tap(find.text('Save & Select'));
        await tester.pump();

        // Still on the inline form; nothing persisted.
        expect(find.text('New Env Group'), findsOneWidget);
        expect((await GlobalEnvGroupsService.instance.loadAll()).length, 1);
      });
    });

    testWidgets('does nothing when the group name is blank', (tester) async {
      await tester.runAsync(() async {
        await seedGroup();
        await openPicker(tester);

        await tester.tap(find.text('New Group'));
        await tester.pump();

        await tester.enterText(fieldByHint('Group name'), '   ');
        await tester.enterText(fieldByHint('KEY'), 'TOKEN');
        await tester.enterText(fieldByHint('value'), 'abc');
        await tester.tap(find.text('Save & Select'));
        await tester.pump();

        expect(find.text('New Env Group'), findsOneWidget);
        expect((await GlobalEnvGroupsService.instance.loadAll()).length, 1);
      });
    });

    testWidgets('saves a new group, selects it and resets the form', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedGroup();
        await openPicker(tester);

        await tester.tap(find.text('New Group'));
        await tester.pump();

        // Add a second variable row, then fill both pairs.
        await tester.tap(find.text('Add variable'));
        await tester.pump();
        expect(fieldByHint('KEY'), findsNWidgets(2));

        await tester.enterText(fieldByHint('Group name'), 'Secrets');
        await tester.enterText(fieldByHint('KEY').at(0), 'TOKEN');
        await tester.enterText(fieldByHint('value').at(0), 'abc');
        await tester.enterText(fieldByHint('KEY').at(1), 'HOST');
        await tester.enterText(fieldByHint('value').at(1), 'localhost');

        await tester.tap(find.text('Save & Select'));
        // Save is real async I/O; the inline form collapses when done.
        await waitForGone(tester, find.text('New Env Group'));
        await tester.pump();

        // Form collapsed; the new group shows up in the picker.
        expect(find.text('New Env Group'), findsNothing);
        expect(find.text('Secrets'), findsOneWidget);
        // It is also pre-selected, so the 'Selected order' section appears.
        expect(find.text('Selected order'), findsOneWidget);

        final groups = await GlobalEnvGroupsService.instance.loadAll();
        expect(groups.length, 2);
        final saved = groups.firstWhere((g) => g.name == 'Secrets');
        expect(saved.values, {'TOKEN': 'abc', 'HOST': 'localhost'});

        // The name field was reset for the next inline add.
        await tester.tap(find.text('New Group'));
        await tester.pump();
        final nameField = tester.widget<TextField>(fieldByHint('Group name'));
        expect(nameField.controller?.text, 'New Group');
      });
    });

    testWidgets('shows a snackbar when saving fails', (tester) async {
      await tester.runAsync(() async {
        await seedGroup();
        await openPicker(tester);

        await tester.tap(find.text('New Group'));
        await tester.pump();
        await tester.enterText(fieldByHint('Group name'), 'Broken');
        await tester.enterText(fieldByHint('KEY'), 'TOKEN');
        await tester.enterText(fieldByHint('value'), 'abc');

        // Break the metadata file write: point configDir into a path that
        // has a regular file where a directory is required.
        final blocker = File(p.join(tmpDir.path, 'blocker'))
          ..writeAsStringSync('x');
        PlatformDirs.setInstance(
          _BrokenPlatformDirs(p.join(blocker.path, 'config')),
        );

        await tester.tap(find.text('Save & Select'));
        await waitFor(tester, find.textContaining('Failed to save:'));

        expect(find.textContaining('Failed to save:'), findsOneWidget);
      });
    });
  });

  group('EnvGroupPickerDialog quick search & key preview', () {
    Future<void> seedTwoGroups() => GlobalEnvGroupsService.instance.saveAll([
      const GlobalEnvGroup(
        id: 'g1',
        name: 'Alpha',
        values: {'OPENAI_KEY': 'v1', 'OTHER': 'v2'},
      ),
      const GlobalEnvGroup(id: 'g2', name: 'Beta', values: {'UNRELATED': 'v3'}),
    ]);

    testWidgets('quick search filters groups by key name', (tester) async {
      await tester.runAsync(() async {
        await seedTwoGroups();
        await openPicker(tester);

        await tester.enterText(
          fieldByHint('Quick search: group or key name…'),
          'openai',
        );
        await waitForGone(tester, find.text('Beta'));

        expect(find.text('Beta'), findsNothing);
        expect(find.text('Alpha'), findsOneWidget);
      });
    });

    testWidgets('shows a no-match caption when nothing matches', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedTwoGroups();
        await openPicker(tester);

        await tester.enterText(
          fieldByHint('Quick search: group or key name…'),
          'zzz_no_match',
        );
        await waitFor(tester, find.textContaining('No groups or keys match'));

        expect(find.textContaining('No groups or keys match'), findsOneWidget);
      });
    });

    testWidgets('expanding a row previews keys but not values', (tester) async {
      await tester.runAsync(() async {
        await seedTwoGroups();
        await openPicker(tester);

        expect(find.text('OPENAI_KEY'), findsNothing);
        await tester.tap(find.byTooltip('Show keys').first);
        await tester.pump();

        expect(find.text('OPENAI_KEY'), findsOneWidget);
        expect(find.text('OTHER'), findsOneWidget);
        // Values are secrets and must never be previewed.
        expect(find.text('v1'), findsNothing);
        expect(find.text('v2'), findsNothing);

        await tester.tap(find.byTooltip('Hide keys').first);
        await tester.pump();
        expect(find.text('OPENAI_KEY'), findsNothing);
      });
    });

    testWidgets('searching highlights matching keys in the preview', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedTwoGroups();
        await openPicker(tester);

        await tester.enterText(
          fieldByHint('Quick search: group or key name…'),
          'openai',
        );
        await waitForGone(tester, find.text('Beta'));

        await tester.tap(find.byTooltip('Show keys'));
        await tester.pump();

        expect(find.text('OPENAI_KEY'), findsOneWidget);
        expect(find.text('OTHER'), findsNothing);
      });
    });
  });
}

class _BrokenPlatformDirs extends PlatformDirs {
  const _BrokenPlatformDirs(this._configDir);
  final String _configDir;

  @override
  String get configDir => _configDir;

  @override
  String get dataDir => _configDir;

  @override
  String? get userHome => null;

  @override
  String get logsDir => _configDir;

  @override
  String get tempDir => _configDir;

  @override
  String get skillsDir => p.join(_configDir, 'skills');

  @override
  String get yoloitTempDir => p.join(_configDir, 'tmp');
}
