import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

import '../../../helpers/remote_widget_smoke_data.dart';

void main() {
  test('server exposes board API with token auth', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_server_');
    addTearDown(() => dir.delete(recursive: true));
    final server = YoloitdServer(
      store: YoloitdStore(rootDir: dir, actorId: 'test'),
      port: 0,
      token: 'secret',
    );
    await server.start();
    addTearDown(server.stop);

    final unauthorized = await _request(
      server.boundPort!,
      'GET',
      '/api/boards',
    );
    expect(unauthorized.status, 401);

    final created = await _json(
      server.boundPort!,
      'POST',
      '/api/boards',
      token: 'secret',
      body: {'name': 'Remote'},
    );
    expect(created.body['ok'], isTrue);
    final board = created.body['board'] as Map<String, dynamic>;

    final panel = await _json(
      server.boundPort!,
      'POST',
      '/api/boards/${board['id']}/panels',
      token: 'secret',
      body: {
        'id': 'shape-1',
        'type': 'board.shape',
        'title': 'Rhombus',
        'width': 120,
        'height': 120,
        'state': {'shape': 'diamond'},
      },
    );
    expect(panel.body['ok'], isTrue);

    await _json(
      server.boundPort!,
      'PUT',
      '/api/boards/${board['id']}/panels/shape-1',
      token: 'secret',
      body: {'width': 260, 'height': 180},
    );
    final undo = await _json(
      server.boundPort!,
      'POST',
      '/api/boards/${board['id']}/undo',
      token: 'secret',
    );
    expect(undo.body['undone'], isTrue);

    final restored = await _json(
      server.boundPort!,
      'GET',
      '/api/boards/${board['id']}/panels/shape-1',
      token: 'secret',
    );
    final bounds = restored.body['bounds'] as Map<String, dynamic>;
    expect(bounds['width'], 120);
    expect(bounds['height'], 120);
  });

  test('server accepts full board snapshots from UI clients', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_snapshot_');
    addTearDown(() => dir.delete(recursive: true));
    final server = YoloitdServer(
      store: YoloitdStore(rootDir: dir, actorId: 'test'),
      port: 0,
      token: 'secret',
    );
    await server.start();
    addTearDown(server.stop);

    final created = await _json(
      server.boundPort!,
      'POST',
      '/api/boards',
      token: 'secret',
      body: {'name': 'Snapshot'},
    );
    final board = created.body['board'] as Map<String, dynamic>;

    final updated = await _json(
      server.boundPort!,
      'PUT',
      '/api/boards/${board['id']}',
      token: 'secret',
      body: {
        'name': 'Snapshot updated',
        'viewport': {
          'scale': 0.75,
          'translation': [12, 18],
        },
        'panels': [
          {
            'id': 'shape-1',
            'type': 'board.shape',
            'title': 'Shape',
            'bounds': {'x': 10, 'y': 20, 'width': 260, 'height': 180},
            'state': {'shape': 'diamond'},
            'params': <String, Object?>{},
          },
        ],
        'links': [
          {
            'id': 'link-1',
            'fromPanelId': 'shape-1',
            'toPanelId': 'shape-1',
            'style': 'line',
            'behavior': 'fixed',
            'geometry': 'bezier',
            'color': 4284506202,
          },
        ],
        'drawings': <Object?>[],
        'metadata': {'version': 2},
      },
    );

    expect(updated.body['ok'], isTrue);
    final full = await _json(
      server.boundPort!,
      'GET',
      '/api/boards/${board['id']}',
      token: 'secret',
    );
    expect(full.body['name'], 'Snapshot updated');
    final viewport = full.body['viewport'] as Map<String, dynamic>;
    expect(viewport['scale'], 1.0);
    expect((full.body['panels'] as List), hasLength(1));
    expect(((full.body['panels'] as List).single as Map)['title'], 'Shape');
    expect((full.body['links'] as List), hasLength(1));
  });

  test('server ignores viewport-only updates from UI clients', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_viewport_');
    addTearDown(() => dir.delete(recursive: true));
    final server = YoloitdServer(
      store: YoloitdStore(rootDir: dir, actorId: 'test'),
      port: 0,
      token: 'secret',
    );
    await server.start();
    addTearDown(server.stop);

    final created = await _json(
      server.boundPort!,
      'POST',
      '/api/boards',
      token: 'secret',
      body: {'name': 'Viewport'},
    );
    final board = created.body['board'] as Map<String, dynamic>;

    await _json(
      server.boundPort!,
      'PUT',
      '/api/boards/${board['id']}',
      token: 'secret',
      body: {
        'viewport': {
          'scale': 0.25,
          'translation': {'dx': 400, 'dy': -200},
        },
      },
    );

    final full = await _json(
      server.boundPort!,
      'GET',
      '/api/boards/${board['id']}',
      token: 'secret',
    );
    final viewport = full.body['viewport'] as Map<String, dynamic>;
    expect(viewport['scale'], 1.0);
    expect(full.body['metadata'], isNot(contains('historyRevision')));
  });

  test('server rejects stale full board snapshots', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_conflict_');
    addTearDown(() => dir.delete(recursive: true));
    final server = YoloitdServer(
      store: YoloitdStore(rootDir: dir, actorId: 'test'),
      port: 0,
      token: 'secret',
    );
    await server.start();
    addTearDown(server.stop);

    final created = await _json(
      server.boundPort!,
      'POST',
      '/api/boards',
      token: 'secret',
      body: {'name': 'Conflict'},
    );
    final board = created.body['board'] as Map<String, dynamic>;
    await _json(
      server.boundPort!,
      'POST',
      '/api/boards/${board['id']}/panels',
      token: 'secret',
      body: {'id': 'shape-1', 'type': 'board.shape', 'title': 'Shape'},
    );

    final stale = await _request(
      server.boundPort!,
      'PUT',
      '/api/boards/${board['id']}',
      token: 'secret',
      body: {
        'expectedRevision': 0,
        'panels': [
          {
            'id': 'shape-1',
            'type': 'board.shape',
            'title': 'Stale Shape',
            'bounds': {'x': 10, 'y': 20, 'width': 260, 'height': 180},
          },
        ],
      },
    );

    expect(stale.status, 409);
    final body = jsonDecode(stale.body) as Map<String, dynamic>;
    expect(body['currentRevision'], 1);
  });

  test(
    'server lists remote filesystem directories for folder picking',
    () async {
      final dir = await Directory.systemTemp.createTemp('yoloitd_files_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/project').create();
      await File('${dir.path}/notes.md').writeAsString('hello');

      final store = YoloitdStore(rootDir: dir, actorId: 'tester');
      final server = YoloitdServer(store: store, port: 0, token: 'secret');
      await server.start();
      addTearDown(server.stop);

      final response = await _json(
        server.boundPort!,
        'GET',
        '/api/files?path=${Uri.encodeQueryComponent(dir.path)}',
        token: 'secret',
      );

      expect(response.status, 200);
      expect(response.body['path'], dir.path);
      final entries = response.body['entries'] as List;
      expect(
        entries,
        contains(
          allOf(
            containsPair('name', 'project'),
            containsPair('isDirectory', true),
          ),
        ),
      );
      expect(
        entries,
        contains(
          allOf(
            containsPair('name', 'notes.md'),
            containsPair('isDirectory', false),
          ),
        ),
      );
    },
  );

  test('server lists user home by default for folder picking', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_files_home_');
    addTearDown(() => dir.delete(recursive: true));

    final store = YoloitdStore(rootDir: dir, actorId: 'tester');
    final server = YoloitdServer(store: store, port: 0, token: 'secret');
    await server.start();
    addTearDown(server.stop);

    final response = await _json(
      server.boundPort!,
      'GET',
      '/api/files',
      token: 'secret',
    );

    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    expect(response.status, 200);
    if (home != null && home.trim().isNotEmpty) {
      expect(response.body['path'], home.trim());
      expect(
        response.body['roots'],
        contains(
          allOf(
            containsPair('name', 'Home'),
            containsPair('path', home.trim()),
          ),
        ),
      );
    }
  });

  test('server creates remote directories for folder picking', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_mkdir_');
    addTearDown(() => dir.delete(recursive: true));

    final store = YoloitdStore(rootDir: dir, actorId: 'tester');
    final server = YoloitdServer(store: store, port: 0, token: 'secret');
    await server.start();
    addTearDown(server.stop);

    final response = await _json(
      server.boundPort!,
      'POST',
      '/api/files/directories',
      token: 'secret',
      body: {'parentPath': dir.path, 'name': 'created-from-picker'},
    );

    expect(response.status, 200);
    expect(await Directory('${dir.path}/created-from-picker').exists(), isTrue);
    expect(response.body['path'], dir.path);
    expect(
      response.body['entries'],
      contains(
        allOf(
          containsPair('name', 'created-from-picker'),
          containsPair('isDirectory', true),
        ),
      ),
    );
  });

  test(
    'server exposes and round-trips all remote widget panel types',
    () async {
      final dir = await Directory.systemTemp.createTemp('yoloitd_widgets_');
      addTearDown(() => dir.delete(recursive: true));
      final server = YoloitdServer(
        store: YoloitdStore(rootDir: dir, actorId: 'test'),
        port: 0,
        token: 'secret',
      );
      await server.start();
      addTearDown(server.stop);

      final created = await _json(
        server.boundPort!,
        'POST',
        '/api/boards',
        token: 'secret',
        body: {'name': 'Widget Smoke'},
      );
      final board = created.body['board'] as Map<String, dynamic>;
      final boardId = board['id'] as String;

      final panelTypes = await _json(
        server.boundPort!,
        'GET',
        '/api/boards/$boardId/panel-types',
        token: 'secret',
      );
      final remoteTypes =
          (panelTypes.body['types'] as List<dynamic>)
              .whereType<Map<dynamic, dynamic>>()
              .map((entry) => entry['type'])
              .whereType<String>()
              .toSet();
      expect(
        remoteTypes,
        containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
      );
      final terminalType = (panelTypes.body['types'] as List<dynamic>)
          .whereType<Map<dynamic, dynamic>>()
          .singleWhere((entry) => entry['type'] == 'board.terminal');
      expect(terminalType['actions'], contains('set-dir'));
      final terminalCapabilities = terminalType['capabilities'] as Map;
      expect(terminalCapabilities['requiresNativeHost'], isTrue);
      expect(terminalCapabilities['remotePlatforms'], contains('ios'));

      for (var i = 0; i < yoloitdPanelTypes.length; i++) {
        final type = yoloitdPanelTypes[i]['type'] as String;
        final panelId = 'panel-$i';
        final createdPanel = await _json(
          server.boundPort!,
          'POST',
          '/api/boards/$boardId/panels',
          token: 'secret',
          body: {
            'id': panelId,
            'type': type,
            'title': 'Remote $type',
            'x': 80 + (i % 5) * 280,
            'y': 80 + (i ~/ 5) * 220,
            'width': _defaultWidth(type),
            'height': _defaultHeight(type),
            'state': _sampleState(type),
          },
        );
        expect(createdPanel.body['ok'], isTrue, reason: type);

        final fetchedBeforeActions = await _json(
          server.boundPort!,
          'GET',
          '/api/boards/$boardId/panels/$panelId',
          token: 'secret',
        );
        expect(
          fetchedBeforeActions.body['supportedActions'],
          containsAll(
            (yoloitdPanelDescriptorFor(type)?.actions ?? const <String>[]),
          ),
          reason: type,
        );

        for (final action in remoteWidgetSmokeActions(type)) {
          final response = await _json(
            server.boundPort!,
            'POST',
            '/api/boards/$boardId/panels/$panelId/action',
            token: 'secret',
            body: action,
          );
          expect(
            response.body['ok'],
            isTrue,
            reason: '$type ${action['action']}',
          );
          expect(
            response.body['panel'],
            isA<Map<String, dynamic>>(),
            reason: '$type ${action['action']}',
          );
        }

        final resized = await _json(
          server.boundPort!,
          'PUT',
          '/api/boards/$boardId/panels/$panelId',
          token: 'secret',
          body: {'width': 444, 'height': 333},
        );
        expect(resized.body['ok'], isTrue, reason: type);

        final fetched = await _json(
          server.boundPort!,
          'GET',
          '/api/boards/$boardId/panels/$panelId',
          token: 'secret',
        );
        expect(fetched.body['type'], type);
        final bounds = fetched.body['bounds'] as Map<String, dynamic>;
        expect(bounds['width'], 444);
        expect(bounds['height'], 333);
        final content = fetched.body['content'] as Map<String, dynamic>;
        _expectRemoteActionState(type, content);
      }

      final snapshot = await _request(
        server.boundPort!,
        'GET',
        '/api/boards/$boardId/snapshot',
        token: 'secret',
      );
      expect(snapshot.status, 200);
      for (final entry in yoloitdPanelTypes) {
        expect(snapshot.body, contains(entry['type'] as String));
      }
    },
  );

  test('server starts remote terminal and accepts input', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_terminal_');
    addTearDown(() => dir.delete(recursive: true));

    final store = YoloitdStore(rootDir: dir, actorId: 'tester');
    final server = YoloitdServer(store: store, port: 0, token: 'secret');
    await server.start();
    addTearDown(server.stop);

    final started = await _json(
      server.boundPort!,
      'POST',
      '/api/terminals',
      token: 'secret',
      body: {'id': 'term-1', 'cwd': dir.path},
    );
    expect(started.status, 200);

    await _json(
      server.boundPort!,
      'POST',
      '/api/terminals/term-1/input',
      token: 'secret',
      body: {'data': 'pwd\nexit\n'},
    );

    Map<String, dynamic> log = const <String, dynamic>{};
    for (var i = 0; i < 20; i++) {
      log =
          (await _json(
            server.boundPort!,
            'GET',
            '/api/terminals/term-1/log',
            token: 'secret',
          )).body;
      if ((log['chunks'] as List<dynamic>).join().contains(dir.path)) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect((log['chunks'] as List<dynamic>).join(), contains(dir.path));
  });

  test(
    'server exposes setup snapshot and rejects empty install requests',
    () async {
      final dir = await Directory.systemTemp.createTemp('yoloitd_setup_');
      addTearDown(() => dir.delete(recursive: true));

      final store = YoloitdStore(rootDir: dir, actorId: 'tester');
      final server = YoloitdServer(store: store, port: 0, token: 'secret');
      await server.start();
      addTearDown(server.stop);

      final snapshot = await _json(
        server.boundPort!,
        'GET',
        '/api/setup',
        token: 'secret',
      );
      expect(snapshot.status, 200);
      expect(snapshot.body['runtime'], isA<Map<String, dynamic>>());
      expect(snapshot.body['packages'], isA<List<dynamic>>());
      final packages = snapshot.body['packages'] as List<dynamic>;
      expect(
        packages.any(
          (entry) =>
              entry is Map<String, dynamic> &&
              entry['id'] == 'codex' &&
              entry['installAction'] is Map<String, dynamic>,
        ),
        isTrue,
      );

      final install = await _request(
        server.boundPort!,
        'POST',
        '/api/setup/install',
        token: 'secret',
        body: {'packageIds': <String>[]},
      );
      expect(install.status, 400);
    },
  );
}

