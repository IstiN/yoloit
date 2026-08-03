import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:yoloit/features/collaboration/collaboration_ports.dart';
import 'package:yoloit/features/collaboration/model/sync_message.dart';
import 'package:yoloit/features/collaboration/services/collaboration_cipher.dart';

/// WebSocket server (port [port]) + static HTTP server (port [httpPort]).
///
/// Uses plain [ServerSocket] — NOT [HttpServer] — to avoid a macOS/Dart bug
/// where dart:_http calls setOption(TCP_NODELAY) on accepted sockets and
/// gets errno=22 (EINVAL) for connections coming in on the LAN interface.
///
/// WebSocket frames are parsed manually so the socket's stream subscription
/// is never cancelled (cancelling it after reading headers permanently moves
/// the stream to _STATE_CANCELED, preventing WebSocket.fromUpgradedSocket
/// from re-subscribing — "Bad state: Stream has already been listened to").
class CollaborationServer {
  CollaborationServer({
    required this.onClientMessage,
    this.port = kDefaultWsPort,
    this.httpPort = kDefaultHttpPort,
    this.cipher,
  });

  final void Function(String clientId, SyncMessage msg) onClientMessage;
  final int port;
  final int httpPort;

  /// When non-null, ALL outgoing WS frames are AES-256-GCM encrypted and all
  /// incoming frames are expected to be encrypted.  Plain frames from clients
  /// are still decoded (they just won't decrypt and SyncMessage.decode will
  /// handle them gracefully).
  CollaborationCipher? cipher;

  ServerSocket? _wsServerSocket;
  ServerSocket? _staticServerSocket;
  final Map<String, _WsClient> _clients = {};
  /// Per-client metadata (name, colour) accumulated as hellos arrive.
  final Map<String, _PeerMeta> _peerMeta = {};
  String _resolvedIp = '127.0.0.1';

  /// Colour palette for assigning distinct colours to guests.
  static const _palette = [
    '#60A5FA', '#34D399', '#F87171', '#FBBF24',
    '#A78BFA', '#F472B6', '#38BDF8', '#4ADE80',
  ];
  int _nextColor = 0;

  bool get isRunning => _wsServerSocket != null;
  int get clientCount => _clients.length;

