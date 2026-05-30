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
}
