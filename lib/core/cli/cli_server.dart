import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';

/// Local HTTP server that exposes YoLoIT board functionality via a REST-like
/// API on `localhost`. A companion CLI script (`tools/yoloit`) communicates
/// with this server so that boards, panels and their content can be managed
/// from the terminal.
///
/// Start the server once from the app's widget tree:
/// ```dart
/// CliServer.instance.start(boardCubit);
/// ```
class CliServer {
  CliServer._();
  static final CliServer instance = CliServer._();

  HttpServer? _server;
  BoardCubit? _cubit;

  /// Port file written so the CLI client knows which port to connect to.
  static String get _portFilePath =>
      '${Platform.environment['HOME'] ?? '/tmp'}/.config/yoloit/cli.port';

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  int? get port => _server?.port;

  // ── Panel CLI handler registry ──────────────────────────────────────────

  final Map<String, PanelCliHandler> _panelHandlers = {};

  void registerPanelHandler(PanelCliHandler handler) {
    _panelHandlers[handler.typeId] = handler;
  }

  PanelCliHandler? handlerFor(String typeId) => _panelHandlers[typeId];

  // ── UI-thread helper ────────────────────────────────────────────────────

  /// Schedule a UI frame so Flutter repaints after a cubit mutation.
  /// Shelf runs on the same isolate, so cubit mutations work directly —
  /// we just need to tell the engine a new frame is needed.
  void _scheduleRebuild() {
    try {
      SchedulerBinding.instance.scheduleFrame();
    } catch (_) {}
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> start(BoardCubit cubit) async {
    // If server is already running but cubit changed (e.g. after hot restart),
    // update cubit reference and return — routes close over _cubit field.
    if (_server != null) {
      _cubit = cubit;
      return;
    }
    _cubit = cubit;

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests(logger: (msg, isError) {
          if (isError) debugPrint('[CLI] ERROR: $msg');
        }))
        .addHandler(_router);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
      _writePortFile(_server!.port);
      debugPrint('[CliServer] listening on localhost:${_server!.port}');
    } catch (e) {
      debugPrint('[CliServer] failed to start: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _cubit = null;
    _deletePortFile();
  }

  // ── Port file ──────────────────────────────────────────────────────────

  void _writePortFile(int port) {
    try {
      final file = File(_portFilePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$port');
    } catch (_) {}
  }

  void _deletePortFile() {
    try {
      final file = File(_portFilePath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  // ── Router ─────────────────────────────────────────────────────────────

  FutureOr<shelf.Response> _router(shelf.Request request) async {
    final segments = request.url.pathSegments;
    final method = request.method;

    // Health check
    if (segments.isEmpty || (segments.length == 1 && segments[0] == 'health')) {
      return _json({'status': 'ok', 'port': _server?.port});
    }

    // Must start with /api
    if (segments.isEmpty || segments[0] != 'api') {
      return _notFound('Unknown route');
    }
    final path = segments.sublist(1);
    return _handleApi(method, path, request);
  }

  Future<shelf.Response> _handleApi(
    String method,
    List<String> path,
    shelf.Request request,
  ) async {
    final cubit = _cubit;
    if (cubit == null) return _error('Board cubit not available');

    // GET /api/boards
    if (path.length == 1 && path[0] == 'boards' && method == 'GET') {
      return _listBoards(cubit);
    }

    // POST /api/boards  { name: "..." }
    if (path.length == 1 && path[0] == 'boards' && method == 'POST') {
      final body = await _body(request);
      return _createBoard(cubit, body);
    }

    // /api/boards/:boardIdOrName/...
    if (path.length >= 2 && path[0] == 'boards') {
      final board = _findBoard(cubit, path[1]);
      if (board == null) return _notFound('Board not found: ${path[1]}');

      final sub = path.sublist(2);
      return _handleBoard(method, sub, board, cubit, request);
    }

    return _notFound('Unknown route');
  }

  // ── Board routes ────────────────────────────────────────────────────────

  Future<shelf.Response> _handleBoard(
    String method,
    List<String> sub,
    BoardDocument board,
    BoardCubit cubit,
    shelf.Request request,
  ) async {
    // GET /api/boards/:id → board details
    if (sub.isEmpty && method == 'GET') {
      return _boardDetails(board);
    }
    // PUT /api/boards/:id → update board (rename, focus)
    if (sub.isEmpty && method == 'PUT') {
      final body = await _body(request);
      return _updateBoard(cubit, board, body);
    }
    // DELETE /api/boards/:id → delete board
    if (sub.isEmpty && method == 'DELETE') {
      await cubit.deleteBoard(board.id);
      _scheduleRebuild();
      return _json({'ok': true, 'message': 'Deleted board ${board.name}'});
    }
    // GET /api/boards/:id/snapshot
    if (sub.length == 1 && sub[0] == 'snapshot' && method == 'GET') {
      return _boardSnapshot(board);
    }
    // GET /api/boards/:id/panels
    if (sub.length == 1 && sub[0] == 'panels' && method == 'GET') {
      return _listPanels(board);
    }
    // POST /api/boards/:id/panels → create panel
    if (sub.length == 1 && sub[0] == 'panels' && method == 'POST') {
      final body = await _body(request);
      return _createPanel(cubit, board, body);
    }
    // /api/boards/:id/panels/:panelIdOrTitle/...
    if (sub.length >= 2 && sub[0] == 'panels') {
      final panel = _findPanel(board, sub[1]);
      if (panel == null) return _notFound('Panel not found: ${sub[1]}');
      final panelSub = sub.sublist(2);
      return _handlePanel(method, panelSub, board, panel, cubit, request);
    }
    // GET /api/boards/:id/links
    if (sub.length == 1 && sub[0] == 'links' && method == 'GET') {
      return _listLinks(board);
    }
    // POST /api/boards/:id/links → create link
    if (sub.length == 1 && sub[0] == 'links' && method == 'POST') {
      final body = await _body(request);
      return _createLink(cubit, board, body);
    }
    // DELETE /api/boards/:id/links/:linkId
    if (sub.length == 2 && sub[0] == 'links' && method == 'DELETE') {
      await cubit.removeLink(sub[1], boardId: board.id);
      _scheduleRebuild();
      return _json({'ok': true, 'message': 'Link deleted'});
    }
    // PUT /api/boards/:id/viewport → set scale/translation
    if (sub.length == 1 && sub[0] == 'viewport' && method == 'PUT') {
      final body = await _body(request);
      return _updateViewport(cubit, board, body);
    }
    // POST /api/boards/:id/fit → auto-fit viewport to show all panels
    if (sub.length == 1 && sub[0] == 'fit' && method == 'POST') {
      final body = await _body(request);
      return _fitViewport(cubit, board, body);
    }

    return _notFound('Unknown board route');
  }

  // ── Panel routes ────────────────────────────────────────────────────────

  Future<shelf.Response> _handlePanel(
    String method,
    List<String> sub,
    BoardDocument board,
    BoardPanelInstance panel,
    BoardCubit cubit,
    shelf.Request request,
  ) async {
    // GET .../panels/:id → panel details + content
    if (sub.isEmpty && method == 'GET') {
      return _panelDetails(panel);
    }
    // PUT .../panels/:id → update panel props
    if (sub.isEmpty && method == 'PUT') {
      final body = await _body(request);
      return _updatePanel(cubit, board, panel, body);
    }
    // DELETE .../panels/:id
    if (sub.isEmpty && method == 'DELETE') {
      await cubit.removePanel(panel.id, boardId: board.id);
      _scheduleRebuild();
      return _json({'ok': true, 'message': 'Panel deleted'});
    }
    // POST .../panels/:id/action  { action: "send", ... }
    if (sub.length == 1 && sub[0] == 'action' && method == 'POST') {
      final body = await _body(request);
      return _panelAction(cubit, board, panel, body);
    }

    return _notFound('Unknown panel route');
  }

  // ── Board implementations ──────────────────────────────────────────────

  shelf.Response _listBoards(BoardCubit cubit) {
    final boards = cubit.state.boards;
    final active = cubit.state.activeBoardId;
    return _json({
      'boards': boards.map((b) => {
        'id': b.id,
        'name': b.name,
        'panelCount': b.panels.length,
        'linkCount': b.links.length,
        'active': b.id == active,
      }).toList(),
    });
  }

  Future<shelf.Response> _createBoard(
    BoardCubit cubit,
    Map<String, dynamic> body,
  ) async {
    final name = body['name'] as String? ?? 'New Board';
    final board = await cubit.createBoard(name: name);
    _scheduleRebuild();
    if (board == null) return _error('Failed to create board');
    return _json({
      'ok': true,
      'board': {'id': board.id, 'name': board.name},
    });
  }

  shelf.Response _boardDetails(BoardDocument board) {
    return _json({
      'id': board.id,
      'name': board.name,
      'viewport': {
        'scale': board.viewport.scale,
        'translationX': board.viewport.translation.dx,
        'translationY': board.viewport.translation.dy,
        'focusedPanelId': board.viewport.focusedPanelId,
      },
      'panelCount': board.panels.length,
      'linkCount': board.links.length,
      'panels': board.panels.map(_panelSummary).toList(),
    });
  }

  shelf.Response _boardSnapshot(BoardDocument board) {
    final lines = <String>[];
    lines.add('# Board: ${board.name}');
    lines.add('');
    lines.add('## Panels (${board.panels.length})');
    lines.add('');
    lines.add('| # | ID | Type | Title | Position | Size | Z |');
    lines.add('|---|-----|------|-------|----------|------|---|');
    for (var i = 0; i < board.panels.length; i++) {
      final p = board.panels[i];
      final plugin = BoardPluginRegistry.instance.pluginFor(p.type);
      final typeName = plugin?.displayName ?? p.type;
      lines.add(
        '| ${i + 1} | `${_short(p.id)}` | $typeName | ${p.title} '
        '| (${p.bounds.x.toInt()}, ${p.bounds.y.toInt()}) '
        '| ${p.bounds.width.toInt()}×${p.bounds.height.toInt()} '
        '| ${p.zIndex} |',
      );
    }
    if (board.links.isNotEmpty) {
      lines.add('');
      lines.add('## Links (${board.links.length})');
      lines.add('');
      for (final link in board.links) {
        final from = board.panels
            .where((p) => p.id == link.fromPanelId)
            .firstOrNull
            ?.title ?? _short(link.fromPanelId);
        final to = board.panels
            .where((p) => p.id == link.toPanelId)
            .firstOrNull
            ?.title ?? _short(link.toPanelId);
        lines.add('- $from → $to (${link.style.name}, ${link.geometry.name})');
      }
    }
    return shelf.Response.ok(
      lines.join('\n'),
      headers: {'content-type': 'text/markdown; charset=utf-8'},
    );
  }

  Future<shelf.Response> _updateBoard(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('name')) {
      await cubit.renameBoard(board.id, body['name'] as String);
      _scheduleRebuild();
    }
    if (body['focus'] == true) {
      await cubit.setActiveBoard(board.id);
      _scheduleRebuild();
    }
    // Viewport update: scale, x (translationX), y (translationY)
    if (body.containsKey('scale') || body.containsKey('x') || body.containsKey('y')) {
      final scale = (body['scale'] as num?)?.toDouble() ?? board.viewport.scale;
      final tx = (body['x'] as num?)?.toDouble() ?? board.viewport.translation.dx;
      final ty = (body['y'] as num?)?.toDouble() ?? board.viewport.translation.dy;
      final vp = board.viewport.copyWith(
        scale: scale.clamp(0.1, 4.0),
        translation: Offset(tx, ty),
      );
      await cubit.updateViewport(vp, boardId: board.id);
      _scheduleRebuild();
    }
    // Fit all panels: fit=true auto-calculates scale+translation
    if (body['fit'] == true) {
      final panels = board.panels.where((p) => !p.hidden).toList();
      if (panels.isNotEmpty) {
        final minX = panels.map((p) => p.bounds.x).reduce((a, b) => a < b ? a : b);
        final minY = panels.map((p) => p.bounds.y).reduce((a, b) => a < b ? a : b);
        final maxX = panels.map((p) => p.bounds.x + p.bounds.width).reduce((a, b) => a > b ? a : b);
        final maxY = panels.map((p) => p.bounds.y + p.bounds.height).reduce((a, b) => a > b ? a : b);
        const pad = 80.0;
        final vpW = (body['viewportWidth'] as num?)?.toDouble() ?? 1280.0;
        final vpH = (body['viewportHeight'] as num?)?.toDouble() ?? 800.0;
        final scaleX = (vpW - pad * 2) / (maxX - minX);
        final scaleY = (vpH - pad * 2) / (maxY - minY);
        final s = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 2.0);
        final tx = (vpW - (maxX - minX) * s) / 2 - minX * s;
        final ty = (vpH - (maxY - minY) * s) / 2 - minY * s;
        final vp = board.viewport.copyWith(scale: s, translation: Offset(tx, ty));
        await cubit.updateViewport(vp, boardId: board.id);
        _scheduleRebuild();
      }
    }
    return _json({'ok': true});
  }

  // ── Panel implementations ──────────────────────────────────────────────

  shelf.Response _listPanels(BoardDocument board) {
    return _json({
      'panels': board.panels.map(_panelSummary).toList(),
    });
  }

  Future<shelf.Response> _createPanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> body,
  ) async {
    final typeId = body['type'] as String?;
    if (typeId == null) return _error('Missing "type" field');

    final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
    if (plugin == null) return _error('Unknown panel type: $typeId');

    final title = body['title'] as String? ?? plugin.displayName;
    final x = (body['x'] as num?)?.toDouble() ?? 100;
    final y = (body['y'] as num?)?.toDouble() ?? 100;
    final w = (body['width'] as num?)?.toDouble() ?? plugin.defaultSize.width;
    final h = (body['height'] as num?)?.toDouble() ?? plugin.defaultSize.height;
    final state = body['state'] as Map<String, dynamic>? ?? plugin.initialState;

    final panelId = 'p-${DateTime.now().millisecondsSinceEpoch}';
    final panel = BoardPanelInstance(
      id: panelId,
      type: typeId,
      title: title,
      bounds: BoardPanelBounds(x: x, y: y, width: w, height: h),
      state: state,
    );
    await cubit.addPanel(panel, boardId: board.id);
    _scheduleRebuild();
    return _json({
      'ok': true,
      'panel': _panelSummary(panel),
    });
  }

  shelf.Response _panelDetails(BoardPanelInstance panel) {
    final handler = _panelHandlers[panel.type];
    final content = handler?.getContent(panel);
    return _json({
      ..._panelSummary(panel),
      'state': panel.state,
      if (content != null) 'content': content,
      if (handler != null) 'supportedActions': handler.supportedActions,
    });
  }

  Future<shelf.Response> _updatePanel(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('title')) {
      await cubit.updatePanelTitle(
        panel.id,
        body['title'] as String,
        boardId: board.id,
      );
      _scheduleRebuild();
    }
    if (body.containsKey('x') || body.containsKey('y')) {
      final dx = ((body['x'] as num?)?.toDouble() ?? panel.bounds.x) - panel.bounds.x;
      final dy = ((body['y'] as num?)?.toDouble() ?? panel.bounds.y) - panel.bounds.y;
      await cubit.movePanel(panel.id, Offset(dx, dy), boardId: board.id);
      _scheduleRebuild();
    }
    if (body.containsKey('width') || body.containsKey('height')) {
      await cubit.resizePanel(
        panel.id,
        width: (body['width'] as num?)?.toDouble() ?? panel.bounds.width,
        height: (body['height'] as num?)?.toDouble() ?? panel.bounds.height,
        boardId: board.id,
      );
      _scheduleRebuild();
    }
    if (body['focus'] == true) {
      await cubit.focusPanel(panel.id, boardId: board.id);
      _scheduleRebuild();
    }
    return _json({'ok': true});
  }

  Future<shelf.Response> _panelAction(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    final action = body['action'] as String?;
    if (action == null) return _error('Missing "action" field');

    final handler = _panelHandlers[panel.type];
    if (handler == null) {
      return _error('No CLI handler for panel type: ${panel.type}');
    }
    if (!handler.supportedActions.contains(action)) {
      return _error(
        'Unsupported action "$action" for ${panel.type}. '
        'Supported: ${handler.supportedActions.join(', ')}',
      );
    }

    final result = await handler.handleAction(action, body, panel);

    // Apply state update if provided
    if (result.stateUpdate != null && result.ok) {
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(state: {...p.state, ...result.stateUpdate!}),
        boardId: board.id,
      );
      _scheduleRebuild();
    }

    return _json(result.toJson());
  }

