import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_panel_actions.dart';

RemotePanel _tablePanel() => const RemotePanel(
  id: 'p-table',
  type: 'board.table',
  title: 'Table',
  bounds: RemotePanelBounds(
    x: 0,
    y: 0,
    width: 520,
    height: 360,
  ),
  state: {
    'columns': [
      {'id': 'month', 'title': 'Month', 'type': 'text'},
      {'id': 'sales', 'title': 'Sales', 'type': 'number'},
    ],
    'rows': [
      {'id': 'r-1', 'month': 'Jan', 'sales': 120},
    ],
  },
);

void main() {
  group('board.table actions', () {
    test('add-row puts cells keyed by column id', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-row',
        {'cells': {'month': 'Feb', 'sales': 200}},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      expect(rows, hasLength(2));
      final added = rows.last as Map<String, dynamic>;
      expect(added['month'], 'Feb');
      expect(added['sales'], 200);
    });

    test('add-row maps column titles to ids', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-row',
        {
          'cells': {'Month': 'Feb', 'Sales': 200},
        },
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      expect(rows, hasLength(2));
      final added = rows.last as Map<String, dynamic>;
      expect(added['month'], 'Feb');
      expect(added['sales'], 200);
    });

    test('add-row defaults missing cells to type defaults', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-row',
        <String, dynamic>{},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final added = rows.last as Map<String, dynamic>;
      expect(added['month'], '');
      expect(added['sales'], 0);
    });

    test('update-row maps column titles to ids', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'update-row',
        {
          'rowId': 'r-1',
          'cells': {'Month': 'Apr', 'Sales': 999},
        },
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final updated = rows.single as Map<String, dynamic>;
      expect(updated['month'], 'Apr');
      expect(updated['sales'], 999);
    });

    test('update-row changes only provided cells', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'update-row',
        {'rowId': 'r-1', 'cells': {'sales': 999}},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final updated = rows.single as Map<String, dynamic>;
      expect(updated['month'], 'Jan');
      expect(updated['sales'], 999);
    });

    test('remove-row deletes by id', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'remove-row',
        {'rowId': 'r-1'},
      );
      expect(result.ok, isTrue);
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      expect(rows, isEmpty);
    });

    test('add-column adds default cells to existing rows', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'add-column',
        {'id': 'region', 'title': 'Region', 'type': 'text'},
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate['columns'] as List<dynamic>;
      expect(columns, hasLength(3));
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final row = rows.single as Map<String, dynamic>;
      expect(row.containsKey('region'), isTrue);
      expect(row['region'], '');
    });

    test('rename-column updates title', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'rename-column',
        {'id': 'month', 'title': 'Period'},
      );
      expect(result.ok, isTrue);
      final columns = (result.stateUpdate['columns'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      final month = columns.firstWhere(
        (column) => column['id'] == 'month',
      );
      expect(month['title'], 'Period');
    });

    test('remove-column removes cells from rows', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(
        panel,
        'remove-column',
        {'id': 'sales'},
      );
      expect(result.ok, isTrue);
      final columns = result.stateUpdate['columns'] as List<dynamic>;
      expect(columns, hasLength(1));
      final rows = result.stateUpdate['rows'] as List<dynamic>;
      final row = rows.single as Map<String, dynamic>;
      expect(row.containsKey('sales'), isFalse);
    });

    test('clear removes all rows but keeps columns', () {
      final panel = _tablePanel();
      final result = handleRemotePanelAction(panel, 'clear', {});
      expect(result.ok, isTrue);
      expect(result.stateUpdate['rows'], isEmpty);
      expect(result.stateUpdate.containsKey('columns'), isFalse);
    });
  });
}