  /// Returns the address string "ip:port" of the WS server.
  Future<String> start() async {
    _wsServerSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    try {
      _wsServerSocket!.listen((s) {
        try {
          _handleWsSocket(s);
        } catch (_) {
          _destroySocket(s);
        }
      }, onError: (_) {});
      _resolvedIp = await _localIp();
      await _ensureWebClientInstalled();
      await _startStaticServer();
      return '$_resolvedIp:$port';
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  /// URL to share with remote devices on the same LAN.
  String get webClientUrl {
    if (_staticServerSocket == null) return '';
    return Uri(
      scheme: 'http',
      host: _resolvedIp,
      port: httpPort,
      queryParameters: {'wsPort': '$port'},
    ).toString();
  }

  /// URL to open in a browser on THIS machine (avoids macOS self-connect bug).
  String get localUrl {
    if (_staticServerSocket == null) return '';
    return Uri(
      scheme: 'http',
      host: 'localhost',
      port: httpPort,
      queryParameters: {'wsPort': '$port'},
    ).toString();
  }

  Future<void> stop() async {
    // Iterate over a copy: closing a client can trigger _onDisconnect
    // callbacks that mutate _clients concurrently.
    for (final client in List<_WsClient>.of(_clients.values)) {
      try {
        client.closeNow();
      } catch (_) {}
    }
    _clients.clear();
    await _wsServerSocket?.close();
    await _staticServerSocket?.close();
    _wsServerSocket = null;
    _staticServerSocket = null;
  }

  void broadcastRaw(SyncMessage msg, {String? exclude}) {
    final wire = _toWire(msg);
    for (final entry in _clients.entries) {
      if (entry.key == exclude) continue;
      try {
        entry.value.send(wire);
      } catch (_) {}
    }
  }

  void sendTo(String clientId, SyncMessage msg) {
    try {
      _clients[clientId]?.send(_toWire(msg));
    } catch (_) {}
  }

  /// Encodes a message to the wire format (encrypted if cipher is active).
  String _toWire(SyncMessage msg) {
    final json = msg.encode();
    return cipher != null ? cipher!.encryptWire(json) : json;
  }

  /// Decodes a raw wire frame to its JSON string (decrypts if needed).
  /// Returns `null` if decryption fails (wrong key / tampered frame).
  String? _fromWire(String raw) {
    if (raw.startsWith('e:')) {
      return cipher?.decryptWire(raw); // null if no cipher or bad key
    }
    return raw; // plain JSON (legacy / no key configured)
  }

  /// Broadcasts the current peer list to all clients.
  void _broadcastPresence() {
    final peers = _peerMeta.entries
        .map((e) => {'id': e.key, 'name': e.value.name, 'color': e.value.color})
        .toList();
    broadcastRaw(SyncMessage.presence(peers));
  }

  // ── WebSocket server (single subscription, manual frame parsing) ───────────

  /// Sets up a single [socket.listen] that handles both:
  ///  1. HTTP header phase  → parses headers, sends 101 upgrade
  ///  2. WebSocket phase    → decodes frames, dispatches messages
  ///
  /// We never cancel the stream subscription so the stream never enters
  /// _STATE_CANCELED (which would block any future listen call).
  void _handleWsSocket(Socket socket) {
    final buf = <int>[]; // accumulates header bytes
    bool upgraded = false;
    String? clientId;
    _WsClient? client;

    socket.listen(
      (chunk) {
        if (!upgraded) {
          // ── Header phase ──────────────────────────────────────────────────
          buf.addAll(chunk);

          // Find \r\n\r\n
          final endIdx = _findHttpBoundary(buf);
          if (endIdx == null) {
            if (buf.length > 65536) socket.destroy();
            return; // need more data
          }

          final headers = _parseHeaders(buf.sublist(0, endIdx));
          final leftover = buf.sublist(endIdx);

          final isUpgrade =
              (headers['upgrade'] ?? '').toLowerCase() == 'websocket';

          if (!isUpgrade) {
            // Health-check ping
            _writeRaw(
              socket,
              'HTTP/1.1 200 OK\r\n'
              'Access-Control-Allow-Origin: *\r\n'
              'Content-Type: text/plain\r\n'
              'Content-Length: 27\r\n'
              'Connection: close\r\n'
              '\r\n'
              'YoLoIT collaboration server',
            );
            // flush/close can throw on LAN sockets (macOS EINVAL); swallow.
            socket.flush().catchError((_) {}).whenComplete(() {
              try { socket.destroy(); } catch (_) {}
            });
            return;
          }

          final key = headers['sec-websocket-key'];
          if (key == null) {
            socket.destroy();
            return;
          }

          // Compute Sec-WebSocket-Accept
          final accept = base64.encode(
            sha1
                .convert(
                  utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
                )
                .bytes,
          );
          _writeRaw(
            socket,
            'HTTP/1.1 101 Switching Protocols\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Accept: $accept\r\n'
            '\r\n',
          );

          upgraded = true;
          clientId = 'c_${DateTime.now().millisecondsSinceEpoch}';
          client = _WsClient(socket);
          _clients[clientId!] = client!;

          if (leftover.isNotEmpty) {
            _processWsChunk(client!, clientId!, leftover);
          }
          broadcastRaw(SyncMessage.connected(clientId!, 'Remote'));
        } else if (client != null) {
          // ── WebSocket frame phase ─────────────────────────────────────────
          _processWsChunk(client!, clientId!, chunk);
        }
      },
      onDone: () {
        if (clientId != null) _onDisconnect(clientId!);
      },
      onError: (_) {
        if (clientId != null) _onDisconnect(clientId!);
        _destroySocket(socket);
      },
      cancelOnError: true,
    );
  }

  void _processWsChunk(_WsClient client, String clientId, List<int> chunk) {
    for (final raw in client.processChunk(chunk)) {
      if (raw.isEmpty) {
        if (client.isClosed) {
          _onDisconnect(clientId);
          return;
        }
        continue;
      }
      // Decrypt if the frame is encrypted, else treat as plain JSON.
      final text = _fromWire(raw);
      if (text == null) continue; // wrong key / tampered — drop silently
      final msg = SyncMessage.decode(text);
      if (msg == null) continue;

      // Update peer metadata when hello is received.
      if (msg.type == SyncMessage.kHello) {
        final name  = (msg.payload['name']  as String?) ?? 'Guest';
        final color = (msg.payload['color'] as String?)
            ?? _palette[_nextColor++ % _palette.length];
        _peerMeta[clientId] = _PeerMeta(name: name, color: color);
        // Rebroadcast connected with resolved name/color.
        broadcastRaw(SyncMessage.connected(clientId, name, color: color));
        _broadcastPresence();
      }

      // Relay cursor moves to everyone except the sender.
      if (msg.type == SyncMessage.kCursorMove) {
        broadcastRaw(msg, exclude: clientId);
        // Also deliver to host via onClientMessage so it can render the cursor.
      }

      onClientMessage(clientId, msg);
      // Mirror deltas to all other guests.
      if (msg.type.startsWith('delta.')) broadcastRaw(msg, exclude: clientId);
    }
  }

  void _onDisconnect(String clientId) {
    _clients.remove(clientId);
    _peerMeta.remove(clientId);
    broadcastRaw(SyncMessage.disconnected(clientId));
    _broadcastPresence();
  }

  // ── Static HTTP file server ────────────────────────────────────────────────

  Future<void> _startStaticServer() async {
    final webDir = await _findWebClientDir();
    if (webDir == null) return;
    _staticServerSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      httpPort,
    );
    _staticServerSocket!.listen(
      (socket) => _serveHttpSocket(socket, webDir).catchError((_) {
        try { socket.destroy(); } catch (_) {}
      }),
      onError: (_) {},
    );
    // Trigger macOS "Local Network" privacy dialog.  On macOS 12+ the OS
    // silently kills accepted sockets from LAN IPs until the user grants
    // Local Network access.  The dialog ONLY appears when the app makes an
    // OUTGOING connection to a LAN address.  We do a fire-and-forget connect
    // to ourselves via the LAN IP (not localhost) so the OS shows the prompt
    // on first launch; subsequent launches are already approved and succeed.
    unawaited(_triggerLocalNetworkPermission());
  }

  /// Fire-and-forget: connect to our own HTTP port via the LAN IP so macOS
  /// shows the Local Network privacy alert.  Errors are expected and silently
  /// swallowed; the only purpose is to trigger the OS permission dialog.
  Future<void> _triggerLocalNetworkPermission() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final ip = _resolvedIp;
    if (ip == 'localhost' || ip == '127.0.0.1') return;
    try {
      final s = await Socket.connect(
        ip, httpPort,
        timeout: const Duration(seconds: 3),
      );
      await s.close();
    } catch (_) {
      // Expected on first launch; the dialog will have been shown.
    }
  }

