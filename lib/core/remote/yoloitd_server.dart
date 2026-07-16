import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yoloit/core/remote/server_process_utils.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_panel_actions.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';
import 'package:yoloit/core/utils/directory_utils.dart';

class YoloitdServer with ServerProcessMixin {
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

  int? get boundPort => _server?.port;

  Future<void> start() async {
    await store.init();
    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handle);
    _server = await shelf_io.serve(handler, host, port);
  }

  Future<void> stop() async {
    killAllRunsAndTerminals();
    await _server?.close(force: true);
    _server = null;
  }

  Future<shelf.Response> _handle(shelf.Request request) async {
    if (!_authorized(request)) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'unauthorized',
      }, 401);
    }

    final path = request.url.pathSegments;
    final method = request.method.toUpperCase();

    try {
      if (path.isEmpty) return htmlResponse(_dashboardHtml());
      if (path.length == 1 && path[0] == 'api') {
        return jsonResponse(<String, Object?>{'ok': true, 'service': 'yoloitd'});
      }
      if (path.length == 2 && path[0] == 'api' && path[1] == 'health') {
        return jsonResponse(<String, Object?>{
          'ok': true,
          'service': 'yoloitd',
          'dataDir': store.rootDir.path,
        });
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'boards') {
        return _handleBoards(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'files') {
        return _handleFiles(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'runs') {
        return _handleRuns(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'setup') {
        return _handleSetup(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'terminals') {
        return _handleTerminals(request, method, path.skip(2).toList());
      }
      if (path.length >= 2 && path[0] == 'api' && path[1] == 'templates') {
        return _handleTemplates(request, method, path.skip(2).toList());
      }
      return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
    } catch (error, stackTrace) {
      stderr.writeln('[yoloitd] $error\n$stackTrace');
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
  ) async {
    if (sub.isEmpty && method == 'GET') {
      final boards = await store.loadBoards();
      final activeId = await store.activeBoardId();
      final includeArchived =
          request.url.queryParameters['includeArchived']?.toLowerCase() ==
          'true';
      return jsonResponse(<String, Object?>{
        'boards':
            boards
                .where(
                  (board) =>
                      includeArchived ||
                      (board.metadata['archived'] as bool? ?? false) == false,
                )
                .map((board) => board.summary(active: board.id == activeId))
                .toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await readJsonBody(request);
      final name = (body['name'] as String? ?? 'Remote Board').trim();
      final board = await store.createBoard(
        name.isEmpty ? 'Remote Board' : name,
      );
      return jsonResponse(<String, Object?>{
        'ok': true,
        'board': board.summary(active: true),
      });
    }
    if (sub.isEmpty) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'method not allowed',
      }, 405);
    }

    final board = await store.findBoard(Uri.decodeComponent(sub[0]));
    if (board == null) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'board not found',
      }, 404);
    }

    if (sub.length == 1 && method == 'GET') return jsonResponse(board.toJson());
    if (sub.length == 1 && method == 'DELETE') {
      await store.deleteBoard(board.id);
      return jsonResponse(<String, Object?>{
        'ok': true,
        'message': 'Deleted board ${board.name}',
      });
    }
    if (sub.length == 2 && sub[1] == 'archive' && method == 'POST') {
      final result = await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          metadata: <String, dynamic>{...current.metadata, 'archived': true},
        ),
      );
      return jsonResponse(<String, Object?>{
        'ok': result != null,
        'message': 'Archived board ${board.name}',
      });
    }
    if (sub.length == 2 && sub[1] == 'unarchive' && method == 'POST') {
      final result = await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          metadata: <String, dynamic>{...current.metadata, 'archived': false},
        ),
      );
      return jsonResponse(<String, Object?>{
        'ok': result != null,
        'message': 'Unarchived board ${board.name}',
      });
    }
    if (sub.length == 1 && method == 'PUT') {
      final body = await readJsonBody(request);
      final expectedRevision = _expectedRevision(body);
      if (_isSnapshotUpdate(body) &&
          expectedRevision != null &&
          expectedRevision != board.historyRevision) {
        return jsonResponse(<String, Object?>{
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
      return jsonResponse(<String, Object?>{
        'ok': true,
        'board': result?.after.toJson(),
      });
    }
    if (sub.length == 1 &&
        method == 'GET' &&
        request.url.path.endsWith('/history')) {
      return jsonResponse(<String, Object?>{
        'events':
            (await store.historyForBoard(
              board.id,
            )).map((e) => e.toJson()).toList(),
      });
    }
    if (sub.length == 2 && sub[1] == 'history' && method == 'GET') {
      return jsonResponse(<String, Object?>{
        'events':
            (await store.historyForBoard(
              board.id,
            )).map((e) => e.toJson()).toList(),
      });
    }
    if (sub.length == 2 && sub[1] == 'undo' && method == 'POST') {
      final undone = await store.undoLatestPanelHistory(board.id);
      final updated = await store.findBoard(board.id);
      return jsonResponse(<String, Object?>{
        'ok': undone,
        'undone': undone,
        'redoDepth': store.redoDepthForBoard(board.id),
        'message':
            undone
                ? 'Undid latest panel change'
                : 'No restorable panel history yet',
        if (updated != null) 'board': updated.summary(active: true),
      });
    }
    if (sub.length == 2 && sub[1] == 'redo' && method == 'POST') {
      final redone = await store.redoLatestPanelHistory(board.id);
      final updated = await store.findBoard(board.id);
      return jsonResponse(<String, Object?>{
        'ok': redone,
        'redone': redone,
        'redoDepth': store.redoDepthForBoard(board.id),
        'message':
            redone
                ? 'Redid latest undone panel change'
                : 'No redoable panel history yet',
        if (updated != null) 'board': updated.summary(active: true),
      });
    }
    if (sub.length == 2 && sub[1] == 'panel-types' && method == 'GET') {
      return jsonResponse(<String, Object?>{'types': yoloitdPanelTypes});
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
      return jsonResponse(<String, Object?>{'links': board.links});
    }
    if (sub.length == 2 && sub[1] == 'links' && method == 'POST') {
      final body = await readJsonBody(request);
      final fromId = (body['from'] as String? ?? '').trim();
      final toId = (body['to'] as String? ?? '').trim();
      if (fromId.isEmpty || toId.isEmpty) {
        return jsonResponse(<String, Object?>{
          'ok': false,
          'error': 'from and to required',
        }, 400);
      }
      final fromPanel = _findPanel(board, fromId);
      final toPanel = _findPanel(board, toId);
      if (fromPanel == null || toPanel == null) {
        return jsonResponse(<String, Object?>{
          'ok': false,
          'error': 'panel not found',
        }, 404);
      }
      final link = <String, Object?>{
        'id': _nextId('link'),
        'fromPanelId': fromPanel.id,
        'toPanelId': toPanel.id,
        'from': fromPanel.id,
        'to': toPanel.id,
        if (body['color'] != null) 'color': body['color'],
        if (body['style'] != null) 'style': body['style'],
      };
      final result = await store.updateBoard(
        board.id,
        (current) => current.copyWith(links: <Map<String, dynamic>>[...current.links, link]),
      );
      return jsonResponse(<String, Object?>{
        'ok': result != null,
        'link': link,
      });
    }
    if (sub.length == 3 && sub[1] == 'links' && method == 'DELETE') {
      final linkId = Uri.decodeComponent(sub[2]);
      final result = await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          links: current.links.where((link) => link['id'] != linkId).toList(),
        ),
      );
      return jsonResponse(<String, Object?>{
        'ok': result != null,
        'message': 'Link deleted',
      });
    }
    if (sub.length == 3 && sub[1] == 'links' && method == 'PUT') {
      final linkId = Uri.decodeComponent(sub[2]);
      final body = await readJsonBody(request);
      final result = await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          links: current.links.map((link) {
            if (link['id'] != linkId) return link;
            final next = Map<String, dynamic>.from(link);
            if (body['color'] != null) next['color'] = body['color'];
            if (body['style'] != null) next['style'] = body['style'];
            return next;
          }).toList(),
        ),
      );
      return jsonResponse(<String, Object?>{'ok': result != null});
    }
    if (sub.length >= 2 && sub[1] == 'groups') {
      return _handleGroups(request, method, board, sub.skip(2).toList());
    }
    if (sub.length == 4 &&
        sub[1] == 'panels' &&
        sub[3] == 'lock') {
      final panelId = Uri.decodeComponent(sub[2]);
      final panel = _findPanel(board, panelId);
      if (panel == null) {
        return jsonResponse(
          <String, Object?>{'ok': false, 'error': 'panel not found'},
          404,
        );
      }
      if (method == 'PUT') {
        final body = await readJsonBody(request);
        final actorId = (body['actorId'] as String? ?? '').trim();
        final ttlSec = (body['ttlSec'] as num?)?.toInt() ?? 60;
        if (actorId.isEmpty) {
          return jsonResponse(
            <String, Object?>{'ok': false, 'error': 'actorId required'},
            400,
          );
        }
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        final existing =
            (board.metadata['panelLocks'] as Map?)?[panelId];
        if (existing is Map) {
          final existingActor = existing['actorId'] as String?;
          final existingExpires = existing['expiresAt'];
          if (existingActor != actorId &&
              existingExpires is int &&
              existingExpires > now) {
            return jsonResponse(
              <String, Object?>{
                'ok': false,
                'error': 'panel locked by another actor',
                'actorId': existingActor,
              },
              409,
            );
          }
        }
        final expires = now + ttlSec * 1000;
        await store.updateBoard(
          board.id,
          (current) {
            final locks =
                current.metadata['panelLocks'] is Map
                    ? Map<String, dynamic>.from(
                      current.metadata['panelLocks'] as Map,
                    )
                    : <String, dynamic>{};
            locks[panelId] = {'actorId': actorId, 'expiresAt': expires};
            return current.copyWith(
              metadata: <String, dynamic>{...current.metadata, 'panelLocks': locks},
            );
          },
        );
        return jsonResponse(
          <String, Object?>{'ok': true, 'panelId': panelId, 'actorId': actorId},
        );
      }
      if (method == 'DELETE') {
        await store.updateBoard(
          board.id,
          (current) {
            final locks =
                current.metadata['panelLocks'] is Map
                    ? Map<String, dynamic>.from(
                      current.metadata['panelLocks'] as Map,
                    )
                    : <String, dynamic>{};
            if (!locks.containsKey(panelId)) return current;
            final next = Map<String, dynamic>.from(locks)..remove(panelId);
            return current.copyWith(
              metadata: <String, dynamic>{...current.metadata, 'panelLocks': next},
            );
          },
        );
        return jsonResponse(
          <String, Object?>{'ok': true, 'panelId': panelId},
        );
      }
      return jsonResponse(
        <String, Object?>{'ok': false, 'error': 'method not allowed'},
        405,
      );
    }
    return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  Future<shelf.Response> _handleTemplates(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    if (sub.isEmpty && method == 'GET') {
      return jsonResponse(<String, Object?>{
        'ok': true,
        'templates': const <Map<String, Object?>>[],
      });
    }
    if (sub.isEmpty && method == 'POST') {
      return jsonResponse(<String, Object?>{
        'ok': true,
        'message': 'Templates synced',
        'templates': const <Map<String, Object?>>[],
      });
    }
    if (sub.length == 1 && method == 'GET') {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'Template not found',
      }, 404);
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

  List<Map<String, Object?>> _fileRoots() {
    return buildUniqueRoots({
      'Home': homePath(),
      'YoLoIT data': store.rootDir.path,
      'Current': Directory.current.path,
    })
        .entries
        .map(
          (e) => <String, Object?>{
            'name': e.key,
            'path': e.value,
            'isDirectory': true,
          },
        )
        .toList();
  }

  String _defaultFileRoot() => homePath() ?? store.rootDir.path;

  static bool _isSnapshotUpdate(Map<String, dynamic> body) {
    return body.containsKey('panels') ||
        body.containsKey('links') ||
        body.containsKey('drawings');
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
      viewport: current.viewport,
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
      return jsonResponse(<String, Object?>{
        'panels': board.panels.map(_panelSummary).toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await readJsonBody(request);
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
      return jsonResponse(<String, Object?>{
        'ok': true,
        'panel': created.toJson(),
        'id': created.id,
      });
    }
    if (sub.isEmpty) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'method not allowed',
      }, 405);
    }
    final panelId = Uri.decodeComponent(sub[0]);
    final panel = _findPanel(board, panelId);
    if (panel == null) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'panel not found',
      }, 404);
    }
    if (sub.length == 1 && method == 'GET') {
      return jsonResponse(<String, Object?>{
        ...panel.toJson(),
        'typeName': panel.type,
        'content': panel.state,
        'supportedActions':
            yoloitdPanelDescriptorFor(panel.type)?.actions ??
            const <String>['get', 'set'],
        'actionHelp': remotePanelActionHelp(panel),
      });
    }
    if (sub.length == 1 && method == 'DELETE') {
      final ok = await store.removePanel(board.id, panel.id);
      return jsonResponse(<String, Object?>{'ok': ok});
    }
    if (sub.length == 1 && method == 'PUT') {
      final body = await readJsonBody(request);
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
          zIndex: (body['zIndex'] as num?)?.toInt(),
          color: _parseColorValue(body['color']),
          state:
              body['state'] is Map
                  ? Map<String, dynamic>.from(body['state'] as Map)
                  : current.state,
        ),
      );
      return jsonResponse(<String, Object?>{
        'ok': updated != null,
        'panel': updated?.toJson(),
      });
    }
    if (sub.length == 2 && sub[1] == 'action' && method == 'POST') {
      final body = await readJsonBody(request);
      final action = body['action'] as String? ?? 'get';
      final result = handleRemotePanelAction(panel, action, body);
      if (!result.ok) {
        return jsonResponse(result.toJson(), 400);
      }
      if (result.stateUpdate.isEmpty) {
        return jsonResponse(<String, Object?>{
          ...result.toJson(),
          'content': result.data.isEmpty ? panel.state : result.data,
        });
      }
      final nextState = <String, dynamic>{
        ...panel.state,
        ...result.stateUpdate,
      };
      final updated = await store.updatePanel(
        board.id,
        panel.id,
        (current) => current.copyWith(state: nextState),
      );
      return jsonResponse(result.toJson(panel: updated));
    }
    return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  Future<shelf.Response> _handleGroups(
    shelf.Request request,
    String method,
    RemoteBoard board,
    List<String> sub,
  ) async {
    final groups = _boardGroups(board);

    if (sub.isEmpty && method == 'GET') {
      return jsonResponse(<String, Object?>{'ok': true, 'groups': groups});
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await readJsonBody(request);
      final name = (body['name'] as String? ?? '').trim();
      if (name.isEmpty) {
        return jsonResponse(<String, Object?>{
          'ok': false,
          'error': 'name required',
        }, 400);
      }
      final group = <String, dynamic>{
        'id': _nextId('g'),
        'name': name,
        'panelIds': _parsePanelIds(board, body['panels']),
        if (body['color'] != null && body['color'] != 'clear')
          'color': body['color'],
      };
      groups.add(group);
      final result = await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          metadata: <String, dynamic>{...current.metadata, 'groups': groups},
        ),
      );
      return jsonResponse(<String, Object?>{
        'ok': result != null,
        'group': group,
      });
    }

    if (sub.isEmpty) {
      return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
    }

    final groupId = Uri.decodeComponent(sub[0]);
    final index = groups.indexWhere((group) => group['id'] == groupId);
    if (index < 0) {
      return jsonResponse(<String, Object?>{
        'ok': false,
        'error': 'group not found',
      }, 404);
    }

    if (sub.length == 1 && method == 'DELETE') {
      groups.removeAt(index);
      await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          metadata: <String, dynamic>{...current.metadata, 'groups': groups},
        ),
      );
      return jsonResponse(<String, Object?>{'ok': true, 'message': 'Group deleted'});
    }

    if (sub.length == 1 && method == 'PUT') {
      final body = await readJsonBody(request);
      final group = Map<String, dynamic>.from(groups[index]);
      if (body['name'] is String) group['name'] = body['name'];
      if (body.containsKey('color')) {
        if (body['color'] == null || body['color'] == 'clear') {
          group.remove('color');
        } else {
          group['color'] = body['color'];
        }
      }
      if (body['collapsed'] is bool) group['collapsed'] = body['collapsed'];
      groups[index] = group;
      await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          metadata: <String, dynamic>{...current.metadata, 'groups': groups},
        ),
      );
      return jsonResponse(<String, Object?>{'ok': true, 'group': group});
    }

    if (sub.length == 2 && sub[1] == 'panels' && method == 'POST') {
      final body = await readJsonBody(request);
      final ids = _parsePanelIds(board, body['panels']);
      final group = Map<String, dynamic>.from(groups[index]);
      final panelIds = _stringList(group['panelIds']).toSet()..addAll(ids);
      group['panelIds'] = panelIds.toList();
      groups[index] = group;
      await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          metadata: <String, dynamic>{...current.metadata, 'groups': groups},
        ),
      );
      return jsonResponse(<String, Object?>{
        'ok': true,
        'message': 'Panels added to group',
      });
    }

    if (sub.length == 2 && sub[1] == 'panels' && method == 'DELETE') {
      final body = await readJsonBody(request);
      final ids = _parsePanelIds(board, body['panels']);
      final group = Map<String, dynamic>.from(groups[index]);
      group['panelIds'] = _stringList(group['panelIds'])
          .where((String id) => !ids.contains(id))
          .toList();
      groups[index] = group;
      await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          metadata: <String, dynamic>{...current.metadata, 'groups': groups},
        ),
      );
      return jsonResponse(<String, Object?>{
        'ok': true,
        'message': 'Panels removed from group',
      });
    }

    if (sub.length == 2 && sub[1] == 'move' && method == 'POST') {
      final body = await readJsonBody(request);
      final dx = (body['dx'] as num?)?.toDouble() ?? 0.0;
      final dy = (body['dy'] as num?)?.toDouble() ?? 0.0;
      final group = groups[index];
      final panelIds = _stringList(group['panelIds']).toSet();
      await store.updateBoard(
        board.id,
        (current) => current.copyWith(
          panels: current.panels.map((panel) {
            if (!panelIds.contains(panel.id)) return panel;
            return panel.copyWith(
              bounds: panel.bounds.copyWith(
                x: panel.bounds.x + dx,
                y: panel.bounds.y + dy,
              ),
            );
          }).toList(),
        ),
      );
      return jsonResponse(<String, Object?>{'ok': true, 'message': 'Group moved'});
    }

    return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
  }

  List<Map<String, dynamic>> _boardGroups(RemoteBoard board) {
    final raw = board.metadata['groups'];
    if (raw is List) {
      return raw.whereType<Map<Object?, Object?>>().map(
        (entry) => Map<String, dynamic>.from(entry),
      ).toList();
    }
    return <Map<String, dynamic>>[];
  }

  List<String> _parsePanelIds(RemoteBoard board, dynamic value) {
    List<String> rawIds() {
      if (value is String) {
        return value.split(',').map((part) => part.trim()).where(
          (part) => part.isNotEmpty,
        ).toList();
      }
      if (value is List) {
        return value.map((entry) => entry.toString().trim()).where(
          (part) => part.isNotEmpty,
        ).toList();
      }
      return const <String>[];
    }

    return rawIds().map((id) => _findPanel(board, id)?.id ?? id).toList();
  }

  int? _parseColorValue(dynamic value) {
    if (value == null || value == 'clear') return null;
    if (value is int) return value;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'clear') return null;
    if (text.startsWith('#')) {
      final hex = text.substring(1);
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((entry) => entry.toString().trim()).where(
        (part) => part.isNotEmpty,
      ).toList();
    }
    if (value is String) {
      return value.split(',').map((part) => part.trim()).where(
        (part) => part.isNotEmpty,
      ).toList();
    }
    return const <String>[];
  }

  Future<shelf.Response> _handleRuns(
    shelf.Request request,
    String method,
    List<String> sub,
  ) async {
    if (sub.isEmpty && method == 'GET') {
      final ids =
          <String>{
              ...runs.keys,
              ...runExitCodes.keys,
              ...runLogs.keys,
            }.toList()
            ..sort();
      return jsonResponse(<String, Object?>{
        'runs':
            ids
                .map(
                  (id) => <String, Object?>{
                    'id': id,
                    'running':
                        runs.containsKey(id) || activeTaskRuns.contains(id),
                    if (runExitCodes.containsKey(id)) 'exitCode': runExitCodes[id],
                    'logLines': runLogs[id]?.length ?? 0,
                  },
                )
                .toList(),
      });
    }
    if (sub.isEmpty && method == 'POST') {
      final body = await readJsonBody(request);
      final command = (body['command'] as String? ?? '').trim();
      if (command.isEmpty) {
        return jsonResponse(<String, Object?>{
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
      runs[id] = process;
      runLogs[id] = <String>[];
      unawaited(collectRun(id, process));
      return jsonResponse(
        <String, Object?>{'ok': true, 'id': id, 'pid': process.pid},
      );
    }
    if (sub.length == 2 && sub[1] == 'log' && method == 'GET') {
      return jsonResponse(<String, Object?>{
        'id': sub[0],
        'lines': runLogs[sub[0]] ?? const <String>[],
      });
    }
    if (sub.length == 2 && sub[1] == 'stop' && method == 'POST') {
      final process = runs.remove(sub[0]);
      final ok = process?.kill() ?? false;
      return jsonResponse(<String, Object?>{'ok': ok});
    }
    return jsonResponse(<String, Object?>{'ok': false, 'error': 'not found'}, 404);
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
        store.rootDir.path,
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
      defaultCwd: store.rootDir.path,
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

  bool _authorized(shelf.Request request) => isAuthorized(request, token);

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
}
