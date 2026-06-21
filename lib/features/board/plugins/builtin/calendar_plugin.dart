import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/calendar/ui/calendar_panel_content.dart';

final _calendarDefaultColors = AppColorScheme.fromAccent(Colors.blue);

class CalendarPlugin extends BoardPanelPlugin {
  const CalendarPlugin();

  static const String kTypeId = 'board.calendar';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Calendar';

  @override
  IconData get icon => Icons.calendar_month_outlined;

  @override
  Color get accentColor => _calendarDefaultColors.accentBlue;

  @override
  Size get defaultSize => const Size(720, 520);

  @override
  Map<String, dynamic> get initialState => const {
    'view': 'month',
    'focusedDate': null,
    'eventCount': 0,
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return CalendarPanelContent(
      panel: panel,
      renderContext: renderContext,
    );
  }
}
