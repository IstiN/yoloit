import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

class YoloitdServer {
  YoloitdServer({
    required this.store,
    this.host = '127.0.0.1',
    this.port = 43110,
    this.token,
  });

  final YoloitdStore store;
  final String host;
  final int port;
  final String? token;

  HttpServer? _server;
  final Map<String, Process> _runs = <String, Process>{};
  final Map<String, List<String>> _runLogs = <String, List<String>>{};
  final Map<String, int> _runExitCodes = <String, int>{};

  int? get boundPort => _server?.port;

  Future<void> start() async {
    await store.init();
    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handle);
    _server = await shelf_io.serve(handler, host, port);
  }

  Future<void> stop() async {
    for (final process in _runs.values) {
      process.kill();
    }
    _runs.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<shelf.Response> _handle(shelf.Request request) async {
    if (!_authorized(request)) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'unauthorized',
      }, 401);
    }

    final path = request.url.pathSegments;
    final method = request.method.toUpperCase();

    try {
      if (path.isEmpty) return _html(_dashboardHtml());
      if (path.length == 1 && path[0] == 'api') {
        return _json(<String, Object?>{'ok': true, 'service': 'yoloitd'});
      }
      if (path.length == 2 && path[0] == 'api' && path[1] == 'health') {
        return _json(<String, Object?>{
          'ok': true,
          'service': 'yoloitd',
          'dataDir': store.rootDir.path,
        });
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'boards') {
        return _handleBoards(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'files') {
        return _handleFiles(request, method);
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'runs') {
        return _handleRuns(request, method, path.skip(2).toList());
      }
      return _json(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
    } catch (error, stackTrace) {
      stderr.writeln('[yoloitd] $error\n$stackTrace');
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
  ) async {
    if (sub.isEmpty && method == 'GET') {
      final boards = await store.loadBoards();
      final activeId = await store.activeBoardId();
      return _json(<String, Object?>{
        'boards':
            boards
                .map((board) => board.summary(active: board.id == activeId))
                .toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await _body(request);
      final name = (body['name'] as String? ?? 'Remote Board').trim();
      final board = await store.createBoard(
        name.isEmpty ? 'Remote Board' : name,
      );
      return _json(<String, Object?>{
        'ok': true,
        'board': board.summary(active: true),
      });
    }
    if (sub.isEmpty) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'method not allowed',
      }, 405);
    }

    final board = await store.findBoard(Uri.decodeComponent(sub[0]));
    if (board == null) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'board not found',
      }, 404);
    }

    if (sub.length == 1 && method == 'GET') return _json(board.toJson());
    if (sub.length == 1 && method == 'DELETE') {
      await store.deleteBoard(board.id);
      return _json(<String, Object?>{
        'ok': true,
        'message': 'Deleted board ${board.name}',
      });
    }
    if (sub.length == 1 && method == 'PUT') {
      final body = await _body(request);
      final expectedRevision = _expectedRevision(body);
      if (_isSnapshotUpdate(body) &&
          expectedRevision != null &&
          expectedRevision != board.historyRevision) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'board revision conflict',
          'expectedRevision': expectedRevision,
          'currentRevision': board.historyRevision,
          'board': board.toJson(),
        }, 409);
      }
      final result = await store.updateBoard(
        board.id,
        (current) => _updatedBoardFromBody(current, body),
        historyEvent:
            (before, after, revision) =>
                _snapshotPanelHistoryEvent(before, after, revision),
      );
      return _json(<String, Object?>{
        'ok': true,
        'board': result?.after.toJson(),
      });
    }
    if (sub.length == 1 &&
        method == 'GET' &&
        request.url.path.endsWith('/history')) {
      return _json(<String, Object?>{
        'events':
            (await store.historyForBoard(
              board.id,
            )).map((e) => e.toJson()).toList(),
      });
    }
    if (sub.length == 2 && sub[1] == 'history' && method == 'GET') {
      return _json(<String, Object?>{
        'events':
            (await store.historyForBoard(
              board.id,
            )).map((e) => e.toJson()).toList(),
      });
    }
    if (sub.length == 2 && sub[1] == 'undo' && method == 'POST') {
      final undone = await store.undoLatestPanelHistory(board.id);
      final updated = await store.findBoard(board.id);
      return _json(<String, Object?>{
        'ok': undone,
        'undone': undone,
        'message':
            undone
                ? 'Undid latest panel change'
                : 'No restorable panel history yet',
        if (updated != null) 'board': updated.summary(active: true),
      });
    }
    if (sub.length == 2 && sub[1] == 'panel-types' && method == 'GET') {
      return _json(<String, Object?>{'types': _panelTypes});
    }
    if (sub.length == 2 && sub[1] == 'snapshot' && method == 'GET') {
      return shelf.Response.ok(
        _snapshot(board),
        headers: <String, String>{'content-type': 'text/plain; charset=utf-8'},
      );
    }
    if (sub.length >= 2 && sub[1] == 'panels') {
      return _handlePanels(request, method, board, sub.skip(2).toList());
    }
    if (sub.length == 2 && sub[1] == 'links' && method == 'GET') {
      return _json(<String, Object?>{'links': board.links});
    }
    return _json(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  Future<shelf.Response> _handleFiles(
    shelf.Request request,
    String method,
  ) async {
    if (method != 'GET') {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'method not allowed',
      }, 405);
    }
    final requested = request.url.queryParameters['path']?.trim();
    final directory = Directory(
      requested == null || requested.isEmpty ? store.rootDir.path : requested,
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

  List<Map<String, Object?>> _fileRoots() {
    final roots = <String>{store.rootDir.path, Directory.current.path};
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) roots.add(home.trim());
    return roots
        .map(
          (path) => <String, Object?>{
            'name': path == store.rootDir.path ? 'YoLoIT data' : path,
            'path': path,
            'isDirectory': true,
          },
        )
        .toList();
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

  static bool _isSnapshotUpdate(Map<String, dynamic> body) {
    return body.containsKey('panels') ||
        body.containsKey('links') ||
        body.containsKey('drawings') ||
        body.containsKey('viewport');
  }

  static int? _expectedRevision(Map<String, dynamic> body) {
    final explicit = body['expectedRevision'];
    if (explicit is num) return explicit.toInt();
    final metadata = body['metadata'];
    if (metadata is Map) {
      final revision = metadata['historyRevision'];
      if (revision is num) return revision.toInt();
    }
    return null;
  }

  static RemoteBoard _updatedBoardFromBody(
    RemoteBoard current,
    Map<String, dynamic> body,
  ) {
    var metadata =
        body['metadata'] is Map
            ? Map<String, dynamic>.from(body['metadata'] as Map)
            : current.metadata;
    if (body.containsKey('defaultFolder')) {
      metadata = <String, dynamic>{
        ...metadata,
        'defaultFolder': body['defaultFolder'] as String? ?? '',
      };
    }
    return current.copyWith(
      name: body['name'] as String? ?? current.name,
      viewport:
          body['viewport'] is Map
              ? Map<String, dynamic>.from(body['viewport'] as Map)
              : current.viewport,
      panels:
          body['panels'] is List
              ? (body['panels'] as List)
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (entry) =>
                        RemotePanel.fromJson(Map<String, dynamic>.from(entry)),
                  )
                  .toList()
              : current.panels,
      links:
          body['links'] is List
              ? (body['links'] as List)
                  .whereType<Map<Object?, Object?>>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList()
              : current.links,
      drawings:
          body['drawings'] is List
              ? (body['drawings'] as List)
                  .whereType<Map<Object?, Object?>>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList()
              : current.drawings,
      metadata: metadata,
    );
  }

  RemoteHistoryEvent _snapshotPanelHistoryEvent(
    RemoteBoard before,
    RemoteBoard after,
    int revision,
  ) {
    final beforeById = {for (final panel in before.panels) panel.id: panel};
    final afterById = {for (final panel in after.panels) panel.id: panel};

    for (final entry in afterById.entries) {
      final beforePanel = beforeById[entry.key];
      if (beforePanel == null) {
        return _historyEvent(
          boardId: before.id,
          type: 'panel.created',
          entityId: entry.key,
          revision: revision,
          after: entry.value.toJson(),
        );
      }
      if (jsonEncode(beforePanel.toJson()) !=
          jsonEncode(entry.value.toJson())) {
        return _historyEvent(
          boardId: before.id,
          type: 'panel.updated',
          entityId: entry.key,
          revision: revision,
          before: beforePanel.toJson(),
          after: entry.value.toJson(),
        );
      }
    }

    for (final entry in beforeById.entries) {
      if (afterById.containsKey(entry.key)) continue;
      return _historyEvent(
        boardId: before.id,
        type: 'panel.deleted',
        entityId: entry.key,
        revision: revision,
        before: entry.value.toJson(),
      );
    }

    return _historyEvent(
      boardId: before.id,
      type: 'board.updated',
      entityId: before.id,
      entityType: 'board',
      revision: revision,
    );
  }

  RemoteHistoryEvent _historyEvent({
    required String boardId,
    required String type,
    required String entityId,
    required int revision,
    String entityType = 'panel',
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) {
    return RemoteHistoryEvent(
      opId: _nextId('op'),
      boardId: boardId,
      type: type,
      entityType: entityType,
      entityId: entityId,
      actorId: store.actorId,
      timestamp: DateTime.now().toUtc(),
      revision: revision,
      before: before,
      after: after,
    );
  }

  Future<shelf.Response> _handlePanels(
    shelf.Request request,
    String method,
    RemoteBoard board,
    List<String> sub,
  ) async {
    if (sub.isEmpty && method == 'GET') {
      return _json(<String, Object?>{
        'panels': board.panels.map(_panelSummary).toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await _body(request);
      final panel = RemotePanel(
        id: body['id'] as String? ?? _nextId('p'),
        type: body['type'] as String? ?? 'board.note.markdown',
        title: body['title'] as String? ?? 'Panel',
        bounds: RemotePanelBounds(
          x: (body['x'] as num?)?.toDouble() ?? 120.0,
          y: (body['y'] as num?)?.toDouble() ?? 120.0,
          width: (body['width'] as num?)?.toDouble() ?? 360.0,
          height: (body['height'] as num?)?.toDouble() ?? 240.0,
        ),
        state: Map<String, dynamic>.from(body['state'] as Map? ?? const {}),
      );
      final created = await store.addPanel(board.id, panel);
      return _json(<String, Object?>{
        'ok': true,
        'panel': created.toJson(),
        'id': created.id,
      });
    }
    if (sub.isEmpty) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'method not allowed',
      }, 405);
    }
    final panelId = Uri.decodeComponent(sub[0]);
    final panel = _findPanel(board, panelId);
    if (panel == null) {
      return _json(<String, Object?>{
        'ok': false,
        'error': 'panel not found',
      }, 404);
    }
    if (sub.length == 1 && method == 'GET') {
      return _json(<String, Object?>{
        ...panel.toJson(),
        'typeName': panel.type,
        'content': panel.state,
        'supportedActions': const <String>['get', 'set'],
        'actionHelp': const <String, Object?>{},
      });
    }
    if (sub.length == 1 && method == 'DELETE') {
      final ok = await store.removePanel(board.id, panel.id);
      return _json(<String, Object?>{'ok': ok});
    }
    if (sub.length == 1 && method == 'PUT') {
      final body = await _body(request);
      final updated = await store.updatePanel(
        board.id,
        panel.id,
        (current) => current.copyWith(
          title: body['title'] as String? ?? current.title,
          bounds: current.bounds.copyWith(
            x: (body['x'] as num?)?.toDouble(),
            y: (body['y'] as num?)?.toDouble(),
            width: (body['width'] as num?)?.toDouble(),
            height: (body['height'] as num?)?.toDouble(),
          ),
          hidden: body['hidden'] as bool?,
          locked: body['locked'] as bool?,
          pinned: body['pinned'] as bool?,
          state:
              body['state'] is Map
                  ? Map<String, dynamic>.from(body['state'] as Map)
                  : current.state,
        ),
      );
      return _json(<String, Object?>{
        'ok': updated != null,
        'panel': updated?.toJson(),
      });
    }
    if (sub.length == 2 && sub[1] == 'action' && method == 'POST') {
      final body = await _body(request);
      final action = body['action'] as String? ?? 'get';
      if (action == 'get') {
        return _json(<String, Object?>{'ok': true, 'content': panel.state});
      }
      if (action == 'set') {
        final nextState = <String, dynamic>{...panel.state, ...body}
          ..remove('action');
        final updated = await store.updatePanel(
          board.id,
          panel.id,
          (current) => current.copyWith(state: nextState),
        );
        return _json(<String, Object?>{'ok': true, 'panel': updated?.toJson()});
      }
      return _json(<String, Object?>{
        'ok': false,
        'error': 'unknown action',
      }, 400);
    }
    return _json(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  Future<shelf.Response> _handleRuns(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    if (sub.isEmpty && method == 'GET') {
      final ids =
          <String>{
              ..._runs.keys,
              ..._runExitCodes.keys,
              ..._runLogs.keys,
            }.toList()
            ..sort();
      return _json(<String, Object?>{
        'runs':
            ids
                .map(
                  (id) => <String, Object?>{
                    'id': id,
                    'running': _runs.containsKey(id),
                    if (_runExitCodes.containsKey(id))
                      'exitCode': _runExitCodes[id],
                    'logLines': _runLogs[id]?.length ?? 0,
                  },
                )
                .toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await _body(request);
      final command = (body['command'] as String? ?? '').trim();
      if (command.isEmpty) {
        return _json(<String, Object?>{
          'ok': false,
          'error': 'command required',
        }, 400);
      }
      final id = body['id'] as String? ?? _nextId('run');
      final process = await Process.start(
        Platform.environment['SHELL'] ?? '/bin/sh',
        <String>['-lc', command],
        workingDirectory: body['cwd'] as String?,
      );
      _runs[id] = process;
      _runLogs[id] = <String>[];
      unawaited(_collectRun(id, process));
      return _json(<String, Object?>{'ok': true, 'id': id, 'pid': process.pid});
    }
    if (sub.length == 2 && sub[1] == 'log' && method == 'GET') {
      return _json(<String, Object?>{
        'id': sub[0],
        'lines': _runLogs[sub[0]] ?? const <String>[],
      });
    }
    if (sub.length == 2 && sub[1] == 'stop' && method == 'POST') {
      final process = _runs.remove(sub[0]);
      final ok = process?.kill() ?? false;
      return _json(<String, Object?>{'ok': ok});
    }
    return _json(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
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

  bool _authorized(shelf.Request request) {
    final expected = token?.trim();
    if (expected == null || expected.isEmpty) return true;
    final auth = request.headers['authorization'] ?? '';
    if (auth == 'Bearer $expected') return true;
    return request.url.queryParameters['token'] == expected;
  }

  Future<Map<String, dynamic>> _body(shelf.Request request) async {
    final text = await request.readAsString();
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  shelf.Response _json(Object? value, [int status = 200]) {
    return shelf.Response(
      status,
      body: jsonEncode(value),
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  shelf.Response _html(String value) {
    return shelf.Response.ok(
      value,
      headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
    );
  }

  String _dashboardHtml() {
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>YoLoIT Remote</title>
  <style>
    body{font-family:system-ui,-apple-system,sans-serif;background:#111827;color:#e5e7eb;margin:0;padding:24px}
    button,input{font:inherit}
    .card{border:1px solid #334155;border-radius:8px;padding:16px;margin:12px 0;background:#1f2937}
    a{color:#93c5fd}
  </style>
</head>
<body>
  <h1>YoLoIT Remote</h1>
  <p>Headless daemon is running. Use <code>tools/yoloit remote:connect</code> or the REST API.</p>
  <div id="boards"></div>
  <script>
    fetch('/api/boards${token == null ? '' : '?token=$token'}').then(r=>r.json()).then(data=>{
      document.getElementById('boards').innerHTML=(data.boards||[]).map(b=>
        '<div class="card"><b>'+b.name+'</b><br>'+b.id+'<br>'+b.panelCount+' panels</div>'
      ).join('');
    });
  </script>
</body>
</html>
''';
  }

  static RemotePanel? _findPanel(RemoteBoard board, String idOrTitle) {
    final byId =
        board.panels.where((panel) => panel.id == idOrTitle).firstOrNull;
    if (byId != null) return byId;
    return board.panels
        .where((panel) => panel.title.toLowerCase() == idOrTitle.toLowerCase())
        .firstOrNull;
  }

  static Map<String, dynamic> _panelSummary(RemotePanel panel) {
    return <String, dynamic>{
      ...panel.toJson(),
      'typeName': panel.type,
      'content': panel.state,
    };
  }

  static String _snapshot(RemoteBoard board) {
    final buffer =
        StringBuffer()
          ..writeln('# ${board.name}')
          ..writeln()
          ..writeln('| Panel | Type | Position | Size |')
          ..writeln('|-------|------|----------|------|');
    for (final panel in board.panels) {
      buffer.writeln(
        '| ${panel.title} | ${panel.type} | ${panel.bounds.x},${panel.bounds.y} | ${panel.bounds.width}x${panel.bounds.height} |',
      );
    }
    return buffer.toString();
  }

  static String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  static const List<Map<String, dynamic>> _panelTypes = <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'board.note.markdown',
      'displayName': 'Markdown Note',
      'defaultSize': <String, dynamic>{'width': 300, 'height': 240},
    },
    <String, dynamic>{
      'type': 'board.sticky',
      'displayName': 'Sticky Note',
      'defaultSize': <String, dynamic>{'width': 300, 'height': 260},
    },
    <String, dynamic>{
      'type': 'board.shape',
      'displayName': 'Shape / Frame',
      'defaultSize': <String, dynamic>{'width': 300, 'height': 220},
    },
    <String, dynamic>{
      'type': 'board.terminal',
      'displayName': 'Terminal',
      'defaultSize': <String, dynamic>{'width': 520, 'height': 360},
    },
  ];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
