import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/chart/ui/chart_panel_content.dart';

void main() {
  testWidgets(
    'chart data dialog calls onUpdateState with edited data when Save is pressed',
    (tester) async {
      Map<String, dynamic>? updatedState;
      final panel = BoardPanelInstance(
        id: 'panel-chart-1',
        type: 'board.chart',
        title: 'Sales Chart',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 560, height: 400),
        state: <String, dynamic>{
          'type': 'line',
          'data': [
            {'month': 'Jan', 'sales': 120},
            {'month': 'Feb', 'sales': 190},
          ],
          'xKey': 'month',
          'yKey': 'sales',
          'groupKey': null,
          'tablePanelId': null,
          'animated': true,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [AppColorScheme.fromAccent(Colors.blue)],
          ),
          home: Scaffold(
            body: ChartPanelContent(
              panel: panel,
              renderContext: _FakeRenderContext(
                onUpdateState: (state) => updatedState = state,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Data'));
      await tester.pumpAndSettle();

      final dataField = find.widgetWithText(TextField, 'Inline JSON data');
      expect(dataField, findsOneWidget);

      await tester.enterText(dataField, '[{"month":"Jan","sales":200}]');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(updatedState, isNotNull);
      expect(updatedState!['data'], isA<List<Object?>>());
      final data = updatedState!['data'] as List<Object?>;
      expect(data.length, 1);
      expect((data.first as Map<String, dynamic>)['sales'], 200);
    },
  );

  testWidgets(
    'chart data dialog stays open and shows error when JSON is invalid',
    (tester) async {
      Map<String, dynamic>? updatedState;
      final panel = BoardPanelInstance(
        id: 'panel-chart-2',
        type: 'board.chart',
        title: 'Sales Chart',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 560, height: 400),
        state: <String, dynamic>{
          'type': 'line',
          'data': [
            {'month': 'Jan', 'sales': 120},
          ],
          'xKey': 'month',
          'yKey': 'sales',
          'groupKey': null,
          'tablePanelId': null,
          'animated': true,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [AppColorScheme.fromAccent(Colors.blue)],
          ),
          home: Scaffold(
            body: ChartPanelContent(
              panel: panel,
              renderContext: _FakeRenderContext(
                onUpdateState: (state) => updatedState = state,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Data'));
      await tester.pumpAndSettle();

      final dataField = find.widgetWithText(TextField, 'Inline JSON data');
      await tester.enterText(dataField, 'not-json');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(updatedState, isNull);
      expect(find.text('Invalid JSON data'), findsOneWidget);
    },
  );
}

class _FakeRenderContext extends Fake implements BoardPanelRenderContext {
  _FakeRenderContext({required this.onUpdateState});

  @override
  final void Function(Map<String, dynamic> state) onUpdateState;
}
