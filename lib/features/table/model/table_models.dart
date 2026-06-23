import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

/// Column definition for a Table panel.
class TableColumn {
  const TableColumn({
    required this.id,
    required this.title,
    this.type = TableColumnType.text,
    this.options = const <String>[],
  });

  final String id;
  final String title;
  final TableColumnType type;
  final List<String> options;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'type': type.name,
    if (options.isNotEmpty) 'options': options,
  };

  factory TableColumn.fromJson(Map<String, dynamic> json) {
    return TableColumn(
      id: (json['id'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? json['id'] as String? ?? '').trim(),
      type: TableColumnTypeExtension.fromJson(json['type']),
      options: TableDataHelper._stringList(json['options']),
    );
  }

  TableColumn copyWith({
    String? id,
    String? title,
    TableColumnType? type,
    List<String>? options,
  }) {
    return TableColumn(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      options: options ?? this.options,
    );
  }
}

enum TableColumnType { text, number, date, select }

extension TableColumnTypeExtension on TableColumnType {
  static TableColumnType fromJson(dynamic value) {
    final raw = value?.toString().toLowerCase() ?? 'text';
    return TableColumnType.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => TableColumnType.text,
    );
  }
}

/// Row data for a Table panel.
class TableRow {
  const TableRow({required this.id, required this.cells});

  final String id;
  final Map<String, dynamic> cells;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, ...cells};

  factory TableRow.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final nestedCells = json['cells'];
    final Map<String, dynamic> cells;
    if (nestedCells is Map) {
      cells = Map<String, dynamic>.from(
        nestedCells.map((k, v) => MapEntry(k.toString(), v)),
      );
    } else {
      cells = Map<String, dynamic>.from(json)..remove('id');
    }
    return TableRow(
      id: id.isEmpty ? TableDataHelper._nextId('r') : id,
      cells: cells,
    );
  }

  TableRow copyWith({String? id, Map<String, dynamic>? cells}) {
    return TableRow(id: id ?? this.id, cells: cells ?? this.cells);
  }
}

/// Helpers for converting Table panel state to/from PlutoGrid objects.
class TableDataHelper {
  const TableDataHelper._();

  static List<TableColumn> defaultColumns() => const <TableColumn>[
    TableColumn(id: 'month', title: 'Month', type: TableColumnType.text),
    TableColumn(id: 'sales', title: 'Sales', type: TableColumnType.number),
  ];

  static List<TableRow> defaultRows() => const <TableRow>[
    TableRow(id: 'r-1', cells: <String, dynamic>{'month': 'Jan', 'sales': 120}),
    TableRow(id: 'r-2', cells: <String, dynamic>{'month': 'Feb', 'sales': 190}),
    TableRow(id: 'r-3', cells: <String, dynamic>{'month': 'Mar', 'sales': 150}),
  ];

  static List<TableColumn> parseColumns(dynamic value) {
    if (value is! List) return defaultColumns();
    final parsed =
        value
            .whereType<Map<Object?, Object?>>()
            .map(
              (entry) => TableColumn.fromJson(
                Map<String, dynamic>.from(
                  entry.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ),
            )
            .where((column) => column.id.isNotEmpty)
            .toList();
    return parsed.isEmpty ? defaultColumns() : parsed;
  }

  static List<TableRow> parseRows(dynamic value) {
    if (value is! List) return defaultRows();
    final parsed =
        value
            .whereType<Map<Object?, Object?>>()
            .map(
              (entry) => TableRow.fromJson(
                Map<String, dynamic>.from(
                  entry.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ),
            )
            .toList();
    return parsed.isEmpty ? defaultRows() : parsed;
  }

  static List<Map<String, dynamic>> rowsToJson(List<TableRow> rows) =>
      rows.map((row) => row.toJson()).toList();

  static List<Map<String, dynamic>> columnsToJson(List<TableColumn> columns) =>
      columns.map((column) => column.toJson()).toList();

  static PlutoColumn toPlutoColumn(
    TableColumn column, {
    InlineSpan? titleSpan,
  }) {
    return PlutoColumn(
      title: column.title,
      field: column.id,
      type: _plutoType(column),
      titleSpan: titleSpan,
      enableEditingMode: true,
      enableContextMenu: false,
      enableFilterMenuItem: false,
      enableDropToResize: false,
    );
  }

  static PlutoColumnType _plutoType(TableColumn column) {
    switch (column.type) {
      case TableColumnType.number:
        return PlutoColumnType.number();
      case TableColumnType.date:
        return PlutoColumnType.date();
      case TableColumnType.select:
        return PlutoColumnType.select(column.options.isEmpty ? <String>[''] : column.options);
      case TableColumnType.text:
        return PlutoColumnType.text();
    }
  }

  static PlutoRow toPlutoRow(TableRow row, List<TableColumn> columns) {
    return PlutoRow(
      cells: {
        for (final column in columns)
          column.id: PlutoCell(value: row.cells[column.id]),
      },
    );
  }

  static String _nextId(String prefix) =>
      '$prefix-${DateTime.now().millisecondsSinceEpoch}';

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const <String>[];
  }

  static String effectiveId(Map<String, dynamic> state, String panelId) {
    final custom = (state['tableId'] as String?)?.trim() ?? '';
    return custom.isEmpty ? panelId : custom;
  }
}
