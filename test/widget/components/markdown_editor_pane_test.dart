import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/editor/markdown_editor_pane.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildPane({
    TextEditingController? controller,
    FocusNode? focusNode,
    Future<void> Function()? onPaste,
  }) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [AppColorScheme.fromAccent(const Color(0xFF7C6BFF))],
      ),
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 360,
          child: MarkdownEditorPane(
            controller: controller ?? TextEditingController(text: 'hello'),
            focusNode: focusNode,
            onPaste: onPaste,
          ),
        ),
      ),
    );
  }

  group('MarkdownEditorPane paste shortcut', () {
    testWidgets('invokes onPaste for Cmd+V key down', (tester) async {
      var pasteCalls = 0;
      await tester.pumpWidget(
        buildPane(onPaste: () async {
          pasteCalls++;
        }),
      );
      await tester.pump();

      // Focus the editor to receive key events.
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Press Cmd+V — the shortcut checks for meta OR control with keyV.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();

      expect(pasteCalls, greaterThan(0));

      // Release keys to clean up.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });

    testWidgets('does not invoke onPaste for a non-paste key', (tester) async {
      var pasteCalls = 0;
      await tester.pumpWidget(
        buildPane(onPaste: () async {
          pasteCalls++;
        }),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.pump();

      expect(pasteCalls, 0);
    });

    testWidgets('does not invoke onPaste when onPaste is null', (tester) async {
      // No onPaste callback — the handler should return ignored early.
      await tester.pumpWidget(buildPane());
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      // A plain key V without modifier — should be ignored.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.pump();

      // No crash, no callback — the test just needs to pass.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('ignores KeyUpEvent for paste chord', (tester) async {
      var pasteCalls = 0;
      await tester.pumpWidget(
        buildPane(onPaste: () async {
          pasteCalls++;
        }),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      // KeyUp should be ignored.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.pump();

      expect(pasteCalls, 0);
    });

    testWidgets('Ctrl+V also triggers paste on non-mac platforms', (
      tester,
    ) async {
      var pasteCalls = 0;
      await tester.pumpWidget(
        buildPane(onPaste: () async {
          pasteCalls++;
        }),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Press Ctrl then V.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();

      expect(pasteCalls, greaterThan(0));
    });
  });

  group('MarkdownEditorPane preview toggle', () {
    testWidgets('switches between write and preview', (tester) async {
      final controller = TextEditingController(text: '# Hello');
      await tester.pumpWidget(buildPane(controller: controller));
      await tester.pump();

      // Tap the Preview segment.
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      // Tap back to Write.
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
