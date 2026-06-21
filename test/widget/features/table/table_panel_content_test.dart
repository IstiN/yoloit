import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/table_plugin.dart';
import 'package:yoloit/features/table/ui/table_panel_content.dart';

void main() {
  const plugin = TablePlugin();

  BoardPanelRenderContext context(List<Map<String, dynamic>?> storage) {
    return BoardPanelRenderContext(
      isSelected: false,
      onFocus: () {},
      onDelete: () {},
      onUpdateState: (state) => storage[0] = state,
      onShowEditor: () {},
    );
  }

  BoardPanelInstance panel({Map<String, dynamic> state = const {}}) =>
      BoardPanelInstance(
        id: 'table-widget',
        type: TablePlugin.kTypeId,
        title: 'Table',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 520, height: 360),
        state: {...plugin.initialState, ...state},
      );

  Future<void> pumpTable(
    WidgetTester tester,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 360,
            child: TablePanelContent(
              panel: panel,
              renderContext: renderContext,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders default table data', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    final p = panel();
    await pumpTable(tester, p, context(storage));
    expect(find.byType(TablePanelContent), findsOneWidget);
    expect(find.text('Month'), findsWidgets);
    expect(find.text('Jan'), findsOneWidget);
    expect(find.textContaining(p.id), findsOneWidget);
  });

  testWidgets('adds row via toolbar', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpTable(tester, panel(), context(storage));
    await tester.tap(find.text('Row').first);
    await tester.pump();
    expect(storage[0], isNotNull);
    final rows = storage[0]!['rows'] as List;
    expect(rows.length, 4);
  });

  testWidgets('clears rows via toolbar', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpTable(tester, panel(), context(storage));
    await tester.tap(find.text('Clear').first);
    await tester.pump();
    expect(storage[0], isNotNull);
    final rows = storage[0]!['rows'] as List;
    expect(rows, isEmpty);
  });

  testWidgets('adds row and updates the grid UI', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpTable(tester, panel(), context(storage));
    await tester.tap(find.text('Row').first);
    await tester.pumpAndSettle();
    expect(storage[0], isNotNull);
    final rows = storage[0]!['rows'] as List;
    expect(rows.length, 4);
    await pumpTable(tester, panel(state: storage[0]!), context(storage));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('removes last row and updates the grid UI', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpTable(tester, panel(), context(storage));
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pumpAndSettle();
    expect(storage[0], isNotNull);
    final rows = storage[0]!['rows'] as List;
    expect(rows.length, 2);
    await pumpTable(tester, panel(state: storage[0]!), context(storage));
    await tester.pumpAndSettle();
    expect(find.text('Mar'), findsNothing);
  });

  testWidgets('removes column and updates the grid UI', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpTable(tester, panel(), context(storage));
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();
    expect(storage[0], isNotNull);
    final columns = storage[0]!['columns'] as List;
    expect(columns.length, 1);
    await pumpTable(tester, panel(state: storage[0]!), context(storage));
    await tester.pumpAndSettle();
    expect(find.text('Month'), findsNothing);
  });

  testWidgets('renames column by double-tapping header', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpTable(tester, panel(), context(storage));
    final header = find.text('Month').first;
    await tester.tap(header);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Quarter');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(storage[0], isNotNull);
    final columns = storage[0]!['columns'] as List;
    expect(columns.first['title'], 'Quarter');
    await pumpTable(tester, panel(state: storage[0]!), context(storage));
    await tester.pumpAndSettle();
    expect(find.text('Quarter'), findsWidgets);
    expect(find.text('Month'), findsNothing);
  });

  testWidgets('edits custom table ID', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    final p = panel();
    await pumpTable(tester, p, context(storage));
    await tester.tap(find.byIcon(Icons.edit).last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sales-data');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(storage[0], isNotNull);
    expect(storage[0]!['tableId'], 'sales-data');
    await pumpTable(tester, panel(state: storage[0]!), context(storage));
    await tester.pumpAndSettle();
    expect(find.text('sales-data'), findsOneWidget);
  });
}
