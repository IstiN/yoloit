import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import 'cli_server_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await CliServer.instance.stop();
  });

  group('apply YAML', () {
    test('rejects an empty payload', () async {
      await startServer();

      final res = await httpRequest(
        'POST',
        '/api/boards/board/apply',
        body: '   ',
        contentType: 'text/yaml',
      );

      expect(res.status, 400);
      expect(res.body, contains('Empty YAML payload'));
    });

    test('rejects a payload without operations', () async {
      await startServer();

      final res = await httpRequest(
        'POST',
        '/api/boards/board/apply',
        body: 'foo: bar',
        contentType: 'text/yaml',
      );

      expect(res.status, 400);
      expect(res.body, contains('No operations found'));
    });

    test('rejects a non-mapping operation', () async {
      await startServer();

      final res = await httpRequest(
        'POST',
        '/api/boards/board/apply',
        body: '- 42',
        contentType: 'text/yaml',
      );

      expect(res.status, 400);
      expect(res.body, contains('must be a YAML mapping'));
    });

    test('fails an operation without an op field', () async {
      await startServer();

      final res = await applyYamlJson('- title: x');

      expect(res.status, 400);
      expect(res.json['error'], contains('Missing "op" field'));
    });

    test('fails an unknown op', () async {
      await startServer();

      final res = await applyYamlJson('- op: board.nope');

      expect(res.status, 400);
      expect(res.json['error'], contains('Unknown op'));
    });

    test('accepts a single operation map', () async {
      final cubit = await startServer();

      final res = await applyYaml('op: board.zoom\nscale: 2.0');

      expect(res.status, 200, reason: res.body);
      expect(cubit.state.boards.single.viewport.scale, 2.0);
    });

    test('accepts a map with an operations list', () async {
      final cubit = await startServer();

      final res = await applyYaml(
        'operations:\n  - op: board.translate\n    x: 5\n    y: 7',
      );

      expect(res.status, 200, reason: res.body);
      final viewport = cubit.state.boards.single.viewport;
      expect(viewport.translation.dx, 5);
      expect(viewport.translation.dy, 7);
    });

    test('runs a full panel lifecycle with refs', () async {
      final cubit = await startServer();
      CliServer.instance.registerPanelHandler(
        FakePanelHandler(
          typeId: 'board.sticky',
          supportedActions: const ['echo'],
          onAction: (action, args, panel) async => CliActionResult(
            data: {'echoed': args['text']},
            stateUpdate: {'lastEcho': args['text']},
          ),
        ),
      );

      const yaml = '''
- op: panel.create
  type: board.sticky
  title: Note A
  ref: a
  x: 10
  y: 20
- op: panel.create
  type: board.note.markdown
  title: Note B
  ref: b
  state:
    markdown: hello world
    autoHeight: true
- op: panel.update
  panel: a
  title: Renamed A
  hidden: true
  locked: true
  pinned: true
  color: '#FF0000'
  params:
    tag: x
  state:
    foo: bar
  zIndex: 5
  x: 50
  y: 60
  width: 400
  height: 300
- op: panel.update
  panel: a
  color: clear
- op: panel.move
  panel: a
  x: 100
  y: 120
- op: panel.resize
  panel: a
  width: 500
  height: 320
- op: panel.hide
  panel: a
- op: panel.show
  panel: a
- op: panel.color
  panel: a
  color: green
- op: panel.focus
  panel: a
- op: link.create
  from: a
  to: b
  style: line
  geometry: straight
  ref: l1
- op: link.delete
  link: l1
- op: board.zoom
  scale: 1.5
- op: board.translate
  x: 10
  y: 20
- op: board.fit
- op: board.focus
- op: board.arrange
  direction: down
- op: panel.action
  panel: a
  action: echo
  text: hello
- op: panel.delete
  panel: b
''';

      final res = await applyYaml(yaml);

      expect(res.status, 200, reason: res.body);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['ok'], true);
      expect(json['applied'], 19);
      final refs = json['refs'] as Map<String, dynamic>;
      expect(refs.keys, containsAll(['a', 'b', 'l1']));

      final board = cubit.state.boards.single;
      expect(board.panels.length, 1);
      final a = board.panels.single;
      expect(a.title, 'Renamed A');
      expect(a.hidden, false);
      expect(a.locked, true);
      expect(a.pinned, true);
      expect(a.params['tag'], 'x');
      expect(a.state['lastEcho'], 'hello');
      expect(a.color, isNotNull);
      expect(board.links, isEmpty);
    });

    test('resolves panels by yamlRef across apply calls', () async {
      final cubit = await startServer();

      final created = await applyYaml(
        '- op: panel.create\n  type: board.sticky\n  title: Ref Note\n  ref: rn',
      );
      expect(created.status, 200, reason: created.body);

      final updated = await applyYaml(
        '- op: panel.update\n  panel: rn\n  title: Updated Ref',
      );

      expect(updated.status, 200, reason: updated.body);
      expect(cubit.state.boards.single.panels.single.title, 'Updated Ref');
    });

    test('panel.update merges state and params', () async {
      final cubit = await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await applyYaml(
        '- op: panel.update\n'
        '  panel: p1\n'
        '  state:\n'
        '    foo: bar\n'
        '  params:\n'
        '    tag: x',
      );

      expect(res.status, 200, reason: res.body);
      final panel = cubit.state.boards.single.panels.single;
      expect(panel.state['foo'], 'bar');
      expect(panel.params['tag'], 'x');
    });

    test('updates and restyles existing links', () async {
      final cubit = await startServer(
        panels: [stickyPanel('p1', 'A'), stickyPanel('p2', 'B', x: 400)],
        links: const [
          BoardPanelLink(id: 'l1', fromPanelId: 'p1', toPanelId: 'p2'),
        ],
      );

      final res = await applyYaml(
        '- op: link.style\n'
        '  link: l1\n'
        '  style: arrow\n'
        '- op: link.color\n'
        '  link: l1\n'
        '  color: red\n'
        '- op: link.update\n'
        '  link: l1\n'
        '  style: line\n'
        '  geometry: elbow\n'
        '  color: "#00FF00"',
      );

      expect(res.status, 200, reason: res.body);
      final link = cubit.state.boards.single.links.single;
      expect(link.style, BoardLinkStyle.line);
      expect(link.geometry, BoardLinkGeometry.elbow);
    });

    test('fails link update without an identifier', () async {
      await startServer();

      final res = await applyYamlJson('- op: link.update\n  style: line');

      expect(res.status, 400);
      expect(res.json['error'], contains('Missing link identifier'));
    });

    test('fails panel.create without a type', () async {
      await startServer();

      final res = await applyYamlJson('- op: panel.create\n  title: x');

      expect(res.status, 400);
      expect(res.json['error'], contains('Missing "type"'));
    });

    test('fails panel.update for an unknown panel', () async {
      await startServer();

      final res = await applyYamlJson(
        '- op: panel.update\n  panel: ghost\n  title: x',
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('Panel not found'));
      expect(res.json['failedAt'], 1);
    });

    test('fails panel.move without coordinates', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await applyYamlJson('- op: panel.move\n  panel: p1');

      expect(res.status, 400);
      expect(res.json['error'], contains('Missing "x" and/or "y"'));
    });

    test('fails board.fit without panels', () async {
      await startServer();

      final res = await applyYamlJson('- op: board.fit');

      expect(res.status, 400);
      expect(res.json['error'], contains('No panels to fit'));
    });

    test('fails panel.action without an action', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);
      registerEchoHandler('board.sticky', const ['echo']);

      final res = await applyYamlJson('- op: panel.action\n  panel: p1');

      expect(res.status, 400);
      expect(res.json['error'], contains('Missing "action"'));
    });

    test('fails panel.action with an unsupported action', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);
      registerEchoHandler('board.sticky', const ['echo']);

      final res = await applyYamlJson(
        '- op: panel.action\n  panel: p1\n  action: nope',
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('Unsupported action'));
    });
  });

  group('board history ops', () {
    test('board.undo and board.redo round-trip a panel resize', () async {
      final cubit = await startServer();
      await cubit.addPanel(stickyPanel('p1', 'A'));
      await cubit.updatePanel(
        'p1',
        (p) => p.copyWith(bounds: p.bounds.copyWith(width: 500)),
      );

      final undo = await applyYamlJson('- op: board.undo');

      expect(undo.status, 200, reason: undo.json.toString());
      final undoResult =
          (undo.json['results'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(undoResult['ok'], true);
      expect(undoResult['undone'], true);
      expect(undoResult['redoDepth'], 1);
      expect(cubit.state.boards.single.panels.single.bounds.width, 300);

      final redo = await applyYamlJson('- op: board.redo');

      expect(redo.status, 200, reason: redo.json.toString());
      final redoResult =
          (redo.json['results'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(redoResult['ok'], true);
      expect(redoResult['redone'], true);
      expect(redoResult['redoDepth'], 0);
      expect(cubit.state.boards.single.panels.single.bounds.width, 500);
    });

    test('board.undo without history fails the apply', () async {
      await startServer();

      final res = await applyYamlJson('- op: board.undo');

      expect(res.status, 400);
      expect(res.json['error'], contains('No restorable panel history yet'));
      expect(res.json['failedAt'], 1);
    });

    test('board.redo without history fails the apply', () async {
      await startServer();

      final res = await applyYamlJson('- op: board.redo');

      expect(res.status, 400);
      expect(res.json['error'], contains('No redoable panel history yet'));
      expect(res.json['failedAt'], 1);
    });
  });
}
