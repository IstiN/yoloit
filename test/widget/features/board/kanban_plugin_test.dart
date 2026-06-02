import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/kanban_plugin.dart';

void main() {
  const plugin = KanbanPlugin();

  testWidgets('kanban card opens editor and saves card fields', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var state = <String, dynamic>{
      'columns': ['Todo', 'Done'],
      'cards': <Map<String, dynamic>>[
        {
          'id': 'card-1',
          'title': 'Old title',
          'description': '',
          'columnIndex': 0,
        },
      ],
    };

    BoardPanelInstance panelForState() => BoardPanelInstance(
      id: 'kanban',
      type: KanbanPlugin.kTypeId,
      title: 'Kanban',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 640, height: 420),
      state: state,
    );

    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 420,
            child: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return plugin.buildContent(
                  context,
                  panelForState(),
                  BoardPanelRenderContext(
                    isSelected: true,
                    onFocus: () {},
                    onDelete: () {},
                    onUpdateState: (nextState) {
                      state = nextState;
                      refresh(() {});
                    },
                    onShowEditor: () {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Old title'));
    await tester.pumpAndSettle();

    expect(find.text('Edit kanban card'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'New title');
    await tester.enterText(fields.at(1), 'Long card description');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final cards = state['cards'] as List<dynamic>;
    final card = Map<String, dynamic>.from(cards.single as Map);
    expect(card['title'], 'New title');
    expect(card['description'], 'Long card description');
    expect(card['columnIndex'], 1);
  });
}
