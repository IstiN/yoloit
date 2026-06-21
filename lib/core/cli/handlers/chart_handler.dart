import 'dart:convert';

import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/chart/model/chart_models.dart';
import 'package:yoloit/features/table/model/table_models.dart';

/// CLI handler for Chart panels (`board.chart`).
class ChartCliHandler extends PanelCliHandler {
  const ChartCliHandler();

  @override
  String get typeId => 'board.chart';

  @override
  List<String> get supportedActions => [
    'get',
    'set-data',
    'set-type',
    'set-options',
    'link-table',
    'unlink-table',
    'refresh',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return <String, dynamic>{
      'type': panel.state['type'] ?? 'line',
      'data': panel.state['data'] ?? ChartDataHelper.defaultData(),
      'xKey': panel.state['xKey'] ?? 'month',
      'yKey': panel.state['yKey'] ?? 'sales',
      'groupKey': panel.state['groupKey'],
      'tablePanelId': panel.state['tablePanelId'],
      'animated': panel.state['animated'] ?? true,
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
      case 'set-data':
        return _handleSetData(args, panel);
      case 'set-type':
        return _handleSetType(args, panel);
      case 'set-options':
        return _handleSetOptions(args, panel);
      case 'link-table':
        return _handleLinkTable(args, panel);
      case 'unlink-table':
        return _handleUnlinkTable(panel);
      case 'refresh':
        return _handleRefresh(args, panel);
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  CliActionResult _handleSetData(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final data = _parseData(args['data'] ?? args['json']);
    if (data == null) {
      return const CliActionResult(
        ok: false,
        message: 'Missing or invalid "data" (must be a JSON array)',
      );
    }
    return CliActionResult(
      message: 'Chart data updated',
      stateUpdate: <String, dynamic>{
        ...panel.state,
        'data': data,
      },
    );
  }

  CliActionResult _handleSetType(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final type = _string(args['type']);
    final allowed = ChartType.values.map((t) => t.name).toSet();
    if (type == null || !allowed.contains(type)) {
      return CliActionResult(
        ok: false,
        message: 'Invalid type. Allowed: ${allowed.join(', ')}',
      );
    }
    return CliActionResult(
      message: 'Chart type set to $type',
      stateUpdate: <String, dynamic>{...panel.state, 'type': type},
    );
  }

  CliActionResult _handleSetOptions(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final next = Map<String, dynamic>.from(panel.state);
    final xKey = _string(args['xKey'] ?? args['x']);
    final yKey = _string(args['yKey'] ?? args['y']);
    final groupKey = _string(args['groupKey'] ?? args['group']);
    final animated = args['animated'];
    if (xKey != null) next['xKey'] = xKey;
    if (yKey != null) next['yKey'] = yKey;
    if (groupKey != null) next['groupKey'] = groupKey.isEmpty ? null : groupKey;
    if (animated is bool) next['animated'] = animated;
    return CliActionResult(
      message: 'Chart options updated',
      stateUpdate: next,
    );
  }

  CliActionResult _handleLinkTable(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final tablePanelId = _string(args['tablePanelId'] ?? args['table']);
    if (tablePanelId == null || tablePanelId.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: tablePanelId',
      );
    }
    return CliActionResult(
      message: 'Linked to table panel $tablePanelId',
      stateUpdate: <String, dynamic>{
        ...panel.state,
        'tablePanelId': tablePanelId,
      },
    );
  }

  CliActionResult _handleUnlinkTable(BoardPanelInstance panel) {
    return CliActionResult(
      message: 'Table link removed',
      stateUpdate: <String, dynamic>{
        ...panel.state,
        'tablePanelId': null,
      },
    );
  }

  CliActionResult _handleRefresh(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final tablePanelId =
        _string(args['tablePanelId'] ?? args['table']) ??
        ChartDataHelper.tablePanelIdFromState(panel.state);
    if (tablePanelId == null || tablePanelId.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'No table panel linked. Use link-table first.',
      );
    }
    final rawPanels = args['_currentBoardPanels'];
    BoardPanelInstance? targetPanel;
    if (rawPanels is List) {
      targetPanel =
          rawPanels
              .whereType<Map<Object?, Object?>>()
              .map(
                (entry) => BoardPanelInstance.fromJson(
                  Map<String, dynamic>.from(
                    entry.map((k, v) => MapEntry(k.toString(), v)),
                  ),
                ),
              )
              .firstWhereOrNull(
                (panel) =>
                    panel.id == tablePanelId ||
                    TableDataHelper.effectiveId(panel.state, panel.id) ==
                        tablePanelId,
              );
    }
    if (targetPanel == null) {
      return CliActionResult(
        ok: false,
        message: 'Table panel not found: $tablePanelId',
      );
    }
    if (targetPanel.type != 'board.table') {
      return CliActionResult(
        ok: false,
        message: 'Panel $tablePanelId is not a table',
      );
    }
    final rows = TableDataHelper.parseRows(targetPanel.state['rows']);
    final data = rows.map((row) => row.cells).toList();
    return CliActionResult(
      message: 'Chart refreshed from table $tablePanelId',
      stateUpdate: <String, dynamic>{
        ...panel.state,
        'data': data,
        'tablePanelId': tablePanelId,
      },
    );
  }

  List<Map<String, dynamic>>? _parseData(dynamic value) {
    if (value == null) return null;
    List<dynamic> list;
    if (value is List) {
      list = value;
    } else if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is! List) return null;
        list = decoded;
      } catch (_) {
        return null;
      }
    } else {
      return null;
    }
    return
        list
            .whereType<Map<Object?, Object?>>()
            .map(
              (entry) => Map<String, dynamic>.from(
                entry.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
  }

  String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  Map<String, CliActionHelp> get actionHelp => <String, CliActionHelp>{
    'get': const CliActionHelp(description: 'Get chart configuration and data'),
    'set-data': const CliActionHelp(
      description: 'Set inline chart data (JSON array)',
      params: {'data': 'JSON array of objects'},
    ),
    'set-type': const CliActionHelp(
      description: 'Change chart type',
      params: {
        'type': 'line | bar | pie | scatter | radar | area',
      },
    ),
    'set-options': const CliActionHelp(
      description: 'Update x/y keys, group key, animation',
      params: {
        'xKey': 'Field name for X/category',
        'yKey': 'Field name for value',
        'groupKey': 'Optional field for multi-series grouping',
        'animated': 'true/false',
      },
    ),
    'link-table': const CliActionHelp(
      description: 'Link chart data to a Table panel',
      params: {
        'tablePanelId': 'Table panel id or custom tableId',
      },
    ),
    'unlink-table': const CliActionHelp(
      description: 'Remove Table panel link',
    ),
    'refresh': const CliActionHelp(
      description: 'Snapshot linked table data into chart state',
      params: {'tablePanelId': 'Optional table panel id'},
    ),
  };
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
