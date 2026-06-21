import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/table/model/table_models.dart';
import 'package:yoloit/features/table/ui/table_panel_content.dart';

final _tableDefaultColors = AppColorScheme.fromAccent(Colors.green);

class TablePlugin extends BoardPanelPlugin {
  const TablePlugin();

  static const String kTypeId = 'board.table';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Table';

  @override
  IconData get icon => Icons.table_chart_outlined;

  @override
  Color get accentColor => _tableDefaultColors.accentGreen;

  @override
  Size get defaultSize => const Size(520, 360);

  @override
  Map<String, dynamic> get initialState => <String, dynamic>{
    'columns': TableDataHelper.columnsToJson(TableDataHelper.defaultColumns()),
    'rows': TableDataHelper.rowsToJson(TableDataHelper.defaultRows()),
    'tableId': '',
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return TablePanelContent(panel: panel, renderContext: renderContext);
  }
}
