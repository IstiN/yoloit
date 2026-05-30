import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';

void main() {
  const plugin = ShapePlugin();

  test('shape uses Miro-style chrome and transparent fill by default', () {
    expect(plugin.usePanelChrome, isFalse);
    expect(plugin.showHeader, isFalse);
    expect(plugin.initialState['fillColor'], '#00000000');
  });

  testWidgets('shape edits label inline', (tester) async {
    var state = <String, dynamic>{...plugin.initialState, 'text': 'Initial'};
    final panel = BoardPanelInstance(
      id: 'shape',
      type: ShapePlugin.kTypeId,
      title: 'Shape',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 220),
      state: state,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
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

    await tester.enterText(find.byType(TextField), 'Updated shape');
    expect(state['text'], 'Updated shape');
  });
}
