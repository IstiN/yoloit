import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/global_env_groups_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );

  late Directory home;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    home = Directory.systemTemp.createTempSync('env_groups_section_test_');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
    // Delete the temp home before resetting PlatformDirs so that any stray
    // in-flight write fails loudly here instead of landing in the real
    // user config directory.
    if (home.existsSync()) home.deleteSync(recursive: true);
    PlatformDirs.reset();
  });

  /// Mocks the file_picker method channel so the next pick returns [path]
  /// (or a cancellation when [path] is null).
  void mockPickedFile(String? path) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async {
      if (path == null) return null;
      return [
        <String, Object?>{
          'name': p.basename(path),
          'path': path,
          'size': 0,
          'bytes': null,
          'identifier': null,
        },
      ];
    });
  }

  Future<void> seedGroups(List<GlobalEnvGroup> groups) =>
      GlobalEnvGroupsService.instance.saveAll(groups);

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: SingleChildScrollView(child: GlobalEnvGroupsSection()),
        ),
      ),
    );
  }

  /// Polls (real async, inside runAsync) until [condition] holds or the
  /// timeout elapses. Robust replacement for fixed delays, which are flaky
  /// when the full suite runs many isolates concurrently.
  Future<void> pumpUntil(
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

  /// Pumps the section and waits for the async _load() to finish.
  Future<void> pumpLoaded(WidgetTester tester) async {
    await pumpSection(tester);
    // First frame: loading indicator while groups load.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  Finder fieldByHint(String hint) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );

  /// Variable-row delete buttons (group delete buttons carry a tooltip).
  Finder variableDeleteButtons() => find.byWidgetPredicate(
    (widget) =>
        widget is IconButton &&
        widget.tooltip == null &&
        widget.icon is Icon &&
        (widget.icon as Icon).icon == Icons.delete_outline,
  );

  Finder revealButtons() => find.byWidgetPredicate(
    (widget) =>
        widget is IconButton &&
        widget.icon is Icon &&
        ((widget.icon as Icon).icon == Icons.visibility_outlined ||
            (widget.icon as Icon).icon == Icons.visibility_off_outlined),
  );

  group('GlobalEnvGroupsSection.build / _load', () {
    testWidgets('shows the empty state when no groups exist', (tester) async {
      await tester.runAsync(() async {
        await pumpLoaded(tester);

        expect(find.text('Add Group'), findsOneWidget);
        expect(find.text('Import .env'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(
          find.text('No env groups yet. Create one or import a .env file.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('renders seeded groups, variables, and the empty-vars hint', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedGroups([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Prod',
            values: {'API_KEY': 'abc', 'EMPTY_VAR': ''},
          ),
          const GlobalEnvGroup(id: 'g2', name: 'Empty Group', values: {}),
        ]);
        await pumpLoaded(tester);

        // Both group name fields are rendered.
        expect(fieldByHint('Group name'), findsNWidgets(2));
        expect(find.text('Prod'), findsOneWidget);
        expect(find.text('Empty Group'), findsOneWidget);
        // The group without variables shows the hint.
        expect(find.text('No variables yet.'), findsOneWidget);
        // Two variable rows in the first group.
        expect(fieldByHint('KEY'), findsNWidgets(2));
        expect(fieldByHint('VALUE'), findsNWidgets(2));
        expect(find.text('API_KEY'), findsOneWidget);
        expect(find.text('Add Variable'), findsNWidgets(2));
        // The empty-state caption is gone once groups exist.
        expect(
          find.text('No env groups yet. Create one or import a .env file.'),
          findsNothing,
        );
      });
    });

    testWidgets('reveal toggle switches value field obscurity', (tester) async {
      await tester.runAsync(() async {
        await seedGroups([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Prod',
            values: {'API_KEY': 'abc'},
          ),
        ]);
        await pumpLoaded(tester);

        TextField valueField() => tester.widget<TextField>(fieldByHint('VALUE'));
        expect(valueField().obscureText, isTrue);

        await tester.tap(find.byIcon(Icons.visibility_outlined));
        await tester.pump();
        expect(valueField().obscureText, isFalse);
        expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

        await tester.tap(find.byIcon(Icons.visibility_off_outlined));
        await tester.pump();
        expect(valueField().obscureText, isTrue);
        expect(revealButtons(), findsOneWidget);
      });
    });

    testWidgets('add variable inserts a draft row, delete removes rows', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedGroups([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Prod',
            values: {'API_KEY': 'abc'},
          ),
        ]);
        await pumpLoaded(tester);

        // Add a variable: a draft row with an empty key field appears.
        await tester.tap(find.text('Add Variable'));
        await tester.pump();
        expect(fieldByHint('KEY'), findsNWidgets(2));
        expect(variableDeleteButtons(), findsNWidgets(2));

        // Delete the original row.
        await tester.tap(variableDeleteButtons().first);
        await tester.pump();
        expect(find.text('API_KEY'), findsNothing);
        expect(fieldByHint('KEY'), findsOneWidget);

        // Delete the draft row: back to the empty-vars hint.
        await tester.tap(variableDeleteButtons());
        await tester.pump();
        expect(find.text('No variables yet.'), findsOneWidget);
      });
    });
  });

  group('GlobalEnvGroupsSection._save', () {
    testWidgets('saves normalized groups and shows a confirmation', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedGroups([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Prod',
            values: {'API_KEY': 'abc'},
          ),
        ]);
        await pumpLoaded(tester);

        // Blank name normalizes to 'Untitled Group'.
        await tester.enterText(fieldByHint('Group name'), '   ');
        // A draft variable (no key) is dropped on save.
        await tester.tap(find.text('Add Variable'));
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pump();
        // While the save is in flight the button reflects the busy state.
        expect(find.text('Saving…'), findsOneWidget);

        await pumpUntil(
          tester,
          () => find.text('Env groups saved.').evaluate().isNotEmpty,
        );
        expect(find.text('Env groups saved.'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);

        final groups = await GlobalEnvGroupsService.instance.loadAll();
        expect(groups.length, 1);
        expect(groups.single.name, 'Untitled Group');
        expect(groups.single.values, {'API_KEY': 'abc'});
      });
    });

    testWidgets('shows an error snackbar when saving fails', (tester) async {
      await tester.runAsync(() async {
        await seedGroups([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Prod',
            values: {'API_KEY': 'abc'},
          ),
        ]);
        await pumpLoaded(tester);

        // Break the metadata file write: point configDir into a path that
        // has a regular file where a directory is required.
        final blocker = File(p.join(home.path, 'blocker'))
          ..writeAsStringSync('x');
        PlatformDirs.setInstance(
          _BlockedPlatformDirs(p.join(blocker.path, 'config')),
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await pumpUntil(
          tester,
          () =>
              find.textContaining('Failed to save env groups:')
                  .evaluate()
                  .isNotEmpty,
        );
        expect(
          find.textContaining('Failed to save env groups:'),
          findsOneWidget,
        );
        // The busy state is cleared after the failure.
        expect(find.text('Save'), findsOneWidget);
      });
    });
  });

  group('GlobalEnvGroupsSection._importIntoGroup', () {
    testWidgets('merges variables from a picked .env file into the group', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedGroups([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Prod',
            values: {'API_KEY': 'abc'},
          ),
        ]);
        final envFile = File(p.join(home.path, 'extra.env'))
          ..writeAsStringSync(
            'NEW_KEY=new_value\nAPI_KEY=overridden\n# comment\n\n',
          );
        mockPickedFile(envFile.path);

        await pumpLoaded(tester);
        expect(fieldByHint('KEY'), findsOneWidget);

        await tester.tap(find.byTooltip('Import into group'));
        await pumpUntil(
          tester,
          () => find.text('NEW_KEY').evaluate().isNotEmpty,
        );

        // Imported keys are merged in; the imported value wins on conflicts.
        expect(find.text('NEW_KEY'), findsOneWidget);
        expect(fieldByHint('KEY'), findsNWidgets(2));
        final values =
            tester
                .widgetList<TextField>(fieldByHint('VALUE'))
                .map((field) => field.controller?.text)
                .toList();
        expect(values, containsAll(<String>['overridden', 'new_value']));
        expect(values, isNot(contains('abc')));
      });
    });

    testWidgets('does nothing when the picker is cancelled', (tester) async {
      await tester.runAsync(() async {
        await seedGroups([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'Prod',
            values: {'API_KEY': 'abc'},
          ),
        ]);
        mockPickedFile(null);

        await pumpLoaded(tester);

        await tester.tap(find.byTooltip('Import into group'));
        // Give the (cancelled) picker future time to resolve.
        await pumpUntil(tester, () => false, timeout: const Duration(seconds: 1));

        expect(fieldByHint('KEY'), findsOneWidget);
        expect(find.text('API_KEY'), findsOneWidget);
      });
    });
  });
}

/// A PlatformDirs whose configDir cannot be created because a regular file
/// blocks the path — used to force save failures.
class _BlockedPlatformDirs extends PlatformDirs {
  const _BlockedPlatformDirs(this._configDir);
  final String _configDir;

  @override
  String get configDir => _configDir;

  @override
  String get dataDir => _configDir;

  @override
  String get logsDir => _configDir;

  @override
  String get tempDir => _configDir;

  @override
  String get skillsDir => p.join(_configDir, 'skills');

  @override
  String get yoloitTempDir => p.join(_configDir, 'tmp');
}
