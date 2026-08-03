/// Tests for [CollaborationServer]'s WebSocket side: HTTP upgrade handling
/// (`_handleWsSocket`), manual frame parsing (`_parseFrameHeader`,
/// `_extractPayload`, `_dispatchFrame`) and message routing
/// (`_processWsChunk`).
///
/// All tests use real loopback sockets and raw hand-built WebSocket frames so
/// the binary parsing logic is exercised exactly as in production.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/collaboration/model/sync_message.dart';
import 'package:yoloit/features/collaboration/services/collaboration_cipher.dart';
import 'package:yoloit/features/collaboration/services/collaboration_server.dart';

// ── Raw WebSocket test client ────────────────────────────────────────────────

/// Encodes one client→server WebSocket frame (FIN=1, optionally masked).
List<int> _encodeFrame(int opcode, List<int> payload, {bool masked = true}) {
  final frame = <int>[0x80 | opcode];
  final maskBit = masked ? 0x80 : 0;
  if (payload.length < 126) {
    frame.add(maskBit | payload.length);
  } else if (payload.length < 65536) {
    frame
      ..add(maskBit | 126)
      ..add((payload.length >> 8) & 0xFF)
      ..add(payload.length & 0xFF);
  } else {
    frame.add(maskBit | 127);
    for (int i = 7; i >= 0; i--) {
      frame.add((payload.length >> (i * 8)) & 0xFF);
    }
  }
  if (masked) {
    const mask = [0x11, 0x22, 0x33, 0x44];
    frame.addAll(mask);
    for (int i = 0; i < payload.length; i++) {
      frame.add(payload[i] ^ mask[i % 4]);
    }
  } else {
    frame.addAll(payload);
  }
  return frame;
}

/// A minimal WebSocket client speaking raw frames over a loopback socket.
/// Buffers everything the server sends and decodes complete frames.
class _TestWsClient {
  _TestWsClient._(this.socket);

  final Socket socket;
  final List<int> _rx = <int>[];
  final List<({int opcode, List<int> payload})> frames = [];
  String headerText = '';
  bool done = false;
  int? _headerEnd;

  static Future<_TestWsClient> connect(
    int port, {
    String key = 'dGhlIHNhbXBsZSBub25jZQ==',
    List<int> trailingBytes = const [],
  }) async {
    final socket = await Socket.connect( // ignore: close_sinks
      '127.0.0.1',
      port,
      timeout: const Duration(seconds: 5),
    );
    final client = _TestWsClient._(socket);
    socket.listen(
      client._onData,
      onDone: () => client.done = true,
      onError: (_) => client.done = true,
      cancelOnError: true,
    );
    socket.add(
      utf8.encode(
        'GET /chat HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Key: $key\r\n'
        'Sec-WebSocket-Version: 13\r\n'
        '\r\n',
      ),
    );
    if (trailingBytes.isNotEmpty) socket.add(trailingBytes);
    await _waitFor(() => client._headerEnd != null);
    return client;
  }

  void _onData(List<int> chunk) {
    _rx.addAll(chunk);
    if (_headerEnd == null) {
      for (int i = 0; i <= _rx.length - 4; i++) {
        if (_rx[i] == 13 &&
            _rx[i + 1] == 10 &&
            _rx[i + 2] == 13 &&
            _rx[i + 3] == 10) {
          _headerEnd = i + 4;
          headerText = utf8.decode(_rx.sublist(0, i + 4));
          final leftover = _rx.sublist(i + 4);
          _rx
            ..clear()
            ..addAll(leftover);
          break;
        }
      }
      if (_headerEnd == null) return;
    }
    _drainFrames();
  }

