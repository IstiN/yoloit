import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/chart_plugin.dart';
import 'package:yoloit/features/chart/ui/chart_panel_content.dart';

void main() {
  const plugin = ChartPlugin();

  BoardPanelRenderContext context(List<Map<String, dynamic>?> storage) {
    return BoardPanelRenderContext(
      isSelected: false,
      onFocus: () {},
      onDelete: () {},
      onUpdateState: (state) => storage[0] = state,
      onShowEditor: () {},
    );
  }

  BoardPanelInstance chartPanel({Map<String, dynamic> state = const {}}) =>
      BoardPanelInstance(
        id: 'chart-widget',
        type: ChartPlugin.kTypeId,
        title: 'Chart',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 560, height: 400),
        state: {...plugin.initialState, ...state},
      );

  Future<void> pumpChart(
    WidgetTester tester,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 560,
            height: 400,
            child: ChartPanelContent(
              panel: panel,
              renderContext: renderContext,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders default line chart', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpChart(tester, chartPanel(), context(storage));
    expect(find.byType(ChartPanelContent), findsOneWidget);
    expect(find.text('Line'), findsOneWidget);
  });

  testWidgets('switches chart type to bar', (tester) async {
    final storage = <Map<String, dynamic>?>[null];
    await pumpChart(tester, chartPanel(), context(storage));
    await tester.tap(find.text('Line'));
    await tester.pump();
    await tester.tap(find.text('Bar').last);
    await tester.pump();
    expect(storage[0], isNotNull);
    expect(storage[0]!['type'], 'bar');
  });

  testWidgets('resolves linked table data', (tester) async {
    const tablePanel = BoardPanelInstance(
      id: 'linked-table',
      type: 'board.table',
      title: 'Linked Table',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 200, height: 200),
      state: {
        'columns': [
          {'id': 'month', 'title': 'Month', 'type': 'text'},
          {'id': 'sales', 'title': 'Sales', 'type': 'number'},
        ],
        'rows': [
          {'id': 'r1', 'month': 'Q1', 'sales': 500},
        ],
      },
    );
    final panel = chartPanel(
      state: {
        'type': 'bar',
        'tablePanelId': 'linked-table',
        'xKey': 'month',
        'yKey': 'sales',
      },
    );
    final renderContext = BoardPanelRenderContext(
      isSelected: false,
      onFocus: () {},
      onDelete: () {},
      onUpdateState: (_) {},
      onShowEditor: () {},
      onFindPanelById: (id) => id == 'linked-table' ? tablePanel : null,
    );
    await pumpChart(tester, panel, renderContext);
    expect(find.byType(ChartPanelContent), findsOneWidget);
    expect(find.text('Bar'), findsOneWidget);
  });

  testWidgets('renders all chart types with fl_chart 1.x', (tester) async {
    for (final type in ['line', 'bar', 'pie', 'scatter', 'radar', 'area']) {
      final storage = <Map<String, dynamic>?>[null];
      await pumpChart(
        tester,
        chartPanel(state: {'type': type, 'animated': false}),
        context(storage),
      );
      expect(find.byType(ChartPanelContent), findsOneWidget);
    }
  });
}
