import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

import '../helpers/remote_widget_smoke_data.dart';

void main() {
  final runDocker = Platform.environment['YOLOIT_RUN_DOCKER_TESTS'] == '1';

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    PlatformDirs.setInstance(const IosPlatformDirs(homeOverride: '/ios/app'));
  });

  tearDown(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  test(
    'mobile client connects to docker yoloitd and syncs every remote widget panel',
    () async {
      final harness = await _DockerYoloitdHarness.start();
      addTearDown(harness.dispose);

      final created = await harness.json(
        'POST',
        '/api/boards',
        body: {'name': 'Docker Mobile Remote'},
      );
      final boardId =
          (created['board'] as Map<String, dynamic>)['id'] as String;

      for (var i = 0; i < yoloitdPanelTypes.length; i++) {
        final type = yoloitdPanelTypes[i]['type'] as String;
        final size =
            yoloitdPanelTypes[i]['defaultSize'] as Map<String, dynamic>;
        await harness.json(
          'POST',
          '/api/boards/$boardId/panels',
          body: {
            'id': 'mobile-panel-$i',
            'type': type,
            'title': 'Mobile $type',
            'x': 60 + (i % 3) * 360,
            'y': 60 + (i ~/ 3) * 280,
            'width': size['width'],
            'height': size['height'],
            'state': remoteWidgetSmokeState(type),
          },
        );
      }

      final cubit = BoardCubit(actorId: 'mobile-docker-test');
      addTearDown(cubit.close);
      await cubit.load();
      final boards = await cubit.connectRemoteBoards(
        url: harness.baseUrl,
        token: harness.token,
      );

      final targetBoard = boards.singleWhere(
        (board) => board.name == 'Docker Mobile Remote',
      );
      await cubit.setActiveBoard(targetBoard.id);

      final active = cubit.state.activeBoard!;
      expect(active.name, 'Docker Mobile Remote');
      expect(active.panels, hasLength(yoloitdPanelTypes.length));
      expect(
        active.panels.map((panel) => panel.type).toSet(),
        containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
      );

      for (final panel in active.panels) {
        await cubit.updatePanel(
          panel.id,
          (current) => current.copyWith(
            bounds: current.bounds.copyWith(
              x: current.bounds.x + 11,
              y: current.bounds.y + 13,
              width: current.bounds.width + 23,
              height: current.bounds.height + 19,
            ),
          ),
        );
      }
      await cubit.flushRemoteSync();

      final serverBoard = await harness.json('GET', '/api/boards/$boardId');
      final panels =
          (serverBoard['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .toList();
      expect(panels, hasLength(yoloitdPanelTypes.length));
      for (var i = 0; i < panels.length; i++) {
        final size =
            yoloitdPanelTypes[i]['defaultSize'] as Map<String, dynamic>;
        final bounds = panels[i]['bounds'] as Map<String, dynamic>;
        expect(bounds['x'], 60 + (i % 3) * 360 + 11);
        expect(bounds['y'], 60 + (i ~/ 3) * 280 + 13);
        expect(bounds['width'], (size['width'] as num).toDouble() + 23);
        expect(bounds['height'], (size['height'] as num).toDouble() + 19);
      }
    },
    skip:
        runDocker
            ? false
            : 'Set YOLOIT_RUN_DOCKER_TESTS=1 to run Docker smoke test.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

class _DockerYoloitdHarness {
  _DockerYoloitdHarness({
    required this.container,
    required this.baseUrl,
    required this.token,
  });

  final String container;
  final String baseUrl;
  final String token;

  static Future<_DockerYoloitdHarness> start() async {
    final image =
        Platform.environment['YOLOITD_DOCKER_IMAGE']?.trim().isNotEmpty == true
            ? Platform.environment['YOLOITD_DOCKER_IMAGE']!.trim()
            : 'yoloitd:dev';
    if (!await _imageExists(image)) {
      fail(
        'Docker image $image was not found. Build it first with:\n'
        '  docker build -f docker/Dockerfile.yoloitd -t $image .',
      );
    }
    final port = await _freePort();
    final container =
        'yoloitd-mobile-client-${DateTime.now().microsecondsSinceEpoch}';
    const token = 'docker-secret';
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
    final harness = _DockerYoloitdHarness(
      container: container,
      baseUrl: 'http://127.0.0.1:$port',
      token: token,
    );
    await harness._waitForHealth();
    return harness;
  }

  Future<void> dispose() async {
    await _runProcess('docker', ['rm', '-f', container]);
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        final encoded = utf8.encode(jsonEncode(body));
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.contentLength = encoded.length;
        request.add(encoded);
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        fail('HTTP ${response.statusCode} $method $path: $text');
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _waitForHealth() async {
    Object? lastError;
    for (var i = 0; i < 60; i++) {
      try {
        final health = await json('GET', '/api/health');
        if (health['ok'] == true) return;
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    fail('Timed out waiting for yoloitd health: $lastError');
  }
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<bool> _imageExists(String image) async {
  final result = await _runProcess('docker', ['image', 'inspect', image]);
  return result.exitCode == 0;
}

Future<void> _docker(List<String> args) async {
  final result = await _runProcess('docker', args);
  if (result.exitCode != 0) {
    fail(
      'docker ${args.join(' ')} failed with ${result.exitCode}\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}

Future<ProcessResult> _runProcess(String executable, List<String> args) {
  return Process.run(executable, args, runInShell: false);
}
