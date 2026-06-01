import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

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
    expect((full.body['panels'] as List), hasLength(1));
    expect(((full.body['panels'] as List).single as Map)['title'], 'Shape');
    expect((full.body['links'] as List), hasLength(1));
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
      if ((log['chunks'] as List).join().contains(dir.path)) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect((log['chunks'] as List).join(), contains(dir.path));
  });
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
