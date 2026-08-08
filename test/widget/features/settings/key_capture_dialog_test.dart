import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/hotkeys/hotkey_definition.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/dialogs/key_capture_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final definition = HotkeyDefinition(
    id: 'test_action',
    description: 'Test action',
    category: 'Test',
    defaultActivator: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
    intent: const DoNothingIntent(),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () {
                    showDialog<SingleActivator>(
                      context: context,
                      builder: (_) => Dialog(child: KeyCaptureDialog(definition: definition)),
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Remap: Test action'), findsOneWidget);
  }

  group('KeyCaptureDialog._onKey', () {
    testWidgets('shows the capture prompt initially', (tester) async {
      await openDialog(tester);
      expect(find.text('Press a key combination…'), findsOneWidget);
      // Apply is disabled until something is captured.
      final apply = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Apply'),
      );
      expect(apply.onPressed, isNull);
    });

    testWidgets('ignores key-up events and pure modifier presses', (
      tester,
    ) async {
      await openDialog(tester);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(find.text('Press a key combination…'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.text('Press a key combination…'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    });

    testWidgets('captures a plain key and applies it', (tester) async {
      await openDialog(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.pump();

      expect(find.text('B'), findsOneWidget);
      expect(find.text('Press a key combination…'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
      await tester.pumpAndSettle();

      // Dialog closed after applying.
      expect(find.text('Remap: Test action'), findsNothing);
    });

    testWidgets('captures a meta combo and reports a conflict', (tester) async {
      await openDialog(tester);

      // ⌘W is bound to 'close_tab' in the default registry.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pump();

      expect(find.text('⌘W'), findsOneWidget);
      expect(find.textContaining('Conflicts with'), findsOneWidget);
      expect(find.textContaining('Close terminal tab'), findsOneWidget);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    });

    testWidgets('a non-conflicting combo shows no warning', (tester) async {
      await openDialog(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();

      expect(find.text('⌘Z'), findsOneWidget);
      expect(find.textContaining('Conflicts with'), findsNothing);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    });

    testWidgets('escape without meta cancels the dialog', (tester) async {
      await openDialog(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Remap: Test action'), findsNothing);
    });

    testWidgets('escape with meta is captured instead of cancelling', (
      tester,
    ) async {
      await openDialog(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Still open, and the combo is shown in the capture area.
      expect(find.text('Remap: Test action'), findsOneWidget);
      expect(find.text('⌘⎋'), findsOneWidget);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    });

    testWidgets('cancel button closes the dialog', (tester) async {
      await openDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Remap: Test action'), findsNothing);
    });
  });
}