  /// Serves one HTTP request on [socket] using the same stream-listener pattern
  /// as [_handleWsSocket] — no `await for`, no subscription cancel.
  static Future<void> _serveHttpSocket(Socket socket, String webDir) async {
    final reader = _HttpRequestReader(socket)..listen();
    await reader.requestDone.future;
    final buf = reader.buf;
    if (buf.length < 4) { socket.destroy(); return; }

    final headers = _parseHeaders(buf);
    final method = headers['_method'] ?? 'GET';
    final path = headers['_path'] ?? '/';

    if (method == 'OPTIONS') {
      await _writeOptionsResponse(socket, reader.peerEof);
      return;
    }

    await _serveStaticFile(socket, webDir, path, reader.peerEof);
  }

  /// Answers a CORS preflight (OPTIONS) request and closes the socket.
  static Future<void> _writeOptionsResponse(
    Socket socket,
    Completer<void> peerEof,
  ) async {
    _writeRaw(
      socket,
      'HTTP/1.1 204 No Content\r\n'
      'Access-Control-Allow-Origin: *\r\n'
      'Access-Control-Allow-Methods: GET, OPTIONS\r\n'
      'Access-Control-Allow-Headers: Content-Type\r\n'
      'Connection: close\r\n'
      '\r\n',
    );
    await _closeAfterFlush(socket, peerEof);
  }

