import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/chart/model/chart_models.dart';
import 'package:yoloit/features/table/model/table_models.dart' as table_models;

class ChartPanelContent extends StatelessWidget {
  const ChartPanelContent({
    super.key,
    required this.panel,
    required this.renderContext,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  void _setType(BuildContext context, ChartType type) {
    renderContext.onUpdateState(<String, dynamic>{
      ...panel.state,
      'type': type.name,
    });
  }

  void _setData(BuildContext context) {
    _showEditDialog(context);
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final dataTextController = TextEditingController(
      text: _prettyJson(panel.state['data']),
    );
    final xKeyController = TextEditingController(
      text: ChartDataHelper.xKeyFromState(panel.state),
    );
    final yKeyController = TextEditingController(
      text: ChartDataHelper.yKeyFromState(panel.state),
    );
    final groupKeyController = TextEditingController(
      text: ChartDataHelper.groupKeyFromState(panel.state) ?? '',
    );
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) {
        return _ChartDataDialog(
          panel: panel,
          xKeyController: xKeyController,
          yKeyController: yKeyController,
          groupKeyController: groupKeyController,
          dataTextController: dataTextController,
        );
      },
    );

    if (confirmed == null) return;

    final parsedData = _parseJson(dataTextController.text);
    if (parsedData == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Invalid JSON data')),
      );
      return;
    }