  void _drainFrames() {
    while (true) {
      if (_rx.length < 2) return;
      var len = _rx[1] & 0x7F;
      var offset = 2;
      if (len == 126) {
        if (_rx.length < 4) return;
        len = (_rx[2] << 8) | _rx[3];
        offset = 4;
      } else if (len == 127) {
        if (_rx.length < 10) return;
        len = 0;
        for (int i = 0; i < 8; i++) {
          len = (len << 8) | _rx[2 + i];
        }
        offset = 10;
      }
      if (_rx.length < offset + len) return;
      frames.add((opcode: _rx[0] & 0x0F, payload: _rx.sublist(offset, offset + len)));
      _rx.removeRange(0, offset + len);
    }
  }

  void sendText(String text, {bool masked = true}) =>
      sendFrame(0x1, utf8.encode(text), masked: masked);

  void sendFrame(int opcode, List<int> payload, {bool masked = true}) {
    socket.add(_encodeFrame(opcode, payload, masked: masked));
  }

  /// All decoded text-frame messages received so far.
  List<SyncMessage> messages() {
    final result = <SyncMessage>[];
    for (final frame in frames) {
      if (frame.opcode != 0x1) continue;
      final msg = SyncMessage.decode(utf8.decode(frame.payload));
      if (msg != null) result.add(msg);
    }
    return result;
  }

  /// Raw text payloads of all text frames received so far.
  List<String> texts() => [
        for (final frame in frames)
          if (frame.opcode == 0x1) utf8.decode(frame.payload),
      ];

