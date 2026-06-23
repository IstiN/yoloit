// ignore_for_file: unnecessary_overrides

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

Future<Map<String, dynamic>> _postJson(
  HttpClient client,
  String baseUrl,
  String path,
  Map<String, dynamic> body, {
  String token = 'local-secret',
}) async {
  final request = await client.postUrl(Uri.parse('$baseUrl$path'));
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.add(utf8.encode(jsonEncode(body)));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    fail('POST $path -> ${response.statusCode}: $text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _putJson(
  HttpClient client,
  String baseUrl,
  String path,
  Map<String, dynamic> body, {
  String token = 'local-secret',
}) async {
  final request = await client.putUrl(Uri.parse('$baseUrl$path'));
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.add(utf8.encode(jsonEncode(body)));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    fail('PUT $path -> ${response.statusCode}: $text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _getJson(
  HttpClient client,
  String baseUrl,
  String path, {
  String token = 'local-secret',
}) async {
  final request = await client.getUrl(Uri.parse('$baseUrl$path'));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    fail('GET $path -> ${response.statusCode}: $text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _deleteJson(
  HttpClient client,
  String baseUrl,
  String path, {
  String token = 'local-secret',
}) async {
  final request = await client.deleteUrl(Uri.parse('$baseUrl$path'));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    fail('DELETE $path -> ${response.statusCode}: $text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

Future<void> _withRealHttpClient(
  FutureOr<void> Function(HttpClient client) test,
) async {
  await HttpOverrides.runWithHttpOverrides(
    () async {
      final client = HttpClient();
      try {
        await test(client);
      } finally {
        client.close(force: true);
      }
    },
    _RealHttpOverrides(),
  );
}

void main() {
  group('YoloitdServer endpoints', () {
    late Directory tempDir;
    late YoloitdServer server;
    late String baseUrl;
    const token = 'local-secret';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloitd_server_test');
      final store = YoloitdStore(
        rootDir: tempDir,
        actorId: 'test',
      );
      server = YoloitdServer(
        store: store,
        host: '127.0.0.1',
        port: 0,
        token: token,
      );
      await server.start();
      baseUrl = 'http://127.0.0.1:${server.boundPort}';
    });

    tearDown(() async {
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('boards list respects archived filter', () async {
      await _withRealHttpClient((client) async {
        final created = await _postJson(
          client,
          baseUrl,
          '/api/boards',
          {'name': 'Archive Test'},
        );
        final boardId =
            (created['board'] as Map<String, dynamic>)['id'] as String;

        final listBefore = await _getJson(
          client,
          baseUrl,
          '/api/boards',
        );
        expect(
          (listBefore['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .any((board) => board['id'] == boardId),
          isTrue,
        );

        final archived = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/archive',
          {},
        );
        expect(archived['ok'], isTrue);

        final listAfter = await _getJson(
          client,
          baseUrl,
          '/api/boards',
        );
        expect(
          (listAfter['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .any((board) => board['id'] == boardId),
          isFalse,
        );

        final listWithArchived = await _getJson(
          client,
          baseUrl,
          '/api/boards?includeArchived=true',
        );
        expect(
          (listWithArchived['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .any((board) => board['id'] == boardId),
          isTrue,
        );

        final unarchived = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/unarchive',
          {},
        );
        expect(unarchived['ok'], isTrue);
      });
    });

    test('groups CRUD', () async {
      await _withRealHttpClient((client) async {
        final created = await _postJson(
          client,
          baseUrl,
          '/api/boards',
          {'name': 'Groups Test'},
        );
        final boardId =
            (created['board'] as Map<String, dynamic>)['id'] as String;

        final panel = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels',
          {
            'type': 'board.note.markdown',
            'title': 'Notes',
            'x': 0,
            'y': 0,
            'width': 200,
            'height': 150,
          },
        );
        final panelId = (panel['panel'] as Map<String, dynamic>)['id'] as String;

        final groupCreated = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/groups',
          {'name': 'Research', 'panels': panelId},
        );
        expect(groupCreated['ok'], isTrue);
        final groupId =
            (groupCreated['group'] as Map<String, dynamic>)['id'] as String;

        final groups = await _getJson(
          client,
          baseUrl,
          '/api/boards/$boardId/groups',
        );
        expect(groups['groups'], hasLength(1));
        final createdGroup =
            (groups['groups'] as List<dynamic>).first as Map<String, dynamic>;
        expect(createdGroup['panelIds'], contains(panelId));

        final renamed = await _putJson(
          client,
          baseUrl,
          '/api/boards/$boardId/groups/$groupId',
          {'name': 'Reference'},
        );
        expect(renamed['ok'], isTrue);

        final board = await _getJson(client, baseUrl, '/api/boards/$boardId');
        final storedGroups =
            ((board['metadata'] as Map<String, dynamic>)['groups']
                    as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .toList();
        expect(storedGroups.first['name'], 'Reference');
      });
    });

    test('links CRUD', () async {
      await _withRealHttpClient((client) async {
        final created = await _postJson(
          client,
          baseUrl,
          '/api/boards',
          {'name': 'Links Test'},
        );
        final boardId =
            (created['board'] as Map<String, dynamic>)['id'] as String;

        final p1 = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels',
          {
            'type': 'board.note.markdown',
            'title': 'A',
            'x': 0,
            'y': 0,
            'width': 200,
            'height': 150,
          },
        );
        final p2 = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels',
          {
            'type': 'board.note.markdown',
            'title': 'B',
            'x': 300,
            'y': 0,
            'width': 200,
            'height': 150,
          },
        );
        final id1 = (p1['panel'] as Map<String, dynamic>)['id'] as String;
        final id2 = (p2['panel'] as Map<String, dynamic>)['id'] as String;

        final linkCreated = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/links',
          {'from': id1, 'to': id2},
        );
        expect(linkCreated['ok'], isTrue);
        final linkId =
            (linkCreated['link'] as Map<String, dynamic>)['id'] as String;

        final links = await _getJson(
          client,
          baseUrl,
          '/api/boards/$boardId/links',
        );
        expect(links['links'], hasLength(1));
        final storedLink =
            (links['links'] as List<dynamic>).first as Map<String, dynamic>;
        expect(storedLink['fromPanelId'], id1);
        expect(storedLink['toPanelId'], id2);

        final deleted = await _deleteJson(
          client,
          baseUrl,
          '/api/boards/$boardId/links/$linkId',
        );
        expect(deleted['ok'], isTrue);
      });
    });

    test('table panel actions round-trip', () async {
      await _withRealHttpClient((client) async {
        final created = await _postJson(
          client,
          baseUrl,
          '/api/boards',
          {'name': 'Table Test'},
        );
        final boardId =
            (created['board'] as Map<String, dynamic>)['id'] as String;

        final panel = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels',
          {
            'type': 'board.table',
            'title': 'Sales',
            'x': 0,
            'y': 0,
            'width': 520,
            'height': 360,
            'state': {
              'columns': [
                {'id': 'month', 'title': 'Month', 'type': 'text'},
                {'id': 'sales', 'title': 'Sales', 'type': 'number'},
              ],
              'rows': [
                {'id': 'r-1', 'month': 'Jan', 'sales': 100},
              ],
            },
          },
        );
        final panelId = (panel['panel'] as Map<String, dynamic>)['id'] as String;

        final initial = await _getJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels/$panelId',
        );
        final initialRows =
            ((initial['content'] as Map<String, dynamic>)['rows']
                    as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .toList();
        expect(initialRows, hasLength(1));

        final addRow = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels/$panelId/action',
          {
            'action': 'add-row',
            'cells': {'month': 'Apr', 'sales': 210},
          },
        );
        expect(addRow['ok'], isTrue);

        final fetched = await _getJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels/$panelId',
        );
        final content = fetched['content'] as Map<String, dynamic>;
        final rows = (content['rows'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
        expect(rows, hasLength(2));
        expect(
          rows.any(
            (row) => row['month'] == 'Apr' && row['sales'] == 210,
          ),
          isTrue,
        );
      });
    });
  });
}