  // ── Viewport implementations ───────────────────────────────────────────

  Future<shelf.Response> _updateViewport(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> body,
  ) async {
    final scale = (body['scale'] as num?)?.toDouble() ?? board.viewport.scale;
    final tx = (body['x'] as num?)?.toDouble() ?? board.viewport.translation.dx;
    final ty = (body['y'] as num?)?.toDouble() ?? board.viewport.translation.dy;
    final vp = board.viewport.copyWith(
      scale: scale.clamp(0.1, 4.0),
      translation: Offset(tx, ty),
    );
    await cubit.updateViewport(vp, boardId: board.id);
    _scheduleRebuild();
    return _json({'ok': true, 'viewport': {'scale': vp.scale, 'x': vp.translation.dx, 'y': vp.translation.dy}});
  }

  Future<shelf.Response> _fitViewport(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> body,
  ) async {
    final panels = board.panels.where((p) => !p.hidden).toList();
    if (panels.isEmpty) return _error('No panels to fit');

    // Bounding box of all panels
    final minX = panels.map((p) => p.bounds.x).reduce((a, b) => a < b ? a : b);
    final minY = panels.map((p) => p.bounds.y).reduce((a, b) => a < b ? a : b);
    final maxX = panels.map((p) => p.bounds.x + p.bounds.width).reduce((a, b) => a > b ? a : b);
    final maxY = panels.map((p) => p.bounds.y + p.bounds.height).reduce((a, b) => a > b ? a : b);

    final contentW = maxX - minX;
    final contentH = maxY - minY;
    const padding = 80.0;

    // Viewport size hint from body (fallback to 1280×800 typical window)
    final vpW = (body['viewportWidth'] as num?)?.toDouble() ?? 1280.0;
    final vpH = (body['viewportHeight'] as num?)?.toDouble() ?? 800.0;

    final scaleX = (vpW - padding * 2) / contentW;
    final scaleY = (vpH - padding * 2) / contentH;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 2.0);

