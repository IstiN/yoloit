import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/table/model/table_models.dart' as table_models;

class TablePanelContent extends StatefulWidget {
  const TablePanelContent({
    super.key,
    required this.panel,
    required this.renderContext,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<TablePanelContent> createState() => _TablePanelContentState();
}

class _TablePanelContentState extends State<TablePanelContent> {
  PlutoGridStateManager? _stateManager;
  AppColorScheme? _colors;

  List<table_models.TableColumn> get _columns =>
      table_models.TableDataHelper.parseColumns(widget.panel.state['columns']);

  List<table_models.TableRow> get _rows =>
      table_models.TableDataHelper.parseRows(widget.panel.state['rows']);

  @override
  void didUpdateWidget(covariant TablePanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_stateManager == null) return;
    final oldColumns = _parseColumns(oldWidget.panel.state['columns']);
    final newColumns = _parseColumns(widget.panel.state['columns']);
    // When the column set changes the grid is recreated via its key, so the
    // old state manager must not be touched.
    if (oldColumns.length != newColumns.length) return;
    if (oldWidget.panel.state['columns'] != widget.panel.state['columns'] ||
        oldWidget.panel.state['rows'] != widget.panel.state['rows']) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncStateManager());
    }
  }

  List<table_models.TableColumn> _parseColumns(dynamic value) =>
      table_models.TableDataHelper.parseColumns(value);

  void _syncStateManager() {
    final manager = _stateManager;
    if (manager == null) return;

    final columns = _columns;
    final rows = _rows;
    final desiredColumns = columns
        .map(
          (column) => table_models.TableDataHelper.toPlutoColumn(
            column,
            titleSpan: _buildTitleSpan(column),
          ),
        )
        .toList();
    final desiredRows =
        rows.map((row) => table_models.TableDataHelper.toPlutoRow(row, columns)).toList();

    final currentColumns = manager.columns;
    if (!_columnListsEqual(currentColumns, desiredColumns)) {
      manager.removeColumns(currentColumns);
      manager.insertColumns(0, desiredColumns);
    } else {
      var titleChanged = false;
      for (var i = 0; i < currentColumns.length; i++) {
        if (currentColumns[i].title != desiredColumns[i].title) {
          titleChanged = true;
          break;
        }
      }
      if (titleChanged) {
        manager.removeColumns(currentColumns);
        manager.insertColumns(0, desiredColumns);
      }
    }

    final currentRows = manager.rows;
    if (!_rowListsEqual(currentRows, desiredRows)) {
      manager.removeAllRows();
      manager.appendRows(desiredRows);
    }
  }

  static bool _columnListsEqual(
    List<PlutoColumn> a,
    List<PlutoColumn> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].field != b[i].field) return false;
    }
    return true;
  }

  static bool _rowListsEqual(
    List<PlutoRow> a,
    List<PlutoRow> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key) return false;
    }
    return true;
  }

  void _updateState({
    List<table_models.TableColumn>? columns,
    List<table_models.TableRow>? rows,
    String? tableId,
  }) {
    widget.renderContext.onUpdateState(<String, dynamic>{
      ...widget.panel.state,
      if (columns != null)
        'columns': table_models.TableDataHelper.columnsToJson(columns),
      if (rows != null) 'rows': table_models.TableDataHelper.rowsToJson(rows),
      if (tableId != null) 'tableId': tableId,
    });
  }

  void _onCellChanged(PlutoGridOnChangedEvent event) {
    final rows = _rows;
    final rowIndex = event.rowIdx;
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    final field = event.column.field;
    final updatedRows = List<table_models.TableRow>.from(rows);
    updatedRows[rowIndex] = updatedRows[rowIndex].copyWith(
      cells: <String, dynamic>{...updatedRows[rowIndex].cells, field: event.value},
    );
    _updateState(rows: updatedRows);
  }

  void _addRow() {
    final columns = _columns;
    final cells = <String, dynamic>{
      for (final column in columns)
        column.id: column.type == table_models.TableColumnType.number ? 0 : '',
    };
    final newRow = table_models.TableRow(
      id: 'r-${DateTime.now().millisecondsSinceEpoch}',
      cells: cells,
    );
    _updateState(rows: [..._rows, newRow]);
  }

  void _removeLastRow() {
    final rows = _rows;
    if (rows.isEmpty) return;
    _updateState(rows: rows.sublist(0, rows.length - 1));
  }

  void _addColumn() {
    final columns = _columns;
    final id = 'col-${columns.length + 1}';
    _updateState(
      columns: [...columns, table_models.TableColumn(id: id, title: id)],
      rows:
          _rows
              .map(
                (row) => row.copyWith(
                  cells: <String, dynamic>{...row.cells, id: ''},
                ),
              )
              .toList(),
    );
  }

  void _clearRows() {
    _updateState(rows: const <table_models.TableRow>[]);
  }

  void _showColumnMenu(BuildContext anchorContext) {
    final columns = _columns;
    final box = anchorContext.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + (box?.size.height ?? 0),
        pos.dx + (box?.size.width ?? 0),
        pos.dy + (box?.size.height ?? 0) + 100,
      ),
      items: [
        for (var i = 0; i < columns.length; i++)
          PopupMenuItem<void>(
            child: Text(columns[i].title),
            onTap: () => _removeColumn(i),
          ),
      ],
    );
  }

  void _removeColumn(int index) {
    final columns = _columns;
    if (index < 0 || index >= columns.length) return;
    final removedId = columns[index].id;
    final newColumns = List<table_models.TableColumn>.from(columns)..removeAt(index);
    final newRows =
        _rows
            .map(
              (row) => row.copyWith(
                cells: Map<String, dynamic>.from(row.cells)..remove(removedId),
              ),
            )
            .toList();
    _updateState(columns: newColumns, rows: newRows);
  }

  InlineSpan _buildTitleSpan(table_models.TableColumn column) {
    final colors = _colors;
    return WidgetSpan(
      child: GestureDetector(
        onDoubleTap: () => _showRenameColumnDialog(column),
        child: Text(
          column.title,
          style: TextStyle(
            color: colors?.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _showRenameColumnDialog(table_models.TableColumn column) async {
    final controller = TextEditingController(text: column.title);
    final newTitle = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename column'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Column name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == column.title) return;
    final updatedColumns =
        _columns
            .map(
              (c) => c.id == column.id ? c.copyWith(title: newTitle) : c,
            )
            .toList();
    _updateState(columns: updatedColumns);
  }

  Future<void> _showEditTableIdDialog() async {
    final effectiveId = table_models.TableDataHelper.effectiveId(
      widget.panel.state,
      widget.panel.id,
    );
    final controller = TextEditingController(text: effectiveId);
    final newId = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Table ID'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Custom table ID',
              helperText: 'Leave empty to use the panel ID',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newId == null || newId == effectiveId) return;
    _updateState(tableId: newId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    _colors = colors;
    final columns = _columns;
    final plutoColumns = columns
        .map(
          (column) => table_models.TableDataHelper.toPlutoColumn(
            column,
            titleSpan: _buildTitleSpan(column),
          ),
        )
        .toList();
    final plutoRows =
        _rows
            .map((row) => table_models.TableDataHelper.toPlutoRow(row, columns))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          colors: colors,
          tableId: table_models.TableDataHelper.effectiveId(
            widget.panel.state,
            widget.panel.id,
          ),
          onCopyTableId: () {
            Clipboard.setData(
              ClipboardData(
                text: table_models.TableDataHelper.effectiveId(
                  widget.panel.state,
                  widget.panel.id,
                ),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Table ID copied to clipboard')),
            );
          },
          onEditTableId: _showEditTableIdDialog,
          onAddRow: _addRow,
          onRemoveRow: _rows.isEmpty ? null : _removeLastRow,
          onAddColumn: _addColumn,
          onRemoveColumn: columns.isEmpty ? null : (ctx) => _showColumnMenu(ctx),
          onClear: _rows.isEmpty ? null : _clearRows,
        ),
        const Divider(height: 1),
        Expanded(
          child: plutoColumns.isEmpty
              ? Center(
                  child: Text(
                    'No columns. Tap +Column to start.',
                    style: TextStyle(color: colors.textMuted),
                  ),
                )
              : PlutoGrid(
                  key: ValueKey<int>(columns.length),
                  columns: plutoColumns,
                  rows: plutoRows,
                  onChanged: _onCellChanged,
                  onLoaded: (event) {
                    _stateManager = event.stateManager;
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _syncStateManager());
                  },
                  mode: PlutoGridMode.normal,
                  configuration: PlutoGridConfiguration(
                    style: PlutoGridStyleConfig.dark(
                      gridBackgroundColor: colors.surface,
                      rowColor: colors.surface,
                      checkedColor: colors.surfaceHighlight,
                      cellColorInReadOnlyState: colors.surface,
                      cellColorInEditState: colors.surfaceElevated,
                      defaultCellPadding: const EdgeInsets.symmetric(horizontal: 8),
                      borderColor: colors.border,
                      activatedBorderColor: colors.primary,
                      activatedColor: colors.primary.withValues(alpha: 0.12),
                      iconColor: colors.textSecondary,
                      disabledIconColor: colors.textMuted,
                      menuBackgroundColor: colors.surfaceElevated,
                      columnTextStyle: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      cellTextStyle: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.colors,
    required this.tableId,
    required this.onCopyTableId,
    required this.onEditTableId,
    required this.onAddRow,
    required this.onRemoveRow,
    required this.onAddColumn,
    required this.onRemoveColumn,
    required this.onClear,
  });

  final AppColorScheme colors;
  final String tableId;
  final VoidCallback onCopyTableId;
  final VoidCallback onEditTableId;
  final VoidCallback onAddRow;
  final VoidCallback? onRemoveRow;
  final VoidCallback onAddColumn;
  final ValueChanged<BuildContext>? onRemoveColumn;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ToolbarButton(
            icon: Icons.add,
            label: 'Row',
            onPressed: onAddRow,
            colors: colors,
          ),
          _ToolbarButton(
            icon: Icons.remove,
            label: 'Row',
            onPressed: onRemoveRow,
            colors: colors,
          ),
          _ToolbarButton(
            icon: Icons.view_column,
            label: 'Col',
            onPressed: onAddColumn,
            colors: colors,
          ),
          Builder(
            builder: (context) {
              final onRemove = onRemoveColumn;
              return _ToolbarButton(
                icon: Icons.delete_outline,
                label: 'Col',
                onPressed:
                    onRemove == null ? null : () => onRemove(context),
                colors: colors,
              );
            },
          ),
          _ToolbarButton(
            icon: Icons.clear_all,
            label: 'Clear',
            onPressed: onClear,
            colors: colors,
          ),
          _PanelIdChip(
            id: tableId,
            onCopy: onCopyTableId,
            onEdit: onEditTableId,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _PanelIdChip extends StatelessWidget {
  const _PanelIdChip({
    required this.id,
    required this.onCopy,
    required this.onEdit,
    required this.colors,
  });

  final String id;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Table ID: $id\nTap to copy, tap ✎ to edit',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: onCopy,
            icon: Icon(Icons.fingerprint, size: 12, color: colors.textMuted),
            label: Text(
              id.length > 14 ? '${id.substring(0, 14)}...' : id,
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.edit, size: 12, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: colors.textSecondary),
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: colors.textSecondary),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
