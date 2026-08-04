/// Tests for [CollaborationServer]'s static HTTP side (`_serveHttpSocket`,
/// `_serveStaticFile`, `_mimeString`, `_closeAfterFlush`,
/// `_HttpRequestReader`), the web-client discovery/install helpers
/// (`findWebClientDir`, `installWebClient`) and the low-level
/// [CollaborationServer.readHeaders] socket parser.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/collaboration/services/collaboration_server.dart';

Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

/// Sends [request] to [port] and returns the full raw response.
Future<String> _rawHttpRequest(int port, String request) async {
  final socket = await Socket.connect(
    '127.0.0.1',
    port,
    timeout: const Duration(seconds: 5),
  );
  socket.add(utf8.encode(request));
  final buf = StringBuffer();
  await socket
      .listen((d) => buf.write(utf8.decode(d, allowMalformed: true)))
      .asFuture<void>()
      .timeout(const Duration(seconds: 5));
  socket.destroy();
  return buf.toString();
}

String _bodyOf(String rawResponse) {
  final sep = rawResponse.indexOf('\r\n\r\n');
  return sep == -1 ? '' : rawResponse.substring(sep + 4);
}

void main() {
  group('CollaborationServer static HTTP', () {
    late Directory tmp;
    late String webDir;
    CollaborationServer? server;
    late int wsPort;
    late int httpPort;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('collab_http_test');
      webDir = '${tmp.path}/web_client';
      await Directory(webDir).create(recursive: true);
      await File('$webDir/index.html').writeAsString('INDEX-CONTENT');
      await File('$webDir/style.css').writeAsString('CSS-CONTENT');
      await File('$webDir/app.js').writeAsString('JS-CONTENT');
      // A secret outside the web root, used by the traversal tests.
      await File('${tmp.path}/secret.txt').writeAsString('SECRET');
      CollaborationServer.debugWebClientDirOverride = webDir;

      // Retry with fresh ports: under the full suite many isolates probe and
      // bind ephemeral ports concurrently, so a port found free by
      // _freePort() can be grabbed before start() binds it.
      Object? lastError;
      for (var attempt = 0; attempt < 5; attempt++) {
        wsPort = await _freePort();
        httpPort = await _freePort();
        server = CollaborationServer(
          onClientMessage: (_, _) {},
          port: wsPort,
          httpPort: httpPort,
        );
        try {
          await server!.start();
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          await server?.stop();
          server = null;
        }
      }
      if (lastError != null) {
        throw StateError('no free port after 5 attempts: $lastError');
      }
    });

    tearDown(() async {
      CollaborationServer.debugWebClientDirOverride = null;
      await server?.stop();
      server = null;
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('start() binds both servers and exposes shareable URLs', () {
      expect(server!.isRunning, isTrue);
      expect(server!.webClientUrl, contains(':$httpPort'));
      expect(server!.webClientUrl, contains('wsPort=$wsPort'));
      expect(server!.localUrl, contains('localhost:$httpPort'));
    });

    test('GET / serves index.html with the HTML content type', () async {
      final raw = await _rawHttpRequest(
        httpPort,
        'GET / HTTP/1.1\r\nHost: x\r\n\r\n',
      );
      expect(raw, contains('200 OK'));
      expect(raw, contains('Content-Type: text/html; charset=utf-8'));
      expect(_bodyOf(raw), 'INDEX-CONTENT');
    });

    test('GET of a real asset serves it with the right MIME type', () async {
      final css = await _rawHttpRequest(
        httpPort,
        'GET /style.css HTTP/1.1\r\nHost: x\r\n\r\n',
      );
      expect(css, contains('Content-Type: text/css'));
      expect(_bodyOf(css), 'CSS-CONTENT');

      final js = await _rawHttpRequest(
        httpPort,
        'GET /app.js?v=42 HTTP/1.1\r\nHost: x\r\n\r\n',
      );
      expect(js, contains('Content-Type: application/javascript'));
      expect(_bodyOf(js), 'JS-CONTENT');
    });

    test('serves correct MIME types for binary and data assets', () async {
      final cases = <String, String>{
        'img.png': 'image/png',
        'icon.ico': 'image/x-icon',
        'img.svg': 'image/svg+xml',
        'data.json': 'application/json',
        'mod.wasm': 'application/wasm',
        'file.bin': 'application/octet-stream',
      };
      for (final entry in cases.entries) {
        await File('$webDir/${entry.key}').writeAsString('x');
        final raw = await _rawHttpRequest(
          httpPort,
          'GET /${entry.key} HTTP/1.1\r\nHost: x\r\n\r\n',
        );
        expect(raw, contains('Content-Type: ${entry.value}'),
            reason: 'wrong MIME for ${entry.key}');
      }
    });

    test('missing files fall back to index.html (SPA routing)', () async {
      final raw = await _rawHttpRequest(
        httpPort,
        'GET /does-not-exist.js HTTP/1.1\r\nHost: x\r\n\r\n',
      );
      expect(raw, contains('200 OK'));
      expect(_bodyOf(raw), 'INDEX-CONTENT');
    });

    test('extension-less paths fall back to index.html', () async {
      final raw = await _rawHttpRequest(
        httpPort,
        'GET /some/spa/route HTTP/1.1\r\nHost: x\r\n\r\n',
      );
      expect(_bodyOf(raw), 'INDEX-CONTENT');
    });

    test('path traversal attempts are sanitised', () async {
      for (final path in ['/..%2Fsecret.txt', '/%2e%2e/secret.txt']) {
        final raw = await _rawHttpRequest(
          httpPort,
          'GET $path HTTP/1.1\r\nHost: x\r\n\r\n',
        );
        expect(_bodyOf(raw), isNot(contains('SECRET')),
            reason: 'traversal via $path leaked the secret');
        expect(_bodyOf(raw), 'INDEX-CONTENT');
      }
    });

    test('OPTIONS preflight gets a 204 with CORS headers', () async {
      final raw = await _rawHttpRequest(
        httpPort,
        'OPTIONS /app.js HTTP/1.1\r\nHost: x\r\n\r\n',
      );
      expect(raw, contains('204 No Content'));
      expect(raw, contains('Access-Control-Allow-Origin: *'));
      expect(raw, contains('Access-Control-Allow-Methods: GET, OPTIONS'));
    });

    test('a truncated connection does not break subsequent requests',
        () async {
      // Send < 4 bytes and hang up: _serveHttpSocket destroys the socket.
      final probe = await Socket.connect('127.0.0.1', httpPort);
      probe.add(const [71, 69]); // 'GE'
      await probe.close();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final raw = await _rawHttpRequest(
        httpPort,
        'GET / HTTP/1.1\r\nHost: x\r\n\r\n',
      );
      expect(_bodyOf(raw), 'INDEX-CONTENT');
    });

    test('stop() shuts both servers down', () async {
      expect(server!.isRunning, isTrue);
      await server!.stop();
      expect(server!.isRunning, isFalse);
      expect(server!.webClientUrl, isEmpty);
      server = null;
    });
  });

  group('findWebClientDir', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('webclient_find_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    String resolved(String path) =>
        Directory(path).resolveSymbolicLinksSync();

    test('finds the installed client under HOME/.yoloit', () async {
      final home = '${tmp.path}/home';
      await Directory('$home/.yoloit/web_client').create(recursive: true);
      await File('$home/.yoloit/web_client/index.html').writeAsString('x');
      final found = await CollaborationServer.findWebClientDir(
        home: home,
        exe: '${tmp.path}/nowhere/exe',
        currentDir: '${tmp.path}/nowhere-cwd',
      );
      expect(found, resolved('$home/.yoloit/web_client'));
    });

    test('walks up from the executable to find build/web', () async {
      final root = '${tmp.path}/repo';
      await Directory('$root/build/web').create(recursive: true);
      await File('$root/build/web/index.html').writeAsString('x');
      final exe = '$root/packages/tool/bin/exe';
      final found = await CollaborationServer.findWebClientDir(
        home: '${tmp.path}/empty-home',
        exe: exe,
        currentDir: '${tmp.path}/empty-cwd',
      );
      expect(found, resolved('$root/build/web'));
    });

    test('prefers a client bundled next to the executable', () async {
      final appDir = '${tmp.path}/app';
      await Directory('$appDir/web_client').create(recursive: true);
      await File('$appDir/web_client/index.html').writeAsString('x');
      final found = await CollaborationServer.findWebClientDir(
        home: '${tmp.path}/empty-home',
        exe: '$appDir/exe',
        currentDir: '${tmp.path}/empty-cwd',
      );
      expect(found, resolved('$appDir/web_client'));
    });

    test('returns null when no web client exists anywhere', () async {
      final found = await CollaborationServer.findWebClientDir(
        home: '${tmp.path}/empty-home',
        exe: '${tmp.path}/deep/a/b/exe',
        currentDir: '${tmp.path}/empty-cwd',
      );
      expect(found, isNull);
    });
  });

  group('installWebClient', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('webclient_install_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('is a no-op when HOME is null', () async {
      await CollaborationServer.installWebClient(
        home: null,
        exe: '${tmp.path}/exe',
      );
      expect(await Directory('${tmp.path}/.yoloit').exists(), isFalse);
    });

    test('is a no-op when the client is already installed', () async {
      final home = '${tmp.path}/home';
      final dest = '$home/.yoloit/web_client';
      await Directory(dest).create(recursive: true);
      await File('$dest/index.html').writeAsString('OLD');
      // A newer build/web exists next to the executable but must be ignored.
      final toolDir = '${tmp.path}/tool';
      await Directory('$toolDir/build/web').create(recursive: true);
      await File('$toolDir/build/web/index.html').writeAsString('NEW');

      await CollaborationServer.installWebClient(
        home: home,
        exe: '$toolDir/exe',
      );
      expect(await File('$dest/index.html').readAsString(), 'OLD');
    });

    test('copies build/web found by walking up from the executable',
        () async {
      final home = '${tmp.path}/home';
      final src = '${tmp.path}/proj/build/web';
      await Directory('$src/assets').create(recursive: true);
      await File('$src/index.html').writeAsString('INDEX');
      await File('$src/assets/app.js').writeAsString('JS');

      await CollaborationServer.installWebClient(
        home: home,
        exe: '${tmp.path}/proj/tool/exe',
      );

      final dest = '$home/.yoloit/web_client';
      expect(await File('$dest/index.html').readAsString(), 'INDEX');
      expect(await File('$dest/assets/app.js').readAsString(), 'JS');
    });

    test('does nothing when no build/web can be found', () async {
      final home = '${tmp.path}/home';
      await CollaborationServer.installWebClient(
        home: home,
        exe: '${tmp.path}/deep/a/b/c/exe',
      );
      expect(await Directory('$home/.yoloit').exists(), isFalse);
    });
  });

  group('readHeaders', () {
    Future<Map<String, String>?> runRead(
      Future<void> Function(Socket client) writer,
    ) async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final resultFuture =
          listener.first.then(CollaborationServer.readHeaders);
      final client = await Socket.connect('127.0.0.1', listener.port);
      await writer(client);
      final result = await resultFuture.timeout(
        const Duration(seconds: 5),
      );
      await client.close();
      await listener.close();
      return result;
    }

    test('parses a well-formed request from a real socket', () async {
      final headers = await runRead((client) async {
        client.add(
          utf8.encode(
            'POST /submit?q=1 HTTP/1.1\r\n'
            'Host: example\r\n'
            'X-Custom:  spaced value \r\n'
            'broken-line-without-colon\r\n'
            '\r\n',
          ),
        );
      });
      expect(headers, isNotNull);
      expect(headers!['_method'], 'POST');
      expect(headers['_path'], '/submit?q=1');
      expect(headers['host'], 'example');
      expect(headers['x-custom'], 'spaced value');
      expect(headers.containsKey('broken-line-without-colon'), isFalse);
    });

    test('handles headers split across chunks', () async {
      final headers = await runRead((client) async {
        client.add(utf8.encode('GET / HTTP/1.1\r\nHos'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        client.add(utf8.encode('t: x\r\n\r\n'));
      });
      expect(headers, isNotNull);
      expect(headers!['_method'], 'GET');
      expect(headers['host'], 'x');
    });

    test('returns null when the peer closes without a header boundary',
        () async {
      final headers = await runRead((client) async {
        client.add(utf8.encode('GET /partial'));
        await client.close();
      });
      expect(headers, isNull);
    });

    test('returns null when headers exceed 64 KB', () async {
      final headers = await runRead((client) async {
        client.add(List<int>.filled(70000, 65));
      });
      expect(headers, isNull);
    });
  });
}