    // Center content in viewport
    final scaledW = contentW * scale;
    final scaledH = contentH * scale;
    final tx = (vpW - scaledW) / 2 - minX * scale;
    final ty = (vpH - scaledH) / 2 - minY * scale;

    final vp = board.viewport.copyWith(
      scale: scale,
      translation: Offset(tx, ty),
    );
    await cubit.updateViewport(vp, boardId: board.id);
    _scheduleRebuild();
    return _json({
      'ok': true,
      'viewport': {'scale': vp.scale, 'x': vp.translation.dx, 'y': vp.translation.dy},
      'bounds': {'minX': minX, 'minY': minY, 'maxX': maxX, 'maxY': maxY},
    });
  }

  // ── Link implementations ───────────────────────────────────────────────

  shelf.Response _listLinks(BoardDocument board) {
    return _json({
      'links': board.links.map((l) => {
        'id': l.id,
        'from': l.fromPanelId,
        'to': l.toPanelId,
        'style': l.style.name,
        'geometry': l.geometry.name,
      }).toList(),
    });
  }

  Future<shelf.Response> _createLink(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> body,
  ) async {
    final fromRaw = body['from'] as String?;
    final toRaw = body['to'] as String?;
    if (fromRaw == null || toRaw == null) {
      return _error('Missing "from" or "to" panel id');
    }

    // Resolve panel names/titles to actual IDs.
    final fromPanel = _findPanel(board, fromRaw);
    final toPanel = _findPanel(board, toRaw);
    if (fromPanel == null) return _error('Panel not found: $fromRaw');
    if (toPanel == null) return _error('Panel not found: $toRaw');

    final styleStr = body['style'] as String? ?? 'arrow';
    final geoStr = body['geometry'] as String? ?? 'bezier';

    final style = BoardLinkStyle.values.firstWhere(
      (s) => s.name == styleStr,
      orElse: () => BoardLinkStyle.arrow,
    );
    final geo = BoardLinkGeometry.values.firstWhere(
      (g) => g.name == geoStr,
      orElse: () => BoardLinkGeometry.bezier,
    );

    final link = BoardPanelLink(
      id: 'link-${DateTime.now().millisecondsSinceEpoch}',
      fromPanelId: fromPanel.id,
      toPanelId: toPanel.id,
      style: style,
      geometry: geo,
    );
    await cubit.upsertLink(link, boardId: board.id);
    _scheduleRebuild();
    return _json({'ok': true, 'link': {'id': link.id}});
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  BoardDocument? _findBoard(BoardCubit cubit, String idOrName) {
    final boards = cubit.state.boards;
    // Exact id match
    final byId = boards.where((b) => b.id == idOrName).firstOrNull;
    if (byId != null) return byId;
    // Exact name match (case-insensitive)
    final byName = boards
        .where((b) => b.name.toLowerCase() == idOrName.toLowerCase())
        .firstOrNull;
    if (byName != null) return byName;
    // Partial id match
    return boards.where((b) => b.id.startsWith(idOrName)).firstOrNull;
  }

  BoardPanelInstance? _findPanel(BoardDocument board, String idOrTitle) {
    final panels = board.panels;
    final byId = panels.where((p) => p.id == idOrTitle).firstOrNull;
    if (byId != null) return byId;
    final byTitle = panels
        .where((p) => p.title.toLowerCase() == idOrTitle.toLowerCase())
        .firstOrNull;
    if (byTitle != null) return byTitle;
    return panels.where((p) => p.id.startsWith(idOrTitle)).firstOrNull;
  }

  Map<String, dynamic> _panelSummary(BoardPanelInstance p) {
    final plugin = BoardPluginRegistry.instance.pluginFor(p.type);
    return {
      'id': p.id,
      'type': p.type,
      'typeName': plugin?.displayName ?? p.type,
      'title': p.title,
      'bounds': {
        'x': p.bounds.x,
        'y': p.bounds.y,
        'width': p.bounds.width,
        'height': p.bounds.height,
      },
      'zIndex': p.zIndex,
      'hidden': p.hidden,
      'locked': p.locked,
      'pinned': p.pinned,
    };
  }

  String _short(String id) => id.length > 12 ? '${id.substring(0, 12)}…' : id;

  Future<Map<String, dynamic>> _body(shelf.Request request) async {
    try {
      final raw = await request.readAsString();
      if (raw.isEmpty) return {};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  shelf.Response _json(Object data) => shelf.Response.ok(
    jsonEncode(data),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  shelf.Response _error(String msg) => shelf.Response(
    400,
    body: jsonEncode({'ok': false, 'error': msg}),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  shelf.Response _notFound(String msg) => shelf.Response.notFound(
    jsonEncode({'ok': false, 'error': msg}),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
