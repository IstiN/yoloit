import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class BoardShareServerInfo {
  const BoardShareServerInfo({
    required this.url,
    required this.token,
    required this.host,
    required this.port,
  });

  final String url;
  final String token;
  final String host;
  final int port;
}

class BoardShareServer {
  BoardShareServer._();

  static final BoardShareServer instance = BoardShareServer._();

  HttpServer? _server;
  BoardCubit? _cubit;
  String? _token;
  String _host = '0.0.0.0';
  String _advertisedHost = '127.0.0.1';

  bool get isRunning => _server != null;
  BoardShareServerInfo? get info {
    final server = _server;
    final token = _token;
    if (server == null || token == null) return null;
    final url = 'http://$_advertisedHost:${server.port}';
    return BoardShareServerInfo(
      url: url,
      token: token,
      host: _host,
      port: server.port,
    );
  }

  Future<BoardShareServerInfo> start(
    BoardCubit cubit, {
    String host = '0.0.0.0',
    int port = 43110,
  }) async {
    _cubit = cubit;
    if (_server != null) return info!;

    _host = host;
    _token = _newToken();
    _advertisedHost = await _bestLanHost();
    final handler = const shelf.Pipeline()
        .addMiddleware(
          shelf.logRequests(
            logger: (message, isError) {
              if (isError) debugPrint('[BoardShare] $message');
            },
          ),
        )
        .addHandler(_handle);

    try {
      _server = await shelf_io.serve(handler, host, port);
    } on SocketException {
      _server = await shelf_io.serve(handler, host, 0);
    }
    return info!;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _cubit = null;
  }

  Future<shelf.Response> _handle(shelf.Request request) async {
    if (!_authorized(request)) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'unauthorized',
      }, 401);
    }

    final method = request.method.toUpperCase();
    final path = request.url.pathSegments;
    final cubit = _cubit;
    if (cubit == null) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'board share server is not attached',
      }, 503);
    }

    try {
      if (path.isEmpty) return _html(_dashboardHtml());
      if (path.length == 2 && path[0] == 'api' && path[1] == 'health') {
        return _json(<String, Object?>{
          'ok': true,
          'service': 'yoloit-board-share',
          'boards': cubit.state.boards.length,
        });
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'boards') {
        return _handleBoards(request, method, path.skip(2).toList(), cubit);
      }
      return _json(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
    } catch (error, stackTrace) {
      debugPrint('[BoardShare] $error\n$stackTrace');
      return _json(<String, Object?>{
        'ok': false,
        'error': error.toString(),
      }, 500);
    }
  }

  Future<shelf.Response> _handleBoards(
    shelf.Request request,
    String method,
    List<String> sub,
    BoardCubit cubit,
  ) async {
    if (sub.isEmpty && method == 'GET') {
      final active = cubit.state.activeBoardId;
      return _json(<String, Object?>{
        'boards':
            cubit.state.boards
                .map((board) => _summary(board, activeId: active))
                .toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await _body(request);
      final name = (body['name'] as String? ?? 'Remote Board').trim();
      final board = await cubit.createBoard(
        name: name.isEmpty ? 'Remote Board' : name,
      );
      return _json(<String, Object?>{
        'ok': board != null,
        if (board != null) 'board': _summary(board, activeId: board.id),
      });
    }
    if (sub.isEmpty) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'method not allowed',
      }, 405);
    }

    final id = Uri.decodeComponent(sub[0]);
    BoardDocument? board;
    for (final candidate in cubit.state.boards) {
      if (candidate.id == id) {
        board = candidate;
        break;
      }
    }
    if (board == null) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'board not found',
      }, 404);
    }

    if (sub.length == 1 && method == 'GET') return _json(_sharedBoard(board));
    if (sub.length == 1 && method == 'PUT') {
      final body = await _body(request);
      final expectedRevision = (body['expectedRevision'] as num?)?.toInt();
      final currentRevision =
          (board.metadata['historyRevision'] as num?)?.toInt() ?? 0;
      if (expectedRevision != null && expectedRevision != currentRevision) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'board revision conflict',
          'expectedRevision': expectedRevision,
          'currentRevision': currentRevision,
          'board': _sharedBoard(board),
        }, 409);
      }
      final snapshot = BoardDocument.fromJson(
        Map<String, dynamic>.from(body)..['id'] = board.id,
      );
      final updated = await cubit.replaceBoardSnapshotFromShare(snapshot);
      if (updated == null) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'board not found',
        }, 404);
      }
      return _json(<String, Object?>{
        'ok': true,
        'board': _sharedBoard(updated),
      });
    }
    return _json(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  bool _authorized(shelf.Request request) {
    final token = _token;
    if (token == null || token.isEmpty) return true;
    final auth = request.headers['authorization'] ?? '';
    if (auth == 'Bearer $token') return true;
    return request.url.queryParameters['token'] == token;
  }

  Map<String, Object?> _summary(BoardDocument board, {String? activeId}) {
    return <String, Object?>{
      'id': board.id,
      'name': board.name,
      'panelCount': board.panels.length,
      'linkCount': board.links.length,
      'defaultFolder': board.defaultFolder,
      if (activeId != null) 'active': board.id == activeId,
    };
  }

  Map<String, dynamic> _sharedBoard(BoardDocument board) {
    final metadata =
        Map<String, dynamic>.from(board.metadata)
          ..remove('remote')
          ..remove('remoteSource');
    return <String, dynamic>{...board.toJson(), 'metadata': metadata};
  }

  Future<Map<String, dynamic>> _body(shelf.Request request) async {
    final text = await request.readAsString();
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  shelf.Response _json(Map<String, Object?> body, [int statusCode = 200]) {
    return shelf.Response(
      statusCode,
      body: jsonEncode(body),
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  shelf.Response _html(String body) {
    return shelf.Response.ok(
      body,
      headers: const <String, String>{
        'content-type': 'text/html; charset=utf-8',
      },
    );
  }

  String _dashboardHtml() {
    final info = this.info;
    return '''
<!doctype html>
<meta charset="utf-8">
<title>YoLoIT board share</title>
<body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px">
  <h1>YoLoIT board share</h1>
  <p>Use Connect remote YoLoIT from another YoLoIT app.</p>
  <p><code>${info?.url ?? ''}</code></p>
</body>
''';
  }

  String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String> _bestLanHost() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final value = address.address;
          if (!value.startsWith('169.254.')) return value;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}
