import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yaml/yaml.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';
import 'package:yoloit/core/cli/board_svg_exporter.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

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
  final Set<String> _warnedActionHelpTypes = <String>{};

  /// Port file written so the CLI client knows which port to connect to.
  static String get _portFilePath =>
      '${Platform.environment['HOME'] ?? '/tmp'}/.config/yoloit/cli.port';

  /// VM service URI file so the CLI can trigger hot reload/restart.
  static String get _vmServiceFilePath =>
      '${Platform.environment['HOME'] ?? '/tmp'}/.config/yoloit/cli.vmservice';

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
        .addMiddleware(
          shelf.logRequests(
            logger: (msg, isError) {
              if (isError) debugPrint('[CLI] ERROR: $msg');
            },
          ),
        )
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
    // Also write VM service URI for hot reload support
    _writeVmServiceFile();
  }

  void _writeVmServiceFile() {
    try {
      developer.Service.getInfo().then((info) {
        final uri = info.serverWebSocketUri;
        if (uri != null) {
          final file = File(_vmServiceFilePath);
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(uri.toString());
        }
      });
    } catch (_) {}
  }

  void _deletePortFile() {
    try {
      final file = File(_portFilePath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    try {
      final file = File(_vmServiceFilePath);
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

    // GET /api/vmservice → return VM service WebSocket URI for hot reload
    if (path.length == 1 && path[0] == 'vmservice' && method == 'GET') {
      _writeVmServiceFile(); // refresh
      final f = File(_vmServiceFilePath);
      final uri = f.existsSync() ? f.readAsStringSync().trim() : '';
      return _json({'vmServiceWsUri': uri, 'ok': uri.isNotEmpty});
    }

    // /api/local-models/...
    if (path.isNotEmpty && path[0] == 'local-models') {
      return _handleLocalModels(method, path.sublist(1), request);
    }

    // POST /api/lm/generate  { messages: [...], systemPrompt?: "...", maxTokens?: 512 }
    if (path.length == 2 && path[0] == 'lm' && path[1] == 'generate' && method == 'POST') {
      return _handleLmGenerate(request);
    }

    // /api/yolochat/...
    if (path.isNotEmpty && path[0] == 'yolochat') {
      return _handleYoloChat(method, path.sublist(1), request, cubit);
    }

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

  Future<shelf.Response> _handleLocalModels(
    String method,
    List<String> sub,
    shelf.Request request,
  ) async {
    final service = LocalAiModelsService.instance;
    await service.initialize();

    if (sub.isEmpty && method == 'GET') {
      return _json(service.snapshot());
    }
    if (sub.length == 1 && sub[0] == 'download' && method == 'POST') {
      final body = await _body(request);
      final modelId = body['id'] as String?;
      if (modelId == null || modelId.trim().isEmpty) {
        return _error('Missing "id" field');
      }
      await service.downloadOrUpdateModel(modelId);
      return _json({'ok': true, 'action': 'download', 'id': modelId});
    }
    if (sub.length == 1 && sub[0] == 'resume' && method == 'POST') {
      final body = await _body(request);
      final modelId = body['id'] as String?;
      if (modelId == null || modelId.trim().isEmpty) {
        return _error('Missing "id" field');
      }
      await service.resumeModelDownload(modelId);
      return _json({'ok': true, 'action': 'resume', 'id': modelId});
    }
    if (sub.length == 1 && sub[0] == 'stop' && method == 'POST') {
      final body = await _body(request);
      final modelId = body['id'] as String?;
      if (modelId == null || modelId.trim().isEmpty) {
        return _error('Missing "id" field');
      }
      await service.pauseModelDownload(modelId);
      return _json({
        'ok': true,
        'action': 'pause',
        'id': modelId,
        'alias': 'stop',
      });
    }
    if (sub.length == 1 && sub[0] == 'pause' && method == 'POST') {
      final body = await _body(request);
      final modelId = body['id'] as String?;
      if (modelId == null || modelId.trim().isEmpty) {
        return _error('Missing "id" field');
      }
      await service.pauseModelDownload(modelId);
      return _json({'ok': true, 'action': 'pause', 'id': modelId});
    }
    if (sub.length == 1 && sub[0] == 'cancel' && method == 'POST') {
      final body = await _body(request);
      final modelId = body['id'] as String?;
      if (modelId == null || modelId.trim().isEmpty) {
        return _error('Missing "id" field');
      }
      await service.cancelModelDownload(modelId);
      return _json({'ok': true, 'action': 'cancel', 'id': modelId});
    }
    if (sub.length == 1 && sub[0] == 'delete' && method == 'POST') {
      final body = await _body(request);
      final modelId = body['id'] as String?;
      if (modelId == null || modelId.trim().isEmpty) {
        return _error('Missing "id" field');
      }
      await service.deleteInstalledModel(modelId);
      return _json({'ok': true, 'action': 'delete', 'id': modelId});
    }
    if (sub.length == 1 && sub[0] == 'select' && method == 'POST') {
      final body = await _body(request);
      final kind = body['kind'] as String?;
      final modelId = body['id'] as String?;
      if (kind == null || modelId == null) {
        return _error('Missing "kind" or "id" field');
      }
      if (kind == 'chat') {
        await service.setSelectedChatModel(modelId);
      } else if (kind == 'asr') {
        await service.setSelectedAsrModel(modelId);
      } else {
        return _error('Unsupported kind "$kind". Expected "chat" or "asr".');
      }
      return _json({
        'ok': true,
        'action': 'select',
        'kind': kind,
        'id': modelId,
      });
    }

    return _notFound('Unknown local-models route');
  }

  Future<shelf.Response> _handleLmGenerate(shelf.Request request) async {
    final body = await _body(request);
    final service = LocalAiModelsService.instance;
    final modelId = body['modelId'] as String? ?? service.selectedChatModelId;
    final systemPrompt = body['systemPrompt'] as String? ?? '';
    final rawMessages = body['messages'] as List<dynamic>? ?? [];
    final maxTokens = (body['maxTokens'] as num?)?.toInt() ?? 512;
    final temperature = (body['temperature'] as num?)?.toDouble() ?? 0.2;
    // enableThinking: explicit bool from body, or auto-false for Qwen3 models
    final bool? enableThinking = body.containsKey('enableThinking')
        ? (body['enableThinking'] as bool?)
        : (modelId.toLowerCase().contains('qwen3') ? false : null);

    await service.initialize();
    await service.ensureRuntimeReady();
    final installedInfo = service.installedModelById(modelId);
    if (installedInfo == null) {
      return _error('Model "$modelId" is not installed');
    }

    final messages = <Map<String, String>>[];
    if (systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in rawMessages) {
      if (m is Map) {
        messages.add({
          'role': m['role'] as String? ?? 'user',
          'content': m['content'] as String? ?? '',
        });
      }
    }
    if (messages.isEmpty || messages.last['role'] != 'user') {
      return _error('At least one user message is required');
    }

    try {
      final engine = flm.NativeLmEngine();
      final installed = flm.InstalledModel(
        manifest: installedInfo.manifest,
        directory: installedInfo.directory,
        sourceLabel: installedInfo.sourceLabel,
        installedAt: installedInfo.installedAt,
        sizeBytes: installedInfo.sizeBytes,
        metadataUpdatedAt: installedInfo.metadataUpdatedAt,
      );
      final t0 = DateTime.now();
      int firstTokenMs = -1;
      final buffer = StringBuffer();
      int tokenCount = 0;

      final full = await engine.completeStreaming(
        flm.LmCompletionRequest(
          modelPath: installed.directory.path,
          manifest: installed.manifest,
          messages: messages,
          maxTokens: maxTokens,
          temperature: temperature,
          enableThinking: enableThinking,
          tools: [],
        ),
        (chunk) {
          if (firstTokenMs < 0) {
            firstTokenMs = DateTime.now().difference(t0).inMilliseconds;
          }
          buffer.write(chunk);
          tokenCount++;
        },
      );

      final totalMs = DateTime.now().difference(t0).inMilliseconds;
      final genMs = totalMs - (firstTokenMs < 0 ? 0 : firstTokenMs);
      final response = full.trim().isNotEmpty ? full.trim() : buffer.toString().trim();
      final hasThink = response.contains('<think>');

      return _json({
        'ok': true,
        'modelId': modelId,
        'response': response,
        'hasThinkBlock': hasThink,
        'timings': {
          'ttftMs': firstTokenMs,
          'generationMs': genMs,
          'totalMs': totalMs,
          'tokens': tokenCount,
          'tps': genMs > 0 ? (tokenCount * 1000.0 / genMs).roundToDouble() : 0,
        },
      });
    } catch (e) {
      return _error('LM generate error: $e');
    }
  }

  Future<shelf.Response> _handleYoloChat(
    String method,
    List<String> sub,
    shelf.Request request,
    BoardCubit cubit,
  ) async {
    if (sub.length == 1 && sub[0] == 'panels' && method == 'GET') {
      final out = <Map<String, dynamic>>[];
      for (final board in cubit.state.boards) {
        for (final panel in board.panels.where((p) => p.type == 'board.chat')) {
          out.add({
            'boardId': board.id,
            'boardName': board.name,
            'panelId': panel.id,
            'panelTitle': panel.title,
          });
        }
      }
      return _json({'ok': true, 'items': out});
    }

    if (sub.length == 1 && sub[0] == 'send' && method == 'POST') {
      final body = await _body(request);
      final text = body['text'] as String? ?? body['message'] as String?;
      if (text == null || text.trim().isEmpty) {
        return _error('Missing "text" field');
      }
      final target = _resolveYoloChatTarget(
        cubit,
        boardHint: body['board'] as String? ?? body['boardId'] as String?,
        panelHint: body['panel'] as String? ?? body['panelId'] as String?,
      );
      if (target == null) {
        return _error('No board.chat panel found (or target not found)');
      }
      final actionBody = <String, dynamic>{
        ...body,
        'action': 'send',
        'text': text,
      };
      return _panelAction(cubit, target.board, target.panel, actionBody);
    }

    if (sub.length == 1 && sub[0] == 'messages' && method == 'GET') {
      final boardHint = request.url.queryParameters['board'];
      final panelHint = request.url.queryParameters['panel'];
      final limitRaw = request.url.queryParameters['limit'];
      final target = _resolveYoloChatTarget(
        cubit,
        boardHint: boardHint,
        panelHint: panelHint,
      );
      if (target == null) {
        return _error('No board.chat panel found (or target not found)');
      }
      final body = <String, dynamic>{'action': 'messages'};
      final limit = int.tryParse(limitRaw ?? '');
      if (limit != null && limit > 0) {
        body['limit'] = limit;
      }
      return _panelAction(cubit, target.board, target.panel, body);
    }

    return _notFound('Unknown yolochat route');
  }

  ({BoardDocument board, BoardPanelInstance panel})? _resolveYoloChatTarget(
    BoardCubit cubit, {
    String? boardHint,
    String? panelHint,
  }) {
    BoardDocument? board;
    if (boardHint != null && boardHint.trim().isNotEmpty) {
      board = _findBoard(cubit, boardHint);
    } else {
      board = cubit.state.activeBoard ?? cubit.state.boards.firstOrNull;
    }
    if (board == null) return null;

    BoardPanelInstance? panel;
    if (panelHint != null && panelHint.trim().isNotEmpty) {
      panel = _findPanel(board, panelHint);
      if (panel?.type != 'board.chat') return null;
    } else {
      panel = board.panels.where((p) => p.type == 'board.chat').firstOrNull;
    }
    if (panel == null) return null;
    return (board: board, panel: panel);
  }

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
      final format = request.url.queryParameters['format'] ?? 'md';
      return _boardSnapshot(board, format: format);
    }
    // POST /api/boards/:id/apply → apply YAML bulk operations
    if (sub.length == 1 && sub[0] == 'apply' && method == 'POST') {
      return _applyYaml(cubit, board, request);
    }
    // GET /api/boards/:id/screenshot
    if (sub.length == 1 && sub[0] == 'screenshot' && method == 'GET') {
      return _boardScreenshot(board);
    }
    // GET /api/boards/:id/svg
    if (sub.length == 1 && sub[0] == 'svg' && method == 'GET') {
      return _boardSvg(board);
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
    // PUT /api/boards/:id/links/:linkId → update link style/color
    if (sub.length == 2 && sub[0] == 'links' && method == 'PUT') {
      final body = await _body(request);
      return _updateLink(cubit, board, sub[1], body);
    }
    // GET /api/boards/:id/panel-types → list available panel types
    if (sub.length == 1 && sub[0] == 'panel-types' && method == 'GET') {
      return _listPanelTypes();
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
    // POST /api/boards/:id/arrange → auto-layout panels in tree/mindmap structure
    if (sub.length == 1 && sub[0] == 'arrange' && method == 'POST') {
      final body = await _body(request);
      return _arrangeBoard(cubit, board, body);
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
      'boards':
          boards
              .map(
                (b) => {
                  'id': b.id,
                  'name': b.name,
                  'panelCount': b.panels.length,
                  'linkCount': b.links.length,
                  'active': b.id == active,
                },
              )
              .toList(),
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

  shelf.Response _boardSnapshot(BoardDocument board, {String format = 'md'}) {
    final normalized = format.trim().toLowerCase();
    if (normalized == 'mermaid' || normalized == 'mmd') {
      final lines = <String>['graph TD'];
      final nodeByPanelId = <String, String>{};
      for (var i = 0; i < board.panels.length; i++) {
        final panel = board.panels[i];
        final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
        final nodeId = 'p${i + 1}';
        nodeByPanelId[panel.id] = nodeId;
        final label = _escapeMermaidLabel(
          '${panel.title}\\n${plugin?.displayName ?? panel.type}',
        );
        lines.add('  $nodeId["$label"]');
      }
      for (final link in board.links) {
        final from = nodeByPanelId[link.fromPanelId];
        final to = nodeByPanelId[link.toPanelId];
        if (from == null || to == null) continue;
        lines.add('  $from --> $to');
      }
      return shelf.Response.ok(
        lines.join('\n'),
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    }

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
        final from =
            board.panels
                .where((p) => p.id == link.fromPanelId)
                .firstOrNull
                ?.title ??
            _short(link.fromPanelId);
        final to =
            board.panels
                .where((p) => p.id == link.toPanelId)
                .firstOrNull
                ?.title ??
            _short(link.toPanelId);
        lines.add('- $from → $to (${link.style.name}, ${link.geometry.name})');
      }
    }
    return shelf.Response.ok(
      lines.join('\n'),
      headers: {'content-type': 'text/markdown; charset=utf-8'},
    );
  }

  String _escapeMermaidLabel(String input) {
    return input
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
  }

  Future<shelf.Response> _boardScreenshot(BoardDocument board) async {
    final png = await BoardScreenshotService.instance.capturePng(
      pixelRatio: 1.5,
    );
    if (png == null) {
      return _error('Failed to capture board screenshot');
    }
    return shelf.Response.ok(png, headers: {'content-type': 'image/png'});
  }

  shelf.Response _boardSvg(BoardDocument board) {
    final svg = BoardSvgExporter.export(board);
    return shelf.Response.ok(
      svg,
      headers: {'content-type': 'image/svg+xml; charset=utf-8'},
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
    if (body.containsKey('scale') ||
        body.containsKey('x') ||
        body.containsKey('y')) {
      final scale = (body['scale'] as num?)?.toDouble() ?? board.viewport.scale;
      final tx =
          (body['x'] as num?)?.toDouble() ?? board.viewport.translation.dx;
      final ty =
          (body['y'] as num?)?.toDouble() ?? board.viewport.translation.dy;
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
        final minX = panels
            .map((p) => p.bounds.x)
            .reduce((a, b) => a < b ? a : b);
        final minY = panels
            .map((p) => p.bounds.y)
            .reduce((a, b) => a < b ? a : b);
        final maxX = panels
            .map((p) => p.bounds.x + p.bounds.width)
            .reduce((a, b) => a > b ? a : b);
        final maxY = panels
            .map((p) => p.bounds.y + p.bounds.height)
            .reduce((a, b) => a > b ? a : b);
        const pad = 80.0;
        final vpW = (body['viewportWidth'] as num?)?.toDouble() ?? 1280.0;
        final vpH = (body['viewportHeight'] as num?)?.toDouble() ?? 800.0;
        final scaleX = (vpW - pad * 2) / (maxX - minX);
        final scaleY = (vpH - pad * 2) / (maxY - minY);
        final s = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 2.0);
        final tx = (vpW - (maxX - minX) * s) / 2 - minX * s;
        final ty = (vpH - (maxY - minY) * s) / 2 - minY * s;
        final vp = board.viewport.copyWith(
          scale: s,
          translation: Offset(tx, ty),
        );
        await cubit.updateViewport(vp, boardId: board.id);
        _scheduleRebuild();
      }
    }
    return _json({'ok': true});
  }

  // ── Panel implementations ──────────────────────────────────────────────

  shelf.Response _listPanels(BoardDocument board) {
    return _json({'panels': board.panels.map(_panelSummary).toList()});
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
    final w = (body['width'] as num?)?.toDouble() ?? plugin.defaultSize.width;
    final h = (body['height'] as num?)?.toDouble() ?? plugin.defaultSize.height;
    final state = body['state'] as Map<String, dynamic>? ?? plugin.initialState;
    final hasCustomPosition = body['x'] is num || body['y'] is num;
    final bounds =
        !hasCustomPosition
            ? _nextAvailableBoundsFor(
              board,
              preferredWidth: w,
              preferredHeight: h,
            )
            : BoardPanelBounds(
              x: (body['x'] as num?)?.toDouble() ?? 100,
              y: (body['y'] as num?)?.toDouble() ?? 100,
              width: w,
              height: h,
            );

    final panelId = 'p-${DateTime.now().millisecondsSinceEpoch}';
    final panel = BoardPanelInstance(
      id: panelId,
      type: typeId,
      title: title,
      bounds: bounds,
      state: state,
      zIndex:
          board.panels.fold<int>(
            0,
            (value, p) => p.zIndex > value ? p.zIndex : value,
          ) +
          1,
    );
    await cubit.addPanel(panel, boardId: board.id);
    _scheduleRebuild();
    return _json({'ok': true, 'panel': _panelSummary(panel)});
  }

  BoardPanelBounds _nextAvailableBoundsFor(
    BoardDocument board, {
    required double preferredWidth,
    required double preferredHeight,
  }) {
    const startX = 120.0;
    const startY = 120.0;
    const gap = 24.0;
    const stepX = 56.0;
    const stepY = 42.0;
    const maxColumns = 8;

    final occupiedRects =
        board.panels
            .where((panel) => !panel.hidden)
            .map((panel) => panel.bounds.rect.inflate(gap))
            .toList();

    for (var row = 0; row < 40; row++) {
      for (var column = 0; column < maxColumns; column++) {
        final candidate = Rect.fromLTWH(
          startX + (column * (preferredWidth + stepX)),
          startY + (row * (preferredHeight + stepY)),
          preferredWidth,
          preferredHeight,
        );
        final overlaps = occupiedRects.any(candidate.overlaps);
        if (!overlaps) {
          return BoardPanelBounds(
            x: candidate.left,
            y: candidate.top,
            width: preferredWidth,
            height: preferredHeight,
          );
        }
      }
    }

    return BoardPanelBounds(
      x: startX,
      y: startY + (occupiedRects.length * (preferredHeight + stepY) * 0.35),
      width: preferredWidth,
      height: preferredHeight,
    );
  }

  shelf.Response _panelDetails(BoardPanelInstance panel) {
    final handler = _panelHandlers[panel.type];
    if (handler != null) _warnIfActionHelpIncomplete(handler);
    final content = handler?.getContent(panel);
    return _json({
      ..._panelSummary(panel),
      'state': panel.state,
      if (content != null) 'content': content,
      if (handler != null) 'supportedActions': handler.supportedActions,
      if (handler != null) 'actionHelp': _serializeActionHelp(handler),
    });
  }

  Map<String, dynamic> _serializeActionHelp(PanelCliHandler handler) {
    final out = <String, dynamic>{};
    handler.actionHelp.forEach((action, help) {
      out[action] = {
        'description': help.description,
        if (help.params.isNotEmpty) 'params': help.params,
        if (help.example != null && help.example!.trim().isNotEmpty)
          'example': help.example,
      };
    });
    return out;
  }

  void _warnIfActionHelpIncomplete(PanelCliHandler handler) {
    if (_warnedActionHelpTypes.contains(handler.typeId)) return;
    final missing =
        handler.supportedActions
            .where((action) => !handler.actionHelp.containsKey(action))
            .toList();
    if (missing.isEmpty) return;
    _warnedActionHelpTypes.add(handler.typeId);
    developer.log(
      '[CliServer] ${handler.typeId}: missing actionHelp for ${missing.join(', ')}. '
      'New CLI actions should include English description and params for self-help.',
      name: 'yoloit.cli',
      level: 900,
    );
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
      final dx =
          ((body['x'] as num?)?.toDouble() ?? panel.bounds.x) - panel.bounds.x;
      final dy =
          ((body['y'] as num?)?.toDouble() ?? panel.bounds.y) - panel.bounds.y;
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
    if (body.containsKey('color')) {
      final colorStr = body['color'] as String?;
      final parsed = colorStr == 'clear' ? null : _parseColor(colorStr);
      await cubit.updatePanelColor(panel.id, color: parsed, boardId: board.id);
      _scheduleRebuild();
    }
    if (body.containsKey('hidden')) {
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(hidden: body['hidden'] as bool),
        boardId: board.id,
      );
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
        'Supported: ${handler.supportedActions.join(', ')}. '
        'Use `yoloit panel:help "<board>" "<panel>"` for action details.',
      );
    }

    final result = await handler.handleAction(action, body, panel);

    // Apply state update if provided
    if (result.stateUpdate != null && result.ok) {
      final mergedState = {...panel.state, ...result.stateUpdate!};
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(state: mergedState),
        boardId: board.id,
      );
      if (panel.type == 'board.note.markdown' &&
          mergedState['autoHeight'] == true) {
        final markdown = mergedState['markdown'] as String? ?? '';
        final targetHeight = _estimateMarkdownNoteHeight(
          markdown,
          panel.bounds.width,
        );
        await cubit.resizePanel(
          panel.id,
          width: panel.bounds.width,
          height: targetHeight,
          boardId: board.id,
        );
      }
      _scheduleRebuild();
    }

    return _json(result.toJson());
  }

  double _estimateMarkdownNoteHeight(String markdown, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: markdown.isEmpty ? '*Empty note*' : markdown,
        style: const TextStyle(fontSize: 14, height: 1.25),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: (width - 32 - 24).clamp(100.0, 2000.0));

    // text height + inner note padding (32) + panel chrome (header 44 + content padding 24)
    return (painter.height + 100).clamp(140.0, 2000.0);
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
    return _json({
      'ok': true,
      'viewport': {
        'scale': vp.scale,
        'x': vp.translation.dx,
        'y': vp.translation.dy,
      },
    });
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
    final maxX = panels
        .map((p) => p.bounds.x + p.bounds.width)
        .reduce((a, b) => a > b ? a : b);
    final maxY = panels
        .map((p) => p.bounds.y + p.bounds.height)
        .reduce((a, b) => a > b ? a : b);

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
      'viewport': {
        'scale': vp.scale,
        'x': vp.translation.dx,
        'y': vp.translation.dy,
      },
      'bounds': {'minX': minX, 'minY': minY, 'maxX': maxX, 'maxY': maxY},
    });
  }

  // ── Arrange implementation ─────────────────────────────────────────────

  /// Auto-layout panels in a tree/mindmap structure based on link relationships.
  ///
  /// Body params:
  /// - layout: "tree" (default) — BFS tree layout
  /// - direction: "right" (default) | "down" — children expand right or down
  /// - rootPanelId: optional root panel ID/title; if omitted, infers from links
  /// - hSpacing: horizontal gap (default 80)
  /// - vSpacing: vertical gap (default 60)
  Future<shelf.Response> _arrangeBoard(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> body,
  ) async {
    final direction = (body['direction'] as String?) ?? 'right';
    final hSpacing = (body['hSpacing'] as num?)?.toDouble() ?? 80.0;
    final vSpacing = (body['vSpacing'] as num?)?.toDouble() ?? 60.0;
    final rootHint = body['rootPanelId'] as String?;

    final panels = board.panels.where((p) => !p.hidden).toList();
    if (panels.isEmpty) return _error('No panels to arrange');

    // Build adjacency: fromId → [toId]
    final children = <String, List<String>>{};
    final hasIncoming = <String>{};
    for (final link in board.links) {
      children.putIfAbsent(link.fromPanelId, () => []).add(link.toPanelId);
      hasIncoming.add(link.toPanelId);
    }

    // Collect all panel IDs in the linked graph
    final linkedIds = {...children.keys, ...hasIncoming};
    final unlinked = panels.where((p) => !linkedIds.contains(p.id)).toList();

    // Determine root: hint → no-incoming node → first panel
    BoardPanelInstance? root;
    if (rootHint != null) {
      root = _findPanel(board, rootHint);
    }
    root ??= panels.firstWhere(
      (p) => linkedIds.contains(p.id) && !hasIncoming.contains(p.id),
      orElse: () => panels.first,
    );

    // BFS to compute (depth, siblingIndex) for each node
    final positions = <String, (int depth, int index)>{};
    final siblingCount = <int, int>{}; // depth → next sibling index
    final queue = <String>[root.id];
    positions[root.id] = (0, 0);
    siblingCount[0] = 1;

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final (depth, _) = positions[current]!;
      final kids = children[current] ?? [];
      for (final kid in kids) {
        if (positions.containsKey(kid)) continue; // avoid cycles
        final idx = siblingCount[depth + 1] ?? 0;
        positions[kid] = (depth + 1, idx);
        siblingCount[depth + 1] = idx + 1;
        queue.add(kid);
      }
    }

    // Find max panel size for spacing calculations
    final maxW = panels
        .map((p) => p.bounds.width)
        .reduce((a, b) => a > b ? a : b);
    final maxH = panels
        .map((p) => p.bounds.height)
        .reduce((a, b) => a > b ? a : b);

    // Assign x/y based on depth/index and direction
    const originX = 80.0;
    const originY = 80.0;

    final moves = <String, (double x, double y)>{};
    for (final entry in positions.entries) {
      final panelId = entry.key;
      final (depth, index) = entry.value;
      double x, y;
      if (direction == 'down') {
        x = originX + index * (maxW + hSpacing);
        y = originY + depth * (maxH + vSpacing);
      } else {
        // right (default): depth → column, index → row
        x = originX + depth * (maxW + hSpacing);
        y = originY + index * (maxH + vSpacing);
      }
      moves[panelId] = (x, y);
    }

    // Also arrange unlinked panels below the tree
    if (unlinked.isNotEmpty) {
      final treeMaxY =
          moves.values.isEmpty
              ? originY
              : moves.values.map((v) => v.$2).reduce((a, b) => a > b ? a : b);
      final startY = treeMaxY + maxH + vSpacing * 2;
      for (var i = 0; i < unlinked.length; i++) {
        final x = originX + i * (maxW + hSpacing);
        moves[unlinked[i].id] = (x, startY);
      }
    }

    // Apply all position updates
    for (final entry in moves.entries) {
      final panelId = entry.key;
      final (x, y) = entry.value;
      await cubit.updatePanel(
        panelId,
        (p) => p.copyWith(bounds: p.bounds.copyWith(x: x, y: y)),
        boardId: board.id,
      );
    }
    _scheduleRebuild();

    return _json({
      'ok': true,
      'arranged': moves.length,
      'layout': 'tree',
      'direction': direction,
    });
  }

  // ── YAML bulk apply implementation ───────────────────────────────────────

  Future<shelf.Response> _applyYaml(
    BoardCubit cubit,
    BoardDocument board,
    shelf.Request request,
  ) async {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) {
      return _yamlError('Empty YAML payload');
    }

    final parsed = loadYaml(raw);
    final operations = _yamlOperations(parsed);
    if (operations.isEmpty) {
      return _yamlError(
        'No operations found. Use a YAML list or a map with "operations".',
      );
    }

    var currentBoard = board;
    final refs = <String, String>{};
    final pendingPanels = <String, BoardPanelInstance>{};
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < operations.length; i++) {
      final opMap = _yamlMap(operations[i]);
      if (opMap == null) {
        return _yamlError('Operation ${i + 1} must be a YAML mapping');
      }

      final result = await _applyYamlOperation(
        cubit,
        currentBoard,
        refs,
        pendingPanels,
        opMap,
        index: i + 1,
      );
      results.add(result);
      if (result['ok'] != true) {
        return _yamlError(
          'Operation ${i + 1} failed: ${result['error'] ?? result['message'] ?? 'unknown error'}',
          details: {'failedAt': i + 1, 'results': results},
        );
      }
      if (opMap['op'] == 'panel.create' || opMap['action'] == 'panel.create') {
        final panelId = _string(result['panelId']);
        final created = panelId == null ? null : pendingPanels[panelId];
        if (created != null) {
          currentBoard = currentBoard.copyWith(
            panels: [...currentBoard.panels, created],
          );
        }
      } else if (opMap['op'] == 'panel.delete' ||
          opMap['action'] == 'panel.delete') {
        final panelId = _string(result['panelId']);
        if (panelId != null) {
          currentBoard = currentBoard.copyWith(
            panels:
                currentBoard.panels
                    .where((panel) => panel.id != panelId)
                    .toList(),
          );
        }
      }
    }

    _scheduleRebuild();
    return _json({
      'ok': true,
      'applied': results.length,
      'results': results,
      if (refs.isNotEmpty) 'refs': refs,
    });
  }

  List<dynamic> _yamlOperations(dynamic parsed) {
    final root = _yamlToDart(parsed);
    if (root is List) return root;
    if (root is Map) {
      for (final key in ['operations', 'ops', 'changes']) {
        final value = root[key];
        if (value is List) return value;
      }
      if (root.containsKey('op') || root.containsKey('action')) {
        return [root];
      }
    }
    return const [];
  }

  Future<Map<String, dynamic>> _applyYamlOperation(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final op = _string(raw['op'] ?? raw['action']);
    if (op == null || op.isEmpty) {
      return {'ok': false, 'error': 'Missing "op" field'};
    }

    switch (op) {
      case 'panel.create':
        return _yamlCreatePanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'panel.update':
        return _yamlUpdatePanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'panel.move':
        return _yamlMovePanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'panel.resize':
        return _yamlResizePanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'panel.delete':
        return _yamlDeletePanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'panel.focus':
        return _yamlFocusPanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'panel.color':
        return _yamlColorPanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'panel.hide':
      case 'panel.show':
        return _yamlHideShowPanel(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          hidden: op == 'panel.hide',
          index: index,
        );
      case 'panel.action':
        return _yamlPanelAction(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );

      case 'link.create':
        return _yamlCreateLink(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'link.delete':
        return _yamlDeleteLink(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          index: index,
        );
      case 'link.update':
      case 'link.style':
      case 'link.color':
        return _yamlUpdateLink(
          cubit,
          board,
          refs,
          pendingPanels,
          raw,
          op,
          index: index,
        );

      case 'board.focus':
        await cubit.setActiveBoard(board.id);
        return {'ok': true, 'message': 'Board focused'};
      case 'board.fit':
        return _yamlFitBoard(cubit, board, raw, index: index);
      case 'board.zoom':
        return _yamlZoomBoard(cubit, board, raw, index: index);
      case 'board.translate':
        return _yamlTranslateBoard(cubit, board, raw, index: index);
      case 'board.arrange':
        return _yamlArrangeBoard(cubit, board, raw, index: index);
      default:
        return {'ok': false, 'error': 'Unknown op "$op"'};
    }
  }

  Future<Map<String, dynamic>> _yamlCreatePanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final typeId = _string(raw['type'] ?? raw['typeId']);
    if (typeId == null) return {'ok': false, 'error': 'Missing "type"'};

    final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
    if (plugin == null) {
      return {'ok': false, 'error': 'Unknown panel type: $typeId'};
    }

    final title = _string(raw['title']) ?? plugin.displayName;
    final x = _double(raw['x']) ?? 100.0;
    final y = _double(raw['y']) ?? 100.0;
    final width = _double(raw['width']) ?? plugin.defaultSize.width;
    final height = _double(raw['height']) ?? plugin.defaultSize.height;
    final state = _map(raw['state']);
    final params = _map(raw['params']);
    final ref = _string(raw['ref']);
    final color = _color(raw['color']);
    final hidden = _bool(raw['hidden']) ?? false;
    final locked = _bool(raw['locked']) ?? false;
    final pinned = _bool(raw['pinned']) ?? false;
    final panelId = _string(raw['id'] ?? raw['panelId']) ?? _nextBulkId('p');
    final zIndex =
        _int(raw['zIndex']) ??
        board.panels.fold<int>(
              0,
              (value, panel) => panel.zIndex > value ? panel.zIndex : value,
            ) +
            1;

    final panel = BoardPanelInstance(
      id: panelId,
      type: typeId,
      title: title.trim().isEmpty ? plugin.displayName : title.trim(),
      bounds: BoardPanelBounds(x: x, y: y, width: width, height: height),
      color: color,
      params: {...?params, if (ref != null && ref.isNotEmpty) 'yamlRef': ref},
      state: {...plugin.initialState, if (state != null) ...state},
      zIndex: zIndex,
      hidden: hidden,
      locked: locked,
      pinned: pinned,
    );

    await cubit.addPanel(panel, boardId: board.id);
    pendingPanels[panel.id] = panel;
    if (_bool(raw['focus']) == true) {
      await cubit.focusPanel(panel.id, boardId: board.id);
    }
    if ((panel.type == 'board.note.markdown') &&
        (panel.state['autoHeight'] == true)) {
      final targetHeight = _estimateMarkdownNoteHeight(
        panel.state['markdown'] as String? ?? '',
        panel.bounds.width,
      );
      await cubit.resizePanel(
        panel.id,
        width: panel.bounds.width,
        height: targetHeight,
        boardId: board.id,
      );
    }
    if (ref != null && ref.isNotEmpty) {
      refs[ref] = panel.id;
      pendingPanels[ref] = panel;
    }
    return {'ok': true, 'panelId': panel.id};
  }

  Future<Map<String, dynamic>> _yamlUpdatePanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) {
      return {
        'ok': false,
        'error': 'Panel not found',
        'rawPanel': raw['panel']?.toString(),
        'rawPanelId': raw['panelId']?.toString(),
        'rawPanelRef': raw['panelRef']?.toString(),
        'rawRef': raw['ref']?.toString(),
        'refs': refs,
        'pending': pendingPanels.keys.toList(),
      };
    }

    final updates = <String, dynamic>{};
    if (raw.containsKey('title'))
      updates['title'] = _string(raw['title']) ?? panel.title;
    if (raw.containsKey('hidden'))
      updates['hidden'] = _bool(raw['hidden']) ?? panel.hidden;
    if (raw.containsKey('locked'))
      updates['locked'] = _bool(raw['locked']) ?? panel.locked;
    if (raw.containsKey('pinned'))
      updates['pinned'] = _bool(raw['pinned']) ?? panel.pinned;
    if (raw.containsKey('color')) {
      final colorStr = _string(raw['color']);
      updates['color'] = colorStr == 'clear' ? null : _parseColor(colorStr);
    }
    if (raw.containsKey('params')) {
      updates['params'] = {...panel.params, ...?_map(raw['params'])};
    }
    if (raw.containsKey('state')) {
      updates['state'] = {...panel.state, ...?_map(raw['state'])};
    }
    if (raw.containsKey('zIndex'))
      updates['zIndex'] = _int(raw['zIndex']) ?? panel.zIndex;
    if (raw.containsKey('x') || raw.containsKey('y')) {
      final x = _double(raw['x']) ?? panel.bounds.x;
      final y = _double(raw['y']) ?? panel.bounds.y;
      updates['x'] = x;
      updates['y'] = y;
    }
    if (raw.containsKey('width') || raw.containsKey('height')) {
      final w = _double(raw['width']) ?? panel.bounds.width;
      final h = _double(raw['height']) ?? panel.bounds.height;
      updates['width'] = w;
      updates['height'] = h;
    }

    if (updates.isNotEmpty) {
      await _applyYamlPanelUpdates(cubit, board, panel, updates);
    }
    if (_bool(raw['focus']) == true) {
      await cubit.focusPanel(panel.id, boardId: board.id);
    }
    return {'ok': true, 'panelId': panel.id};
  }

  Future<void> _applyYamlPanelUpdates(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey('title')) {
      await cubit.updatePanelTitle(
        panel.id,
        updates['title'] as String,
        boardId: board.id,
      );
    }
    if (updates.containsKey('x') || updates.containsKey('y')) {
      final x = (updates['x'] as num?)?.toDouble() ?? panel.bounds.x;
      final y = (updates['y'] as num?)?.toDouble() ?? panel.bounds.y;
      await cubit.movePanel(
        panel.id,
        Offset(x - panel.bounds.x, y - panel.bounds.y),
        boardId: board.id,
      );
    }
    if (updates.containsKey('width') || updates.containsKey('height')) {
      await cubit.resizePanel(
        panel.id,
        width: (updates['width'] as num?)?.toDouble() ?? panel.bounds.width,
        height: (updates['height'] as num?)?.toDouble() ?? panel.bounds.height,
        boardId: board.id,
      );
    }
    if (updates.containsKey('hidden')) {
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(hidden: updates['hidden'] as bool),
        boardId: board.id,
      );
    }
    if (updates.containsKey('locked') ||
        updates.containsKey('pinned') ||
        updates.containsKey('params') ||
        updates.containsKey('state') ||
        updates.containsKey('zIndex') ||
        updates.containsKey('color')) {
      final color = updates['color'] as Color?;
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(
          color: updates.containsKey('color') && color == null ? null : color,
          clearColor: updates.containsKey('color') && color == null,
          params: updates['params'] as Map<String, dynamic>? ?? p.params,
          state: updates['state'] as Map<String, dynamic>? ?? p.state,
          zIndex: updates['zIndex'] as int? ?? p.zIndex,
          locked: updates['locked'] as bool? ?? p.locked,
          pinned: updates['pinned'] as bool? ?? p.pinned,
        ),
        boardId: board.id,
      );
    }

    if (panel.type == 'board.note.markdown' &&
        ((updates['state'] as Map<String, dynamic>?)?['autoHeight'] == true)) {
      final markdown =
          ((updates['state'] as Map<String, dynamic>?)?['markdown']
              as String?) ??
          panel.state['markdown'] as String? ??
          '';
      final targetHeight = _estimateMarkdownNoteHeight(
        markdown,
        panel.bounds.width,
      );
      await cubit.resizePanel(
        panel.id,
        width: panel.bounds.width,
        height: targetHeight,
        boardId: board.id,
      );
    }
  }

  Future<Map<String, dynamic>> _yamlMovePanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) {
      return {
        'ok': false,
        'error': 'Panel not found',
        'rawPanel': raw['panel']?.toString(),
        'rawPanelId': raw['panelId']?.toString(),
        'rawPanelRef': raw['panelRef']?.toString(),
        'rawRef': raw['ref']?.toString(),
        'refs': refs,
        'pending': pendingPanels.keys.toList(),
      };
    }
    final x = _double(raw['x']);
    final y = _double(raw['y']);
    if (x == null && y == null) {
      return {'ok': false, 'error': 'Missing "x" and/or "y"'};
    }
    await cubit.movePanel(
      panel.id,
      Offset(
        (x ?? panel.bounds.x) - panel.bounds.x,
        (y ?? panel.bounds.y) - panel.bounds.y,
      ),
      boardId: board.id,
    );
    return {'ok': true, 'panelId': panel.id};
  }

  Future<Map<String, dynamic>> _yamlResizePanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) return {'ok': false, 'error': 'Panel not found'};
    final width = _double(raw['width']);
    final height = _double(raw['height']);
    if (width == null && height == null) {
      return {'ok': false, 'error': 'Missing "width" and/or "height"'};
    }
    await cubit.resizePanel(
      panel.id,
      width: width ?? panel.bounds.width,
      height: height ?? panel.bounds.height,
      boardId: board.id,
    );
    return {'ok': true, 'panelId': panel.id};
  }

  Future<Map<String, dynamic>> _yamlDeletePanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) return {'ok': false, 'error': 'Panel not found'};
    await cubit.removePanel(panel.id, boardId: board.id);
    return {'ok': true, 'panelId': panel.id};
  }

  Future<Map<String, dynamic>> _yamlFocusPanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) return {'ok': false, 'error': 'Panel not found'};
    await cubit.focusPanel(panel.id, boardId: board.id);
    return {'ok': true, 'panelId': panel.id};
  }

  Future<Map<String, dynamic>> _yamlColorPanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) return {'ok': false, 'error': 'Panel not found'};
    final colorStr = _string(raw['color']);
    await cubit.updatePanelColor(
      panel.id,
      color: colorStr == 'clear' ? null : _parseColor(colorStr),
      boardId: board.id,
    );
    return {'ok': true, 'panelId': panel.id};
  }

  Future<Map<String, dynamic>> _yamlHideShowPanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required bool hidden,
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) return {'ok': false, 'error': 'Panel not found'};
    await cubit.updatePanel(
      panel.id,
      (p) => p.copyWith(hidden: hidden),
      boardId: board.id,
    );
    return {'ok': true, 'panelId': panel.id};
  }

  Future<Map<String, dynamic>> _yamlPanelAction(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panel = _resolveYamlPanel(cubit, board, refs, pendingPanels, raw);
    if (panel == null) return {'ok': false, 'error': 'Panel not found'};
    final action = _string(raw['action']);
    if (action == null) return {'ok': false, 'error': 'Missing "action"'};

    final body =
        <String, dynamic>{...raw}
          ..remove('op')
          ..remove('panel')
          ..remove('panelId')
          ..remove('panelRef')
          ..remove('ref');
    body['action'] = action;

    final handler = _panelHandlers[panel.type];
    if (handler == null) {
      return {
        'ok': false,
        'error': 'No CLI handler for panel type: ${panel.type}',
      };
    }
    if (!handler.supportedActions.contains(action)) {
      return {
        'ok': false,
        'error':
            'Unsupported action "$action" for ${panel.type}. '
            'Supported: ${handler.supportedActions.join(', ')}',
      };
    }

    final result = await handler.handleAction(action, body, panel);
    if (result.stateUpdate != null && result.ok) {
      final mergedState = {...panel.state, ...result.stateUpdate!};
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(state: mergedState),
        boardId: board.id,
      );
      if (panel.type == 'board.note.markdown' &&
          mergedState['autoHeight'] == true) {
        final markdown = mergedState['markdown'] as String? ?? '';
        final targetHeight = _estimateMarkdownNoteHeight(
          markdown,
          panel.bounds.width,
        );
        await cubit.resizePanel(
          panel.id,
          width: panel.bounds.width,
          height: targetHeight,
          boardId: board.id,
        );
      }
    }
    return {'ok': true, 'panelId': panel.id, ...result.toJson()};
  }

  Future<Map<String, dynamic>> _yamlCreateLink(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final from = _resolveYamlPanel(cubit, board, refs, pendingPanels, {
      'panel': raw['from'] ?? raw['fromPanelId'],
    });
    final to = _resolveYamlPanel(cubit, board, refs, pendingPanels, {
      'panel': raw['to'] ?? raw['toPanelId'],
    });
    if (from == null || to == null) {
      return {'ok': false, 'error': 'Link endpoints not found'};
    }
    final style = _string(raw['style']) ?? 'arrow';
    final geometry = _string(raw['geometry']) ?? 'bezier';
    final link = BoardPanelLink(
      id: _nextBulkId('link'),
      fromPanelId: from.id,
      toPanelId: to.id,
      style: BoardLinkStyle.values.firstWhere(
        (s) => s.name == style,
        orElse: () => BoardLinkStyle.arrow,
      ),
      geometry: BoardLinkGeometry.values.firstWhere(
        (g) => g.name == geometry,
        orElse: () => BoardLinkGeometry.bezier,
      ),
      color: _color(raw['color']) ?? const Color(0xFF60A5FA),
    );
    await cubit.upsertLink(link, boardId: board.id);
    final ref = _string(raw['ref']);
    if (ref != null && ref.isNotEmpty) refs[ref] = link.id;
    return {'ok': true, 'linkId': link.id};
  }

  Future<Map<String, dynamic>> _yamlDeleteLink(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final linkId =
        _string(raw['link'] ?? raw['linkId'] ?? raw['ref']) ??
        refs[_string(raw['ref']) ?? ''];
    if (linkId == null || linkId.isEmpty) {
      return {'ok': false, 'error': 'Missing link identifier'};
    }
    await cubit.removeLink(linkId, boardId: board.id);
    return {'ok': true, 'linkId': linkId};
  }

  Future<Map<String, dynamic>> _yamlUpdateLink(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw,
    String op, {
    required int index,
  }) async {
    final linkId =
        _string(raw['link'] ?? raw['linkId'] ?? raw['ref']) ??
        refs[_string(raw['ref']) ?? ''];
    if (linkId == null || linkId.isEmpty) {
      return {'ok': false, 'error': 'Missing link identifier'};
    }
    final link = board.links.where((l) => l.id == linkId).firstOrNull;
    if (link == null) return {'ok': false, 'error': 'Link not found: $linkId'};

    final styleStr = _string(raw['style']);
    final geometryStr = _string(raw['geometry']);
    final colorStr = _string(raw['color']);

    final style =
        styleStr == null
            ? link.style
            : BoardLinkStyle.values.firstWhere(
              (s) => s.name == styleStr,
              orElse: () => link.style,
            );
    final geometry =
        geometryStr == null
            ? link.geometry
            : BoardLinkGeometry.values.firstWhere(
              (g) => g.name == geometryStr,
              orElse: () => link.geometry,
            );
    final color =
        colorStr == null ? link.color : _parseColor(colorStr) ?? link.color;

    await cubit.upsertLink(
      link.copyWith(style: style, geometry: geometry, color: color),
      boardId: board.id,
    );
    return {'ok': true, 'linkId': linkId};
  }

  Future<Map<String, dynamic>> _yamlFitBoard(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final panels = board.panels.where((p) => !p.hidden).toList();
    if (panels.isEmpty) return {'ok': false, 'error': 'No panels to fit'};

    final minX = panels.map((p) => p.bounds.x).reduce((a, b) => a < b ? a : b);
    final minY = panels.map((p) => p.bounds.y).reduce((a, b) => a < b ? a : b);
    final maxX = panels
        .map((p) => p.bounds.x + p.bounds.width)
        .reduce((a, b) => a > b ? a : b);
    final maxY = panels
        .map((p) => p.bounds.y + p.bounds.height)
        .reduce((a, b) => a > b ? a : b);

    final contentW = maxX - minX;
    final contentH = maxY - minY;
    const padding = 80.0;

    final vpW = _double(raw['viewportWidth']) ?? 1280.0;
    final vpH = _double(raw['viewportHeight']) ?? 800.0;
    final scaleX = (vpW - padding * 2) / contentW;
    final scaleY = (vpH - padding * 2) / contentH;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 2.0);
    final tx = (vpW - contentW * scale) / 2 - minX * scale;
    final ty = (vpH - contentH * scale) / 2 - minY * scale;

    final vp = board.viewport.copyWith(
      scale: scale,
      translation: Offset(tx, ty),
    );
    await cubit.updateViewport(vp, boardId: board.id);
    return {
      'ok': true,
      'viewport': {
        'scale': vp.scale,
        'x': vp.translation.dx,
        'y': vp.translation.dy,
      },
      'bounds': {'minX': minX, 'minY': minY, 'maxX': maxX, 'maxY': maxY},
    };
  }

  Future<Map<String, dynamic>> _yamlZoomBoard(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final scale = _double(raw['scale']);
    if (scale == null) return {'ok': false, 'error': 'Missing "scale"'};
    await cubit.updateViewport(
      board.viewport.copyWith(scale: scale.clamp(0.1, 4.0)),
      boardId: board.id,
    );
    return {'ok': true, 'scale': scale};
  }

  Future<Map<String, dynamic>> _yamlTranslateBoard(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final x = _double(raw['x']) ?? board.viewport.translation.dx;
    final y = _double(raw['y']) ?? board.viewport.translation.dy;
    await cubit.updateViewport(
      board.viewport.copyWith(translation: Offset(x, y)),
      boardId: board.id,
    );
    return {'ok': true, 'x': x, 'y': y};
  }

  Future<Map<String, dynamic>> _yamlArrangeBoard(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, dynamic> raw, {
    required int index,
  }) async {
    final response = await _arrangeBoard(cubit, board, {
      'direction': _string(raw['direction']) ?? 'right',
      'hSpacing': _double(raw['hSpacing']) ?? 80.0,
      'vSpacing': _double(raw['vSpacing']) ?? 60.0,
      if (raw.containsKey('rootPanelId')) 'rootPanelId': raw['rootPanelId'],
    });
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  BoardPanelInstance? _resolveYamlPanel(
    BoardCubit cubit,
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw,
  ) {
    final spec =
        raw['panel'] ?? raw['panelId'] ?? raw['panelRef'] ?? raw['ref'];
    final ref = _string(spec);
    if (ref == null || ref.isEmpty) return null;
    final liveBoard = cubit.state.boards.firstWhere(
      (b) => b.id == board.id,
      orElse: () => board,
    );
    final pending = pendingPanels[ref];
    if (pending != null) {
      return pending;
    }
    final byRef = refs[ref];
    if (byRef != null) {
      final pendingById = pendingPanels[byRef];
      if (pendingById != null) {
        return pendingById;
      }
      return _findPanel(liveBoard, byRef);
    }
    for (final panel in liveBoard.panels) {
      if (panel.params['yamlRef'] == ref) {
        return panel;
      }
    }
    return _findPanel(liveBoard, ref);
  }

  dynamic _yamlToDart(dynamic value) {
    if (value is YamlMap) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _yamlToDart(entry.value),
      };
    }
    if (value is YamlList) {
      return value.map(_yamlToDart).toList();
    }
    return value;
  }

  Map<String, dynamic>? _yamlMap(dynamic value) {
    final dart = _yamlToDart(value);
    if (dart is Map) {
      return Map<String, dynamic>.from(dart);
    }
    return null;
  }

  String? _string(dynamic value) => value?.toString();
  double? _double(dynamic value) =>
      value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
  int? _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  bool? _bool(dynamic value) =>
      value is bool ? value : (value?.toString().toLowerCase() == 'true');
  Map<String, dynamic>? _map(dynamic value) =>
      value is Map
          ? Map<String, dynamic>.from(_yamlToDart(value) as Map)
          : null;
  Color? _color(dynamic value) =>
      value == null ? null : _parseColor(value.toString());
  String _nextBulkId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  shelf.Response _yamlError(String message, {Map<String, dynamic>? details}) {
    return shelf.Response(
      400,
      body: jsonEncode({
        'ok': false,
        'error': message,
        if (details != null) ...details,
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  // ── Link implementations ───────────────────────────────────────────────

  shelf.Response _listPanelTypes() {
    final plugins = BoardPluginRegistry.instance.all;
    return _json({
      'types':
          plugins
              .map(
                (p) => {
                  'typeId': p.typeId,
                  'name': p.displayName,
                  'defaultSize': {
                    'w': p.defaultSize.width.toInt(),
                    'h': p.defaultSize.height.toInt(),
                  },
                },
              )
              .toList(),
    });
  }

  Future<shelf.Response> _updateLink(
    BoardCubit cubit,
    BoardDocument board,
    String linkId,
    Map<String, dynamic> body,
  ) async {
    final link = board.links.where((l) => l.id == linkId).firstOrNull;
    if (link == null) return _notFound('Link not found: $linkId');

    final styleStr = body['style'] as String?;
    final geoStr = body['geometry'] as String?;
    final colorStr = body['color'] as String?;

    final style =
        styleStr != null
            ? BoardLinkStyle.values.firstWhere(
              (s) => s.name == styleStr,
              orElse: () => link.style,
            )
            : link.style;
    final geo =
        geoStr != null
            ? BoardLinkGeometry.values.firstWhere(
              (g) => g.name == geoStr,
              orElse: () => link.geometry,
            )
            : link.geometry;
    final color =
        colorStr != null ? (_parseColor(colorStr) ?? link.color) : link.color;

    final updated = link.copyWith(style: style, geometry: geo, color: color);
    await cubit.upsertLink(updated, boardId: board.id);
    _scheduleRebuild();
    return _json({'ok': true});
  }

  shelf.Response _listLinks(BoardDocument board) {
    return _json({
      'links':
          board.links
              .map(
                (l) => {
                  'id': l.id,
                  'from': l.fromPanelId,
                  'to': l.toPanelId,
                  'style': l.style.name,
                  'geometry': l.geometry.name,
                },
              )
              .toList(),
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
    return _json({
      'ok': true,
      'link': {'id': link.id},
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  BoardDocument? _findBoard(BoardCubit cubit, String idOrName) {
    final boards = cubit.state.boards;
    // Exact id match
    final byId = boards.where((b) => b.id == idOrName).firstOrNull;
    if (byId != null) return byId;
    // Exact name match (case-insensitive)
    final byName =
        boards
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
    final byTitle =
        panels
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

  /// Parse a color string to a [Color].
  /// - `null` → returns null (clear/no color)
  /// - `#RRGGBB` / `#AARRGGBB` hex strings
  /// - Named colors: red, green, blue, yellow, purple, pink, orange, teal, gray, white
  /// - Falls back to [Colors.blue] for unrecognised values
  Color? _parseColor(String? s) {
    if (s == null || s == 'clear') return null;
    if (s.startsWith('#')) {
      final hex = s.replaceFirst('#', '');
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        // If 6-digit hex, force full opacity
        return Color(hex.length == 6 ? (value | 0xFF000000) : value);
      }
    }
    const named = <String, int>{
      'red': 0xFFFF4444,
      'green': 0xFF44BB44,
      'blue': 0xFF4488FF,
      'yellow': 0xFFFFD644,
      'purple': 0xFFA855F7,
      'pink': 0xFFEC4899,
      'orange': 0xFFF97316,
      'teal': 0xFF14B8A6,
      'gray': 0xFF6B7280,
      'white': 0xFFF3F4F6,
    };
    final v = named[s.toLowerCase()];
    if (v != null) return Color(v);
    return Colors.blue;
  }
}
