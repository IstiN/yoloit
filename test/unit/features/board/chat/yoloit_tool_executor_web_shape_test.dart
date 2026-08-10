import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import '../../../../helpers/fake_board_cubit.dart';

/// Coverage-focused tests for the shape:set handler in
/// `yoloit_tool_executor_web.dart` and the chart table-panel id resolution
/// (`_resolveTablePanelId`) in `yoloit_tool_executor_web_handlers.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardPanelInstance fakePanel(
    String id,
    String type,
    String title, {
    Map<String, dynamic> state = const {},
  }) {
    return BoardPanelInstance(
      id: id,
      type: type,
      title: title,
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      state: state,
    );
  }

  Map<String, dynamic> decode(String result) =>
      jsonDecode(result) as Map<String, dynamic>;

  group('YoloitWebToolExecutor shape:set', () {
    late FakeBoardCubit cubit;
    late YoloitWebToolExecutor executor;

    setUp(() {
      cubit = FakeBoardCubit();
      executor = YoloitWebToolExecutor();
    });

    Future<String> invoke(String functionName, Map<String, Object?> args) {
      return executor.invoke(
        functionName,
        args,
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
    }

    test('updates text, fill, stroke and stroke width', () async {
      cubit.addFakePanel(fakePanel('p-ss1', 'board.shape', 'ShapeA'));

      final result = await invoke('yoloit_shape_set', {
        'panel': 'ShapeA',
        'text': 'Hello',
        'fill': '#FF0000',
        'stroke': '#00FF00',
        'stroke_width': 3,
      });
      expect(decode(result)['ok'], isTrue);

      final state = cubit.updatedPanels['p-ss1']?.state;
      expect(state?['text'], 'Hello');
      expect(state?['fillColor'], '#ff0000');
      expect(state?['strokeColor'], '#00ff00');
      expect(state?['strokeWidth'], 3);
    });

    test('accepts the tx and sw aliases', () async {
      cubit.addFakePanel(fakePanel('p-ss2', 'board.shape', 'ShapeB'));

      final result = await invoke('yoloit_shape_set', {
        'panel': 'ShapeB',
        'tx': 'Alias text',
        'sw': 2,
      });
      expect(decode(result)['ok'], isTrue);

      final state = cubit.updatedPanels['p-ss2']?.state;
      expect(state?['text'], 'Alias text');
      expect(state?['strokeWidth'], 2);
      expect(state?.containsKey('fillColor'), isFalse);
    });

    test('returns error when no properties are provided', () async {
      cubit.addFakePanel(fakePanel('p-ss3', 'board.shape', 'ShapeC'));

      final result = await invoke('yoloit_shape_set', {'panel': 'ShapeC'});
      final decoded = decode(result);
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('No properties to update'));
      expect(cubit.updatedPanels.containsKey('p-ss3'), isFalse);
    });

    test('returns error when the shape panel does not exist', () async {
      final result = await invoke('yoloit_shape_set', {
        'panel': 'Missing',
        'text': 'Hi',
      });
      final decoded = decode(result);
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Shape panel not found'));
    });
  });

  group('YoloitWebToolExecutor chart table resolution', () {
    late FakeBoardCubit cubit;
    late YoloitWebToolExecutor executor;

    setUp(() {
      cubit = FakeBoardCubit();
      executor = YoloitWebToolExecutor();
    });

    Future<String> invoke(String functionName, Map<String, Object?> args) {
      return executor.invoke(
        functionName,
        args,
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
    }

    test('chart:link-table resolves a table panel by id', () async {
      cubit.addFakePanel(fakePanel('p-tr-t', 'board.table', 'DataT'));
      cubit.addFakePanel(fakePanel('p-tr-c', 'board.chart', 'ChartC'));

      final result = await invoke('yoloit_chart_link_table', {
        'panel': 'ChartC',
        'table_panel': 'p-tr-t',
      });
      expect(decode(result)['ok'], isTrue);
      expect(cubit.updatedPanels['p-tr-c']?.state['tablePanelId'], 'p-tr-t');
    });

    test('chart:link-table keeps the hint when it matches a non-table panel',
        () async {
      cubit.addFakePanel(fakePanel('p-tr-n', 'board.note.markdown', 'JustNote'));
      cubit.addFakePanel(fakePanel('p-tr-c2', 'board.chart', 'ChartN'));

      final result = await invoke('yoloit_chart_link_table', {
        'panel': 'ChartN',
        'table_panel': 'JustNote',
      });
      expect(decode(result)['ok'], isTrue);
      expect(
        cubit.updatedPanels['p-tr-c2']?.state['tablePanelId'],
        'JustNote',
      );
    });

    test('chart:link-table keeps an unknown hint as-is', () async {
      cubit.addFakePanel(fakePanel('p-tr-c3', 'board.chart', 'ChartU'));

      final result = await invoke('yoloit_chart_link_table', {
        'panel': 'ChartU',
        'table_panel': 'missing-table',
      });
      expect(decode(result)['ok'], isTrue);
      expect(
        cubit.updatedPanels['p-tr-c3']?.state['tablePanelId'],
        'missing-table',
      );
    });
  });
}
