import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/platform/platform_capabilities_web.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/ui/dialogs/board_settings_dialog.dart';

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
}
