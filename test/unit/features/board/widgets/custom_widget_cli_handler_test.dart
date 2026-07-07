// covers: board.widget.custom (CLI handler)
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_base.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_content.dart';

void main() {
  group('CustomWidgetCliHandler', () {
    const handler = CustomWidgetCliHandler();

    BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
        BoardPanelInstance(
          id: 'p1',
          type: CustomWidgetPluginBase.kTypeId,
          title: 'Widget',
          bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
          state: state,
        );

    test('metadata', () {
      expect(handler.typeId, CustomWidgetPluginBase.kTypeId);
      expect(handler.supportedActions, ['setState', 'info', 'execute', 'snapshot']);
      expect(handler.actionHelp.keys, contains('execute'));
      expect(handler.getContent(_panel(state: {'widgetId': 'w1'})), {
        'widgetId': 'w1',
      });
    });

    test('setState merges state', () async {
      final result = await handler.handleAction(
        'setState',
        {'state': {'widgetId': 'w2', 'foo': 'bar'}},
        _panel(),
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate, {'widgetId': 'w2', 'foo': 'bar'});
    });

    test('setState without state returns error', () async {
      final result = await handler.handleAction('setState', {}, _panel());
      expect(result.ok, isFalse);
    });

    test('info returns empty widget id when unset', () async {
      final result = await handler.handleAction('info', {}, _panel());
      expect(result.ok, isTrue);
      expect(result.data?['widgetId'], '');
      expect(result.data?['manifest'], isNull);
    });

    test('snapshot returns error when no tree is available', () async {
      final result = await handler.handleAction(
        'snapshot',
        {},
        _panel(state: {'widgetId': 'w1'}),
      );
      expect(result.ok, isFalse);
    });

    test('execute returns error when actionId is missing', () async {
      final result = await handler.handleAction(
        'execute',
        {},
        _panel(state: {'widgetId': 'w1'}),
      );
      expect(result.ok, isFalse);
    });

    test('execute returns error when engine is not running', () async {
      final result = await handler.handleAction(
        'execute',
        {'actionId': 'tap'},
        _panel(state: {'widgetId': 'w1'}),
      );
      expect(result.ok, isFalse);
    });
  });
}
