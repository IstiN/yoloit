// covers-write: board.ui
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/ui_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin.dart';

void main() {
  const handler = UiViewCliHandler();

  BoardPanelInstance newPanel({Map<String, dynamic> state = const {}}) =>
      BoardPanelInstance(
        id: 'panel-ui',
        type: UiViewPlugin.kTypeId,
        title: 'Card',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 320),
        state: state,
      );

  group('UiViewCliHandler', () {
    test('typeId is board.ui', () {
      expect(handler.typeId, UiViewPlugin.kTypeId);
    });

    test('get returns tree and text', () async {
      final panel = newPanel(
        state: <String, dynamic>{
          'tree': <String, dynamic>{
            'type': 'text',
            'data': 'Hello',
          },
        },
      );
      final result = await handler.handleAction('get', {}, panel);
      expect(result.ok, isTrue);
      expect(result.data?['tree'], isA<Map<String, dynamic>>());
      expect(result.data?['text'], contains('Hello'));
    });

    test('render updates tree in state', () async {
      final panel = newPanel();
      final tree = <String, dynamic>{
        'type': 'column',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'data': 'Grodno'},
        ],
      };
      final result = await handler.handleAction(
        'render',
        <String, dynamic>{'tree': tree},
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate?['tree'], tree);
    });

    test('render rejects invalid tree', () async {
      final panel = newPanel();
      final result = await handler.handleAction(
        'render',
        <String, dynamic>{'tree': 'not-json'},
        panel,
      );
      expect(result.ok, isFalse);
    });

    test('parseUiTree accepts JSON string', () {
      final parsed = parseUiTree('{"type":"text","data":"Hi"}');
      expect(parsed?['type'], 'text');
      expect(parsed?['data'], 'Hi');
    });

    test('set-state merges storage', () async {
      final panel = newPanel(
        state: <String, dynamic>{
          '_storage': <String, dynamic>{'taps': 1},
        },
      );
      final result = await handler.handleAction(
        'set-state',
        <String, dynamic>{'state': <String, dynamic>{'message': 'Hi'}},
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate?['_storage'], <String, dynamic>{
        'taps': 1,
        'message': 'Hi',
      });
    });

    test('set-scripts merges handlers', () async {
      final panel = newPanel(
        state: <String, dynamic>{
          '_scripts': <String, dynamic>{'a': 'old();'},
        },
      );
      final result = await handler.handleAction(
        'set-scripts',
        <String, dynamic>{
          'scripts': <String, dynamic>{'b': 'yoloit.inc("taps");'},
        },
        panel,
      );
      expect(result.ok, isTrue);
      expect(result.stateUpdate?['_scripts'], <String, dynamic>{
        'a': 'old();',
        'b': 'yoloit.inc("taps");',
      });
    });

    test('parseUiTree normalizes React-style types', () {
      final parsed = parseUiTree('{"type":"View","children":[{"type":"Text","content":"Hi"}]}');
      expect(parsed?['type'], 'column');
      final children = parsed?['children'] as List<dynamic>;
      expect((children.first as Map)['type'], 'text');
      expect((children.first as Map)['data'], 'Hi');
    });
  });
}