  /// Serves the file at [path] from [webDir], falling back to index.html
  /// for extension-less or missing paths (SPA-style routing).
  static Future<void> _serveStaticFile(
    Socket socket,
    String webDir,
    String path,
    Completer<void> peerEof,
  ) async {
    var filePath = path;
    if (filePath == '/' || filePath.isEmpty || !filePath.contains('.')) {
      filePath = '/index.html';
    }
    final safePath = Uri.decodeFull(filePath.split('?').first)
        .replaceAll(RegExp(r'\.\.[\\/]'), '');

    var file = File('$webDir$safePath');
    if (!await file.exists()) file = File('$webDir/index.html');

    final bytes = await file.readAsBytes();
    final mimeStr = _mimeString(safePath);

    _writeRaw(
      socket,
      'HTTP/1.1 200 OK\r\n'
      'Access-Control-Allow-Origin: *\r\n'
      'Cache-Control: no-store, no-cache, must-revalidate\r\n'
      'Content-Type: $mimeStr\r\n'
      'Content-Length: ${bytes.length}\r\n'
      'Connection: close\r\n'
      '\r\n',
    );
    try { socket.add(bytes); } catch (_) {}
    await _closeAfterFlush(socket, peerEof);
  }

  /// Flushes [socket] and closes it gracefully.
  ///
  /// On macOS, [socket.close()] (shutdown SHUT_WR) throws EINVAL (errno=22)
  /// for sockets accepted on a LAN interface (non-loopback). On loopback it
  /// works fine.
  ///
  /// Strategy:
  ///  1. Flush buffered writes to the OS.
  ///  2. Try socket.close() — succeeds on loopback, throws EINVAL on LAN.
  ///  3. If close() throws: wait for the peer to send its FIN (which happens
  ///     once the peer has read all Content-Length bytes), then destroy().
  ///     A 10-second timeout guards against peers that never close.
  static Future<void> _closeAfterFlush(
    Socket socket,
    Completer<void> peerEof,
  ) async {
    try { await socket.flush(); } catch (_) {}
    try {
      await socket.close();
      return; // graceful half-close succeeded (loopback / most platforms)
    } catch (_) {
      // macOS EINVAL on LAN sockets — fall through to peer-wait approach
    }
    await peerEof.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    try { socket.destroy(); } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns the index after `\r\n\r\n` if found, otherwise `null`.
  static int? _findHttpBoundary(List<int> buf) {
    for (int i = 0; i <= buf.length - 4; i++) {
      if (buf[i] == 13 &&
          buf[i + 1] == 10 &&
          buf[i + 2] == 13 &&
          buf[i + 3] == 10) {
        return i + 4;
      }
    }
    return null;
  }

  /// Parses raw header bytes into a map (lowercase keys + '_method'/'_path').
  static Map<String, String> _parseHeaders(List<int> rawBytes) {
    final text = utf8.decode(rawBytes, allowMalformed: true);
    final lines = text.split('\r\n');
    final result = <String, String>{};
    if (lines.isEmpty) return result;

    final parts = lines[0].split(' ');
    result['_method'] = parts.isNotEmpty ? parts[0] : 'GET';
    result['_path'] = parts.length > 1 ? parts[1] : '/';

    for (int i = 1; i < lines.length; i++) {
      final colon = lines[i].indexOf(':');
      if (colon < 0) continue;
      result[lines[i].substring(0, colon).trim().toLowerCase()] = lines[i]
          .substring(colon + 1)
          .trim();
    }
    return result;
  }

  /// Reads HTTP request headers from [socket] using a single await-for loop.
  /// Safe to use when you won't re-subscribe (e.g. static HTTP handler).
  @visibleForTesting
  static Future<Map<String, String>?> readHeaders(Socket socket) async {
    final buf = <int>[];
    try {
      await for (final chunk in socket) {
        buf.addAll(chunk);
        // Search entire buffer for \r\n\r\n (handles split-chunk delivery)
        final boundary = _findHttpBoundary(buf);
        if (boundary != null) {
          return _parseHeaders(buf.sublist(0, boundary));
        }
        if (buf.length > 65536) return null;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static void _writeRaw(Socket socket, String data) {
    try {
      socket.add(utf8.encode(data));
    } catch (_) {}
  }

  static void _destroySocket(Socket s) {
    try {
      s.destroy();
    } catch (_) {}
  }

  static String _mimeString(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'html' => 'text/html; charset=utf-8',
      'js' => 'application/javascript; charset=utf-8',
      'css' => 'text/css; charset=utf-8',
      'json' => 'application/json',
      'png' => 'image/png',
      'ico' => 'image/x-icon',
      'svg' => 'image/svg+xml',
      'wasm' => 'application/wasm',
      _ => 'application/octet-stream',
    };
  }

  // ── Web client installation ────────────────────────────────────────────────

  static Future<void> _ensureWebClientInstalled() => installWebClient(
        home: Platform.environment['HOME'],
        exe: Platform.resolvedExecutable,
      );

  /// Test-visible implementation of [_ensureWebClientInstalled] with the
  /// home directory and executable path passed in explicitly.
  @visibleForTesting
  static Future<void> installWebClient({
    required String? home,
    required String exe,
  }) async {
    if (home == null) return;
    final dest = '$home/.yoloit/web_client';
    if (await File('$dest/index.html').exists()) return;

    var dir = File(exe).parent;
    for (int i = 0; i < 12; i++) {
      final candidate = '${dir.path}/build/web';
      if (await File('$candidate/index.html').exists()) {
        try {
          await Directory(dest).create(recursive: true);
          await _copyDirectory(Directory(candidate), Directory(dest));
        } catch (_) {}
        return;
      }
      dir = dir.parent;
    }
  }

  static Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      // Directory URIs end with '/', so the last segment can be empty.
      final name =
          entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final target = '${dest.path}/$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  /// When set, overrides all web-client directory discovery (tests only).
  @visibleForTesting
  static String? debugWebClientDirOverride;

  static Future<String?> _findWebClientDir() {
    final override = debugWebClientDirOverride;
    if (override != null) return Future<String?>.value(override);
    return findWebClientDir(
      home: Platform.environment['HOME'] ?? '',
      exe: Platform.resolvedExecutable,
      currentDir: Directory.current.path,
    );
  }

  /// Test-visible implementation of [_findWebClientDir] with the environment
  /// values (home dir, executable path, working dir) passed in explicitly.
  @visibleForTesting
  static Future<String?> findWebClientDir({
    required String home,
    required String exe,
    required String currentDir,
  }) async {
    final appDir = File(exe).parent.path;

    // Release: web client is bundled inside .app/Contents/Resources/web_client
    if (kReleaseMode) {
      final path = '$appDir/../Resources/web_client';
      if (await File('$path/index.html').exists()) return _resolved(path);
      return null;
    }

    // Debug: check well-known dev locations, then walk up to find build/web
    final devCandidates = [
      '$appDir/../Resources/web_client',
      '$appDir/web_client',
      '$home/.yoloit/web_client',
      '$currentDir/build/web',
    ];
    for (final path in devCandidates) {
      if (await File('$path/index.html').exists()) return _resolved(path);
    }
    // Walk up from executable to find build/web in the repo
    var dir = File(exe).parent;
    for (int i = 0; i < 12; i++) {
      final path = '${dir.path}/build/web';
      if (await File('$path/index.html').exists()) return _resolved(path);
      dir = dir.parent;
    }
    return null;
  }

  static String _resolved(String path) =>
      Directory(path).resolveSymbolicLinksSync();

  static Future<String> _localIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return '127.0.0.1';
  }
}

// ── Peer metadata ──────────────────────────────────────────────────────────

class _PeerMeta {
  const _PeerMeta({required this.name, required this.color});
  final String name;
  final String color;
}

// ── Manual WebSocket client (no dart:io WebSocket, avoids stream re-sub bug) ──

class _WsClient {
  _WsClient(this._socket);

  final Socket _socket;
  final List<int> _rxBuf = [];
  bool _closed = false;

  bool get isClosed => _closed;

  /// Send a text message as a WebSocket text frame (server→client, unmasked).
  void send(String text) {
    if (_closed) return;
    try {
      _socket.add(_encodeTextFrame(text));
    } catch (_) {}
  }

  /// Send a close frame and destroy the underlying socket.
  void closeNow() {
    if (_closed) return;
    _closed = true;
    try {
      _socket.add(const [0x88, 0x00]); // close frame, no payload
      _socket.destroy();
    } catch (_) {}
  }

  /// Accumulate [chunk] and return all fully received text messages.
  List<String> processChunk(List<int> chunk) {
    _rxBuf.addAll(chunk);
    final messages = <String>[];
    while (true) {
      final result = _tryExtractFrame();
      if (result == null) break;
      messages.add(result);
    }
    return messages;
  }

  /// Tries to decode one complete WebSocket frame from [_rxBuf].
  /// Returns the decoded text ('' for control frames), or null if incomplete.
  String? _tryExtractFrame() {
    final header = _parseFrameHeader();
    if (header == null) return null;

    final maskLen = header.masked ? 4 : 0;
    final totalLen = header.offset + maskLen + header.payloadLen;
    if (_rxBuf.length < totalLen) return null;

    final payload = _extractPayload(header, maskLen, totalLen);

    _rxBuf.removeRange(0, totalLen);

    return _dispatchFrame(header.opcode, payload);
  }

  /// Parses the frame header from [_rxBuf], or returns null if incomplete.
  ({int opcode, bool masked, int payloadLen, int offset})? _parseFrameHeader() {
    if (_rxBuf.length < 2) return null;

    final b0 = _rxBuf[0];
    final b1 = _rxBuf[1];
    final opcode = b0 & 0x0F;
    final masked = (b1 & 0x80) != 0;
    int payloadLen = b1 & 0x7F;
    int offset = 2;

    if (payloadLen == 126) {
      if (_rxBuf.length < 4) return null;
      payloadLen = (_rxBuf[2] << 8) | _rxBuf[3];
      offset = 4;
    } else if (payloadLen == 127) {
      if (_rxBuf.length < 10) return null;
      payloadLen = 0;
      for (int i = 0; i < 8; i++) {
        payloadLen = (payloadLen << 8) | _rxBuf[2 + i];
      }
      offset = 10;
    }

    return (opcode: opcode, masked: masked, payloadLen: payloadLen, offset: offset);
  }

  /// Copies the payload bytes out of [_rxBuf] and unmasks them if needed.
  List<int> _extractPayload(
    ({int opcode, bool masked, int payloadLen, int offset}) header,
    int maskLen,
    int totalLen,
  ) {
    final payload = List<int>.from(
      _rxBuf.sublist(header.offset + maskLen, totalLen),
    );
    if (header.masked) {
      final mask = _rxBuf.sublist(header.offset, header.offset + 4);
      for (int i = 0; i < payload.length; i++) {
        payload[i] ^= mask[i % 4];
      }
    }
    return payload;
  }

  /// Handles a fully received frame by opcode and returns its text payload.
  String _dispatchFrame(int opcode, List<int> payload) {
    switch (opcode) {
      case 0x8: // Close
        _closed = true;
        try {
          _socket.add(const [0x88, 0x00]);
          _socket.close();
        } catch (_) {}
        return '';
      case 0x9: // Ping → Pong
        try {
          _socket.add(const [0x8A, 0x00]);
        } catch (_) {}
        return '';
      case 0xA: // Pong
        return '';
      case 0x1: // Text
      case 0x2: // Binary (treated as UTF-8 text)
        return utf8.decode(payload, allowMalformed: true);
      default:
        return '';
    }
  }

  static List<int> _encodeTextFrame(String text) {
    final payload = utf8.encode(text);
    final frame = <int>[0x81]; // FIN=1, opcode=1 (text)
    if (payload.length < 126) {
      frame.add(payload.length);
    } else if (payload.length < 65536) {
      frame.add(126);
      frame.add((payload.length >> 8) & 0xFF);
      frame.add(payload.length & 0xFF);
    } else {
      frame.add(127);
      for (int i = 7; i >= 0; i--) {
        frame.add((payload.length >> (i * 8)) & 0xFF);
      }
    }
    frame.addAll(payload);
    return frame;
  }
}

/// Buffers one incoming HTTP request on a socket until the request headers
/// are complete (or the peer errors out / closes).
///
/// Two completers: one fires when we have the full request headers, the
/// other fires when the peer closes its write side (FIN received).
class _HttpRequestReader {
  _HttpRequestReader(this._socket);

  final Socket _socket;

  /// Fires when we have the full request headers.
  final Completer<void> requestDone = Completer<void>();

  /// Fires when the peer closes its write side (FIN received).
  final Completer<void> peerEof = Completer<void>();

  /// Raw request bytes received so far.
  final List<int> buf = <int>[];

  void listen() {
    _socket.listen(
      _onChunk,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onChunk(List<int> chunk) {
    if (requestDone.isCompleted) return;
    buf.addAll(chunk);
    if (CollaborationServer._findHttpBoundary(buf) != null) {
      requestDone.complete();
      return;
    }
    if (buf.length > 65536) requestDone.complete();
  }

  void _onError(Object _) {
    if (!requestDone.isCompleted) requestDone.complete();
    if (!peerEof.isCompleted) peerEof.complete();
  }

  void _onDone() {
    if (!requestDone.isCompleted) requestDone.complete();
    if (!peerEof.isCompleted) peerEof.complete();
  }
}
