import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/table/model/table_models.dart' as table_models;
import 'package:yoloit/ui/components/buttons/toolbar_button.dart';
import 'package:yoloit/ui/components/chips/panel_id_chip.dart';

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

  Future<String?> _promptText({
    required String title,
    required String label,
    required String initialValue,
    String? helper,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              helperText: helper,
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
    return result;
  }

  Future<void> _showRenameColumnDialog(table_models.TableColumn column) async {
    final newTitle = await _promptText(
      title: 'Rename column',
      label: 'Column name',
      initialValue: column.title,
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
    final newId = await _promptText(
      title: 'Table ID',
      label: 'Custom table ID',
      helper: 'Leave empty to use the panel ID',
      initialValue: effectiveId,
    );
    if (newId == null || newId == effectiveId) return;
    _updateState(tableId: newId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    _colors = colors;
    final columns = _columns;
    final readOnly = widget.renderContext.readOnly;
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
          tableId: table_models.TableDataHelper.effectiveId(
            widget.panel.state,
            widget.panel.id,
          ),
          readOnly: readOnly,
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
          onEditTableId: readOnly ? null : _showEditTableIdDialog,
          onAddRow: readOnly ? null : _addRow,
          onRemoveRow: readOnly || _rows.isEmpty ? null : _removeLastRow,
          onAddColumn: readOnly ? null : _addColumn,
          onRemoveColumn:
              readOnly || columns.isEmpty ? null : (ctx) => _showColumnMenu(ctx),
          onClear: readOnly || _rows.isEmpty ? null : _clearRows,
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
                  onChanged: readOnly ? null : _onCellChanged,
                  onLoaded: (event) {
                    _stateManager = event.stateManager;
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _syncStateManager());
                  },
                  mode:
                      readOnly ? PlutoGridMode.readOnly : PlutoGridMode.normal,
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
    required this.tableId,
    required this.onCopyTableId,
    this.onEditTableId,
    this.onAddRow,
    this.onRemoveRow,
    this.onAddColumn,
    this.onRemoveColumn,
    this.onClear,
    this.readOnly = false,
  });

  final String tableId;
  final VoidCallback onCopyTableId;
  final VoidCallback? onEditTableId;
  final VoidCallback? onAddRow;
  final VoidCallback? onRemoveRow;
  final VoidCallback? onAddColumn;
  final ValueChanged<BuildContext>? onRemoveColumn;
  final VoidCallback? onClear;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ToolbarButton(
            icon: Icons.add,
            label: 'Row',
            onPressed: onAddRow,
          ),
          ToolbarButton(
            icon: Icons.remove,
            label: 'Row',
            onPressed: onRemoveRow,
          ),
          ToolbarButton(
            icon: Icons.view_column,
            label: 'Col',
            onPressed: onAddColumn,
          ),
          Builder(
            builder: (context) {
              final onRemove = onRemoveColumn;
              return ToolbarButton(
                icon: Icons.delete_outline,
                label: 'Col',
                onPressed:
                    onRemove == null ? null : () => onRemove(context),
              );
            },
          ),
          ToolbarButton(
            icon: Icons.clear_all,
            label: 'Clear',
            onPressed: onClear,
          ),
          PanelIdChip(
            id: tableId,
            label: 'Table ID',
            onCopy: onCopyTableId,
            onEdit: onEditTableId,
          ),
        ],
      ),
    );
  }
}
