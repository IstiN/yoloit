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
