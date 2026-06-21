import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/chart_plugin.dart';
import 'package:yoloit/features/chart/ui/chart_panel_content.dart';

BoardPanelRenderContext _noopContext() => BoardPanelRenderContext(
  isSelected: false,
  onFocus: () {},
  onDelete: () {},
  onUpdateState: (_) {},
  onShowEditor: () {},
);

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'chart-golden',
      type: ChartPlugin.kTypeId,
      title: 'Chart',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 560, height: 400),
      state: {...const ChartPlugin().initialState, ...state},
    );

Widget _chartShell(BoardPanelInstance panel) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: SizedBox(
        width: 560,
        height: 400,
        child: ChartPanelContent(
          panel: panel,
          renderContext: _noopContext(),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Golden tests — ChartPanelContent', () {
    testGoldens('line chart', (tester) async {
      await tester.pumpWidgetBuilder(
        _chartShell(_panel()),
        surfaceSize: const Size(560, 400),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'chart_panel_line');
    });

    testGoldens('bar chart', (tester) async {
      await tester.pumpWidgetBuilder(
        _chartShell(_panel(state: {'type': 'bar'})),
        surfaceSize: const Size(560, 400),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'chart_panel_bar');
    });

    testGoldens('pie chart', (tester) async {
      await tester.pumpWidgetBuilder(
        _chartShell(_panel(state: {'type': 'pie'})),
        surfaceSize: const Size(560, 400),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'chart_panel_pie');
    });
  });
}
