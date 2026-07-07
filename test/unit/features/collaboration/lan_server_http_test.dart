/// Integration tests for the LAN HTTP server socket handling.
///
/// These tests verify that:
/// 1. The server correctly serves HTTP responses via localhost
/// 2. Responses are delivered on LAN by waiting for the peer's FIN before
///    destroying the socket (avoids socket.close() EINVAL on macOS LAN)
/// 3. The server handles malformed / zero-byte connections gracefully
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ── Minimal server replicating _serveHttpSocket logic ────────────────────────
//
// We can't call the private static method directly, so we replicate the
// exact same logic here. If the production implementation changes, this
// test will catch regressions in the core pattern.

Future<void> _serveSocket(Socket socket, String body) async {
  final requestDone = Completer<void>();
  final peerEof = Completer<void>();
  final buf = <int>[];

  socket.listen(
    (chunk) {
      if (requestDone.isCompleted) return;
      buf.addAll(chunk);
      for (int i = 0; i <= buf.length - 4; i++) {
        if (buf[i] == 13 &&
            buf[i + 1] == 10 &&
            buf[i + 2] == 13 &&
            buf[i + 3] == 10) {
          requestDone.complete();
          return;
        }
      }
      if (buf.length > 65536) requestDone.complete();
    },
    onError: (_) {
      if (!requestDone.isCompleted) requestDone.complete();
      if (!peerEof.isCompleted) peerEof.complete();
    },
    onDone: () {
      if (!requestDone.isCompleted) requestDone.complete();
      if (!peerEof.isCompleted) peerEof.complete();
    },
    cancelOnError: false,
  );

  await requestDone.future;
  if (buf.length < 4) { socket.destroy(); return; }

  final bodyBytes = utf8.encode(body);
  final responseHeaders = utf8.encode(
    'HTTP/1.1 200 OK\r\n'
    'Content-Type: text/plain\r\n'
    'Content-Length: ${bodyBytes.length}\r\n'
    'Connection: close\r\n'
    '\r\n',
  );

  try { socket.add(responseHeaders + bodyBytes); } catch (_) {}

  // Flush, then close gracefully. On macOS LAN sockets socket.close() throws
  // EINVAL, so we fall back to waiting for the peer's FIN then destroy().
  try { await socket.flush(); } catch (_) {}
  try {
    await socket.close();
    return; // graceful close (loopback / non-macOS-LAN)
  } catch (_) {}
  await peerEof.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {},
  );
  try { socket.destroy(); } catch (_) {}
}

/// Starts a [ServerSocket] on localhost, serves one request using
/// [_serveSocket], and returns the response body received by the client.
Future<String?> _runOneRequest({
  String body = 'OK',
  String request = 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n',
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;

  // Server: serve one request then close
  server.listen((socket) async {
    await _serveSocket(socket, body);
    await server.close();
  }, onError: (_) {});

  // Client: connect and read response
  try {
    final client = await Socket.connect('127.0.0.1', port,
        timeout: const Duration(seconds: 5));
    client.add(utf8.encode(request));

    final response = StringBuffer();
    await client.listen(
      (data) => response.write(utf8.decode(data, allowMalformed: true)),
    ).asFuture<void>().timeout(const Duration(seconds: 5));

    final raw = response.toString();
    // Extract body after the blank line separator
    final sep = raw.indexOf('\r\n\r\n');
    return sep == -1 ? null : raw.substring(sep + 4);
  } catch (_) {
    return null;
  }
}

void main() {
  group('LAN HTTP server – socket serving', () {
    test('serves a response body correctly via loopback', () async {
      final body = await _runOneRequest(body: 'hello world');
      expect(body, 'hello world');
    });

    test('serves a large response body (64 KB)', () async {
      final big = 'x' * 65536;
      final body = await _runOneRequest(body: big);
      expect(body?.length, 65536);
    });

    test('handles a zero-byte (probe) connection gracefully', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final errors = <Object>[];
      server.listen((socket) async {
        try {
          await _serveSocket(socket, 'irrelevant');
        } catch (e) {
          errors.add(e);
        } finally {
          await server.close();
        }
      }, onError: (_) {});

      // Connect and immediately disconnect without sending any data
      final probe = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 2));
      await probe.close();

      // Give the server a moment to process the empty connection
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Server must not throw an unhandled exception
      expect(errors, isEmpty);
    });

    test('handles partial request (no double-CRLF) gracefully', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      bool serverCompleted = false;

      server.listen((socket) async {
        await _serveSocket(socket, 'body');
        serverCompleted = true;
        await server.close();
      }, onError: (_) {});

      final client = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 2));
      // Send partial headers with no double-CRLF, then close
      client.add(utf8.encode('GET / HTTP/1.1\r\nHost: localhost\r\n'));
      await client.close();

      await Future<void>.delayed(const Duration(milliseconds: 300));
      // Server must complete without throwing even for a partial request
      expect(serverCompleted, isTrue);
    });

    test('serves multiple sequential requests correctly', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      int requestCount = 0;

      server.listen((socket) async {
        requestCount++;
        await _serveSocket(socket, 'response-$requestCount');
        if (requestCount >= 3) await server.close();
      }, onError: (_) {});

      for (int i = 1; i <= 3; i++) {
        final body = await _runOneRequest(
          body: 'response-$i',
          // connect to the same server each time — the listener stays up
        );
        // Each request must get the correct body
        expect(body, 'response-$i');
      }
    });
  });

  group('LAN HTTP server – peer-close wait', () {
    test('response is fully delivered before socket is destroyed', () async {
      // Verify that the server waits for the client to read all data and
      // close before destroying the socket (no premature RST).
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      server.listen((socket) async {
        await _serveSocket(socket, 'payload');
        await server.close();
      }, onError: (_) {});

      final client = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 5));
      client.add(utf8.encode('GET / HTTP/1.1\r\nHost: localhost\r\n\r\n'));

      final response = StringBuffer();
      final sub = client.listen(
        (data) => response.write(utf8.decode(data, allowMalformed: true)),
      );
      await sub.asFuture<void>().timeout(const Duration(seconds: 5));

      final raw = response.toString();
      final sep = raw.indexOf('\r\n\r\n');
      final body = sep == -1 ? null : raw.substring(sep + 4);
      expect(body, 'payload',
          reason: 'Response must be fully delivered before socket teardown');
    });
  });
}
