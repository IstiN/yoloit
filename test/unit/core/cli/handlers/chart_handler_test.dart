// covers-write: board.chart
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/chart_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  const handler = ChartCliHandler();

  BoardPanelInstance newPanel({Map<String, dynamic> state = const {}}) =>
      BoardPanelInstance(
        id: 'panel-chart',
        type: 'board.chart',
        title: 'Chart',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 500, height: 360),
        state: state,
      );

  BoardPanelInstance tablePanel({
    String id = 'panel-table',
    String title = 'Table',
    String? tableId,
    List<Map<String, dynamic>> columns = const [
      {'id': 'month', 'title': 'Month', 'type': 'text'},
      {'id': 'sales', 'title': 'Sales', 'type': 'number'},
    ],
    List<Map<String, dynamic>> rows = const [
      {'id': 'r1', 'month': 'Jan', 'sales': 120},
      {'id': 'r2', 'month': 'Feb', 'sales': 190},
    ],
  }) =>
      BoardPanelInstance(
        id: id,
        type: 'board.table',
        title: title,
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
        state: {
          'columns': columns,
          'rows': rows,
          if (tableId != null) 'tableId': tableId,
        },
      );

  group('ChartCliHandler — metadata', () {
    test('typeId is board.chart', () {
      expect(handler.typeId, 'board.chart');
    });

    test('supportedActions includes all actions', () {
      expect(
        handler.supportedActions,
        containsAll(<String>[
          'get',
          'set-data',
          'set-type',
          'set-options',
          'link-table',
          'unlink-table',
          'refresh',
        ]),
      );
    });

    test('getContent returns chart config', () {
      final panel = newPanel();
      final content = handler.getContent(panel);
      expect(content['type'], 'line');
      expect(content['xKey'], 'month');
      expect(content['yKey'], 'sales');
      expect(content['data'], isA<List<dynamic>>());
    });
  });

  group('ChartCliHandler — set-data', () {
    test('set-data updates inline data', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'set-data',
        {
          'data': [
            {'month': 'Q1', 'sales': 500},
          ],
        },
        panel,
      );
      expect(result.ok, isTrue);
      final data = result.stateUpdate!['data'] as List<dynamic>;
      expect(data.length, 1);
      expect((data.first as Map<String, dynamic>)['sales'], 500);
    });

    test('set-data rejects invalid data', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'set-data',
        {'data': 'not-an-array'},
        panel,
      );
      expect(result.ok, isFalse);
    });
  });

  group('ChartCliHandler — set-type', () {
    test('set-type updates type', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'set-type',
        {'type': 'bar'},
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate!['type'], 'bar');
    });

    test('set-type rejects invalid type', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'set-type',
        {'type': 'pyramid'},
        panel,
      );
      expect(result.ok, isFalse);
    });
  });

  group('ChartCliHandler — set-options', () {
    test('set-options updates keys', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'set-options',
        {'xKey': 'label', 'yKey': 'value', 'animated': false},
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate!['xKey'], 'label');
      expect(result.stateUpdate!['yKey'], 'value');
      expect(result.stateUpdate!['animated'], false);
    });
  });

  group('ChartCliHandler — link-table', () {
    test('link-table sets tablePanelId', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'link-table',
        {'tablePanelId': 'panel-table'},
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate!['tablePanelId'], 'panel-table');
    });

    test('link-table resolves table panel by title', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'link-table',
        {
          'tablePanelId': 'Sales Data',
          '_currentBoardPanels': [
            tablePanel(id: 'panel-table', title: 'Sales Data').toJson(),
          ],
        },
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate!['tablePanelId'], 'panel-table');
    });
  });

  group('ChartCliHandler — refresh', () {
    test('refresh inlines data from linked table', () async {
      final panel = newPanel(state: {'tablePanelId': 'panel-table'});
      final result = await handler.handleAction(
        'refresh',
        {
          '_currentBoardPanels': [
            tablePanel(id: 'panel-table').toJson(),
          ],
        },
        panel,
      );
      expect(result.ok, isTrue);
      final data = result.stateUpdate!['data'] as List<dynamic>;
      expect(data.length, 2);
      expect((data.first as Map<String, dynamic>)['sales'], 120);
    });

    test('refresh finds table by custom tableId', () async {
      final panel = newPanel(state: {'tablePanelId': 'sales-data'});
      final result = await handler.handleAction(
        'refresh',
        {
          '_currentBoardPanels': [
            tablePanel(id: 'panel-table', tableId: 'sales-data').toJson(),
          ],
        },
        panel,
      );
      expect(result.ok, isTrue);
      final data = result.stateUpdate!['data'] as List<dynamic>;
      expect(data.length, 2);
    });

    test('refresh finds table by panel title', () async {
      final panel = newPanel(state: {'tablePanelId': 'Sales Data'});
      final result = await handler.handleAction(
        'refresh',
        {
          '_currentBoardPanels': [
            tablePanel(id: 'panel-table', title: 'Sales Data').toJson(),
          ],
        },
        panel,
      );
      expect(result.ok, isTrue);
      final data = result.stateUpdate!['data'] as List<dynamic>;
      expect(data.length, 2);
    });

    test('refresh casts text numbers to numeric values for chart', () async {
      final panel = newPanel(state: {'tablePanelId': 'expenses-table'});
      final result = await handler.handleAction(
        'refresh',
        {
          '_currentBoardPanels': [
            tablePanel(
              id: 'expenses-table',
              title: 'Expenses',
              columns: const [
                {'id': 'category', 'title': 'Категория', 'type': 'text'},
                {'id': 'amount', 'title': 'Сумма', 'type': 'number'},
              ],
              rows: const [
                {'id': 'r1', 'category': 'Продукты', 'amount': '3500'},
                {'id': 'r2', 'category': 'Транспорт', 'amount': '1200'},
              ],
            ).toJson(),
          ],
        },
        panel,
      );
      expect(result.ok, isTrue);
      final data = result.stateUpdate!['data'] as List<dynamic>;
      expect((data.first as Map<String, dynamic>)['amount'], 3500.0);
      expect(
        result.stateUpdate!['xKey'],
        'category',
        reason: 'should infer text column as xKey',
      );
      expect(
        result.stateUpdate!['yKey'],
        'amount',
        reason: 'should infer number column as yKey',
      );
    });

    test('refresh fails when table panel missing', () async {
      final panel = newPanel(state: {'tablePanelId': 'missing'});
      final result = await handler.handleAction('refresh', {}, panel);
      expect(result.ok, isFalse);
    });

    test('refresh fails for non-table panel', () async {
      final panel = newPanel(state: {'tablePanelId': 'not-table'});
      final result = await handler.handleAction(
        'refresh',
        {
          '_currentBoardPanels': [
            const BoardPanelInstance(
              id: 'not-table',
              type: 'board.note.markdown',
              title: 'Note',
              bounds: BoardPanelBounds(
                x: 0,
                y: 0,
                width: 200,
                height: 200,
              ),
            ).toJson(),
          ],
        },
        panel,
      );
      expect(result.ok, isFalse);
    });
  });
}
