import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/board/chat/ui_cli_inprocess.dart';

/// In-memory fake of the local CliServer HTTP API used by
/// [UiCliInProcessClient].
class _FakeCliServer {
  _FakeCliServer(this.server);

  final HttpServer server;
  final postedActions = <Map<String, Object?>>[];
  final putPanels = <Map<String, Object?>>[];
  final createdPanels = <Map<String, Object?>>[];

  int get port => server.port;

  static Future<_FakeCliServer> start() async {
    // Ephemeral-port binds can race under parallel test runs; retry.
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final fake = _FakeCliServer(server);
        server.listen(fake._handle);
        return fake;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    throw StateError('could not bind test server: $lastError');
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    // /api/boards/{board}/panels[/{panel}[/action]]
    final board = segments.length > 2 ? segments[2] : '';

    Object? payload;
    var statusCode = HttpStatus.ok;

    if (request.method == 'GET' && path.endsWith('/panels')) {
      payload = switch (board) {
        'bad' => null,
        'empty' => <String, Object?>{'panels': <Object?>[]},
        _ => <String, Object?>{
          'panels': [
            {'id': 'p-1', 'type': 'board.ui', 'title': 'My UI'},
            {'id': 'p-2', 'type': 'board.ui', 'title': 'Second', 'hidden': true},
            {'id': 'p-3', 'type': 'board.markdown', 'title': 'Notes'},
          ],
        },
      };
      if (board == 'bad') statusCode = HttpStatus.internalServerError;
    } else if (request.method == 'POST' && path.endsWith('/panels')) {
      final body = await _readJson(request);
      createdPanels.add(body);
      if (board == 'fail-board') {
        payload = {'ok': false, 'error': 'boom'};
      } else {
        payload = {
          'ok': true,
          'panel': {'id': 'p-new', 'type': 'board.ui', 'title': body['title']},
        };
      }
    } else if (request.method == 'POST' && path.endsWith('/action')) {
      final body = await _readJson(request);
      postedActions.add(body);
      if (body['action'] == 'render' && board == 'action-fail') {
        payload = {'ok': false, 'error': 'render blew up'};
      } else {
        payload = {
          'ok': true,
          'message': 'action ${body['action']} done',
          'data': {'nodes': 1},
        };
      }
    } else if (request.method == 'PUT') {
      final body = await _readJson(request);
      putPanels.add(body);
      payload = {'ok': true};
    } else {
      statusCode = HttpStatus.notFound;
      payload = {'ok': false, 'error': 'not found'};
    }

    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    await request.response.close();
  }

  static Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, Object?>.from(decoded) : {};
  }

  Future<void> dispose() => server.close(force: true);
}

Map<String, dynamic> _decode(String? json) =>
    Map<String, dynamic>.from(jsonDecode(json!) as Map);

/// `flutter test` installs an HttpOverrides that 400s every request; restore
/// real socket behavior for this suite (each test file runs in its own
/// isolate, so the global override cannot leak into other suites).
final class _PassthroughHttpOverrides extends HttpOverrides {}

