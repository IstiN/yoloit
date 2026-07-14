import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yoloit/core/remote/board_share_server_vm.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

/// Status of the outbound relay connection to a yoloit-hub.
enum BoardRelayStatus { disconnected, connecting, connected }

/// A client that connects a desktop YoLoIT instance to a yoloit-hub relay so
/// mobile / browser clients can reach its boards without any inbound network
/// connectivity on this machine.
///
/// The hub proxies every HTTP request over the outbound WebSocket:
///   hub → device: {"id":"...","method":"GET","path":"/api/boards",...}
///   device → hub: {"id":"...","status":200,"body":"..."}
class BoardRelayClient {
  BoardRelayClient._();

  static final BoardRelayClient instance = BoardRelayClient._();

  final ValueNotifier<BoardRelayStatus> status =
      ValueNotifier<BoardRelayStatus>(BoardRelayStatus.disconnected);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  var _backoffSeconds = 1;
  var _stopped = true;
  String? _hubUrl;
  String? _deviceId;
  String? _deviceKey;

  String? get hubUrl => _hubUrl;
  String? get deviceId => _deviceId;
  bool get isRunning => !_stopped;

  Future<void> start(
    BoardCubit cubit, {
    required String hubUrl,
    required String deviceId,
    required String deviceKey,
  }) async {
    await stop();
    _stopped = false;
    _hubUrl = hubUrl.trim();
    _deviceId = deviceId.trim();
    _deviceKey = deviceKey.trim();
    _backoffSeconds = 1;
    lastError.value = null;
    BoardShareServer.instance.attachForRelay(cubit);
    _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } on Object catch (_) {
      // ignore
    }
    _channel = null;
    BoardShareServer.instance.detachForRelay();
    status.value = BoardRelayStatus.disconnected;
  }

  void _connect() {
    if (_stopped) return;
    status.value = BoardRelayStatus.connecting;
    final hub = _hubUrl!.replaceAll(RegExp(r'/+$'), '');
    final wsBase = hub.startsWith('https://')
        ? hub.replaceFirst('https://', 'wss://')
        : hub.replaceFirst('http://', 'ws://');
    final uri = Uri.parse(
      '$wsBase/api/relay/connect'
      '?deviceId=${Uri.encodeComponent(_deviceId!)}'
      '&key=${Uri.encodeComponent(_deviceKey!)}',
    );

    try {
      debugPrint('[BoardRelayClient] connecting to $uri');
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onFrame,
        onDone: _onConnectionLost,
        onError: (Object error) {
          debugPrint('[BoardRelayClient] stream error: $error');
          _onConnectionLost();
        },
      );
      _channel!.ready
          .then((_) {
            if (!_stopped) {
              _backoffSeconds = 1;
              status.value = BoardRelayStatus.connected;
              debugPrint('[BoardRelayClient] connected');
            }
          })
          .catchError((Object error) {
            debugPrint('[BoardRelayClient] ready error: $error');
            _onConnectionLost();
          });
    } on Object catch (error) {
      debugPrint('[BoardRelayClient] connect error: $error');
      lastError.value = error.toString();
      _scheduleReconnect();
    }
  }

  void _onConnectionLost() {
    if (_stopped) return;
    _channel = null;
    status.value = BoardRelayStatus.connecting;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _reconnectTimer?.cancel();
    lastError.value = 'connection lost; retrying in ${_backoffSeconds}s';
    final delay = _backoffSeconds;
    _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
    _reconnectTimer = Timer(Duration(seconds: delay), _connect);
  }

  Future<void> _onFrame(dynamic data) async {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data as String) as Map<String, dynamic>;
    } on Object catch (_) {
      return;
    }
    final id = frame['id'] as String? ?? '';
    if (id.isEmpty) return;

    final method = (frame['method'] as String? ?? 'GET').toUpperCase();
    final path = frame['path'] as String? ?? '/';
    final query = frame['query'] as String? ?? '';
    final body = frame['body'] as String? ?? '';

    try {
      final response = await BoardShareServer.instance.handleRelayRequest(
        method,
        path,
        query,
        body,
      );
      final responseBody = await response.readAsString();
      _send(<String, Object?>{
        'id': id,
        'status': response.statusCode,
        'body': responseBody,
      });
    } on Object catch (error) {
      _send(<String, Object?>{
        'id': id,
        'status': 500,
        'error': error.toString(),
      });
    }
  }

  void _send(Map<String, Object?> frame) {
    _channel?.sink.add(jsonEncode(frame));
  }
}
