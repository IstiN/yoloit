import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/sticky_note_plugin.dart';

void main() {
  const plugin = StickyNotePlugin();

  test('sticky note uses Miro-style chrome', () {
    expect(plugin.usePanelChrome, isFalse);
    expect(plugin.showHeader, isFalse);
    expect(plugin.hasEditor, isTrue);
    expect(plugin.initialState['fontSize'], 18.0);
  });

  testWidgets('sticky note edits text inline', (tester) async {
    var state = <String, dynamic>{...plugin.initialState, 'text': 'Initial'};
    final panel = BoardPanelInstance(
      id: 'sticky',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 260, height: 220),
      state: state,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 220,
            child: Builder(
              builder:
                  (context) => plugin.buildContent(
                    context,
                    panel,
                    BoardPanelRenderContext(
                      isSelected: true,
                      onFocus: () {},
                      onDelete: () {},
                      onUpdateState: (nextState) => state = nextState,
                      onShowEditor: () {},
                    ),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Updated sticky');
    expect(state['text'], 'Updated sticky');
  });

  testWidgets('sticky editor applies appearance as JSON state', (tester) async {
    Map<String, dynamic>? saved;
    final panel = BoardPanelInstance(
      id: 'sticky',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 260, height: 220),
      state: {...plugin.initialState},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () {
                    plugin.showEditor(context, panel, (state) => saved = state);
                  },
                  child: const Text('Open editor'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.text('Sticky note settings'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!['color'], '#FEF08A');
    expect(saved!['textColor'], '#1F2937');
    expect(saved!['fontSize'], greaterThan(18.0));
  });
}
