import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yoloit/core/setup/setup_catalog.dart';
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
  final Map<String, Process> _runs = <String, Process>{};
  final Map<String, List<String>> _runLogs = <String, List<String>>{};
  final Map<String, int> _runExitCodes = <String, int>{};
  final Map<String, Process> _terminals = <String, Process>{};
  final Map<String, List<String>> _terminalChunks = <String, List<String>>{};
  final Map<String, int> _terminalExitCodes = <String, int>{};

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
    for (final process in _runs.values) {
      process.kill();
    }
    _runs.clear();
    for (final process in _terminals.values) {
      process.kill();
    }
    _terminals.clear();
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
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'files') {
        return _handleFiles(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'setup') {
        return _handleSetup(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'terminals') {
        return _handleTerminals(request, method, path.skip(2).toList());
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
      ).copyWith(viewport: board.viewport);
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

  Future<shelf.Response> _handleFiles(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    if (sub.isEmpty && method == 'GET') {
      return _listFiles(request.url.queryParameters['path']?.trim());
    }
    if (sub.length == 1 && sub[0] == 'directories' && method == 'POST') {
      final body = await _body(request);
      final parentPath = (body['parentPath'] as String? ?? '').trim();
      final name = (body['name'] as String? ?? '').trim();
      if (!_validDirectoryName(name)) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'invalid directory name',
        }, 400);
      }
      final parent = Directory(
        parentPath.isEmpty ? _defaultFileRoot() : parentPath,
      );
      if (!await parent.exists()) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'parent directory not found',
          'path': parent.path,
        }, 404);
      }
      await Directory('${parent.path}${Platform.pathSeparator}$name').create();
      return _listFiles(parent.path);
    }
    return _json(<String, Object?>{
      'ok': false,
      'error': 'method not allowed',
    }, 405);
  }

  Future<shelf.Response> _listFiles(String? requested) async {
    final directory = Directory(
      requested == null || requested.isEmpty ? _defaultFileRoot() : requested,
    );
    if (!await directory.exists()) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'directory not found',
        'path': directory.path,
      }, 404);
    }

    final entries = <Map<String, Object?>>[];
    await for (final entity in directory.list(followLinks: false)) {
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.directory &&
          stat.type != FileSystemEntityType.file) {
        continue;
      }
      entries.add(<String, Object?>{
        'name': _fileName(entity.path),
        'path': entity.path,
        'isDirectory': stat.type == FileSystemEntityType.directory,
      });
    }
    entries.sort((a, b) {
      final aDir = a['isDirectory'] == true;
      final bDir = b['isDirectory'] == true;
      if (aDir != bDir) return aDir ? -1 : 1;
      return (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      );
    });

    return _json(<String, Object?>{
      'ok': true,
      'path': directory.path,
      'parent':
          directory.parent.path == directory.path
              ? null
              : directory.parent.path,
      'roots': _fileRoots(),
      'entries': entries,
    });
  }

  Future<shelf.Response> _handleSetup(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    if (sub.isEmpty && method == 'GET') {
      final snapshot = await SetupCatalog.check();
      return _json(snapshot.toJson());
    }
    if (sub.length == 1 && sub[0] == 'install' && method == 'POST') {
      final body = await _body(request);
      final ids =
          (body['packageIds'] as List? ?? const <Object?>[])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList();
      if (ids.isEmpty) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'packageIds required',
        }, 400);
      }
      final runtime = await SetupCatalog.detectRuntime();
      final script = SetupCatalog.installScript(ids, runtime.os);
      if (script.trim().isEmpty) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'no install command for selected packages on this OS',
        }, 400);
      }
      if (body['dryRun'] == true) {
        return _json(<String, Object?>{'ok': true, 'script': script});
      }
      final id = body['id'] as String? ?? _nextId('setup');
      final process = await Process.start(
        Platform.environment['SHELL'] ?? '/bin/sh',
        <String>['-lc', script],
        workingDirectory: Directory.current.path,
      );
      _runs[id] = process;
      _runLogs[id] = <String>['\$ $script'];
      _runExitCodes.remove(id);
      unawaited(_collectRun(id, process));
      return _json(<String, Object?>{
        'ok': true,
        'id': id,
        'pid': process.pid,
        'script': script,
      });
    }
    if (sub.length == 2 && sub[1] == 'log' && method == 'GET') {
      return _json(<String, Object?>{
        'id': sub[0],
        'lines': _runLogs[sub[0]] ?? const <String>[],
        'running': _runs.containsKey(sub[0]),
        if (_runExitCodes.containsKey(sub[0]))
          'exitCode': _runExitCodes[sub[0]],
      });
    }
    return _json(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  Future<shelf.Response> _handleTerminals(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    if (sub.isEmpty && method == 'POST') {
      final body = await _body(request);
      final id = (body['id'] as String? ?? _nextId('terminal')).trim();
      final cwd = (body['cwd'] as String? ?? Directory.current.path).trim();
      if (id.isEmpty) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'id required',
        }, 400);
      }
      final directory = Directory(cwd.isEmpty ? Directory.current.path : cwd);
      if (!await directory.exists()) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'working directory not found',
          'path': directory.path,
        }, 404);
      }
      _terminals.remove(id)?.kill();
      final rawEnv = body['env'];
      final env =
          rawEnv is Map
              ? rawEnv.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
              : const <String, String>{};
      final shell = Platform.environment['SHELL'] ?? '/bin/sh';
      final launcher = await _terminalLauncher(shell);
      final process = await Process.start(
        launcher.executable,
        launcher.arguments,
        workingDirectory: directory.path,
        environment: <String, String>{
          'TERM': 'xterm-256color',
          if (env.isNotEmpty) ...env,
        },
      );
      _terminals[id] = process;
      _terminalChunks[id] = <String>[];
      _terminalExitCodes.remove(id);
      unawaited(_collectTerminal(id, process));
      return _json(<String, Object?>{'ok': true, 'id': id, 'pid': process.pid});
    }
    if (sub.length == 2 && sub[1] == 'log' && method == 'GET') {
      final since =
          int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
      final chunks = _terminalChunks[sub[0]] ?? const <String>[];
      final start = since.clamp(0, chunks.length);
      return _json(<String, Object?>{
        'id': sub[0],
        'next': chunks.length,
        'chunks': chunks.skip(start).toList(),
        'running': _terminals.containsKey(sub[0]),
        if (_terminalExitCodes.containsKey(sub[0]))
          'exitCode': _terminalExitCodes[sub[0]],
      });
    }
    if (sub.length == 2 && sub[1] == 'input' && method == 'POST') {
      final process = _terminals[sub[0]];
      if (process == null) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'terminal not found',
        }, 404);
      }
      final body = await _body(request);
      process.stdin.write(body['data'] as String? ?? '');
      await process.stdin.flush();
      return _json(<String, Object?>{'ok': true});
    }
    if (sub.length == 2 && sub[1] == 'stop' && method == 'POST') {
      final process = _terminals.remove(sub[0]);
      final ok = process?.kill() ?? false;
      return _json(<String, Object?>{'ok': ok});
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

  static bool _validDirectoryName(String name) {
    if (name.isEmpty || name == '.' || name == '..') return false;
    return !name.contains('/') &&
        !name.contains('\\') &&
        !name.contains('\x00');
  }

  List<Map<String, Object?>> _fileRoots() {
    final roots = <Map<String, Object?>>[];
    final seen = <String>{};
    void addRoot(String name, String? path) {
      final value = path?.trim();
      if (value == null || value.isEmpty || !seen.add(value)) return;
      roots.add(<String, Object?>{
        'name': name,
        'path': value,
        'isDirectory': true,
      });
    }

    addRoot('Home', _homePath());
    addRoot('Current', Directory.current.path);
    return roots;
  }

  String _defaultFileRoot() => _homePath() ?? Directory.current.path;

  static String? _homePath() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final trimmed = home?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _fileName(String path) {
    final normalized =
        path.endsWith(Platform.pathSeparator)
            ? path.substring(0, path.length - 1)
            : path;
    final index = normalized.lastIndexOf(Platform.pathSeparator);
    if (index == -1) return normalized;
    return normalized.substring(index + 1);
  }

  Future<({String executable, List<String> arguments})> _terminalLauncher(
    String shell,
  ) async {
    final script =
        (Platform.isLinux || Platform.isMacOS)
            ? await _findExecutable('script')
            : null;
    if (script != null) {
      if (Platform.isMacOS) {
        return (
          executable: script,
          arguments: <String>['-q', '/dev/null', shell, '-i'],
        );
      }
      return (
        executable: script,
        arguments: <String>['-q', '-f', '-c', shell, '/dev/null'],
      );
    }
    return (executable: shell, arguments: <String>['-i']);
  }

  Future<String?> _findExecutable(String name) async {
    final result = await Process.run(
      Platform.environment['SHELL'] ?? '/bin/sh',
      <String>['-lc', 'command -v ${_shellQuote(name)}'],
    );
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path.split('\n').first.trim();
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  Future<void> _collectTerminal(String id, Process process) async {
    void add(String chunk) {
      final chunks = _terminalChunks[id] ??= <String>[];
      chunks.add(chunk);
      if (chunks.length > 2000) chunks.removeRange(0, chunks.length - 2000);
    }

    process.stdout.transform(utf8.decoder).listen(add);
    process.stderr.transform(utf8.decoder).listen(add);
    final exitCode = await process.exitCode;
    add('\n[exit $exitCode]\n');
    _terminals.remove(id);
    _terminalExitCodes[id] = exitCode;
  }

  Future<void> _collectRun(String id, Process process) async {
    void add(String line) {
      final lines = _runLogs[id] ??= <String>[];
      lines.add(line);
      if (lines.length > 1000) lines.removeRange(0, lines.length - 1000);
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(add);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(add);
    final exitCode = await process.exitCode;
    add('[exit $exitCode]');
    _runs.remove(id);
    _runExitCodes[id] = exitCode;
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
