// covers: ui:create, ui:render, ui:get, ui:set-state, ui:set-scripts

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

import '../helpers/yoloit_cli_harness.dart';

void main() {
  group('real yoloit CLI — board.ui e2e', () {
    late Directory tempDir;
    late YoloitdServer server;
    late YoloitCliHarness cli;
    late String baseUrl;
    const token = 'ui-view-e2e-secret';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloit_cli_ui_view');
      server = YoloitdServer(
        store: YoloitdStore(rootDir: tempDir, actorId: 'test'),
        host: '127.0.0.1',
        port: 0,
        token: token,
      );
      await server.start();
      baseUrl = 'http://127.0.0.1:${server.boundPort}';
      cli = await YoloitCliHarness.create(baseUrl: baseUrl, token: token);
    });

    tearDown(() async {
      await cli.dispose();
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    Future<Map<String, dynamic>> uiGet(String panel) async {
      final response = await cli.json(['ui:get', 'UI E2E Board', panel]);
      expect(response['ok'], isTrue);
      return response['data'] as Map<String, dynamic>;
    }

    test('create, render, get with svg button and LLM type aliases', () async {
      await cli.json(['board:create', 'UI E2E Board']);
      final created = await cli.json([
        'ui:create',
        'UI E2E Board',
        'Dashboard',
      ]);
      expect(created['ok'], isTrue);
      final panel = created['panel'] as Map<String, dynamic>;
      expect(panel['type'], 'board.ui');

      const tree = '''
{
  "type": "View",
  "children": [
    {"type": "Text", "content": "Hello"},
    {"type": "listTile", "title": "Row", "subtitle": "Details", "onTap": "open"},
    {
      "type": "svg",
      "path": "M 50 10 a 40,40 0 1,0 80,0 a 40,40 0 1,0 -80,0 Z",
      "fill": "#FF5733",
      "width": 32,
      "height": 32
    },
    {
      "type": "Button",
      "title": "Tap {{taps}}",
      "onTap": "bump",
      "style": {"backgroundColor": "#800080", "color": "white"}
    }
  ]
}
''';

      final rendered = await cli.json([
        'ui:render',
        'UI E2E Board',
        'Dashboard',
        tree,
      ]);
      expect(rendered['ok'], isTrue);

      final data = await uiGet('Dashboard');
      final gotTree = data['tree'] as Map<String, dynamic>;
      expect(gotTree['type'], 'column');

      final children = gotTree['children'] as List<dynamic>;
      expect(children, hasLength(4));
      expect((children[0] as Map)['type'], 'text');
      expect((children[0] as Map)['data'], 'Hello');
      expect((children[1] as Map)['type'], 'listTile');
      expect((children[3] as Map)['type'], 'button');
      expect((children[3] as Map)['data'], 'Tap {{taps}}');

      final textLines = data['text'] as List<dynamic>;
      expect(textLines, contains('Hello'));
      expect(textLines, contains('Row'));
    });

    test('set-state updates storage and resolvedTree bindings', () async {
      await cli.json(['board:create', 'UI E2E Board']);
      await cli.json(['ui:create', 'UI E2E Board', 'Bindings']);

      const tree =
          '{"type":"column","children":[{"type":"text","data":"Count: {{taps}}"},{"type":"text","data":"{{message}}","when":"{{message}}"}]}';
      await cli.json(['ui:render', 'UI E2E Board', 'Bindings', tree]);

      final patched = await cli.json([
        'ui:set-state',
        'UI E2E Board',
        'Bindings',
        '{"taps":7,"message":"Grodno"}',
      ]);
      expect(patched['ok'], isTrue);

      final data = await uiGet('Bindings');
      final storage = data['storage'] as Map<String, dynamic>;
      expect(storage['taps'], 7);
      expect(storage['message'], 'Grodno');

      final resolved = data['resolvedTree'] as Map<String, dynamic>;
      final resolvedChildren = resolved['children'] as List<dynamic>;
      expect((resolvedChildren[0] as Map)['data'], 'Count: 7');
      expect((resolvedChildren[1] as Map)['data'], 'Grodno');
      expect(data['text'], contains('Count: 7'));
      expect(data['text'], contains('Grodno'));
    });

    test('set-scripts stores handler map retrievable via ui:get', () async {
      await cli.json(['board:create', 'UI E2E Board']);
      await cli.json(['ui:create', 'UI E2E Board', 'Scripts']);
      await cli.json([
        'ui:render',
        'UI E2E Board',
        'Scripts',
        '{"type":"button","data":"Go","onTap":"go"}',
      ]);

      const script = 'yoloit.inc("taps"); yoloit.set("lastAction", actionId);';
      final updated = await cli.json([
        'ui:set-scripts',
        'UI E2E Board',
        'Scripts',
        jsonEncode(<String, String>{'go': script}),
      ]);
      expect(updated['ok'], isTrue);

      final data = await uiGet('Scripts');
      final scripts = data['scripts'] as Map<String, dynamic>;
      expect(scripts['go'], script);
    });

    test('panel help lists board.ui actions including set-state', () async {
      await cli.json(['board:create', 'UI E2E Board']);
      await cli.json(['ui:create', 'UI E2E Board', 'Help Me']);

      final help = await cli.json([
        'panel:help',
        'UI E2E Board',
        'Help Me',
      ]);
      expect(help['panelType'], 'board.ui');
      final actions = (help['supportedActions'] as List<dynamic>).cast<String>();
      expect(actions, containsAll(<String>['get', 'render', 'set-state', 'set-scripts']));
    });

    test('ui:render rejects invalid tree json', () async {
      await cli.json(['board:create', 'UI E2E Board']);
      await cli.json(['ui:create', 'UI E2E Board', 'Bad']);

      final result = await cli.run([
        'ui:render',
        'UI E2E Board',
        'Bad',
        'not-json',
      ]);
      expect(result.exitCode, isNot(0));
    });
  });
}