void main() {
  HttpOverrides.global = _PassthroughHttpOverrides();

  late _FakeCliServer server;

  setUp(() async {
    server = await _FakeCliServer.start();
  });

  tearDown(() async {
    await server.dispose();
  });

  group('UiCliInProcessClient.tryExecute', () {
    test('returns null for unknown commands', () async {
      final result = await UiCliInProcessClient.tryExecute(
        command: 'board:list',
        arguments: const {},
        port: server.port,
      );
      expect(result, isNull);
    });

    test('ui:create posts a board.ui panel and returns it', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:create',
          arguments: const {'board': 'main', 'title': 'Dashboard'},
          port: server.port,
        ),
      );

      expect(result['ok'], isTrue);
      expect(result['executed'], isTrue);
      expect(result['command'], 'ui:create main Dashboard');
      expect(result['panel'], {'id': 'p-new', 'type': 'board.ui', 'title': 'Dashboard'});
      expect(server.createdPanels.single, {
        'type': 'board.ui',
        'title': 'Dashboard',
      });
    });

    test('ui:create supports shorthand argument keys', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:create',
          arguments: const {'b': 'main', 't': 'Short'},
          port: server.port,
        ),
      );
      expect(result['ok'], isTrue);
    });

    test('ui:create fails when board or title is missing', () async {
      final missingTitle = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:create',
          arguments: const {'board': 'main'},
          port: server.port,
        ),
      );
      expect(missingTitle['ok'], isFalse);
      expect(missingTitle['error'], contains('Missing board or title'));

      final blankBoard = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:create',
          arguments: const {'board': '   ', 'title': 'T'},
          port: server.port,
        ),
      );
      expect(blankBoard['ok'], isFalse);
    });

    test('ui:create surfaces server-side errors', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:create',
          arguments: const {'board': 'fail-board', 'title': 'X'},
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], 'boom');
    });

    test('ui:create reports HTTP failures for unreachable servers', () async {
      // Bind and immediately close to get a guaranteed-refused port.
      final temp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = temp.port;
      await temp.close();

      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:create',
          arguments: const {'board': 'main', 'title': 'X'},
          port: deadPort,
        ),
      );
      expect(result['ok'], isFalse);
      // The POST itself fails; the client surfaces the socket error.
      expect('${result['error']}', contains('Connection refused'));
    });

    test('ui:render requires a board', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'tree': {'type': 'column'},
          },
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('Missing board'));
    });

    test('ui:render rejects unparseable trees', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {'board': 'main', 'tree': 'not json at all'},
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('Missing or invalid tree'));
    });

    test('ui:render posts the tree to the resolved panel', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'main',
            'tree': {
              'type': 'column',
              'children': [
                {'type': 'text', 'value': 'hi'},
              ],
            },
          },
          port: server.port,
        ),
      );

      expect(result['ok'], isTrue);
      expect(result['command'], 'ui:render main p-1');
      expect(result['message'], 'action render done');
      expect(server.postedActions.single['action'], 'render');
      expect(server.postedActions.single['tree'], isA<Map<String, Object?>>());
    });

    test('ui:render accepts a markdown-fenced JSON string tree', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'main',
            'tree': '```json\n{"type":"text","value":"fenced"}\n```',
          },
          port: server.port,
        ),
      );
      expect(result['ok'], isTrue);
    });

    test('ui:render unwraps a nested tree envelope', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'main',
            'tree': {
              'tree': {'type': 'text', 'value': 'nested'},
            },
          },
          port: server.port,
        ),
      );
      expect(result['ok'], isTrue);
      final tree = server.postedActions.single['tree']! as Map;
      expect(tree['type'], 'text');
    });

    test('ui:render resolves the panel by title or id hint', () async {
      final byTitle = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'main',
            'panel': 'my ui',
            'tree': {'type': 'text'},
          },
          port: server.port,
        ),
      );
      expect(byTitle['command'], 'ui:render main p-1');

      final byIdPrefix = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'main',
            'panel': 'p-1',
            'tree': {'type': 'text'},
          },
          port: server.port,
        ),
      );
      expect(byIdPrefix['command'], 'ui:render main p-1');
    });

    test('ui:render ignores hidden panels when resolving hints', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'main',
            'panel': 'Second',
            'tree': {'type': 'text'},
          },
          port: server.port,
        ),
      );
      // Hidden panel cannot match the hint; falls back to the visible board.ui.
      expect(result['command'], 'ui:render main p-1');
    });

    test('ui:render fails when no board.ui panel exists', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'empty',
            'tree': {'type': 'text'},
          },
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('No board.ui panel found on board "empty"'));
    });

    test('ui:render fails when the panel listing request fails', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'bad',
            'tree': {'type': 'text'},
          },
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('No board.ui panel found'));
    });

    test('ui:render surfaces action errors', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:render',
          arguments: const {
            'board': 'action-fail',
            'tree': {'type': 'text'},
          },
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], 'render blew up');
    });

    test('ui:get returns the panel state', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:get',
          arguments: const {'board': 'main'},
          port: server.port,
        ),
      );

      expect(result['ok'], isTrue);
      expect(result['command'], 'ui:get main p-1');
      expect(result['data'], {'nodes': 1});
      expect(server.postedActions.single['action'], 'get');
    });

    test('ui:get requires a board', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:get',
          arguments: const {},
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('Missing board'));
    });

    test('ui:get fails when no board.ui panel exists', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:get',
          arguments: const {'board': 'empty'},
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('No board.ui panel found'));
    });

    test('ui:edit focuses the panel and reports guidance', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:edit',
          arguments: const {'board': 'main', 'panel': 'p-1'},
          port: server.port,
        ),
      );

      expect(result['ok'], isTrue);
      expect(result['command'], 'ui:edit main p-1');
      expect(result['message'], contains('Panel focused'));
      expect(server.putPanels.single, {'focus': true});
    });

    test('ui:edit requires a board', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:edit',
          arguments: const {},
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('Missing board'));
    });

    test('ui:edit fails when no board.ui panel exists', () async {
      final result = _decode(
        await UiCliInProcessClient.tryExecute(
          command: 'ui:edit',
          arguments: const {'board': 'empty'},
          port: server.port,
        ),
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('No board.ui panel found'));
    });
  });

  group('UiCliInProcessClient.stripMarkdownFence', () {
    test('leaves plain JSON untouched', () {
      expect(
        UiCliInProcessClient.stripMarkdownFence('{"type":"text"}'),
        '{"type":"text"}',
      );
    });

    test('strips language-tagged fences', () {
      expect(
        UiCliInProcessClient.stripMarkdownFence('```json\n{"a":1}\n```'),
        '{"a":1}',
      );
    });

    test('strips bare fences', () {
      expect(
        UiCliInProcessClient.stripMarkdownFence('```\n{}\n```'),
        '{}',
      );
    });
  });
}
