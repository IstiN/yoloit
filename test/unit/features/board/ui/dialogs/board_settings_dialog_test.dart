import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/platform/platform_capabilities_web.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/ui/dialogs/board_settings_dialog.dart';

typedef _BoardSettingsResult =
    ({
      String name,
      String defaultFolder,
      bool archived,
      BoardIconSpec? icon,
      bool iconChanged,
      List<String> envGroupIds,
      Map<String, String> env,
    });

void main() {
  group('BoardSettingsDialog', () {
    Widget buildDialog({
      String initialName = 'My Board',
      String initialDefaultFolder = '/tmp',
      AsyncValueGetter<String?>? onPickFolder,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder:
                          (_) => BoardSettingsDialog(
                            initialName: initialName,
                            initialDefaultFolder: initialDefaultFolder,
                            remoteInfo: null,
                            onPickFolder: onPickFolder,
                          ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      );
    }

    testWidgets('renders title and fields', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Board settings'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'My Board'), findsOneWidget);
      expect(find.widgetWithText(TextField, '/tmp'), findsOneWidget);
    });

    testWidgets('shows Choose folder and Clear buttons', (tester) async {
      await tester.pumpWidget(
        buildDialog(onPickFolder: () async => '/chosen'),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Choose folder'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('hides folder picker on web', (tester) async {
      PlatformCapabilities.current = const WebPlatformCapabilities();
      addTearDown(PlatformCapabilities.reset);

      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Choose folder'), findsNothing);
      expect(find.text('Clear'), findsNothing);
      expect(
        find.text(
          'Not used in the browser; board state is kept in web storage.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Clear button empties folder field', (tester) async {
      await tester.pumpWidget(
        buildDialog(onPickFolder: () async => '/chosen'),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear'));
      await tester.pump();

      final folderField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Default folder'),
      );
      expect(folderField.controller!.text, isEmpty);
    });

    testWidgets('Save action returns updated values', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'My Board'),
        'New Name',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Board settings'), findsNothing);
    });

    testWidgets('renders board icon row with change button', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Board icon'), findsOneWidget);
      expect(
        find.text('Auto-detected from the default folder.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('board-settings-change-icon')), findsOneWidget);
    });
  });

  group('BoardSettingsDialog default env', () {
    (Widget, Object? Function()) pumpCapturingDialog(
      WidgetTester tester, {
      List<String> initialEnvGroupIds = const <String>[],
      Map<String, String> initialEnv = const <String, String>{},
    }) {
      Object? result;
      final widget = MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<Object?>(
                      context: context,
                      builder: (_) => BoardSettingsDialog(
                        initialName: 'My Board',
                        initialDefaultFolder: '/tmp',
                        remoteInfo: null,
                        initialEnvGroupIds: initialEnvGroupIds,
                        initialEnv: initialEnv,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      );
      return (widget, () => result);
    }

    testWidgets('renders default env section with seeded values', (
      tester,
    ) async {
      final (widget, _) = pumpCapturingDialog(
        tester,
        initialEnvGroupIds: ['g1'],
        initialEnv: {'API_KEY': 'abc'},
      );
      await tester.pumpWidget(widget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Default env variables'), findsOneWidget);
      expect(find.text('Env groups'), findsOneWidget);
      expect(find.text('API_KEY'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'abc'), findsOneWidget);
    });

    testWidgets('Save returns edited env groups and inline variables', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (widget, getResult) = pumpCapturingDialog(
        tester,
        initialEnv: {'API_KEY': 'abc'},
      );
      await tester.pumpWidget(widget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Add a variable row and fill it in.
      await tester.tap(find.text('Add Variable'));
      await tester.pump();
      Finder fieldByHint(String hint) => find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == hint,
      );
      // The new row is the only one with an empty KEY / VALUE.
      final emptyKeyField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'KEY' &&
            (widget.controller?.text.isEmpty ?? false),
      );
      final emptyValueField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'VALUE' &&
            (widget.controller?.text.isEmpty ?? false),
      );
      expect(emptyKeyField, findsOneWidget);
      expect(emptyValueField, findsOneWidget);
      await tester.enterText(emptyKeyField, 'NEW_KEY');
      await tester.enterText(emptyValueField, 'new_value');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final result = getResult()! as _BoardSettingsResult;
      expect(result.env, {'API_KEY': 'abc', 'NEW_KEY': 'new_value'});
      expect(result.envGroupIds, isEmpty);
    });

    testWidgets('deleting a row removes the variable from the result', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (widget, getResult) = pumpCapturingDialog(
        tester,
        initialEnv: {'API_KEY': 'abc'},
      );
      await tester.pumpWidget(widget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final result = getResult()! as _BoardSettingsResult;
      expect(result.env, isEmpty);
    });
  });
}
