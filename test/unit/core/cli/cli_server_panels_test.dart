import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';

import 'cli_server_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TimerManager.instance.disposeAll();
    await CliServer.instance.stop();
  });

  group('board snapshot', () {
    test('markdown snapshot lists panels and links', () async {
      await startServer(
        panels: [stickyPanel('p1', 'Alpha'), stickyPanel('p2', 'Beta')],
        links: const [
          BoardPanelLink(id: 'l1', fromPanelId: 'p1', toPanelId: 'p2'),
        ],
      );

      final res = await httpRequest('GET', '/api/boards/board/snapshot');

      expect(res.status, 200);
      expect(res.body, contains('# Board: Board'));
      expect(res.body, contains('## Panels (2)'));
      expect(res.body, contains('Alpha'));
      expect(res.body, contains('## Links (1)'));
      expect(res.body, contains('Alpha → Beta (arrow, bezier)'));
    });

    test('mermaid snapshot renders graph and skips dangling links', () async {
      final cubit = await startServer(
        panels: [stickyPanel('p1', 'Alpha'), stickyPanel('p2', 'Beta')],
      );
      await cubit.upsertLink(
        const BoardPanelLink(id: 'l1', fromPanelId: 'p1', toPanelId: 'p2'),
      );
      await cubit.upsertLink(
        const BoardPanelLink(id: 'l2', fromPanelId: 'p1', toPanelId: 'ghost'),
      );

      final res = await httpRequest(
        'GET',
        '/api/boards/board/snapshot?format=mermaid',
      );

      expect(res.status, 200);
      expect(res.body, contains('graph TD'));
      expect(res.body, contains('p1 --> p2'));
      expect(res.body, isNot(contains('ghost')));
    });
  });

  group('create panel', () {
    test('requires a type field', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels',
        body: const {},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('type'));
    });

    test('rejects unknown panel type', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels',
        body: const {'type': 'board.nope'},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('Unknown panel type'));
    });

    test('rejects widget shell without widgetId', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels',
        body: const {'type': 'board.widget.custom'},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('app:run'));
    });

    test('creates widget shell when widgetId is provided', () async {
      final cubit = await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels',
        body: const {
          'type': 'board.widget.custom',
          'state': {'widgetId': 'w1'},
        },
      );

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
      expect(
        cubit.state.boards.single.panels.single.type,
        'board.widget.custom',
      );
    });

    test('creates panel with explicit geometry and state', () async {
      final cubit = await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels',
        body: const {
          'type': 'board.sticky',
          'title': 'My Note',
          'x': 10,
          'y': 20,
          'width': 320,
          'height': 240,
          'state': {'text': 'hello'},
        },
      );

      expect(res.status, 200, reason: res.body);
      final panel = res.json['panel'] as Map<String, dynamic>;
      expect(panel['title'], 'My Note');
      final created = cubit.state.boards.single.panels.single;
      expect(created.bounds.x, 10);
      expect(created.bounds.y, 20);
      expect(created.bounds.width, 320);
      expect(created.state['text'], 'hello');
    });

    test('auto-places panel when no position is given', () async {
      final cubit = await startServer(
        panels: [stickyPanel('p1', 'Existing', x: 120, y: 120)],
      );

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels',
        body: const {'type': 'board.sticky'},
      );

      expect(res.status, 200, reason: res.body);
      expect(cubit.state.boards.single.panels.length, 2);
      final created = cubit.state.boards.single.panels.last;
      expect(created.bounds.x != 120 || created.bounds.y != 120, true);
    });
  });

  group('update board', () {
    test('renames, sets default folder and focuses', () async {
      final cubit = await startServer();

      final res = await apiJson(
        'PUT',
        '/api/boards/board',
        body: const {
          'name': 'Renamed',
          'defaultFolder': '/tmp/yoloit-cli-test',
          'focus': true,
        },
      );

      expect(res.json['ok'], true);
      final board = cubit.state.boards.single;
      expect(board.name, 'Renamed');
      expect(board.defaultFolder, '/tmp/yoloit-cli-test');
      expect(cubit.state.activeBoardId, 'board');
    });

    test('adjusts viewport scale and translation', () async {
      final cubit = await startServer();

      final res = await apiJson(
        'PUT',
        '/api/boards/board',
        body: const {'scale': 2.0, 'x': 15, 'y': 25},
      );

      expect(res.json['ok'], true);
      final viewport = cubit.state.boards.single.viewport;
      expect(viewport.scale, 2.0);
      expect(viewport.translation.dx, 15);
      expect(viewport.translation.dy, 25);
    });

    test('fit computes a viewport around all panels', () async {
      final cubit = await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await apiJson(
        'PUT',
        '/api/boards/board',
        body: const {'fit': true},
      );

      expect(res.json['ok'], true);
      expect(cubit.state.boards.single.viewport.scale, 2.0);
    });

    test('empty body is a no-op', () async {
      final cubit = await startServer();

      final res = await apiJson('PUT', '/api/boards/board', body: const {});

      expect(res.json['ok'], true);
      expect(cubit.state.boards.single.name, 'Board');
    });
  });

  group('update panel', () {
    test('applies title, geometry, flags and color', () async {
      final cubit = await startServer(panels: [stickyPanel('p1', 'Old')]);

      final res = await apiJson(
        'PUT',
        '/api/boards/board/panels/p1',
        body: const {
          'title': 'New',
          'x': 50,
          'y': 60,
          'width': 400,
          'height': 300,
          'hidden': true,
          'zIndex': 7,
          'color': '#FF0000',
          'focus': true,
        },
      );

      expect(res.json['ok'], true);
      final panel = cubit.state.boards.single.panels.single;
      expect(panel.title, 'New');
      expect(panel.bounds.x, 50);
      expect(panel.bounds.y, 60);
      expect(panel.bounds.width, 400);
      expect(panel.bounds.height, 300);
      expect(panel.hidden, true);
      expect(panel.zIndex, greaterThanOrEqualTo(7));
      expect(panel.color, isNotNull);
    });

    test('clears color with the clear keyword', () async {
      final cubit = await startServer(panels: [stickyPanel('p1', 'Old')]);
      await apiJson(
        'PUT',
        '/api/boards/board/panels/p1',
        body: const {'color': 'red'},
      );

      final res = await apiJson(
        'PUT',
        '/api/boards/board/panels/p1',
        body: const {'color': 'clear'},
      );

      expect(res.json['ok'], true);
      expect(cubit.state.boards.single.panels.single.color, isNull);
    });
  });

  group('grid view', () {
    test('enables grid with cell size and spacing', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await apiJson(
        'POST',
        '/api/boards/board/grid',
        body: const {'enabled': true, 'cellSize': 120, 'spacing': 12},
      );

      expect(res.status, 200, reason: res.body);
      final gridMode = res.json['gridMode'] as Map<String, dynamic>;
      expect(gridMode['enabled'], true);
      expect(gridMode['cellSize'], 120.0);
      expect(gridMode['spacing'], 12.0);
    });

    test('arranges panels and groups by type', () async {
      await startServer(
        panels: [stickyPanel('p1', 'A'), stickyPanel('p2', 'B', x: 400)],
      );

      final res = await apiJson(
        'POST',
        '/api/boards/board/grid',
        body: const {'enabled': true, 'arrange': true, 'groupByType': true},
      );

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
    });

    test('reset works without an enabled flag', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await apiJson(
        'POST',
        '/api/boards/board/grid',
        body: const {'reset': true},
      );

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
    });

    test('requires enabled unless resetting', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards/board/grid',
        body: const {},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('enabled'));
    });
  });

  group('panel action', () {
    test('requires an action field', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels/p1/action',
        body: const {},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('action'));
    });

    test('rejects panel types without a registered handler', () async {
      await startServer(
        panels: const [
          BoardPanelInstance(
            id: 's1',
            type: 'board.shape',
            title: 'Shape',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          ),
        ],
      );

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels/s1/action',
        body: const {'action': 'echo'},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('No CLI handler'));
    });

    test('rejects unsupported actions', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);
      registerEchoHandler('board.sticky', const ['echo']);

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels/p1/action',
        body: const {'action': 'nope'},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('Unsupported action'));
    });

    test('applies state updates to target and additional panels', () async {
      final cubit = await startServer(
        panels: [stickyPanel('p1', 'A'), stickyPanel('p2', 'B', x: 400)],
      );
      CliServer.instance.registerPanelHandler(
        FakePanelHandler(
          typeId: 'board.sticky',
          supportedActions: const ['mutate'],
          onAction: (action, args, panel) async => const CliActionResult(
            message: 'done',
            stateUpdate: {'text': 'from-action'},
            additionalStateUpdates: {
              'p2': {'text': 'secondary'},
            },
          ),
        ),
      );

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels/p1/action',
        body: const {'action': 'mutate'},
      );

      expect(res.status, 200, reason: res.body);
      final panels = cubit.state.boards.single.panels;
      expect(
        panels.firstWhere((p) => p.id == 'p1').state['text'],
        'from-action',
      );
      expect(
        panels.firstWhere((p) => p.id == 'p2').state['text'],
        'secondary',
      );
    });

    test('timer state changes drive TimerManager', () async {
      await startServer(
        panels: const [
          BoardPanelInstance(
            id: 't1',
            type: 'board.timer',
            title: 'Timer',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 200, height: 150),
          ),
        ],
      );
      var running = true;
      CliServer.instance.registerPanelHandler(
        FakePanelHandler(
          typeId: 'board.timer',
          supportedActions: const ['mutate'],
          onAction: (action, args, panel) async => CliActionResult(
            stateUpdate: running
                ? {'isRunning': true, 'remaining': 120}
                : {'isRunning': false},
          ),
        ),
      );

      final startRes = await apiJson(
        'POST',
        '/api/boards/board/panels/t1/action',
        body: const {'action': 'mutate'},
      );
      expect(startRes.status, 200, reason: startRes.body);
      expect(TimerManager.instance.isRunning('t1'), true);

      running = false;
      final stopRes = await apiJson(
        'POST',
        '/api/boards/board/panels/t1/action',
        body: const {'action': 'mutate'},
      );
      expect(stopRes.status, 200, reason: stopRes.body);
      expect(TimerManager.instance.isRunning('t1'), false);
    });

    test('markdown note auto-height resizes the panel', () async {
      final cubit = await startServer(
        panels: const [
          BoardPanelInstance(
            id: 'm1',
            type: 'board.note.markdown',
            title: 'MD',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 100),
          ),
        ],
      );
      CliServer.instance.registerPanelHandler(
        FakePanelHandler(
          typeId: 'board.note.markdown',
          supportedActions: const ['mutate'],
          onAction: (action, args, panel) async => const CliActionResult(
            stateUpdate: {
              'autoHeight': true,
              'markdown':
                  '# Title\n\nline one\n\nline two\n\nline three\n\nline four',
            },
          ),
        ),
      );

      final res = await apiJson(
        'POST',
        '/api/boards/board/panels/m1/action',
        body: const {'action': 'mutate'},
      );

      expect(res.status, 200, reason: res.body);
      final panel = cubit.state.boards.single.panels.single;
      expect(panel.state['autoHeight'], true);
      expect(panel.bounds.height, greaterThanOrEqualTo(140));
    });

    test('panel details include handler content and action help', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);
      registerEchoHandler('board.sticky', const ['echo']);

      final res = await apiJson('GET', '/api/boards/board/panels/p1');

      expect(res.status, 200);
      expect(res.json['content'], isNotNull);
      expect(res.json['supportedActions'], contains('echo'));
      final help = res.json['actionHelp'] as Map<String, dynamic>;
      expect(help['echo'], isNotNull);
    });
  });
}
