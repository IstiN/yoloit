import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/components/editor/markdown_editor_pane.dart';

void main() {
  testWidgets('MarkdownEditorPane toggles preview and applies bold formatting', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Hello');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 420,
            width: 720,
            child: MarkdownEditorPane(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('Preview'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    expect(controller.text, '**Hello**');

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('**Hello**'), findsNothing);
    expect(find.textContaining('Hello'), findsWidgets);

    await tester.tap(find.text('Write'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  group('paste shortcut', () {
    Widget buildPane(
      TextEditingController controller, {
      Future<void> Function()? onPaste,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 420,
            width: 720,
            child: MarkdownEditorPane(
              controller: controller,
              onPaste: onPaste,
            ),
          ),
        ),
      );
    }

    testWidgets('ctrl+V invokes onPaste while the editor is focused', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Hello');
      addTearDown(controller.dispose);
      var pasteCalls = 0;

      await tester.pumpWidget(
        buildPane(controller, onPaste: () async => pasteCalls++),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(pasteCalls, 1);
    });

    testWidgets('meta+V invokes onPaste as well', (tester) async {
      final controller = TextEditingController(text: 'Hello');
      addTearDown(controller.dispose);
      var pasteCalls = 0;

      await tester.pumpWidget(
        buildPane(controller, onPaste: () async => pasteCalls++),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

      expect(pasteCalls, 1);
    });

    testWidgets('plain V without modifiers does not trigger onPaste', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Hello');
      addTearDown(controller.dispose);
      var pasteCalls = 0;

      await tester.pumpWidget(
        buildPane(controller, onPaste: () async => pasteCalls++),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);

      expect(pasteCalls, 0);
      // Plain 'V' key is not consumed by the paste handler; the character
      // may or may not be inserted by the test binding depending on
      // platform text-input state. Assert only that onPaste was not called.
    });

    testWidgets('ctrl+V is ignored when no onPaste handler is set', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Hello');
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildPane(controller));
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Must not throw even though there is no paste handler.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(controller.text, 'Hello');
    });
  });
}