  Future<void> dispose() async {
    try {
      socket.destroy();
    } catch (_) {}
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('CollaborationServer WebSocket', () {
    CollaborationServer? server;
    late int wsPort;
    late int httpPort;
    late List<({String clientId, SyncMessage msg})> received;
    final clients = <_TestWsClient>[];

    Future<void> startServer({CollaborationCipher? cipher}) async {
      wsPort = await _freePort();
      httpPort = await _freePort();
      server = CollaborationServer(
        onClientMessage: (id, msg) =>
            received.add((clientId: id, msg: msg)),
        port: wsPort,
        httpPort: httpPort,
        cipher: cipher,
      );
      await server!.start();
    }

    Future<_TestWsClient> connectClient({
      List<int> trailingBytes = const [],
    }) async {
      final client =
          await _TestWsClient.connect(wsPort, trailingBytes: trailingBytes);
      clients.add(client);
      return client;
    }

    setUp(() {
      received = [];
    });

    tearDown(() async {
      // Stop the server first so close frames are written to peers that are
      // still alive; destroying clients first would RST them and surface
      // broken-pipe write errors on the server sockets.
      await server?.stop();
      server = null;
      for (final client in clients) {
        await client.dispose();
      }
      clients.clear();
    });

    group('handshake (_handleWsSocket)', () {
      test('answers plain HTTP requests with a health-check 200', () async {
        await startServer();
        final raw = await Socket.connect('127.0.0.1', wsPort);
        var done = false;
        final buf = StringBuffer();
        raw.listen(
          (d) => buf.write(utf8.decode(d)),
          onDone: () => done = true,
          onError: (_) => done = true,
        );
        raw.add(utf8.encode('GET / HTTP/1.1\r\nHost: x\r\n\r\n'));
        await _waitFor(() => done);
        expect(buf.toString(), contains('200 OK'));
        expect(buf.toString(), contains('YoLoIT collaboration server'));
        raw.destroy();
      });

      test('completes the upgrade with a correct Sec-WebSocket-Accept',
          () async {
        await startServer();
        final client = await connectClient();
        expect(client.headerText, contains('101 Switching Protocols'));
        // RFC 6455 reference accept value for the sample key.
        expect(
          client.headerText,
          contains('Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo='),
        );
        await _waitFor(() => server!.clientCount == 1);
        // The new client receives the 'connected' broadcast.
        await _waitFor(
          () => client.messages().any((m) => m.type == SyncMessage.kConnected),
        );
        final connected = client
            .messages()
            .firstWhere((m) => m.type == SyncMessage.kConnected);
        expect(connected.payload['name'], 'Remote');
      });

      test('destroys the socket when the upgrade key is missing', () async {
        await startServer();
        final raw = await Socket.connect('127.0.0.1', wsPort);
        var done = false;
        raw.listen((_) {}, onDone: () => done = true, onError: (_) => done = true);
        raw.add(
          utf8.encode(
            'GET / HTTP/1.1\r\n'
            'Host: x\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            '\r\n',
          ),
        );
        await _waitFor(() => done);
        expect(server!.clientCount, 0);
        raw.destroy();
      });

      test('destroys the socket when headers exceed 64 KB without a boundary',
          () async {
        await startServer();
        final raw = await Socket.connect('127.0.0.1', wsPort);
        var done = false;
        raw.listen((_) {}, onDone: () => done = true, onError: (_) => done = true);
        raw.add(List<int>.filled(70000, 65)); // 'A' * 70000, no CRLF
        await _waitFor(() => done);
        raw.destroy();
      });

      test('handles headers split across multiple TCP chunks', () async {
        await startServer();
        final raw = await Socket.connect('127.0.0.1', wsPort);
        final buf = StringBuffer();
        raw.listen(
          (d) => buf.write(utf8.decode(d, allowMalformed: true)),
          onError: (_) {},
        );
        final request = utf8.encode(
          'GET / HTTP/1.1\r\n'
          'Host: x\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          '\r\n',
        );
        raw.add(request.sublist(0, 40));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        raw.add(request.sublist(40));
        await _waitFor(() => buf.toString().contains('101 Switching'));
        await _waitFor(() => server!.clientCount == 1);
        raw.destroy();
      });

      test('processes a frame delivered in the same chunk as the handshake',
          () async {
        await startServer();
        final hello = SyncMessage.hello(clientId: 'x', clientName: 'Early');
        await connectClient(
          trailingBytes: _encodeFrame(0x1, utf8.encode(hello.encode())),
        );
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kHello),
        );
        expect(received.first.msg.payload['name'], 'Early');
      });
    });

    group('frame parsing & dispatch (_processWsChunk)', () {
      test('masked hello updates peer meta and broadcasts connected/presence',
          () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendText(
          SyncMessage.hello(
            clientId: 'x',
            clientName: 'Alice',
            clientColor: '#FF0000',
          ).encode(),
        );
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kHello),
        );
        await _waitFor(
          () => client.messages().any((m) => m.type == SyncMessage.kPresence),
        );
        final messages = client.messages();
        final connected = messages.lastWhere(
          (m) => m.type == SyncMessage.kConnected,
        );
        expect(connected.payload['name'], 'Alice');
        expect(connected.payload['color'], '#FF0000');
        final presence =
            messages.firstWhere((m) => m.type == SyncMessage.kPresence);
        final peers = presence.payload['peers'] as List<dynamic>;
        expect(peers, hasLength(1));
        expect((peers.first as Map<String, dynamic>)['name'], 'Alice');
      });

