import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Shared harness for integration tests that need a real yoloitd daemon
/// running inside Docker.
///
/// Set `YOLOIT_RUN_DOCKER_TESTS=1` to enable tests that use this harness.
/// Set `YOLOITD_DOCKER_IMAGE` to override the image (default: `yoloitd:dev`).
/// Set `YOLOIT_BUILD_DOCKER_IMAGE=1` to build the image automatically when it
/// is missing.
class YoloitdDockerHarness {
  YoloitdDockerHarness._({
    required this.container,
    required this.baseUrl,
    required this.token,
  });

  final String container;
  final String baseUrl;
  final String token;

  static Future<YoloitdDockerHarness> start() async {
    final image =
        Platform.environment['YOLOITD_DOCKER_IMAGE']?.trim().isNotEmpty == true
            ? Platform.environment['YOLOITD_DOCKER_IMAGE']!.trim()
            : 'yoloitd:dev';

    if (!await _imageExists(image)) {
      if (Platform.environment['YOLOIT_BUILD_DOCKER_IMAGE'] == '1') {
        await _docker([
          'build',
          '--progress=plain',
          '-f',
          'docker/Dockerfile.yoloitd',
          '-t',
          image,
          '.',
        ]);
      } else {
        fail(
          'Docker image $image was not found. Build it first with:\n'
          '  docker build -f docker/Dockerfile.yoloitd -t $image .\n'
          'or run this test with YOLOIT_BUILD_DOCKER_IMAGE=1.',
        );
      }
    }

    final port = await _freePort();
    final container =
        'yoloitd-int-${DateTime.now().microsecondsSinceEpoch}';
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

    final harness = YoloitdDockerHarness._(
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
    final raw = await text(method, path, body: body);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<String> text(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('$baseUrl$path'),
      );
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
      return text;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _waitForHealth() async {
    Object? lastError;
    for (var i = 0; i < 80; i++) {
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

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<bool> _imageExists(String image) async {
    final result = await _runProcess('docker', ['image', 'inspect', image]);
    return result.exitCode == 0;
  }

  static Future<void> _docker(List<String> args) async {
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

  static Future<ProcessResult> _runProcess(
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
}
