// ignore_for_file: unnecessary_overrides

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

Future<(int, Map<String, dynamic>)> _request(
  HttpClient client,
  String method,
  String baseUrl,
  String path, {
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer local-secret');
  if (body != null) {
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(body)));
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return (response.statusCode, jsonDecode(text) as Map<String, dynamic>);
}

Future<void> _withClient(
  FutureOr<void> Function(HttpClient client) body,
) async {
  await HttpOverrides.runWithHttpOverrides(
    () async {
      final client = HttpClient();
      try {
        await body(client);
      } finally {
        client.close(force: true);
      }
    },
    _RealHttpOverrides(),
  );
}

void main() {
  group('YoloitdServer template and color routes', () {
    late Directory tempDir;
    late YoloitdServer server;
    late String baseUrl;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloitd_routes_test_');
      server = YoloitdServer(
        store: YoloitdStore(rootDir: tempDir, actorId: 'test'),
        host: '127.0.0.1',
        port: 0,
        token: 'local-secret',
      );
      await server.start();
      baseUrl = 'http://127.0.0.1:${server.boundPort}';
    });

    tearDown(() async {
      await server.stop();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('template collection and item routes return their stub responses', () async {
      await _withClient((client) async {
        final list = await _request(client, 'GET', baseUrl, '/api/templates');
        expect(list.$1, 200);
        expect(list.$2['ok'], isTrue);
        expect(list.$2['templates'], isEmpty);

        final sync = await _request(
          client,
          'POST',
          baseUrl,
          '/api/templates',
          body: <String, Object?>{},
        );
        expect(sync.$1, 200);
        expect(sync.$2['message'], 'Templates synced');

        final item = await _request(
          client,
          'GET',
          baseUrl,
          '/api/templates/missing',
        );
        expect(item.$1, 404);
        expect(item.$2['error'], 'Template not found');

        final unsupported = await _request(
          client,
          'DELETE',
          baseUrl,
          '/api/templates',
        );
        expect(unsupported.$1, 404);
        expect(unsupported.$2['error'], 'not found');
      });
    });

    test('panel updates parse integer, hex, clear, and invalid colors', () async {
      await _withClient((client) async {
        final createdBoard = await _request(
          client,
          'POST',
          baseUrl,
          '/api/boards',
          body: <String, Object?>{'name': 'Colors'},
        );
        final boardId =
            (createdBoard.$2['board'] as Map<String, dynamic>)['id'] as String;
        final createdPanel = await _request(
          client,
          'POST',
          baseUrl,
          '/api/boards/$boardId/panels',
          body: <String, Object?>{
            'type': 'board.note.markdown',
            'title': 'Color target',
          },
        );
        final panelId =
            (createdPanel.$2['panel'] as Map<String, dynamic>)['id'] as String;

        Future<void> expectColor(Object? input, Object? expected) async {
          final updated = await _request(
            client,
            'PUT',
            baseUrl,
            '/api/boards/$boardId/panels/$panelId',
            body: <String, Object?>{'color': input},
          );
          expect(updated.$1, 200);
          final panel = updated.$2['panel'] as Map<String, dynamic>;
          expect(panel['color'], expected, reason: 'input: $input');
        }

        await expectColor(0xFF010203, 0xFF010203);
        await expectColor('#A1B2C3', 0xA1B2C3);
        await expectColor('clear', isNull);
        await expectColor(' clear ', isNull);
        await expectColor('', isNull);
        await expectColor('#not-hex', isNull);
        await expectColor('not-a-color', isNull);
        await expectColor(null, isNull);
      });
    });
  });
}