    renderContext.onUpdateState(<String, dynamic>{
      ...panel.state,
      'data': parsedData,
      'xKey': (confirmed['xKey'] as String).trim(),
      'yKey': (confirmed['yKey'] as String).trim(),
      'groupKey':
          (confirmed['groupKey'] as String).trim().isEmpty
              ? null
              : (confirmed['groupKey'] as String).trim(),
      'tablePanelId': confirmed['tablePanelId'] as String?,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = panel.state;
    final type = ChartDataHelper.typeFromState(state);
    final xKey = ChartDataHelper.xKeyFromState(state);
    final yKey = ChartDataHelper.yKeyFromState(state);
    final groupKey = ChartDataHelper.groupKeyFromState(state);
    final data = ChartDataHelper.resolveData(state, renderContext);
    final animated = ChartDataHelper.animatedFromState(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChartHeader(
          colors: colors,
          type: type,
          onTypeChanged: (value) => _setType(context, value),
          onEditData: () => _setData(context),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _buildChart(type, data, xKey, yKey, groupKey, colors, animated),
          ),
        ),
      ],
    );
  }

  Widget _buildChart(
    ChartType type,
    List<Map<String, dynamic>> data,
    String xKey,
    String yKey,
    String? groupKey,
    AppColorScheme colors,
    bool animated,
  ) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No data. Tap Edit to add data or link a table.',
          style: TextStyle(color: colors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }
    final chart = switch (type) {
      ChartType.line || ChartType.area => LineChart(
          ChartDataHelper.buildLineData(
            data: data,
            xKey: xKey,
            yKey: yKey,
            groupKey: groupKey,
            colors: colors,
            area: type == ChartType.area,
            animated: animated,
          ),
          duration: animated ? const Duration(milliseconds: 800) : Duration.zero,
        ),
      ChartType.bar => BarChart(
          ChartDataHelper.buildBarData(
            data: data,
            xKey: xKey,
            yKey: yKey,
            groupKey: groupKey,
            colors: colors,
            animated: animated,
          ),
          duration: animated ? const Duration(milliseconds: 800) : Duration.zero,
        ),
      ChartType.pie => LayoutBuilder(
          builder: (context, constraints) {
            final radius = math.min(constraints.maxWidth, constraints.maxHeight) * 0.38;
            return _HoverPieChart(
              data: data,
              xKey: xKey,
              yKey: yKey,
              colors: colors,
              animated: animated,
              radius: radius,
            );
          },
        ),
      ChartType.scatter => ScatterChart(
          ChartDataHelper.buildScatterData(
            data: data,
            xKey: xKey,
            yKey: yKey,
            groupKey: groupKey,
            colors: colors,
          ),
        ),
      ChartType.radar => RadarChart(
          ChartDataHelper.buildRadarData(
            data: data,
            xKey: xKey,
            yKey: yKey,
            colors: colors,
          ),
        ),
    };
    return RepaintBoundary(child: chart);
  }

  String _prettyJson(dynamic value) {
    if (value == null) return '';
    try {
      // ignore: avoid_dynamic_calls
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  List<Map<String, dynamic>>? _parseJson(String text) {
    try {
      final decoded = jsonDecode(text) as List<dynamic>;
      return
          decoded
              .whereType<Map<String, dynamic>>()
              .toList();
    } catch (_) {
      return null;
    }
  }
}

class _HoverPieChart extends StatefulWidget {
  const _HoverPieChart({
    required this.data,
    required this.xKey,
    required this.yKey,
    required this.colors,
    required this.animated,
    required this.radius,
  });

  final List<Map<String, dynamic>> data;
  final String xKey;
  final String yKey;
  final AppColorScheme colors;
  final bool animated;
  final double radius;

  @override
  State<_HoverPieChart> createState() => _HoverPieChartState();
}

class _HoverPieChartState extends State<_HoverPieChart> {
  int? _touchedIndex;

  void _onTouch(FlTouchEvent event, PieTouchResponse? response) {
    setState(() {
      if (event is FlPointerExitEvent) {
        _touchedIndex = null;
      } else {
        _touchedIndex = response?.touchedSection?.touchedSectionIndex;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PieChart(
      ChartDataHelper.buildPieData(
        data: widget.data,
        xKey: widget.xKey,
        yKey: widget.yKey,
        colors: widget.colors,
        animated: widget.animated,
        radius: widget.radius,
        touchedIndex: _touchedIndex,
        pieTouchData: PieTouchData(
          enabled: true,
          touchCallback: _onTouch,
        ),
      ),
      duration: Duration.zero,
    );
  }
}

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.colors,
    required this.type,
    required this.onTypeChanged,
    required this.onEditData,
  });

  final AppColorScheme colors;
  final ChartType type;
  final ValueChanged<ChartType> onTypeChanged;
  final VoidCallback onEditData;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Type:', style: TextStyle(fontSize: 11, color: colors.textMuted)),
          DropdownButtonHideUnderline(
            child: DropdownButton<ChartType>(
              value: type,
              isDense: true,
              items: [
                for (final t in ChartType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(
                      t.name[0].toUpperCase() + t.name.substring(1),
                      style: TextStyle(fontSize: 12, color: colors.textPrimary),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onTypeChanged(value);
              },
              dropdownColor: colors.surfaceElevated,
            ),
          ),
          TextButton.icon(
            onPressed: onEditData,
            icon: Icon(Icons.edit, size: 14, color: colors.textSecondary),
            label: Text(
              'Data',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartDataDialog extends StatefulWidget {
  const _ChartDataDialog({
    required this.panel,
    required this.xKeyController,
    required this.yKeyController,
    required this.groupKeyController,
    required this.dataTextController,
  });

  final BoardPanelInstance panel;
  final TextEditingController xKeyController;
  final TextEditingController yKeyController;
  final TextEditingController groupKeyController;
  final TextEditingController dataTextController;

  @override
  State<_ChartDataDialog> createState() => _ChartDataDialogState();
}

class _ChartDataDialogState extends State<_ChartDataDialog> {
  late String? _selectedTableId;

  @override
  void initState() {
    super.initState();
    _selectedTableId = ChartDataHelper.tablePanelIdFromState(widget.panel.state);
  }

  List<BoardPanelInstance> get _tablePanels {
    try {
      final board = context.read<BoardCubit>().state.activeBoard;
      return board?.panels.where((p) => p.type == 'board.table').toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  List<table_models.TableColumn> get _selectedTableColumns {
    final id = _selectedTableId;
    if (id == null) return const [];
    final panels = _tablePanels;
    for (final panel in panels) {
      if (table_models.TableDataHelper.effectiveId(panel.state, panel.id) ==
          id) {
        return table_models.TableDataHelper.parseColumns(panel.state['columns']);
      }
    }
    return const [];
  }

  void _onTableChanged(String? tableId) {
    setState(() {
      _selectedTableId = tableId;
      if (tableId != null) {
        final columns = _selectedTableColumns;
        table_models.TableColumn? firstOfType(table_models.TableColumnType type) {
          for (final column in columns) {
            if (column.type == type) return column;
          }
          return null;
        }

        final textColumn = firstOfType(table_models.TableColumnType.text);
        final numberColumn = firstOfType(table_models.TableColumnType.number);
        widget.xKeyController.text =
            textColumn?.id ?? (columns.isEmpty ? '' : columns.first.id);
        widget.yKeyController.text =
            numberColumn?.id ?? (columns.isEmpty ? '' : columns.first.id);
      }
    });
  }

  void _save() {
    Navigator.of(context).pop(<String, dynamic>{
      'xKey': widget.xKeyController.text,
      'yKey': widget.yKeyController.text,
      'groupKey': widget.groupKeyController.text,
      'tablePanelId': _selectedTableId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final tablePanels = _tablePanels;
    final noTables = tablePanels.isEmpty;
    final tableIds = tablePanels
        .map(
          (table) => table_models.TableDataHelper.effectiveId(
            table.state,
            table.id,
          ),
        )
        .toSet();
    final selectedIdMissing =
        _selectedTableId != null && !tableIds.contains(_selectedTableId);
    final selectedColumns = _selectedTableColumns;
    final selectedColumnIds = selectedColumns.map((c) => c.id).toList();

    return AlertDialog(
      title: const Text('Edit chart data'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedTableId == null) ...[
              TextField(
                controller: widget.xKeyController,
                decoration: const InputDecoration(labelText: 'X key'),
              ),
              TextField(
                controller: widget.yKeyController,
                decoration: const InputDecoration(labelText: 'Y key'),
              ),
            ] else ...[
              _ColumnKeyDropdown(
                label: 'X key',
                columns: selectedColumnIds,
                value: widget.xKeyController.text,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => widget.xKeyController.text = value);
                  }
                },
              ),
              _ColumnKeyDropdown(
                label: 'Y key',
                columns: selectedColumnIds,
                value: widget.yKeyController.text,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => widget.yKeyController.text = value);
                  }
                },
              ),
            ],
            TextField(
              controller: widget.groupKeyController,
              decoration: const InputDecoration(
                labelText: 'Group key (optional)',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _selectedTableId,
              decoration: const InputDecoration(
                labelText: 'Source table',
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Inline JSON data only'),
                ),
                if (selectedIdMissing)
                  DropdownMenuItem<String?>(
                    value: _selectedTableId,
                    child: Text(
                      'Missing table (${_selectedTableId!})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final table in tablePanels)
                  DropdownMenuItem<String?>(
                    value: table_models.TableDataHelper.effectiveId(
                      table.state,
                      table.id,
                    ),
                    child: Text(
                      table.title.isEmpty
                          ? table_models.TableDataHelper.effectiveId(
                            table.state,
                            table.id,
                          )
                          : '${table.title} (${table_models.TableDataHelper.effectiveId(table.state, table.id)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: noTables ? null : _onTableChanged,
            ),
            if (noTables)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No table panels on this board. Add a table first.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.dataTextController,
              decoration: const InputDecoration(
                labelText: 'Inline JSON data',
                alignLabelWithHint: true,
              ),
              maxLines: 8,
              minLines: 4,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ColumnKeyDropdown extends StatelessWidget {
  const _ColumnKeyDropdown({
    required this.label,
    required this.columns,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<String> columns;
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = columns.contains(value) ? value : null;
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          isDense: true,
          isExpanded: true,
          items: [
            for (final column in columns)
              DropdownMenuItem(value: column, child: Text(column)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
