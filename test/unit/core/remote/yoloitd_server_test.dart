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

Future<(int, Map<String, dynamic>)> _sendJson(
  HttpClient client,
  String method,
  String baseUrl,
  String path, {
  Map<String, dynamic>? body,
  String token = 'local-secret',
}) async {
  final uri = Uri.parse('$baseUrl$path');
  final request = await switch (method) {
    'POST' => client.postUrl(uri),
    'PUT' => client.putUrl(uri),
    'DELETE' => client.deleteUrl(uri),
    _ => client.getUrl(uri),
  };
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  if (body != null) {
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(body)));
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return (response.statusCode, jsonDecode(text) as Map<String, dynamic>);
}

Future<void> _waitFor(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('condition not met within $timeout');
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

    test('panel lock lifecycle', () async {
      await _withRealHttpClient((client) async {
        final created = await _postJson(
          client,
          baseUrl,
          '/api/boards',
          {'name': 'Lock Test'},
        );
        final boardId =
            (created['board'] as Map<String, dynamic>)['id'] as String;
        final panel = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels',
          {
            'type': 'board.note.markdown',
            'title': 'Lockable',
            'x': 0,
            'y': 0,
            'width': 200,
            'height': 150,
          },
        );
        final panelId = (panel['panel'] as Map<String, dynamic>)['id'] as String;
        final lockPath = '/api/boards/$boardId/panels/$panelId/lock';

        final (acquireStatus, acquired) = await _sendJson(
          client,
          'PUT',
          baseUrl,
          lockPath,
          body: {'actorId': 'agent-a', 'ttlSec': 60},
        );
        expect(acquireStatus, 200);
        expect(acquired['ok'], isTrue);
        expect(acquired['actorId'], 'agent-a');

        final board = await _getJson(client, baseUrl, '/api/boards/$boardId');
        final locks =
            (board['metadata'] as Map<String, dynamic>)['panelLocks']
                as Map<String, dynamic>;
        final lock = locks[panelId] as Map<String, dynamic>;
        expect(lock['actorId'], 'agent-a');
        expect(lock['expiresAt'], isA<int>());

        // Same actor may refresh the lock while it is still valid.
        final (refreshStatus, refreshed) = await _sendJson(
          client,
          'PUT',
          baseUrl,
          lockPath,
          body: {'actorId': 'agent-a'},
        );
        expect(refreshStatus, 200);
        expect(refreshed['ok'], isTrue);

        // A different actor is rejected while the lock is valid.
        final (conflictStatus, conflict) = await _sendJson(
          client,
          'PUT',
          baseUrl,
          lockPath,
          body: {'actorId': 'agent-b'},
        );
        expect(conflictStatus, 409);
        expect(conflict['ok'], isFalse);
        expect(conflict['actorId'], 'agent-a');

        final released = await _deleteJson(client, baseUrl, lockPath);
        expect(released['ok'], isTrue);

        final afterDelete = await _getJson(
          client,
          baseUrl,
          '/api/boards/$boardId',
        );
        final locksAfter =
            (afterDelete['metadata'] as Map<String, dynamic>)['panelLocks']
                as Map<String, dynamic>;
        expect(locksAfter.containsKey(panelId), isFalse);

        // Releasing a panel with no lock is a no-op success.
        final releasedAgain = await _deleteJson(client, baseUrl, lockPath);
        expect(releasedAgain['ok'], isTrue);
      });
    });

    test('panel lock rejects invalid requests', () async {
      await _withRealHttpClient((client) async {
        final created = await _postJson(
          client,
          baseUrl,
          '/api/boards',
          {'name': 'Lock Errors'},
        );
        final boardId =
            (created['board'] as Map<String, dynamic>)['id'] as String;
        final panel = await _postJson(
          client,
          baseUrl,
          '/api/boards/$boardId/panels',
          {
            'type': 'board.note.markdown',
            'title': 'P',
            'x': 0,
            'y': 0,
            'width': 100,
            'height': 100,
          },
        );
        final panelId = (panel['panel'] as Map<String, dynamic>)['id'] as String;

        final (missingActorStatus, missingActor) = await _sendJson(
          client,
          'PUT',
          baseUrl,
          '/api/boards/$boardId/panels/$panelId/lock',
          body: {},
        );
        expect(missingActorStatus, 400);
        expect(missingActor['ok'], isFalse);

        final (notFoundStatus, notFound) = await _sendJson(
          client,
          'PUT',
          baseUrl,
          '/api/boards/$boardId/panels/no-such-panel/lock',
          body: {'actorId': 'agent-a'},
        );
        expect(notFoundStatus, 404);
        expect(notFound['ok'], isFalse);

        final (methodStatus, methodResult) = await _sendJson(
          client,
          'GET',
          baseUrl,
          '/api/boards/$boardId/panels/$panelId/lock',
        );
        expect(methodStatus, 405);
        expect(methodResult['ok'], isFalse);
      });
    });

    test('runs list, start, log and stop', () async {
      await _withRealHttpClient((client) async {
        final initial = await _getJson(client, baseUrl, '/api/runs');
        expect(initial['runs'], isEmpty);

        final (missingStatus, missing) = await _sendJson(
          client,
          'POST',
          baseUrl,
          '/api/runs',
          body: {'command': '   '},
        );
        expect(missingStatus, 400);
        expect(missing['ok'], isFalse);

        final started = await _postJson(
          client,
          baseUrl,
          '/api/runs',
          {'id': 'run-echo', 'command': 'echo yolo-run-marker'},
        );
        expect(started['ok'], isTrue);
        expect(started['id'], 'run-echo');
        expect(started['pid'], isA<int>());

        await _waitFor(() async {
          final log = await _getJson(client, baseUrl, '/api/runs/run-echo/log');
          final lines = (log['lines'] as List<dynamic>).cast<String>();
          return lines.any((line) => line.contains('yolo-run-marker'));
        });

        await _waitFor(() async {
          final list = await _getJson(client, baseUrl, '/api/runs');
          final runs =
              (list['runs'] as List<dynamic>)
                  .whereType<Map<String, dynamic>>()
                  .toList();
          final entry = runs.firstWhere(
            (run) => run['id'] == 'run-echo',
            orElse: () => <String, dynamic>{},
          );
          return entry.isNotEmpty &&
              entry['running'] == false &&
              entry['exitCode'] == 0;
        });

        final listed = await _getJson(client, baseUrl, '/api/runs');
        final entry =
            (listed['runs'] as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .firstWhere((run) => run['id'] == 'run-echo');
        expect(entry['logLines'], greaterThan(0));

        // Stopping an already-finished run reports ok:false.
        final stoppedLate = await _postJson(
          client,
          baseUrl,
          '/api/runs/run-echo/stop',
          {},
        );
        expect(stoppedLate['ok'], isFalse);

        // Log of an unknown run id is an empty list.
        final unknownLog = await _getJson(
          client,
          baseUrl,
          '/api/runs/no-such-run/log',
        );
        expect(unknownLog['lines'], isEmpty);

        // Stopping a still-running process succeeds.
        final sleeper = await _postJson(
          client,
          baseUrl,
          '/api/runs',
          {'id': 'run-sleep', 'command': 'sleep 30'},
        );
        expect(sleeper['ok'], isTrue);
        final stopped = await _postJson(
          client,
          baseUrl,
          '/api/runs/run-sleep/stop',
          {},
        );
        expect(stopped['ok'], isTrue);

        // Unknown sub-route returns 404.
        final (notFoundStatus, notFound) = await _sendJson(
          client,
          'DELETE',
          baseUrl,
          '/api/runs',
        );
        expect(notFoundStatus, 404);
        expect(notFound['ok'], isFalse);
      });
    });
  });
}