      test('assigns a palette colour when the hello omits one', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendText('{"type":"hello","name":"Bob"}');
        await _waitFor(
          () => client
              .messages()
              .any((m) => m.type == SyncMessage.kPresence),
        );
        final connected = client
            .messages()
            .lastWhere((m) => m.type == SyncMessage.kConnected);
        expect(connected.payload['name'], 'Bob');
        expect(connected.payload['color'] as String, startsWith('#'));
      });

      test('accepts unmasked text frames', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendText(
          SyncMessage.move('n1', 1, 2).encode(),
          masked: false,
        );
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
        );
      });

      test('decodes binary frames as UTF-8 text', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendFrame(
          0x2,
          utf8.encode(SyncMessage.move('n2', 3, 4).encode()),
        );
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
        );
        expect(received.first.msg.payload['id'], 'n2');
      });

      test('replies to a ping frame with a pong', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.frames.clear();
        client.sendFrame(0x9, const []);
        await _waitFor(() => client.frames.any((f) => f.opcode == 0xA));
      });

      test('ignores pong and unknown opcodes without disconnecting', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendFrame(0xA, const []);
        client.sendFrame(0x3, utf8.encode('reserved'));
        // Still usable afterwards.
        client.sendText(SyncMessage.move('n3', 5, 6).encode());
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
        );
        expect(server!.clientCount, 1);
      });

      test('handles close frames: echoes close and disconnects the peer',
          () async {
        await startServer();
        final a = await connectClient();
        final b = await connectClient();
        await _waitFor(() => server!.clientCount == 2);
        a.sendFrame(0x8, const []);
        // A receives the echoed close frame.
        await _waitFor(() => a.frames.any((f) => f.opcode == 0x8));
        // The server drops A and notifies B.
        await _waitFor(() => server!.clientCount == 1);
        await _waitFor(
          () => b.messages().any((m) => m.type == SyncMessage.kDisconnected),
        );
      });

      test('handles abrupt socket teardown via onDone', () async {
        await startServer();
        final a = await connectClient();
        final b = await connectClient();
        await _waitFor(() => server!.clientCount == 2);
        a.socket.destroy();
        await _waitFor(() => server!.clientCount == 1);
        await _waitFor(
          () => b.messages().any((m) => m.type == SyncMessage.kDisconnected),
        );
      });

      test('parses 16-bit extended payload length (126)', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        final big = 'y' * 300;
        client.sendText(
          const SyncMessage(type: 'custom', payload: {}).encode() +
              big, // invalid JSON but > 126 bytes
        );
        // Invalid JSON is dropped; verify with a valid >126-byte message too.
        final msg = SyncMessage(
          type: 'custom.big',
          payload: {'data': big},
        );
        client.sendText(msg.encode());
        await _waitFor(
          () => received.any((r) => r.msg.type == 'custom.big'),
        );
        final r = received.firstWhere((r) => r.msg.type == 'custom.big');
        expect((r.msg.payload['data'] as String).length, 300);
      });

      test('parses 64-bit extended payload length (127)', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        final msg = SyncMessage(
          type: 'custom.huge',
          payload: {'data': 'x' * 70000},
        );
        client.sendText(msg.encode());
        await _waitFor(
          () => received.any((r) => r.msg.type == 'custom.huge'),
        );
        final r = received.firstWhere((r) => r.msg.type == 'custom.huge');
        expect((r.msg.payload['data'] as String).length, 70000);
      });

      test('handles frames split across multiple TCP chunks', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        final frame =
            _encodeFrame(0x1, utf8.encode(SyncMessage.move('n4', 7, 8).encode()));
        // Send byte-by-byte in three slices with delays in between.
        client.socket.add(frame.sublist(0, 2));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        client.socket.add(frame.sublist(2, 6));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        client.socket.add(frame.sublist(6));
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
        );
        expect(received.first.msg.payload['id'], 'n4');
      });

      test('processes two frames delivered in a single TCP chunk', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        final f1 = _encodeFrame(
          0x1,
          utf8.encode(SyncMessage.move('a', 1, 1).encode()),
        );
        final f2 = _encodeFrame(
          0x1,
          utf8.encode(SyncMessage.move('b', 2, 2).encode()),
        );
        client.socket.add(f1 + f2);
        await _waitFor(
          () => received
              .where((r) => r.msg.type == SyncMessage.kDeltaMove)
              .length ==
              2,
        );
      });

      test('silently drops invalid JSON payloads', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendText('this is not json');
        client.sendText(SyncMessage.move('n5', 9, 9).encode());
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
        );
        // Only the valid message was delivered.
        expect(received, hasLength(1));
      });

      test('mirrors delta messages to other guests only', () async {
        await startServer();
        final a = await connectClient();
        final b = await connectClient();
        await _waitFor(() => server!.clientCount == 2);
        final before = b.messages().length;
        a.sendText(SyncMessage.move('node', 10, 20).encode());
        await _waitFor(
          () => b
              .messages()
              .skip(before)
              .any((m) => m.type == SyncMessage.kDeltaMove),
        );
        // The sender must not receive its own delta back.
        expect(
          a.messages().where((m) => m.type == SyncMessage.kDeltaMove),
          isEmpty,
        );
        // Host callback still fired.
        expect(
          received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
          isTrue,
        );
      });

      test('relays cursor moves to everyone except the sender', () async {
        await startServer();
        final a = await connectClient();
        final b = await connectClient();
        await _waitFor(() => server!.clientCount == 2);
        a.sendText(
          SyncMessage.cursorMove(
            'a',
            x: 100,
            y: 200,
            color: '#FFF',
            name: 'A',
          ).encode(),
        );
        await _waitFor(
          () => b.messages().any((m) => m.type == SyncMessage.kCursorMove),
        );
        expect(
          a.messages().where((m) => m.type == SyncMessage.kCursorMove),
          isEmpty,
        );
        expect(
          received.any((r) => r.msg.type == SyncMessage.kCursorMove),
          isTrue,
        );
      });

      test('sendTo delivers a message to one specific client', () async {
        await startServer();
        final a = await connectClient();
        final b = await connectClient();
        await _waitFor(() => server!.clientCount == 2);
        a.sendText(SyncMessage.hello(clientId: 'x', clientName: 'A').encode());
        await _waitFor(() => received.isNotEmpty);
        final aId = received.first.clientId;
        server!.sendTo(aId, SyncMessage.presence(const []));
        await _waitFor(
          () => a.messages().any((m) => m.type == SyncMessage.kPresence),
        );
        // Unknown ids are a no-op and must not throw.
        server!.sendTo('no-such-client', SyncMessage.presence(const []));
        expect(b, isNotNull);
      });
    });

    group('encryption (_fromWire / _toWire)', () {
      test('drops e:-prefixed frames when no cipher is configured', () async {
        await startServer();
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendText('e:bm90LXZhbGlk');
        client.sendText(SyncMessage.move('n6', 1, 1).encode());
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
        );
        expect(received, hasLength(1));
      });

      test('decrypts encrypted frames and encrypts broadcasts', () async {
        final cipher = CollaborationCipher.fromBytes(List<int>.filled(32, 7));
        await startServer(cipher: cipher);
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        // The connected broadcast is encrypted on the wire.
        await _waitFor(() => client.texts().isNotEmpty);
        expect(client.texts().first, startsWith('e:'));
        expect(
          SyncMessage.decode(cipher.decryptWire(client.texts().first)),
          isNotNull,
        );
        // Client → server encrypted hello is decrypted and dispatched.
        client.sendText(
          cipher.encryptWire(
            SyncMessage.hello(clientId: 'x', clientName: 'Cipher').encode(),
          ),
        );
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kHello),
        );
        expect(received.first.msg.payload['name'], 'Cipher');
      });

      test('drops frames encrypted with the wrong key', () async {
        final serverCipher =
            CollaborationCipher.fromBytes(List<int>.filled(32, 1));
        final wrongCipher =
            CollaborationCipher.fromBytes(List<int>.filled(32, 2));
        await startServer(cipher: serverCipher);
        final client = await connectClient();
        await _waitFor(() => server!.clientCount == 1);
        client.sendText(
          wrongCipher.encryptWire(
            SyncMessage.hello(clientId: 'x', clientName: 'Evil').encode(),
          ),
        );
        // Give the server a moment, then verify nothing was delivered and
        // the connection still works (plain JSON is still accepted).
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(received, isEmpty);
        client.sendText(SyncMessage.move('n7', 1, 1).encode());
        await _waitFor(
          () => received.any((r) => r.msg.type == SyncMessage.kDeltaMove),
        );
      });
    });
  });
}
