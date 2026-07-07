import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yoloit/core/remote/board_share_server_base.dart';
import 'package:yoloit/core/remote/server_process_utils.dart';
import 'package:yoloit/core/utils/directory_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class BoardShareServer extends BoardShareServerBase with ServerProcessMixin {
  BoardShareServer._();

  static final BoardShareServer instance = BoardShareServer._();

  HttpServer? _server;
  BoardCubit? _cubit;
  String? _token;
  String _host = '0.0.0.0';
  String _advertisedHost = '127.0.0.1';

  @override
  bool get isRunning => _server != null;

  @override
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

  @override
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

  @override
  Future<void> stop() async {
    killAllRunsAndTerminals();
    await _server?.close(force: true);
    _server = null;
    _cubit = null;
  }

  Future<shelf.Response> _handle(shelf.Request request) async {
    if (!_authorized(request)) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'unauthorized',
      }, 401);
    }

    final method = request.method.toUpperCase();
    final path = request.url.pathSegments;
    final cubit = _cubit;
    if (cubit == null) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'board share server is not attached',
      }, 503);
    }

    try {
      if (path.isEmpty) return htmlResponse(_dashboardHtml());
      if (path.length == 2 && path[0] == 'api' && path[1] == 'health') {
        return jsonResponse(<String, Object?>{
          'ok': true,
          'service': 'yoloit-board-share',
          'boards': cubit.state.boards.length,
        });
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'boards') {
        return _handleBoards(request, method, path.skip(2).toList(), cubit);
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'files') {
        return _handleFiles(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'setup') {
        return _handleSetup(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'terminals') {
        return _handleTerminals(request, method, path.skip(2).toList());
      }
      return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
    } catch (error, stackTrace) {
      debugPrint('[BoardShare] $error\n$stackTrace');
      return jsonResponse(<String, Object?>{
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
      return jsonResponse(<String, Object?>{
        'boards':
            cubit.state.boards
                .map((board) => _summary(board, activeId: active))
                .toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await readJsonBody(request);
      final name = (body['name'] as String? ?? 'Remote Board').trim();
      final board = await cubit.createBoard(
        name: name.isEmpty ? 'Remote Board' : name,
      );
      return jsonResponse(<String, Object?>{
        'ok': board != null,
        if (board != null) 'board': _summary(board, activeId: board.id),
      });
    }
    if (sub.isEmpty) {
      return jsonResponse(<String, Object?>{
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
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'board not found',
      }, 404);
    }

    if (sub.length == 1 && method == 'GET') return jsonResponse(_sharedBoard(board));
    if (sub.length == 1 && method == 'PUT') {
      final body = await readJsonBody(request);
      final expectedRevision = (body['expectedRevision'] as num?)?.toInt();
      final currentRevision =
          (board.metadata['historyRevision'] as num?)?.toInt() ?? 0;
      if (expectedRevision != null && expectedRevision != currentRevision) {
        return jsonResponse(<String, Object?>{
          'ok': false,
          'error': 'board revision conflict',
          'expectedRevision': expectedRevision,
          'currentRevision': currentRevision,
          'board': _sharedBoard(board),
        }, 409);
      }
      final snapshot = BoardDocument.fromJson(
        Map<String, dynamic>.from(body)..['id'] = board.id,
      ).copyWith(viewport: board.viewport);
      final updated = await cubit.replaceBoardSnapshotFromShare(snapshot);
      if (updated == null) {
        return jsonResponse(<String, Object?>{
          'ok': false,
          'error': 'board not found',
        }, 404);
      }
      return jsonResponse(<String, Object?>{
        'ok': true,
        'board': _sharedBoard(updated),
      });
    }
    return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  Future<shelf.Response> _handleFiles(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    return handleFilesRequest(
      request: request,
      method: method,
      sub: sub,
      defaultRoot: _defaultFileRoot,
      listFiles: _listFiles,
    );
  }

  Future<shelf.Response> _listFiles(String? requested) async {
    final directory = Directory(
      requested == null || requested.isEmpty ? _defaultFileRoot() : requested,
    );
    final dirEntries = await listDirectoryEntries(directory);
    final entries =
        dirEntries
            .map(
              (e) => <String, Object?>{
                'name': e.name,
                'path': e.path,
                'isDirectory': e.isDirectory,
              },
            )
            .toList();

    return buildFileListingResponse(
      directory: directory,
      entries: entries,
      roots: _fileRoots(),
    );
  }

  Future<shelf.Response> _handleSetup(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    return handleSetupRequest(
      request: request,
      method: method,
      sub: sub,
      nextId: () => _nextId('setup'),
      startTasks: (id, specialIds, script) => runSetupInstallTasks(
        id,
        specialIds,
        script,
        Directory.current.path,
      ),
    );
  }

  Future<shelf.Response> _handleTerminals(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    return handleTerminalsRequest(
      request: request,
      method: method,
      sub: sub,
      defaultCwd: Directory.current.path,
      nextId: () => _nextId('terminal'),
      killExisting: (id) => terminals.remove(id)?.kill(),
      onProcessStarted: (id, process) {
        terminals[id] = process;
        terminalChunks[id] = <String>[];
        terminalExitCodes.remove(id);
        unawaited(collectTerminal(id, process));
      },
      terminals: terminals,
      terminalChunks: terminalChunks,
      terminalExitCodes: terminalExitCodes,
    );
  }

  bool _authorized(shelf.Request request) => isAuthorized(request, _token);

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

  List<Map<String, Object?>> _fileRoots() {
    final unique = buildUniqueRoots({
      'Home': homePath(),
      'Current': Directory.current.path,
    });
    return unique.entries
        .map(
          (e) => <String, Object?>{
            'name': e.key,
            'path': e.value,
            'isDirectory': true,
          },
        )
        .toList();
  }

  String _defaultFileRoot() => homePath() ?? Directory.current.path;

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

  static String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

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
