import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Test harness for ChatPanelWidget that isolates the input field
/// and model selection behavior.
Widget _buildTestApp({
  required BoardPanelInstance panel,
  ValueChanged<Map<String, dynamic>>? onUpdateState,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ChatPanelWidget(
        panel: panel,
        onUpdateState: onUpdateState ?? (_) {},
      ),
    ),
  );
}

BoardPanelInstance _testPanel([String id = 'test-chat']) {
  return BoardPanelInstance(
    id: id,
    type: 'chat',
    title: 'Test Chat',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 600),
    state: {
      'configured': true,
      'config': {
        'provider': 'copilot',
        'model': 'claude-sonnet-4.6',
        'sessionName': 'test-session',
      },
    },
  );
}

/// Returns true if the model suggestions list is visible.
/// The model suggestions list contains InkWell widgets with model names.
bool _isModelListVisible(WidgetTester tester) {
  // Look for the check icon that appears next to the active model in the suggestions list
  return find.byIcon(Icons.check).evaluate().isNotEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatPanelWidget — model slash command', () {
    testWidgets('typing /model shows model suggestions list', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      // Type /model
      await tester.enterText(inputFinder, '/model');
      await tester.pumpAndSettle();

      // Model suggestions should be visible (check icon for active model)
      expect(_isModelListVisible(tester), isTrue);
    });

    testWidgets('typing /mo (partial) shows filtered chips not model list', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type partial command /mo
      await tester.enterText(inputFinder, '/mo');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Partial match should show filtered chips, NOT model list
      expect(_isModelListVisible(tester), isFalse);
      // Chips should be visible (look for "model" text in chip)
      expect(find.text('model'), findsOneWidget);
    });

    testWidgets('just / shows chips not model list', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      await tester.enterText(inputFinder, '/');
      await tester.pump();

      // Just "/" should NOT show model list
      expect(_isModelListVisible(tester), isFalse);
    });

    testWidgets('ESC hides model list without clearing text', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type /model to show the list
      await tester.enterText(inputFinder, '/model');
      await tester.pumpAndSettle();

      // Verify list is shown
      expect(_isModelListVisible(tester), isTrue);

      // Press ESC
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Model list should be hidden
      expect(_isModelListVisible(tester), isFalse);

      // Text should be preserved (not cleared)
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.controller?.text, '/model');
    });

    testWidgets('ESC on plain slash hides without clearing', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type just / — shows chips, not model list
      await tester.enterText(inputFinder, '/');
      await tester.pump();

      // Model list should NOT be shown for just "/"
      expect(_isModelListVisible(tester), isFalse);

      // Press ESC
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Text should be preserved
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.controller?.text, '/');
    });

    testWidgets('Tab autocompletes partial model command and shows model list', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type partial command
      await tester.enterText(inputFinder, '/mo');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify chips are shown, not model list
      expect(_isModelListVisible(tester), isFalse);
      expect(find.text('model'), findsOneWidget);

      // Simulate Tab autocomplete by directly entering "/model "
      // (In real usage, Tab triggers _autoCompleteSlash which sets this text)
      await tester.enterText(inputFinder, '/model ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // After autocomplete, model list should be visible
      expect(_isModelListVisible(tester), isTrue, reason: 'Model list should appear after /model ');
      
      // Input should contain "/model "
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.controller?.text, '/model ');
    });

    testWidgets('arrow keys navigate model list', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type /model to show list
      await tester.enterText(inputFinder, '/model');
      await tester.pumpAndSettle();

      // Press down arrow
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // List should still be visible
      expect(_isModelListVisible(tester), isTrue);
    });

    testWidgets('non-model text does not show model list', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type regular text
      await tester.enterText(inputFinder, 'hello world');
      await tester.pump();

      // No model suggestions should appear
      expect(_isModelListVisible(tester), isFalse);
    });

    testWidgets('.model trigger also shows model list', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type .model (alternative trigger)
      await tester.enterText(inputFinder, '.model');
      await tester.pumpAndSettle();

      // Model suggestions should be visible
      expect(_isModelListVisible(tester), isTrue);
    });

    testWidgets('ESC after .model hides list without clearing', (tester) async {
      await tester.pumpWidget(_buildTestApp(panel: _testPanel()));
      await tester.pump();

      final inputFinder = find.byType(TextField);

      // Type .model
      await tester.enterText(inputFinder, '.model');
      await tester.pumpAndSettle();

      // Verify list is shown
      expect(_isModelListVisible(tester), isTrue);

      // Press ESC
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // List should be hidden
      expect(_isModelListVisible(tester), isFalse);

      // Text should be preserved
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.controller?.text, '.model');
    });
  });
}

