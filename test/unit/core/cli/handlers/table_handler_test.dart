import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/table_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/table_plugin.dart';

void main() {
  const handler = TableCliHandler();
  const plugin = TablePlugin();

  BoardPanelInstance newPanel({Map<String, dynamic>? state}) =>
      BoardPanelInstance(
        id: 'panel-table',
        type: 'board.table',
        title: 'Table',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
        state: state ?? plugin.initialState,
      );

  group('TableCliHandler — metadata', () {
    test('typeId is board.table', () {
      expect(handler.typeId, 'board.table');
    });

    test('supportedActions includes all actions', () {
      expect(
        handler.supportedActions,
        containsAll(<String>[
          'get',
          'set',
          'set-id',
          'add-column',
          'rename-column',
          'remove-column',
          'add-row',
          'update-row',
          'remove-row',
          'clear',
        ]),
      );
    });

    test('getContent returns columns and rows', () {
      final panel = newPanel();
      final content = handler.getContent(panel);
      expect(content['columns'], isA<List<dynamic>>());
      expect(content['rows'], isA<List<dynamic>>());
      expect((content['columns'] as List<dynamic>).length, 2);
      expect((content['rows'] as List<dynamic>).length, 3);
    });
  });

  group('TableCliHandler — set', () {
    test('set replaces columns and rows', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'set',
        {
          'columns': [
            {'id': 'name', 'title': 'Name', 'type': 'text'},
          ],
          'rows': [
            {'id': 'r1', 'name': 'Alice'},
          ],
        },
        panel,
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate!['columns'] as List<dynamic>;
      final rows = result.stateUpdate!['rows'] as List<dynamic>;
      expect(columns.length, 1);
      expect(rows.length, 1);
      expect((rows.first as Map<String, dynamic>)['name'], 'Alice');
    });

    test('set requires columns and rows lists', () async {
      final panel = newPanel();
      final result = await handler.handleAction('set', {}, panel);
      expect(result.ok, isFalse);
    });
  });

  group('TableCliHandler — set-id', () {
    test('set-id updates tableId', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'set-id',
        {'tableId': 'sales-data'},
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate!['tableId'], 'sales-data');
    });

    test('set-id requires tableId', () async {
      final panel = newPanel();
      final result = await handler.handleAction('set-id', {}, panel);
      expect(result.ok, isFalse);
    });
  });

  group('TableCliHandler — add-column', () {
    test('add-column appends column and default cells', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'add-column',
        {'id': 'region', 'title': 'Region', 'type': 'text'},
        panel,
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate!['columns'] as List<dynamic>;
      final rows = result.stateUpdate!['rows'] as List<dynamic>;
      expect(columns.length, 3);
      expect((rows.first as Map<String, dynamic>).containsKey('region'), isTrue);
    });

    test('add-column rejects duplicate id', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'add-column',
        {'id': 'month', 'title': 'Month'},
        panel,
      );
      expect(result.ok, isFalse);
    });
  });

  group('TableCliHandler — rename-column', () {
    test('rename-column updates title', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'rename-column',
        {'id': 'month', 'title': 'Period'},
        panel,
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate!['columns'] as List<dynamic>;
      expect((columns.first as Map<String, dynamic>)['title'], 'Period');
    });
  });

  group('TableCliHandler — remove-column', () {
    test('remove-column deletes column and cells', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'remove-column',
        {'id': 'sales'},
        panel,
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate!['columns'] as List<dynamic>;
      final rows = result.stateUpdate!['rows'] as List<dynamic>;
      expect(columns.length, 1);
      expect((rows.first as Map<String, dynamic>).containsKey('sales'), isFalse);
    });
  });

  group('TableCliHandler — add-row', () {
    test('add-row appends row with cell values', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'add-row',
        {'month': 'Apr', 'sales': 220},
        panel,
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate!['rows'] as List<dynamic>;
      expect(rows.length, 4);
      expect((rows.last as Map<String, dynamic>)['month'], 'Apr');
      expect((rows.last as Map<String, dynamic>)['sales'], 220);
    });
  });

  group('TableCliHandler — update-row', () {
    test('update-row changes cell values', () async {
      final panel = newPanel();
      final rows = panel.state['rows'] as List<dynamic>;
      final rowId = (rows.first as Map<String, dynamic>)['id'] as String;
      final result = await handler.handleAction(
        'update-row',
        {'rowId': rowId, 'sales': 999},
        panel,
      );
      expect(result.ok, isTrue);
      final updatedRows = result.stateUpdate!['rows'] as List<dynamic>;
      expect((updatedRows.first as Map<String, dynamic>)['sales'], 999);
    });
  });

  group('TableCliHandler — remove-row', () {
    test('remove-row deletes row by id', () async {
      final panel = newPanel();
      final rows = panel.state['rows'] as List<dynamic>;
      final rowId = (rows.first as Map<String, dynamic>)['id'] as String;
      final result = await handler.handleAction(
        'remove-row',
        {'rowId': rowId},
        panel,
      );
      expect(result.ok, isTrue);
      final updatedRows = result.stateUpdate!['rows'] as List<dynamic>;
      expect(updatedRows.length, 2);
    });
  });

  group('TableCliHandler — clear', () {
    test('clear removes all rows', () async {
      final panel = newPanel();
      final result = await handler.handleAction('clear', {}, panel);
      expect(result.ok, isTrue);
      final rows = result.stateUpdate!['rows'] as List<dynamic>;
      expect(rows, isEmpty);
    });
  });
}
