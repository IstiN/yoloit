import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/table/model/table_models.dart';

/// CLI handler for Table panels (`board.table`).
class TableCliHandler extends PanelCliHandler {
  const TableCliHandler();

  @override
  String get typeId => 'board.table';

  @override
  List<String> get supportedActions => [
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
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return <String, dynamic>{
      'tableId': TableDataHelper.effectiveId(panel.state, panel.id),
      'columns': TableDataHelper.columnsToJson(
        TableDataHelper.parseColumns(panel.state['columns']).toList(),
      ),
      'rows': TableDataHelper.rowsToJson(
        TableDataHelper.parseRows(panel.state['rows']).toList(),
      ),
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(data: getContent(panel));
      case 'set':
        return _handleSet(args, panel);
      case 'set-id':
        return _handleSetId(args, panel);
      case 'add-column':
        return _handleAddColumn(args, panel);
      case 'rename-column':
        return _handleRenameColumn(args, panel);
      case 'remove-column':
        return _handleRemoveColumn(args, panel);
      case 'add-row':
        return _handleAddRow(args, panel);
      case 'update-row':
        return _handleUpdateRow(args, panel);
      case 'remove-row':
        return _handleRemoveRow(args, panel);
      case 'clear':
        return _handleClear(panel);
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  CliActionResult _handleSet(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final columns = args['columns'];
    final rows = args['rows'];
    if (columns is! List || rows is! List) {
      return const CliActionResult(
        ok: false,
        message: 'Missing or invalid "columns" or "rows"',
      );
    }
    final parsedColumns = TableDataHelper.parseColumns(columns);
    final parsedRows = TableDataHelper.parseRows(rows);
    if (parsedColumns.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'At least one column is required',
      );
    }
    return CliActionResult(
      message: 'Table data replaced',
      stateUpdate: <String, dynamic>{
        'columns': TableDataHelper.columnsToJson(parsedColumns),
        'rows': TableDataHelper.rowsToJson(parsedRows),
      },
    );
  }

  CliActionResult _handleSetId(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final tableId = _string(args['tableId'] ?? args['id']);
    if (tableId == null) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: tableId',
      );
    }
    return CliActionResult(
      message: 'Table ID set to "$tableId"',
      stateUpdate: <String, dynamic>{
        ...panel.state,
        'tableId': tableId,
      },
    );
  }

  CliActionResult _handleAddColumn(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final id = _string(args['id']) ?? _string(args['columnId']);
    final title = _string(args['title']) ?? _string(args['name']);
    final type = TableColumnTypeExtension.fromJson(args['type']);
    final options = _stringList(args['options']);
    if (id == null || id.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: id',
      );
    }
    final columns = TableDataHelper.parseColumns(panel.state['columns']).toList();
    if (columns.any((column) => column.id == id)) {
      return CliActionResult(
        ok: false,
        message: 'Column already exists: $id',
      );
    }
    final newColumn = TableColumn(
      id: id,
      title: title ?? id,
      type: type,
      options: options,
    );
    final rows = TableDataHelper.parseRows(panel.state['rows']).toList();
    final updatedRows =
        rows
            .map(
              (row) => row.copyWith(
                cells: <String, dynamic>{...row.cells, id: _defaultCellValue(type)},
              ),
            )
            .toList();
    return CliActionResult(
      message: 'Column "$id" added',
      stateUpdate: <String, dynamic>{
        'columns': TableDataHelper.columnsToJson([...columns, newColumn]),
        'rows': TableDataHelper.rowsToJson(updatedRows),
      },
    );
  }

  CliActionResult _handleRenameColumn(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final id = _string(args['id']) ?? _string(args['columnId']);
    final title = _string(args['title']) ?? _string(args['name']);
    if (id == null || title == null || title.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required fields: id and title',
      );
    }
    final columns = TableDataHelper.parseColumns(panel.state['columns']).toList();
    final index = columns.indexWhere((column) => column.id == id);
    if (index < 0) {
      return CliActionResult(ok: false, message: 'Column not found: $id');
    }
    columns[index] = columns[index].copyWith(title: title);
    return CliActionResult(
      message: 'Column renamed to "$title"',
      stateUpdate: <String, dynamic>{
        'columns': TableDataHelper.columnsToJson(columns),
      },
    );
  }

  CliActionResult _handleRemoveColumn(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final id = _string(args['id']) ?? _string(args['columnId']);
    if (id == null || id.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: id',
      );
    }
    final columns = TableDataHelper.parseColumns(panel.state['columns']).toList();
    final index = columns.indexWhere((column) => column.id == id);
    if (index < 0) {
      return CliActionResult(ok: false, message: 'Column not found: $id');
    }
    columns.removeAt(index);
    final rows =
        TableDataHelper
            .parseRows(panel.state['rows'])
            .map(
              (row) => row.copyWith(
                cells: Map<String, dynamic>.from(row.cells)..remove(id),
              ),
            )
            .toList();
    return CliActionResult(
      message: 'Column "$id" removed',
      stateUpdate: <String, dynamic>{
        'columns': TableDataHelper.columnsToJson(columns),
        'rows': TableDataHelper.rowsToJson(rows),
      },
    );
  }

  CliActionResult _handleAddRow(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final columns = TableDataHelper.parseColumns(panel.state['columns']).toList();
    final rows = TableDataHelper.parseRows(panel.state['rows']).toList();
    final cells = <String, dynamic>{
      for (final column in columns)
        column.id: _castCellValue(args[column.id], column.type),
    };
    final newRow = TableRow(
      id: 'r-${DateTime.now().millisecondsSinceEpoch}',
      cells: cells,
    );
    return CliActionResult(
      message: 'Row added',
      stateUpdate: <String, dynamic>{
        'rows': TableDataHelper.rowsToJson([...rows, newRow]),
      },
    );
  }

  CliActionResult _handleUpdateRow(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final rowId = _string(args['id']) ?? _string(args['rowId']);
    if (rowId == null || rowId.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: id',
      );
    }
    final columns = TableDataHelper.parseColumns(panel.state['columns']).toList();
    final rows = TableDataHelper.parseRows(panel.state['rows']).toList();
    final index = rows.indexWhere((row) => row.id == rowId);
    if (index < 0) {
      return CliActionResult(ok: false, message: 'Row not found: $rowId');
    }
    final updatedCells = Map<String, dynamic>.from(rows[index].cells);
    for (final column in columns) {
      if (args.containsKey(column.id)) {
        updatedCells[column.id] = _castCellValue(args[column.id], column.type);
      }
    }
    rows[index] = rows[index].copyWith(cells: updatedCells);
    return CliActionResult(
      message: 'Row updated',
      stateUpdate: <String, dynamic>{
        'rows': TableDataHelper.rowsToJson(rows),
      },
    );
  }

  CliActionResult _handleRemoveRow(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final rowId = _string(args['id']) ?? _string(args['rowId']);
    if (rowId == null || rowId.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: id',
      );
    }
    final rows = TableDataHelper.parseRows(panel.state['rows']).toList();
    final index = rows.indexWhere((row) => row.id == rowId);
    if (index < 0) {
      return CliActionResult(ok: false, message: 'Row not found: $rowId');
    }
    rows.removeAt(index);
    return CliActionResult(
      message: 'Row removed',
      stateUpdate: <String, dynamic>{
        'rows': TableDataHelper.rowsToJson(rows),
      },
    );
  }

  CliActionResult _handleClear(BoardPanelInstance panel) {
    return CliActionResult(
      message: 'Table cleared',
      stateUpdate: <String, dynamic>{
        ...panel.state,
        'rows': const <Map<String, dynamic>>[],
      },
    );
  }

  dynamic _defaultCellValue(TableColumnType type) {
    switch (type) {
      case TableColumnType.number:
        return 0;
      case TableColumnType.date:
        return DateTime.now().toIso8601String().split('T').first;
      case TableColumnType.select:
      case TableColumnType.text:
        return '';
    }
  }

  dynamic _castCellValue(dynamic value, TableColumnType type) {
    if (value == null) return _defaultCellValue(type);
    switch (type) {
      case TableColumnType.number:
        if (value is num) return value;
        return double.tryParse(value.toString()) ?? 0;
      case TableColumnType.date:
      case TableColumnType.select:
      case TableColumnType.text:
        return value.toString();
    }
  }

  String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<String> _stringList(dynamic value) {
    if (value is List) return value.whereType<String>().toList();
    return const <String>[];
  }

  @override
  Map<String, CliActionHelp> get actionHelp => <String, CliActionHelp>{
    'get': const CliActionHelp(description: 'Get table columns and rows'),
    'set': const CliActionHelp(
      description: 'Replace table columns and rows',
      params: {
        'columns': 'List of column objects {id, title, type}',
        'rows': 'List of row objects {id, ...cells}',
      },
    ),
    'set-id': const CliActionHelp(
      description: 'Set a custom table ID for chart linking',
      params: {'tableId': 'Custom ID (empty resets to panel ID)'},
    ),
    'add-column': const CliActionHelp(
      description: 'Add a column',
      params: {
        'id': 'Column id',
        'title': 'Column title',
        'type': 'text | number | date | select',
        'options': 'List of options for select type',
      },
    ),
    'rename-column': const CliActionHelp(
      description: 'Rename a column',
      params: {'id': 'Column id', 'title': 'New title'},
    ),
    'remove-column': const CliActionHelp(
      description: 'Remove a column',
      params: {'id': 'Column id'},
    ),
    'add-row': const CliActionHelp(
      description: 'Add a row. Pass cell values keyed by column id.',
    ),
    'update-row': const CliActionHelp(
      description: 'Update cells in a row',
      params: {'id': 'Row id'},
    ),
    'remove-row': const CliActionHelp(
      description: 'Remove a row by id',
      params: {'id': 'Row id'},
    ),
    'clear': const CliActionHelp(description: 'Remove all rows'),
  };
}
