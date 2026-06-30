import 'package:flutter/material.dart';
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
}
