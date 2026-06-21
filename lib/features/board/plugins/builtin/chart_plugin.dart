import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/chart/model/chart_models.dart';
import 'package:yoloit/features/chart/ui/chart_panel_content.dart';

final _chartDefaultColors = AppColorScheme.fromAccent(Colors.blue);

class ChartPlugin extends BoardPanelPlugin {
  const ChartPlugin();

  static const String kTypeId = 'board.chart';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Chart';

  @override
  IconData get icon => Icons.insert_chart_outlined;

  @override
  Color get accentColor => _chartDefaultColors.accentBlue;

  @override
  Size get defaultSize => const Size(560, 400);

  @override
  Map<String, dynamic> get initialState => <String, dynamic>{
    'type': 'line',
    'data': ChartDataHelper.defaultData(),
    'xKey': 'month',
    'yKey': 'sales',
    'groupKey': null,
    'tablePanelId': null,
    'animated': true,
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return ChartPanelContent(panel: panel, renderContext: renderContext);
  }
}