double _defaultWidth(String type) {
  final entry = yoloitdPanelTypes.firstWhere((entry) => entry['type'] == type);
  final size = entry['defaultSize'] as Map<String, dynamic>;
  return (size['width'] as num).toDouble();
}

double _defaultHeight(String type) {
  final entry = yoloitdPanelTypes.firstWhere((entry) => entry['type'] == type);
  final size = entry['defaultSize'] as Map<String, dynamic>;
  return (size['height'] as num).toDouble();
}

void _expectRemoteActionState(String type, Map<String, dynamic> content) {
  switch (type) {
    case 'board.note.markdown':
      expect(content['markdown'], contains('Appended over remote'));
      expect(content['autoHeight'], isTrue);
    case 'board.sticky':
      expect(content['text'], contains('Second line'));
      expect(content['color'], '#F472B6');
    case 'board.shape':
      expect(content['shape'], 'triangle');
      expect(content['strokeWidth'], 7);
    case 'board.kanban':
      expect(content['cards'], isA<List<dynamic>>());
      expect(
        (content['cards'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .singleWhere(
              (card) => card['id'] == 'remote-card-1',
            )['description'],
        'Done remotely',
      );
    case 'board.webpage':
      expect(content['url'], 'https://example.org');
    case 'board.code.snippet':
      expect(content['language'], 'python');
      expect(content['code'], contains('remote'));
    case 'board.checklist':
      expect(
        (content['items'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .singleWhere((item) => item['id'] == 'remote-item-2')['text'],
        'Remote item renamed',
      );
    case 'board.files':
      expect(content['selectedPath'], '/data');
      expect(
        (content['files'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .any((file) => file['id'] == 'remote-file-2'),
        isTrue,
      );
    case 'board.file.preview':
      expect(content['path'], '/data/TODO.md');
    case 'board.playlist':
      expect(content['tracks'], isNotEmpty);
      expect(content['playing'], isFalse);
    case 'board.run':
    case 'board.run_configs':
      expect(content['group'], 'remote');
      expect(content['activeSessionId'], 'session-remote');
    case 'board.setup_guide':
      expect(content['selectedPackageIds'], contains('node'));
      expect(content['selectedPackageIds'], isNot(contains('tmux')));
    case 'board.chat':
      expect(content['configured'], isTrue);
      expect(content['messages'], isNotEmpty);
    case 'board.terminal':
      final config = content['config'] as Map;
      expect(config['workingDir'], '/workspace');
      expect(config['sessionId'], 'remote-terminal');
    case 'board.filetree':
      expect(content['rootPath'], '/workspace');
      expect(content['expandedDirs'], contains('/workspace/lib'));
      expect(content['selectedFile'], '/workspace/lib/main.dart');
    case 'board.diff.preview':
      expect(content['rootPath'], '/workspace');
      expect(content['filePath'], '/workspace/lib/main.dart');
    case 'board.yolo_assistant':
      expect(content['mode'], 'voice');
      expect(content['assistantStatus'], 'ready');
    case 'board.widget.custom':
      expect(content['widgetId'], 'remote-widget');
      expect(content['config'], containsPair('theme', 'remote'));
    case 'board.timer':
      expect(content['duration'], 900);
      expect(content['isPaused'], isTrue);
    default:
      expect(content, isNotEmpty);
  }
}

Map<String, Object?> _sampleState(String type) {
  return switch (type) {
    'board.note.markdown' => {
      'markdown': '## Remote markdown\nDocker smoke',
      'autoHeight': false,
      'autoScroll': false,
    },
    'board.sticky' => {
      'text': 'Remote sticky',
      'color': '#FEF08A',
      'textColor': '#1F2937',
      'fontSize': 18,
    },
    'board.shape' => {
      'shape': 'diamond',
      'text': 'Remote shape',
      'fillColor': '#00000000',
      'strokeColor': '#93C5FD',
      'textColor': '#E2E8F0',
      'strokeWidth': 3,
      'fontSize': 18,
      'textHAlign': 'center',
      'textVAlign': 'center',
      'textOrientation': 'horizontal',
    },
    'board.kanban' => {
      'columns': ['Todo', 'Done'],
      'cards': [
        {'id': 'card-1', 'title': 'Remote card', 'column': 'Todo'},
      ],
    },
    'board.webpage' => {
      'url': 'https://example.com',
      'title': 'Example',
      'favicon': '',
    },
    'board.code.snippet' => {'code': 'void main() {}', 'language': 'dart'},
    'board.checklist' => {
      'title': 'Remote checklist',
      'items': [
        {'id': 'item-1', 'text': 'Round trip state', 'done': true},
      ],
    },
    'board.files' => {
      'files': [
        {'path': '/data/README.md', 'name': 'README.md'},
      ],
    },
    'board.file.preview' => {'path': '/data/README.md', 'title': 'README.md'},
    'board.playlist' => {
      'tracks': <Map<String, Object?>>[],
      'currentIndex': 0,
      'repeat': false,
      'shuffle': false,
    },
    'board.run' => {'group': 'default', 'activeSessionId': null},
    'board.run_configs' => {'group': 'default'},
    'board.setup_guide' => {
      'selectedPackageIds': ['git', 'tmux', 'codex'],
    },
    'board.chat' => {
      'configured': false,
      'config': {'sessionName': '', 'workingDir': ''},
    },
    'board.terminal' => {
      'config': {'sessionId': '', 'sessionName': '', 'workingDir': ''},
    },
    'board.filetree' => {
      'rootPath': '/data',
      'expandedDirs': <String>[],
      'selectedFile': '',
    },
    'board.diff.preview' => {'filePath': '', 'rootPath': '', 'title': 'Diff'},
    'board.yolo_assistant' => {
      'messages': <Map<String, Object?>>[],
      'activeSkills': ['Terminal', 'Board Control', 'Web Search'],
      'mode': 'text',
      'isListening': false,
      'isSpeaking': false,
    },
    'board.widget.custom' => {
      'widgetId': 'yolo-hello',
      'config': <String, Object?>{},
    },
    'board.timer' => {
      'duration': 300,
      'remaining': 300,
      'isRunning': false,
      'isPaused': false,
      'completed': false,
      'label': 'Remote timer',
      'lastTick': 0,
    },
    _ => <String, Object?>{},
  };
}

Future<({int status, String body})> _request(
  int port,
  String method,
  String path, {
  String? token,
  Map<String, Object?>? body,
}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final encoded = body == null ? '' : jsonEncode(body);
  socket.write(
    [
      '$method $path HTTP/1.1',
      'Host: 127.0.0.1:$port',
      if (token != null) 'Authorization: Bearer $token',
      'Content-Type: application/json',
      'Content-Length: ${utf8.encode(encoded).length}',
      'Connection: close',
      '',
      encoded,
    ].join('\r\n'),
  );
  await socket.flush();
  final bytes = await socket.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  await socket.close();
  final raw = utf8.decode(bytes);
  final split = raw.indexOf('\r\n\r\n');
  expect(split, greaterThanOrEqualTo(0));
  final head = raw.substring(0, split);
  final status = int.parse(
    RegExp(r'^HTTP/\d\.\d\s+(\d+)').firstMatch(head)!.group(1)!,
  );
  return (status: status, body: raw.substring(split + 4));
}

Future<({int status, Map<String, dynamic> body})> _json(
  int port,
  String method,
  String path, {
  String? token,
  Map<String, Object?>? body,
}) async {
  final response = await _request(port, method, path, token: token, body: body);
  return (
    status: response.status,
    body: jsonDecode(response.body) as Map<String, dynamic>,
  );
}
