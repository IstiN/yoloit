import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';

import '../helpers/remote_widget_smoke_data.dart';

void main() {
  final runDocker = Platform.environment['YOLOIT_RUN_DOCKER_TESTS'] == '1';

  test(
    'yoloitd docker container round-trips every remote widget type',
    () async {
      final image =
          Platform.environment['YOLOITD_DOCKER_IMAGE']?.trim().isNotEmpty ==
                  true
              ? Platform.environment['YOLOITD_DOCKER_IMAGE']!.trim()
              : 'yoloitd:dev';
      final shouldBuild =
          Platform.environment['YOLOIT_BUILD_DOCKER_IMAGE'] == '1';
      final container =
          'yoloitd-widget-smoke-${DateTime.now().microsecondsSinceEpoch}';
      const token = 'docker-secret';
      final port = await _freePort();

      // ignore: avoid_print
      print('Docker smoke using image=$image port=$port build=$shouldBuild');
      if (shouldBuild) {
        await _docker([
          'build',
          '--progress=plain',
          '-f',
          'docker/Dockerfile.yoloitd',
          '-t',
          image,
          '.',
        ]);
      } else if (!await _imageExists(image)) {
        fail(
          'Docker image $image was not found. Build it first with:\n'
          '  docker build -f docker/Dockerfile.yoloitd -t $image .\n'
          'or run this test with YOLOIT_BUILD_DOCKER_IMAGE=1.',
        );
      }

      // ignore: avoid_print
      print('Starting container $container');
      await _docker([
        'run',
        '-d',
        '--name',
        container,
        '-e',
        'YOLOITD_TOKEN=$token',
        '-p',
        '127.0.0.1:$port:43110',
        image,
      ]);
      addTearDown(() async {
        await _runProcess('docker', ['rm', '-f', container]);
      });

      final baseUrl = 'http://127.0.0.1:$port';
      // ignore: avoid_print
      print('Waiting for health $baseUrl');
      await _waitForHealth(baseUrl, token);
      // ignore: avoid_print
      print('Container is healthy');

      final created = await _json(
        'POST',
        '$baseUrl/api/boards',
        token,
        body: {'name': 'Docker Remote Widgets'},
      );
      final board = created['board'] as Map<String, dynamic>;
      final boardId = board['id'] as String;

      final typesResponse = await _json(
        'GET',
        '$baseUrl/api/boards/$boardId/panel-types',
        token,
      );
      final remoteTypes =
          (typesResponse['types'] as List<dynamic>)
              .whereType<Map<dynamic, dynamic>>()
              .map((entry) => entry['type'])
              .whereType<String>()
              .toSet();
      expect(
        remoteTypes,
        containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
      );

      for (var i = 0; i < yoloitdPanelTypes.length; i++) {
        final type = yoloitdPanelTypes[i]['type'] as String;
        final panelId = 'docker-panel-$i';
        final size =
            yoloitdPanelTypes[i]['defaultSize'] as Map<String, dynamic>;
        final createdPanel = await _json(
          'POST',
          '$baseUrl/api/boards/$boardId/panels',
          token,
          body: {
            'id': panelId,
            'type': type,
            'title': 'Remote $type',
            'x': 80 + (i % 4) * 360,
            'y': 80 + (i ~/ 4) * 280,
            'width': size['width'],
            'height': size['height'],
            'state': remoteWidgetSmokeState(type),
          },
        );
        expect(createdPanel['ok'], isTrue, reason: type);

        for (final action in remoteWidgetSmokeActions(type)) {
          final response = await _json(
            'POST',
            '$baseUrl/api/boards/$boardId/panels/$panelId/action',
            token,
            body: action,
          );
          expect(response['ok'], isTrue, reason: '$type ${action['action']}');
        }

        final update = await _json(
          'PUT',
          '$baseUrl/api/boards/$boardId/panels/$panelId',
          token,
          body: {'width': 444, 'height': 333},
        );
        expect(update['ok'], isTrue, reason: type);

        final fetched = await _json(
          'GET',
          '$baseUrl/api/boards/$boardId/panels/$panelId',
          token,
        );
        expect(fetched['type'], type);
        _expectRemoteActionState(
          type,
          fetched['content'] as Map<String, dynamic>,
        );
        final bounds = fetched['bounds'] as Map<String, dynamic>;
        expect(bounds['width'], 444, reason: type);
        expect(bounds['height'], 333, reason: type);
      }

      final boardJson = await _json(
        'GET',
        '$baseUrl/api/boards/$boardId',
        token,
      );
      expect(boardJson['panels'], hasLength(yoloitdPanelTypes.length));
      final panelTypes =
          (boardJson['panels'] as List<dynamic>)
              .whereType<Map<dynamic, dynamic>>()
              .map((panel) => panel['type'])
              .whereType<String>()
              .toSet();
      expect(
        panelTypes,
        containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
      );

      final snapshot = await _text(
        'GET',
        '$baseUrl/api/boards/$boardId/snapshot',
        token,
      );
      for (final entry in yoloitdPanelTypes) {
        expect(snapshot, contains(entry['type'] as String));
      }
    },
    skip:
        runDocker
            ? false
            : 'Set YOLOIT_RUN_DOCKER_TESTS=1 to run Docker smoke test.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

void _expectRemoteActionState(String type, Map<String, dynamic> content) {
  switch (type) {
    case 'board.note.markdown':
      expect(content['markdown'], contains('Appended over remote'));
    case 'board.sticky':
      expect(content['color'], '#F472B6');
    case 'board.shape':
      expect(content['shape'], 'triangle');
    case 'board.kanban':
      expect(
        (content['cards'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .any((card) => card['id'] == 'remote-card-1'),
        isTrue,
      );
    case 'board.webpage':
      expect(content['url'], 'https://example.org');
    case 'board.code.snippet':
      expect(content['language'], 'python');
    case 'board.checklist':
      expect(
        (content['items'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .any(
              (item) => item['id'] == 'remote-item-2' && item['done'] == true,
            ),
        isTrue,
      );
    case 'board.files':
      expect(content['selectedPath'], '/data');
    case 'board.file.preview':
      expect(content['path'], '/data/TODO.md');
    case 'board.playlist':
      expect(content['tracks'], isNotEmpty);
    case 'board.run':
    case 'board.run_configs':
      expect(content['activeSessionId'], 'session-remote');
    case 'board.setup_guide':
      expect(content['selectedPackageIds'], contains('node'));
    case 'board.chat':
      expect(content['messages'], isNotEmpty);
    case 'board.terminal':
      expect((content['config'] as Map)['workingDir'], '/workspace');
    case 'board.filetree':
      expect(content['selectedFile'], '/workspace/lib/main.dart');
    case 'board.diff.preview':
      expect(content['filePath'], '/workspace/lib/main.dart');
    case 'board.yolo_assistant':
      expect(content['assistantStatus'], 'ready');
    case 'board.widget.custom':
      expect(content['widgetId'], 'remote-widget');
    case 'board.timer':
      expect(content['duration'], 900);
  }
}

Future<bool> _imageExists(String image) async {
  final result = await _runProcess('docker', ['image', 'inspect', image]);
  return result.exitCode == 0;
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _docker(List<String> args) async {
  // ignore: avoid_print
  print('docker ${args.join(' ')}');
  final result = await _runProcess('docker', args);
  if (result.exitCode != 0) {
    fail(
      'docker ${args.join(' ')} failed (${result.exitCode})\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> args, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final process = await Process.start(executable, args);
  final stdoutFuture = utf8.decoder.bind(process.stdout).join();
  final stderrFuture = utf8.decoder.bind(process.stderr).join();
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      throw TimeoutException(
        '$executable ${args.join(' ')} timed out after $timeout',
      );
    },
  );
  final stdoutText = await stdoutFuture;
  final stderrText = await stderrFuture;
  return ProcessResult(process.pid, exitCode, stdoutText, stderrText);
}

Future<void> _waitForHealth(String baseUrl, String token) async {
  Object? lastError;
  for (var i = 0; i < 80; i++) {
    try {
      final health = await _json('GET', '$baseUrl/api/health', token);
      if (health['ok'] == true) return;
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for yoloitd health: $lastError');
}

Future<Map<String, dynamic>> _json(
  String method,
  String url,
  String token, {
  Map<String, Object?>? body,
}) async {
  final raw = await _text(method, url, token, body: body);
  return jsonDecode(raw) as Map<String, dynamic>;
}

Future<String> _text(
  String method,
  String url,
  String token, {
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      final encoded = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      fail('$method $url returned ${response.statusCode}: $text');
    }
    return text;
  } finally {
    client.close(force: true);
  }
}
