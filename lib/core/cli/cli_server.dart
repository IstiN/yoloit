import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:yaml/yaml.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';
import 'package:yoloit/core/cli/board_svg_exporter.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/chat/chat_session_naming.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/playlist_player_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

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
  TerminalCubit? _terminalCubit;
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

  /// Wait for a single frame to be drawn using a post-frame callback.

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> start(BoardCubit cubit, {TerminalCubit? terminalCubit}) async {
    // If server is already running but cubit changed (e.g. after hot restart),
    // update cubit reference and return — routes close over _cubit field.
    if (_server != null) {
      _cubit = cubit;
      _terminalCubit = terminalCubit ?? _terminalCubit;
      return;
    }
    _cubit = cubit;
    _terminalCubit = terminalCubit;

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
    _terminalCubit = null;
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
    // Install the CLI script to a known location so terminals can use it.
    unawaited(_installCliScript());
  }

  /// Extracts the bundled `tools/yoloit` asset to `~/.config/yoloit/yoloit`
  /// and makes it executable. This ensures the script is available in PATH
  /// both when running in debug mode and when running as an installed app.
  Future<void> _installCliScript() async {
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;
      final binFile = File('$home/.config/yoloit/yoloit');
      final data = await rootBundle.load('tools/yoloit');
      binFile.parent.createSync(recursive: true);
      await binFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await Process.run('chmod', ['+x', binFile.path]);
      debugPrint('[CliServer] CLI script installed at ${binFile.path}');
    } catch (e) {
      debugPrint('[CliServer] Failed to install CLI script: $e');
    }
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

    // GET /api/catalog → command catalog with humanVariants for router model
    if (path.length == 1 && path[0] == 'catalog' && method == 'GET') {
      final yamlVariants = await YoloitCliToolCatalog.loadYamlVariants();
      return shelf.Response.ok(
        YoloitCliToolCatalog.catalogJson(yamlVariants),
        headers: {'content-type': 'application/json'},
      );
    }

    // /api/local-models/...
    if (path.isNotEmpty && path[0] == 'local-models') {
      return _handleLocalModels(method, path.sublist(1), request);
    }

    // POST /api/lm/generate  { messages: [...], systemPrompt?: "...", maxTokens?: 512 }
    if (path.length == 2 &&
        path[0] == 'lm' &&
        path[1] == 'generate' &&
        method == 'POST') {
      return _handleLmGenerate(request);
    }

    // /api/yolochat/...
    if (path.isNotEmpty && path[0] == 'yolochat') {
      return _handleYoloChat(method, path.sublist(1), request, cubit);
    }

    // /api/cloud-providers/...
    if (path.isNotEmpty && path[0] == 'cloud-providers') {
      return _handleCloudProviders(method, path.sublist(1), request);
    }

    // /api/voice-settings/...
    if (path.isNotEmpty && path[0] == 'voice-settings') {
      return _handleVoiceSettings(method, path.sublist(1), request);
    }

    if (path.isNotEmpty && path[0] == 'agents') {
      return _handleAgents(method, path.sublist(1), request);
    }

    if (path.isNotEmpty && path[0] == 'drawings') {
      return _handleDrawings(method, path.sublist(1), request, cubit);
    }

    if (path.isNotEmpty && path[0] == 'search') {
      return _handleSearch(method, path.sublist(1), request, cubit);
    }

    // GET /api/active-board → active board details (or first board)
    if (path.length == 1 && path[0] == 'active-board' && method == 'GET') {
      final board = cubit.state.activeBoard ?? cubit.state.boards.firstOrNull;
      if (board == null) return _json({'board': null});
      return _json({
        'board': {
          'id': board.id,
          'name': board.name,
          'panelCount': board.panels.length,
        },
      });
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

    // /api/widgets
    if (path.isNotEmpty && path[0] == 'widgets') {
      return _handleWidgets(method, path.sublist(1), request);
    }

    // /api/apps
    if (path.isNotEmpty && path[0] == 'apps') {
      return _handleApps(method, path.sublist(1), request);
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

  // ── Cloud provider routes ──────────────────────────────────────────────

  Future<shelf.Response> _handleCloudProviders(
    String method,
    List<String> sub,
    shelf.Request request,
  ) async {
    final service = CloudLlmSettingsService.instance;

    // GET /api/cloud-providers → list all configs + active id + provider type
    if (sub.isEmpty && method == 'GET') {
      final configs = await service.loadConfigs();
      final activeId = await service.loadActiveConfigId();
      final providerType = await service.loadAssistantProviderType();
      return _json({
        'ok': true,
        'providerType': providerType,
        'activeConfigId': activeId,
        'configs':
            configs
                .map(
                  (c) => {
                    'id': c.id,
                    'name': c.name,
                    'baseUrl': c.baseUrl,
                    'model': c.model,
                    'hasKey': c.apiKey.isNotEmpty,
                  },
                )
                .toList(),
      });
    }

    // POST /api/cloud-providers/add { name, baseUrl, apiKey, model, extraHeaders? }
    if (sub.length == 1 && sub[0] == 'add' && method == 'POST') {
      final body = await _body(request);
      final name = body['name'] as String?;
      final baseUrl = body['baseUrl'] as String?;
      final apiKey = body['apiKey'] as String?;
      final model = body['model'] as String?;
      if (name == null || baseUrl == null || apiKey == null || model == null) {
        return _error('Missing required fields: name, baseUrl, apiKey, model');
      }
      final extra = <String, String>{};
      if (body['extraHeaders'] is Map) {
        (body['extraHeaders'] as Map).forEach((k, v) {
          extra[k.toString()] = v.toString();
        });
      }
      final config = CloudLlmConfig(
        id: 'cloud-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        extraHeaders: extra,
      );
      await service.upsertConfig(config);
      return _json({'ok': true, 'action': 'add', 'id': config.id});
    }

    // POST /api/cloud-providers/remove { id }
    if (sub.length == 1 && sub[0] == 'remove' && method == 'POST') {
      final body = await _body(request);
      final id = body['id'] as String?;
      if (id == null) return _error('Missing "id" field');
      await service.removeConfig(id);
      return _json({'ok': true, 'action': 'remove', 'id': id});
    }

    // POST /api/cloud-providers/select { id }
    if (sub.length == 1 && sub[0] == 'select' && method == 'POST') {
      final body = await _body(request);
      final id = body['id'] as String?;
      if (id == null) return _error('Missing "id" field');
      await service.saveActiveConfigId(id);
      return _json({'ok': true, 'action': 'select', 'id': id});
    }

    // POST /api/cloud-providers/provider-type { type: 'local'|'cloud' }
    if (sub.length == 1 && sub[0] == 'provider-type' && method == 'POST') {
      final body = await _body(request);
      final type = body['type'] as String?;
      if (type == null || (type != 'local' && type != 'cloud')) {
        return _error(
          'Missing or invalid "type" field. Expected "local" or "cloud".',
        );
      }
      await service.saveAssistantProviderType(type);
      return _json({'ok': true, 'action': 'set-provider-type', 'type': type});
    }

    // POST /api/cloud-providers/update { id, ...fields }
    if (sub.length == 1 && sub[0] == 'update' && method == 'POST') {
      final body = await _body(request);
      final id = body['id'] as String?;
      if (id == null) return _error('Missing "id" field');
      final existing = await service.loadConfigById(id);
      if (existing == null) return _error('Config not found: $id');
      final updated = CloudLlmConfig(
        id: id,
        name: body['name'] as String? ?? existing.name,
        baseUrl: body['baseUrl'] as String? ?? existing.baseUrl,
        apiKey: body['apiKey'] as String? ?? existing.apiKey,
        model: body['model'] as String? ?? existing.model,
        extraHeaders:
            body['extraHeaders'] is Map
                ? (body['extraHeaders'] as Map).map(
                  (k, v) => MapEntry(k.toString(), v.toString()),
                )
                : existing.extraHeaders,
      );
      await service.upsertConfig(updated);
      return _json({'ok': true, 'action': 'update', 'id': id});
    }

    return _notFound('Unknown cloud-providers route');
  }

  // ── Voice settings routes ──────────────────────────────────────────────

  Future<shelf.Response> _handleVoiceSettings(
    String method,
    List<String> sub,
    shelf.Request request,
  ) async {
    final service = CloudLlmSettingsService.instance;

    // GET /api/voice-settings → current voice settings
    if (sub.isEmpty && method == 'GET') {
      final settings = await service.loadVoiceSettings();
      return _json({
        'ok': true,
        'useCloudAsr': settings.useCloudAsr,
        'convertWavToMp3': settings.convertWavToMp3,
        'useChatModelForCloudAsr': settings.useChatModelForCloudAsr,
        'cloudAsrConfigId': settings.cloudAsrConfigId,
        'cloudAsrModel': settings.cloudAsrModel,
      });
    }

    // POST /api/voice-settings { useCloudAsr?, convertWavToMp3?, cloudAsrConfigId?, cloudAsrModel? }
    if (sub.isEmpty && method == 'POST') {
      final body = await _body(request);
      final current = await service.loadVoiceSettings();
      final updated = current.copyWith(
        useCloudAsr: body['useCloudAsr'] as bool? ?? current.useCloudAsr,
        convertWavToMp3:
            body['convertWavToMp3'] as bool? ?? current.convertWavToMp3,
        useChatModelForCloudAsr:
            body['useChatModelForCloudAsr'] as bool? ??
            current.useChatModelForCloudAsr,
        cloudAsrConfigId:
            body.containsKey('cloudAsrConfigId')
                ? body['cloudAsrConfigId'] as String?
                : current.cloudAsrConfigId,
        cloudAsrModel:
            body.containsKey('cloudAsrModel')
                ? body['cloudAsrModel'] as String?
                : current.cloudAsrModel,
      );
      await service.saveVoiceSettings(updated);
      return _json({
        'ok': true,
        'useCloudAsr': updated.useCloudAsr,
        'convertWavToMp3': updated.convertWavToMp3,
        'useChatModelForCloudAsr': updated.useChatModelForCloudAsr,
        'cloudAsrConfigId': updated.cloudAsrConfigId,
        'cloudAsrModel': updated.cloudAsrModel,
      });
    }

    return _notFound('Unknown voice-settings route');
  }

  Future<shelf.Response> _handleAgents(
    String method,
    List<String> sub,
    shelf.Request request,
  ) async {
    final terminalCubit = _terminalCubit;
    if (terminalCubit == null) return _error('Terminal cubit not available');

    if ((sub.isEmpty || (sub.length == 1 && sub[0] == 'list')) &&
        method == 'GET') {
      final configs = await AgentConfigService.instance.load();
      final defaultId =
          AgentConfigService.instance.defaultAgentId ?? AgentType.copilot.name;
      final state = terminalCubit.state;
      final sessions =
          state is TerminalLoaded
              ? state.allSessions
                  .map(
                    (session) => {
                      'id': session.id,
                      'agent': session.type.name,
                      'displayName':
                          session.customName ?? session.type.displayName,
                      'workspacePath': session.workspacePath,
                      'workspaceId': session.workspaceId,
                      'status': session.status.name,
                    },
                  )
                  .toList()
              : const <Map<String, Object?>>[];
      return _json({
        'ok': true,
        'defaultAgentId': defaultId,
        'agents':
            configs
                .map(
                  (config) => {
                    'id': config.id,
                    'displayName': config.displayName,
                    'iconLabel': config.iconLabel,
                    'launchCommand': config.launchCommand,
                    'visible': config.visible,
                    'isBuiltIn': config.isBuiltIn,
                    'defaultModel': config.defaultModel,
                    'asrMode': config.asrMode,
                    if (config.asrCloudConfigId != null)
                      'asrCloudConfigId': config.asrCloudConfigId,
                    if (config.asrCloudModel != null)
                      'asrCloudModel': config.asrCloudModel,
                    'isDefault': config.id == defaultId,
                  },
                )
                .toList(),
        'sessions': sessions,
      });
    }

    if (sub.length == 1 && sub[0] == 'default' && method == 'POST') {
      final body = await _body(request);
      final id = body['id'] as String?;
      if (id != null &&
          AgentType.values.every((type) => type.name != id) &&
          id.isNotEmpty) {
        return _error('Unknown agent id: $id');
      }
      await AgentConfigService.instance.setDefaultAgentId(id);
      return _json({
        'ok': true,
        'defaultAgentId': id ?? AgentType.copilot.name,
      });
    }

    if (sub.length == 1 && sub[0] == 'run' && method == 'POST') {
      final body = await _body(request);
      final agentId =
          (body['agent'] as String?) ??
          (body['id'] as String?) ??
          AgentConfigService.instance.defaultAgentType.name;
      final workspacePath =
          (body['path'] as String?) ??
          (body['workspacePath'] as String?) ??
          Directory.current.path;
      final task = body['task'] as String?;
      final rawName = (body['name'] as String?)?.trim();
      final requestedSessionName =
          (rawName != null && rawName.isNotEmpty ? rawName : null) ??
          (task != null && task.trim().isNotEmpty
              ? task.trim().length > 40
                  ? '${task.trim().substring(0, 37)}…'
                  : task.trim()
              : 'agent-${DateTime.now().millisecondsSinceEpoch}');

      // Map agent id to board.chat provider string.
      // copilot → 'copilot', opencode → 'opencode', claude → 'claude', etc.
      final provider = agentId; // agent id matches chat provider naming

      // Look up default model from agent config
      final configs = await AgentConfigService.instance.load();
      final agentConfig = configs.firstWhere(
        (c) => c.id == agentId,
        orElse:
            () => AgentConfig(
              id: agentId,
              displayName: agentId,
              iconLabel: agentId[0].toUpperCase(),
              launchCommand: agentId,
              visible: true,
              isBuiltIn: false,
            ),
      );
      final model = agentConfig.defaultModel ?? 'gpt-5-mini';

      // Create board.chat panel on active board
      final cubit = _cubit;
      if (cubit == null) return _error('Board cubit not available');
      final board = cubit.state.activeBoard ?? cubit.state.boards.firstOrNull;
      if (board == null) return _error('No active board');
      final sessionName = makeUniqueChatSessionName(
        requestedSessionName,
        board.panels
            .where((p) => p.type == ChatPanelPlugin.kTypeId)
            .map(
              (p) =>
                  (p.state['config'] is Map
                      ? (Map<String, dynamic>.from(
                            p.state['config'] as Map,
                          ))['sessionName']
                          as String?
                      : null) ??
                  p.title,
            ),
      );

      // Build ChatSessionConfig state for the board.chat panel
      final config = ChatSessionConfig(
        sessionName: sessionName,
        workingDir: workspacePath,
        provider: provider,
        model: model,
        autopilot: false,
      );

      const plugin = ChatPanelPlugin();
      final panelId = 'chat-${DateTime.now().millisecondsSinceEpoch}';
      final bounds = _nextAvailableBoundsFor(
        board,
        preferredWidth: plugin.defaultSize.width,
        preferredHeight: plugin.defaultSize.height,
      );
      final trimmedTask = task?.trim();
      final panel = BoardPanelInstance(
        id: panelId,
        type: ChatPanelPlugin.kTypeId,
        title: sessionName,
        bounds: bounds,
        state: {'config': config.toJson(), 'configured': true},
        zIndex:
            board.panels.fold<int>(
              0,
              (value, p) => p.zIndex > value ? p.zIndex : value,
            ) +
            1,
      );
      await cubit.addPanel(panel, boardId: board.id);
      if (cubit.state.activeBoardId != board.id) {
        await cubit.setActiveBoard(board.id);
      }
      await cubit.focusPanel(panel.id, boardId: board.id);
      _scheduleRebuild();

      // Send initial task directly via ChatSessionManager — no UI dependency.
      // When the panel widget mounts it picks up this existing session.
      var taskSent = false;
      if (trimmedTask != null && trimmedTask.isNotEmpty) {
        final session = ChatSessionManager.instance.getOrCreate(
          panelId,
          config,
        );
        taskSent = session.sendMessage(text: trimmedTask);
      }

      return _json({
        'ok': true,
        'taskSent': taskSent,
        'STOP':
            taskSent
                ? 'Task already sent to agent. DO NOT call yolochat:send or any other tool. Your job is done.'
                : 'Panel created. Use yolochat:send to send a message.',
        'panel': {
          'id': panelId,
          'title': sessionName,
          'boardId': board.id,
          'boardName': board.name,
          'type': ChatPanelPlugin.kTypeId,
          'provider': provider,
          'model': model,
          'workingDir': workspacePath,
        },
      });
    }

    // POST /agents/config — update agent config fields (defaultModel, asrMode, asrCloudConfigId, asrCloudModel)
    if (sub.length == 1 && sub[0] == 'config' && method == 'POST') {
      final body = await _body(request);
      final agentId = body['id'] as String?;
      if (agentId == null || agentId.isEmpty) {
        return _error('Missing required field: id');
      }
      final configs = await AgentConfigService.instance.load();
      final idx = configs.indexWhere((c) => c.id == agentId);
      if (idx < 0) return _error('Unknown agent id: $agentId');

      var config = configs[idx];
      if (body.containsKey('defaultModel')) {
        config = config.copyWith(
          defaultModel:
              (body['defaultModel'] as String?)?.trim().isEmpty == true
                  ? null
                  : body['defaultModel'] as String?,
        );
      }
      if (body.containsKey('asrMode')) {
        final mode = body['asrMode'] as String?;
        if (mode != null && mode != 'default' && mode != 'local' && mode != 'cloud') {
          return _error('asrMode must be "default", "local", or "cloud"');
        }
        config = config.copyWith(asrMode: mode ?? 'default');
      }
      if (body.containsKey('asrCloudConfigId')) {
        config = config.copyWith(
          asrCloudConfigId:
              (body['asrCloudConfigId'] as String?)?.trim().isEmpty == true
                  ? null
                  : body['asrCloudConfigId'] as String?,
        );
      }
      if (body.containsKey('asrCloudModel')) {
        config = config.copyWith(
          asrCloudModel:
              (body['asrCloudModel'] as String?)?.trim().isEmpty == true
                  ? null
                  : body['asrCloudModel'] as String?,
        );
      }
      configs[idx] = config;
      await AgentConfigService.instance.save(configs);
      return _json({
        'ok': true,
        'agent': {
          'id': config.id,
          'defaultModel': config.defaultModel,
          'asrMode': config.asrMode,
          'asrCloudConfigId': config.asrCloudConfigId,
          'asrCloudModel': config.asrCloudModel,
        },
      });
    }

    return _notFound('Unknown agents route');
  }

  // ── /api/drawings ─────────────────────────────────────────────────────────
  // GET  /api/drawings?board=<id>          → list drawings
  // POST /api/drawings                     → add drawing (shape or svg)
  // DELETE /api/drawings/<board>/<id>      → remove drawing
  // DELETE /api/drawings/<board>           → clear all drawings

  Future<shelf.Response> _handleDrawings(
    String method,
    List<String> sub,
    shelf.Request request,
    BoardCubit cubit,
  ) async {
    if (method == 'GET') {
      // GET /api/drawings/svg?board=<id>  → SVG of drawings only
      final isSvgExport = sub.firstOrNull == 'svg';
      final boardId =
          request.url.queryParameters['board'] ??
          (isSvgExport ? sub.elementAtOrNull(1) : sub.firstOrNull);
      final board =
          (boardId != null && boardId.isNotEmpty)
              ? _findBoard(cubit, boardId)
              : cubit.state.activeBoard;
      if (board == null) return _error('Board not found');

      if (isSvgExport) {
        final svg = BoardSvgExporter.exportDrawings(board);
        return shelf.Response.ok(
          svg,
          headers: {'content-type': 'image/svg+xml; charset=utf-8'},
        );
      }
      return _json({
        'ok': true,
        'boardId': board.id,
        'boardName': board.name,
        'count': board.drawings.length,
        'drawings': board.drawings.map(_drawingToJson).toList(),
      });
    }

    if (method == 'POST') {
      try {
        return await _handleDrawingsPost(request, cubit, sub);
      } catch (e, st) {
        developer.log('[Drawings] POST error: $e\n$st');
        return _json({'ok': false, 'error': e.toString()});
      }
    }

    if (method == 'DELETE') {
      // DELETE /api/drawings/<board>/<id>  or  /api/drawings/<board>
      final boardId = sub.firstOrNull;
      if (boardId == null) return _error('Missing board ID in path');
      final board = _findBoard(cubit, boardId);
      if (board == null) return _error('Board not found: $boardId');

      final drawingId = sub.length >= 2 ? sub[1] : null;
      if (drawingId != null) {
        await cubit.removeDrawing(drawingId, boardId: board.id);
        _scheduleRebuild();
        return _json({'ok': true, 'removed': drawingId});
      } else {
        // Clear all drawings
        for (final d in board.drawings) {
          await cubit.removeDrawing(d.id, boardId: board.id);
        }
        _scheduleRebuild();
        return _json({'ok': true, 'cleared': board.drawings.length});
      }
    }

    return _notFound('Unknown drawings route');
  }

  // ── Drawing shape helpers ─────────────────────────────────────────────────

  Future<shelf.Response> _handleDrawingsPost(
    shelf.Request request,
    BoardCubit cubit,
    List<String> sub,
  ) async {
    final body = await _body(request);
    final boardId =
        (body['board'] as String?) ?? request.url.queryParameters['board'];
    final board =
        (boardId != null && boardId.isNotEmpty)
            ? _findBoard(cubit, boardId)
            : cubit.state.activeBoard;
    if (board == null) return _error('Board not found');

    final type = (body['type'] as String? ?? 'freehand').toLowerCase();
    final colorStr = body['color'] as String? ?? '#FFFFFF';
    final color = _parseColor(colorStr) ?? const Color(0xFFFFFFFF);
    final strokeWidth = (body['width'] as num?)?.toDouble() ?? 3.0;
    final posX = (body['x'] as num?)?.toDouble() ?? 100.0;
    final posY = (body['y'] as num?)?.toDouble() ?? 100.0;

    List<List<Offset>> strokes;
    Size size;

    switch (type) {
      case 'line':
        final x1 = (body['x1'] as num?)?.toDouble() ?? posX;
        final y1 = (body['y1'] as num?)?.toDouble() ?? posY;
        final x2 = (body['x2'] as num?)?.toDouble() ?? posX + 200;
        final y2 = (body['y2'] as num?)?.toDouble() ?? posY;
        final result = _lineToElement(x1, y1, x2, y2, strokeWidth);
        strokes = result.$1;
        size = result.$2;

      case 'arrow':
        final x1 = (body['x1'] as num?)?.toDouble() ?? posX;
        final y1 = (body['y1'] as num?)?.toDouble() ?? posY;
        final x2 = (body['x2'] as num?)?.toDouble() ?? posX + 200;
        final y2 = (body['y2'] as num?)?.toDouble() ?? posY;
        final result = _arrowToElement(x1, y1, x2, y2, strokeWidth);
        strokes = result.$1;
        size = result.$2;

      case 'circle':
        final cx = (body['cx'] as num?)?.toDouble() ?? posX;
        final cy = (body['cy'] as num?)?.toDouble() ?? posY;
        final r =
            (body['r'] as num?)?.toDouble() ??
            (body['radius'] as num?)?.toDouble() ??
            50.0;
        final result = _circleToElement(cx, cy, r, strokeWidth);
        strokes = result.$1;
        size = result.$2;

      case 'rect':
      case 'rectangle':
        final rx = (body['x'] as num?)?.toDouble() ?? posX;
        final ry = (body['y'] as num?)?.toDouble() ?? posY;
        // Use 'rw' or 'rectWidth' for shape width; fall back to 'width' only if
        // no stroke-width was explicitly provided (to avoid conflict).
        final w =
            (body['rw'] as num?)?.toDouble() ??
            (body['rectWidth'] as num?)?.toDouble() ??
            (body['w'] as num?)?.toDouble() ??
            200.0;
        final h = (body['height'] as num?)?.toDouble() ?? 100.0;
        final result = _rectToElement(rx, ry, w, h, strokeWidth);
        strokes = result.$1;
        size = result.$2;

      case 'svg':
        final pathD = body['d'] as String? ?? body['path'] as String? ?? '';
        final svgStr = body['svg'] as String?;
        final dStr =
            pathD.isNotEmpty
                ? pathD
                : (svgStr != null ? _extractSvgPathD(svgStr) : '');
        if (dStr.isEmpty) {
          return _json({
            'ok': false,
            'error': 'Missing "d" (SVG path data) or "svg" field',
          });
        }
        final result = _svgPathToElement(dStr, posX, posY, strokeWidth);
        if (result == null) {
          return _json({
            'ok': false,
            'error':
                'Failed to parse SVG path — check "d" syntax (M/L/C/Q/Z commands)',
          });
        }
        strokes = result.$1;
        size = result.$2;

      case 'file':
        // Render all paths from an SVG file as a single drawing element
        final filePath =
            body['file'] as String? ?? body['path'] as String? ?? '';
        if (filePath.isEmpty) {
          return _json({
            'ok': false,
            'error': 'Missing "file" — provide path to SVG file',
          });
        }
        final svgFile = File(filePath);
        if (!svgFile.existsSync()) {
          return _json({'ok': false, 'error': 'SVG file not found: $filePath'});
        }
        final svgContent = await svgFile.readAsString();
        // Extract all d="" attributes and combine into one element per path
        final dMatches = RegExp(r'd="([^"]*)"').allMatches(svgContent);
        final allStrokes = <List<Offset>>[];
        var maxW = 0.0, maxH = 0.0;
        for (final m in dMatches) {
          final d = m.group(1) ?? '';
          if (d.isEmpty) continue;
          final r = _svgPathToElement(d, 0, 0, strokeWidth);
          if (r != null) {
            allStrokes.addAll(r.$1);
            if (r.$2.width > maxW) maxW = r.$2.width;
            if (r.$2.height > maxH) maxH = r.$2.height;
          }
        }
        if (allStrokes.isEmpty) {
          return _json({
            'ok': false,
            'error': 'No drawable paths found in SVG file',
          });
        }
        strokes = allStrokes;
        size = Size(maxW, maxH);

      case 'freehand':
      default:
        final rawPointsVal = body['points'];
        final rawPoints =
            rawPointsVal is List
                ? rawPointsVal
                : rawPointsVal is String
                ? (jsonDecode(rawPointsVal) as List?)
                : null;
        if (rawPoints == null || rawPoints.isEmpty) {
          return _json({
            'ok': false,
            'error': 'Missing "points" for freehand — provide [[x,y],...]',
          });
        }
        final points =
            rawPoints.map((p) {
              final pt = p as List;
              return Offset(
                pt[0] is num ? (pt[0] as num).toDouble() : 0,
                pt[1] is num ? (pt[1] as num).toDouble() : 0,
              );
            }).toList();
        final result = _freehandToElement(points, strokeWidth);
        strokes = result.$1;
        size = result.$2;
    }

    final absPos = switch (type) {
      'line' || 'arrow' => Offset(
        math.min(
              (body['x1'] as num?)?.toDouble() ?? posX,
              (body['x2'] as num?)?.toDouble() ?? posX + 200,
            ) -
            strokeWidth,
        math.min(
              (body['y1'] as num?)?.toDouble() ?? posY,
              (body['y2'] as num?)?.toDouble() ?? posY,
            ) -
            strokeWidth,
      ),
      'circle' => Offset(
        ((body['cx'] as num?)?.toDouble() ?? posX) -
            ((body['r'] as num?)?.toDouble() ?? 50.0) -
            strokeWidth,
        ((body['cy'] as num?)?.toDouble() ?? posY) -
            ((body['r'] as num?)?.toDouble() ?? 50.0) -
            strokeWidth,
      ),
      'rect' || 'rectangle' => Offset(
        (body['x'] as num?)?.toDouble() ?? posX,
        (body['y'] as num?)?.toDouble() ?? posY,
      ),
      _ => Offset(posX, posY),
    };

    final maxZ = board.drawings.fold<int>(
      0,
      (v, d) => d.zIndex > v ? d.zIndex : v,
    );
    final drawing = BoardDrawingElement(
      id: 'drawing-${DateTime.now().millisecondsSinceEpoch}',
      strokes: strokes,
      position: absPos,
      size: size,
      strokeColor: color,
      strokeWidth: strokeWidth,
      zIndex: maxZ + 1,
    );
    await cubit.addDrawing(drawing, boardId: board.id);
    _scheduleRebuild();
    return _json({
      'ok': true,
      'id': drawing.id,
      'boardId': board.id,
      'type': type,
      'strokeCount': strokes.length,
      'pointCount': strokes.fold<int>(0, (s, st) => s + st.length),
    });
  }

  Map<String, dynamic> _drawingToJson(BoardDrawingElement d) => {
    'id': d.id,
    'position': [d.position.dx, d.position.dy],
    'size': [d.size.width, d.size.height],
    'strokeCount': d.strokes.length,
    'pointCount': d.strokes.fold<int>(0, (s, st) => s + st.length),
    'strokeColor':
        '#${d.strokeColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'strokeWidth': d.strokeWidth,
    'zIndex': d.zIndex,
    'hidden': d.hidden,
  };

  (List<List<Offset>>, Size) _lineToElement(
    double x1,
    double y1,
    double x2,
    double y2,
    double sw,
  ) {
    final minX = math.min(x1, x2) - sw;
    final minY = math.min(y1, y2) - sw;
    final origin = Offset(minX, minY);
    final pts = [Offset(x1, y1) - origin, Offset(x2, y2) - origin];
    final size = Size((x2 - x1).abs() + sw * 2, (y2 - y1).abs() + sw * 2);
    return ([pts], size);
  }

  (List<List<Offset>>, Size) _arrowToElement(
    double x1,
    double y1,
    double x2,
    double y2,
    double sw,
  ) {
    final angle = math.atan2(y2 - y1, x2 - x1);
    const headLen = 20.0;
    const headAngle = 0.4; // radians
    final hx1 = x2 - headLen * math.cos(angle - headAngle);
    final hy1 = y2 - headLen * math.sin(angle - headAngle);
    final hx2 = x2 - headLen * math.cos(angle + headAngle);
    final hy2 = y2 - headLen * math.sin(angle + headAngle);
    final minX = [x1, x2, hx1, hx2].reduce(math.min) - sw;
    final minY = [y1, y2, hy1, hy2].reduce(math.min) - sw;
    final maxX = [x1, x2, hx1, hx2].reduce(math.max) + sw;
    final maxY = [y1, y2, hy1, hy2].reduce(math.max) + sw;
    final origin = Offset(minX, minY);
    final shaft = [Offset(x1, y1) - origin, Offset(x2, y2) - origin];
    final head1 = [Offset(hx1, hy1) - origin, Offset(x2, y2) - origin];
    final head2 = [Offset(hx2, hy2) - origin, Offset(x2, y2) - origin];
    return ([shaft, head1, head2], Size(maxX - minX, maxY - minY));
  }

  (List<List<Offset>>, Size) _circleToElement(
    double cx,
    double cy,
    double r,
    double sw,
  ) {
    const steps = 64;
    final minX = cx - r - sw;
    final minY = cy - r - sw;
    final origin = Offset(minX, minY);
    final pts = List.generate(steps + 1, (i) {
      final angle = 2 * math.pi * i / steps;
      return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)) -
          origin;
    });
    final size = Size((r + sw) * 2, (r + sw) * 2);
    return ([pts], size);
  }

  (List<List<Offset>>, Size) _rectToElement(
    double rx,
    double ry,
    double w,
    double h,
    double sw,
  ) {
    final origin = Offset(rx - sw, ry - sw);
    final pts = [
      Offset(rx, ry) - origin,
      Offset(rx + w, ry) - origin,
      Offset(rx + w, ry + h) - origin,
      Offset(rx, ry + h) - origin,
      Offset(rx, ry) - origin,
    ];
    return ([pts], Size(w + sw * 2, h + sw * 2));
  }

  (List<List<Offset>>, Size) _freehandToElement(
    List<Offset> points,
    double sw,
  ) {
    if (points.isEmpty) return ([<Offset>[]], Size(sw * 2, sw * 2));
    double minX = points.first.dx, minY = points.first.dy;
    double maxX = minX, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    final origin = Offset(minX - sw, minY - sw);
    final rel = points.map((p) => p - origin).toList();
    return ([rel], Size(maxX - minX + sw * 2, maxY - minY + sw * 2));
  }

  /// Extract the `d` attribute from a simple SVG string.
  String _extractSvgPathD(String svg) {
    final match = RegExp(r'd="([^"]*)"').firstMatch(svg);
    return match?.group(1) ?? '';
  }

  /// Parse a subset of SVG path commands into strokes.
  /// Supports: M, L, H, V, C (cubic bezier), Q (quadratic), Z, and lowercase variants.
  (List<List<Offset>>, Size)? _svgPathToElement(
    String d,
    double baseX,
    double baseY,
    double sw,
  ) {
    final strokes = <List<Offset>>[];
    List<Offset> current = [];
    double cx = 0, cy = 0;

    // Tokenize: split on command letters, keeping the letter
    final tokens =
        RegExp(
          r'[MLHVCSQTAZmlhvcsqtaz]|[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?',
        ).allMatches(d).map((m) => m.group(0)!).toList();

    int i = 0;
    String cmd = 'M';
    while (i < tokens.length) {
      final t = tokens[i];
      if (RegExp(r'[MLHVCSQTAZmlhvcsqtaz]').hasMatch(t)) {
        i++;
        // Z/z need no arguments — handle immediately
        if (t == 'Z' || t == 'z') {
          if (current.length > 1) current.add(current.first);
          if (current.isNotEmpty) strokes.add(current);
          current = [];
        } else {
          cmd = t;
        }
        continue;
      }
      double num() {
        final v = double.tryParse(tokens[i]) ?? 0;
        i++;
        return v;
      }

      switch (cmd) {
        case 'M':
          if (current.isNotEmpty) strokes.add(current);
          cx = num();
          cy = num();
          current = [Offset(cx, cy)];
          cmd = 'L';
        case 'm':
          if (current.isNotEmpty) strokes.add(current);
          cx += num();
          cy += num();
          current = [Offset(cx, cy)];
          cmd = 'l';
        case 'L':
          cx = num();
          cy = num();
          current.add(Offset(cx, cy));
        case 'l':
          cx += num();
          cy += num();
          current.add(Offset(cx, cy));
        case 'H':
          cx = num();
          current.add(Offset(cx, cy));
        case 'h':
          cx += num();
          current.add(Offset(cx, cy));
        case 'V':
          cy = num();
          current.add(Offset(cx, cy));
        case 'v':
          cy += num();
          current.add(Offset(cx, cy));
        case 'C': // cubic bezier — approximate with 10 points
          final x1 = num(), y1 = num(), x2 = num(), y2 = num();
          final ex = num(), ey = num();
          for (int s = 1; s <= 10; s++) {
            final tt = s / 10;
            final bx = _cubicBezier(cx, x1, x2, ex, tt);
            final by = _cubicBezier(cy, y1, y2, ey, tt);
            current.add(Offset(bx, by));
          }
          cx = ex;
          cy = ey;
        case 'c':
          final x1 = cx + num(), y1 = cy + num();
          final x2 = cx + num(), y2 = cy + num();
          final ex = cx + num(), ey = cy + num();
          for (int s = 1; s <= 10; s++) {
            final tt = s / 10;
            current.add(
              Offset(
                _cubicBezier(cx, x1, x2, ex, tt),
                _cubicBezier(cy, y1, y2, ey, tt),
              ),
            );
          }
          cx = ex;
          cy = ey;
        case 'Q': // quadratic bezier
          final x1 = num(), y1 = num(), ex = num(), ey = num();
          for (int s = 1; s <= 10; s++) {
            final tt = s / 10;
            current.add(
              Offset(_quadBezier(cx, x1, ex, tt), _quadBezier(cy, y1, ey, tt)),
            );
          }
          cx = ex;
          cy = ey;
        case 'q':
          final x1 = cx + num(), y1 = cy + num();
          final ex = cx + num(), ey = cy + num();
          for (int s = 1; s <= 10; s++) {
            final tt = s / 10;
            current.add(
              Offset(_quadBezier(cx, x1, ex, tt), _quadBezier(cy, y1, ey, tt)),
            );
          }
          cx = ex;
          cy = ey;
        default:
          i++; // skip unknown
      }
    }
    if (current.isNotEmpty) strokes.add(current);
    if (strokes.isEmpty) return null;

    // Compute bounding box of all points
    final allPts = strokes.expand((s) => s).toList();
    double minX = allPts.first.dx, minY = allPts.first.dy;
    double maxX = minX, maxY = minY;
    for (final p in allPts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    final origin = Offset(minX - sw, minY - sw);
    final relStrokes =
        strokes.map((s) => s.map((p) => p - origin).toList()).toList();
    return (relStrokes, Size(maxX - minX + sw * 2, maxY - minY + sw * 2));
  }

  double _cubicBezier(double p0, double p1, double p2, double p3, double t) {
    final mt = 1 - t;
    return mt * mt * mt * p0 +
        3 * mt * mt * t * p1 +
        3 * mt * t * t * p2 +
        t * t * t * p3;
  }

  double _quadBezier(double p0, double p1, double p2, double t) {
    final mt = 1 - t;
    return mt * mt * p0 + 2 * mt * t * p1 + t * t * p2;
  }

  Future<shelf.Response> _handleSearch(
    String method,
    List<String> sub,
    shelf.Request request,
    BoardCubit cubit,
  ) async {
    if (method != 'GET' || (sub.isNotEmpty && sub[0] != 'all')) {
      return _notFound('Unknown search route');
    }
    final query =
        request.url.queryParameters['q']?.trim() ??
        request.url.queryParameters['query']?.trim() ??
        '';
    if (query.isEmpty) return _error('Missing "q" query parameter');
    final scope =
        request.url.queryParameters['scope']?.trim().toLowerCase() ?? 'all';

    final items = <Map<String, Object?>>[];
    if (scope == 'all' || scope == 'boards' || scope == 'panels') {
      items.addAll(_searchBoards(cubit, query));
    }
    if (scope == 'all' || scope == 'active-chats' || scope == 'chats') {
      items.addAll(_searchActiveChats(query));
    }
    if (scope == 'all' || scope == 'sessions' || scope == 'history') {
      items.addAll(await _searchSavedChatSessions(query));
    }

    return _json({'ok': true, 'query': query, 'scope': scope, 'items': items});
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
    final bool? enableThinking =
        body.containsKey('enableThinking')
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
      final response =
          full.trim().isNotEmpty ? full.trim() : buffer.toString().trim();
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
      // Inject global cloud provider if no explicit provider specified
      if (!body.containsKey('provider')) {
        final service = CloudLlmSettingsService.instance;
        final providerType = await service.loadAssistantProviderType();
        if (providerType == 'cloud') {
          final activeId = await service.loadActiveConfigId();
          if (activeId != null) {
            body['provider'] = 'cloud:$activeId';
          }
        }
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

    // POST /yolochat/clear
    if (sub.length == 1 && sub[0] == 'clear' && method == 'POST') {
      final body = await _body(request);
      final target = _resolveYoloChatTarget(
        cubit,
        boardHint: body['board'] as String?,
        panelHint: body['panel'] as String?,
      );
      if (target == null) {
        return _error('No board.chat panel found (or target not found)');
      }
      return _panelAction(cubit, target.board, target.panel, {
        'action': 'clear',
      });
    }

    // GET /yolochat/sessions
    // GET /yolochat/sessions — list all active sessions (no target needed)
    if (sub.length == 1 && sub[0] == 'sessions' && method == 'GET') {
      final ids = ChatSessionManager.instance.activeSessionIds;
      final sessions = <Map<String, dynamic>>[];
      for (final id in ids) {
        final session = ChatSessionManager.instance.get(id);
        if (session != null) {
          sessions.add({
            'panelId': id,
            'provider': session.config.provider,
            'model': session.config.model,
            'messageCount': session.messages.length,
            'isProcessing': session.isProcessing,
          });
        }
      }
      return _json({'ok': true, 'sessions': sessions});
    }

    if (sub.length == 1 && sub[0] == 'history' && method == 'GET') {
      final entries = await ChatSessionHistory.instance.loadAll();
      return _json({
        'ok': true,
        'sessions':
            entries
                .map(
                  (entry) => {
                    'id': entry.id,
                    'sessionName': entry.sessionName,
                    'provider': entry.provider,
                    'model': entry.model,
                    'workingDir': entry.workingDir,
                    'messageCount': entry.messageCount,
                    'createdAt': entry.createdAt.toIso8601String(),
                    'lastMessageAt': entry.lastMessageAt?.toIso8601String(),
                  },
                )
                .toList(),
      });
    }

    if (sub.length == 1 && sub[0] == 'restore' && method == 'POST') {
      final body = await _body(request);
      final sessionId = body['sessionId'] as String? ?? body['id'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        return _error('Missing "sessionId" field');
      }
      final entries = await ChatSessionHistory.instance.loadAll();
      final entry = entries.where((item) => item.id == sessionId).firstOrNull;
      if (entry == null) {
        return _error('Saved session not found: $sessionId');
      }
      final messages = await ChatSessionHistory.instance.loadMessages(
        sessionId,
      );
      final target = _resolveYoloChatTarget(
        cubit,
        boardHint: body['board'] as String?,
        panelHint: body['panel'] as String?,
      );
      if (target == null) {
        return _error('No board.chat panel found (or target not found)');
      }
      final restoredState = Map<String, dynamic>.from(target.panel.state)
        ..addAll({
          'messages': messages,
          'provider': entry.provider,
          'model': entry.model,
          'sessionName': entry.sessionName,
          'workingDir': entry.workingDir,
        });
      await cubit.updatePanel(
        target.panel.id,
        (panel) => panel.copyWith(state: restoredState),
        boardId: target.board.id,
      );
      _scheduleRebuild();
      return _json({
        'ok': true,
        'restored': {
          'id': entry.id,
          'sessionName': entry.sessionName,
          'messageCount': messages.length,
        },
      });
    }

    // GET /yolochat/status
    if (sub.length == 1 && sub[0] == 'status' && method == 'GET') {
      final boardHint = request.url.queryParameters['board'];
      final panelHint = request.url.queryParameters['panel'];
      final target = _resolveYoloChatTarget(
        cubit,
        boardHint: boardHint,
        panelHint: panelHint,
      );
      if (target == null) {
        return _error('No board.chat panel found (or target not found)');
      }
      return _panelAction(cubit, target.board, target.panel, {
        'action': 'status',
      });
    }

    // POST /yolochat/stop
    if (sub.length == 1 && sub[0] == 'stop' && method == 'POST') {
      final body = await _body(request);
      final boardHint = body['board'] as String?;
      final panelHint = body['panel'] as String?;
      final hasExplicitTarget =
          (boardHint?.trim().isNotEmpty ?? false) ||
          (panelHint?.trim().isNotEmpty ?? false);

      if (!hasExplicitTarget) {
        final stopped = await _stopAllActiveYoloChats();
        if (stopped > 0) {
          return _json({
            'ok': true,
            'message': 'Stopped $stopped active chat stream(s)',
            'stopped': stopped,
          });
        }
      }

      final target = _resolveYoloChatTarget(
        cubit,
        boardHint: boardHint,
        panelHint: panelHint,
      );
      if (target == null) {
        return _error(
          hasExplicitTarget
              ? 'No board.chat panel found (or target not found)'
              : 'No active chat stream to stop',
        );
      }
      return _panelAction(cubit, target.board, target.panel, {
        'action': 'stop',
      });
    }

    // GET /yolochat/logs — full session log for debugging (copy-paste friendly)
    if (sub.length == 1 && sub[0] == 'logs' && method == 'GET') {
      final boardHint = request.url.queryParameters['board'];
      final panelHint = request.url.queryParameters['panel'];
      final target = _resolveYoloChatTarget(
        cubit,
        boardHint: boardHint,
        panelHint: panelHint,
      );
      if (target == null) {
        return _error('No board.chat panel found (or target not found)');
      }
      final session = ChatSessionManager.instance.get(target.panel.id);
      final messages = session?.messages ?? [];
      final buf = StringBuffer();
      buf.writeln('=== YoLoIT Chat Logs ===');
      buf.writeln('Board: ${target.board.name}');
      buf.writeln('Panel: ${target.panel.title ?? target.panel.id}');
      buf.writeln('Provider: ${session?.config.provider ?? "unknown"}');
      buf.writeln('Model: ${session?.config.model ?? "unknown"}');
      buf.writeln('Messages: ${messages.length}');
      buf.writeln('');
      for (final msg in messages) {
        buf.writeln('--- [${msg.role.name}] ---');
        buf.writeln(msg.content);
        if (msg.toolCalls.isNotEmpty) {
          for (final tc in msg.toolCalls) {
            buf.writeln('  [tool] ${tc.toolName}(${tc.arguments})');
            if (tc.result != null) buf.writeln('  [result] ${tc.result}');
          }
        }
        buf.writeln('');
      }
      return shelf.Response.ok(
        buf.toString(),
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    }

    return _notFound('Unknown yolochat route');
  }

  Future<int> _stopAllActiveYoloChats() async {
    var stopped = 0;
    final ids = ChatSessionManager.instance.activeSessionIds;
    for (final id in ids) {
      final session = ChatSessionManager.instance.get(id);
      if (session == null || !session.isProcessing) continue;
      await session.stopStreaming();
      stopped++;
    }
    return stopped;
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
      final forceOffscreen =
          request.url.queryParameters['mode'] == 'offscreen';
      return _boardScreenshot(
        board,
        cubit: cubit,
        forceOffscreen: forceOffscreen,
      );
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
      if (panel.type == 'board.widget.custom') {
        WidgetEngineManager.instance.remove(panel.id);
      }
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

  Future<shelf.Response> _boardScreenshot(
    BoardDocument board, {
    BoardCubit? cubit,
    bool forceOffscreen = false,
  }) async {
    final activeCubit = cubit ?? _cubit;
    if (activeCubit == null) return _error('Board cubit not available');

    Uint8List? png;
    if (forceOffscreen) {
      debugPrint('[CliServer] screenshot: offscreen board=${board.id}');
      png = await BoardOffscreenRenderer.instance.renderBoard(board);
    } else {
      final activeBoard = activeCubit.state.activeBoard;
      final isActiveBoard =
          activeBoard != null && activeBoard.id == board.id;
      if (isActiveBoard) {
        _scheduleRebuild();
        png = await BoardScreenshotService.instance.capturePng(
          pixelRatio: 1.5,
        );
      } else {
        debugPrint('[CliServer] screenshot: offscreen board=${board.id}');
        png = await BoardOffscreenRenderer.instance.renderBoard(board);
      }
    }

    if (png == null) {
      return _error('Failed to capture board screenshot');
    }

    // Also save to the preview cache directory for the overview.
    try {
      final cacheDir = Directory(
        '${Directory.systemTemp.path}/yoloit_board_previews',
      );
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      File('${cacheDir.path}/${board.id}.png').writeAsBytesSync(png);
    } catch (_) {}

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
      if (cubit.state.activeBoardId != board.id) {
        await cubit.setActiveBoard(board.id);
      }
      await cubit.focusPanel(panel.id, boardId: board.id, zoomOnFocus: true);
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

    final result = await handler.handleAction(action, {
      ...body,
      '_boardId': board.id,
      '_boardName': board.name,
      '_panelType': panel.type,
      '_availableBoardsSummary': cubit.state.boards
          .map((b) {
            final marker = b.id == board.id ? ' (current)' : '';
            return '- ${b.name} [${b.id}]$marker';
          })
          .join('\n'),
      '_currentBoardPanelsSummary': board.panels
          .map((p) => '- ${p.title} [${p.type}] (${p.id})')
          .join('\n'),
    }, panel);

    // Apply state update if provided
    if (result.stateUpdate != null && result.ok) {
      final mergedState = {...panel.state, ...result.stateUpdate!};
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(state: mergedState),
        boardId: board.id,
      );
      // Start/stop TimerManager when timer state changes via CLI
      if (panel.type == 'board.timer') {
        if (mergedState['isRunning'] == true) {
          TimerManager.instance.start(
            panelId: panel.id,
            boardId: board.id,
            remaining: mergedState['remaining'] as int? ?? 300,
          );
        } else {
          TimerManager.instance.stop(panel.id);
        }
      }
      // Directly control playlist player via registry — needed when the widget
      // is not mounted (user is on a different board) and didUpdateWidget won't fire.
      if (panel.type == 'board.playlist') {
        await PlaylistPlayerRegistry.instance.applyPlaybackCommand(
          panel.id,
          mergedState,
        );
      }
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
      if (cubit.state.activeBoardId != board.id) {
        await cubit.setActiveBoard(board.id);
      }
      await cubit.focusPanel(panel.id, boardId: board.id, zoomOnFocus: true);
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
      if (cubit.state.activeBoardId != board.id) {
        await cubit.setActiveBoard(board.id);
      }
      await cubit.focusPanel(panel.id, boardId: board.id, zoomOnFocus: true);
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
    if (panel.type == 'board.widget.custom') {
      WidgetEngineManager.instance.remove(panel.id);
    }
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
    // Switch to the target board first so the panel is actually visible.
    if (cubit.state.activeBoardId != board.id) {
      await cubit.setActiveBoard(board.id);
    }
    await cubit.focusPanel(panel.id, boardId: board.id, zoomOnFocus: true);
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

    final result = await handler.handleAction(action, {
      ...body,
      '_boardId': board.id,
      '_boardName': board.name,
    }, panel);
    if (result.stateUpdate != null && result.ok) {
      final mergedState = {...panel.state, ...result.stateUpdate!};
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(state: mergedState),
        boardId: board.id,
      );
      if (panel.type == 'board.playlist') {
        await PlaylistPlayerRegistry.instance.applyPlaybackCommand(
          panel.id,
          mergedState,
        );
      }
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

  List<Map<String, Object?>> _searchBoards(BoardCubit cubit, String query) {
    final items = <Map<String, Object?>>[];
    for (final board in cubit.state.boards) {
      // Also search board name itself.
      final boardSnippet = _matchSnippet(board.name, query);
      if (boardSnippet != null) {
        items.add({
          'scope': 'board',
          'boardId': board.id,
          'boardName': board.name,
          'panelId': null,
          'panelTitle': null,
          'panelType': null,
          'snippet': boardSnippet,
        });
      }
      for (final panel in board.panels) {
        // Include panel ID as a searchable field so queries like
        // "demo_copilot" or "demo copilot" match a panel named demo_copilot.
        final texts = <String>[
          if ((panel.title ?? '').trim().isNotEmpty) panel.title!.trim(),
          panel.id,
          ..._collectSearchStrings(panel.state),
        ];
        for (final text in texts) {
          final snippet = _matchSnippet(text, query);
          if (snippet == null) continue;
          items.add({
            'scope': 'board',
            'boardId': board.id,
            'boardName': board.name,
            'panelId': panel.id,
            'panelTitle': panel.title ?? panel.id,
            'panelType': panel.type,
            'snippet': snippet,
          });
          break;
        }
      }
    }
    return items;
  }

  List<Map<String, Object?>> _searchActiveChats(String query) {
    final items = <Map<String, Object?>>[];
    for (final panelId in ChatSessionManager.instance.activeSessionIds) {
      final session = ChatSessionManager.instance.get(panelId);
      if (session == null) continue;
      for (final message in session.messages) {
        final snippet = _matchSnippet(message.content, query);
        if (snippet == null) continue;
        items.add({
          'scope': 'active-chat',
          'panelId': panelId,
          'provider': session.config.provider,
          'model': session.config.model,
          'role': message.role.name,
          'snippet': snippet,
        });
      }
    }
    return items;
  }

  Future<List<Map<String, Object?>>> _searchSavedChatSessions(
    String query,
  ) async {
    final entries = await ChatSessionHistory.instance.loadAll();
    final items = <Map<String, Object?>>[];
    for (final entry in entries) {
      final messages = await ChatSessionHistory.instance.loadMessages(entry.id);
      for (final message in messages) {
        if (message is! Map<String, dynamic>) continue;
        final content = message['content'] as String? ?? '';
        final snippet = _matchSnippet(content, query);
        if (snippet == null) continue;
        items.add({
          'scope': 'saved-session',
          'sessionId': entry.id,
          'sessionName': entry.sessionName,
          'provider': entry.provider,
          'model': entry.model,
          'workingDir': entry.workingDir,
          'role': message['role'] ?? 'unknown',
          'snippet': snippet,
        });
      }
    }
    return items;
  }

  List<String> _collectSearchStrings(dynamic value, {int depth = 0}) {
    if (value == null || depth > 4) return const [];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const [] : <String>[trimmed];
    }
    if (value is num || value is bool) return <String>['$value'];
    if (value is List) {
      final out = <String>[];
      for (final item in value) {
        out.addAll(_collectSearchStrings(item, depth: depth + 1));
      }
      return out;
    }
    if (value is Map) {
      final out = <String>[];
      for (final entry in value.entries) {
        if (entry.key == 'id' || entry.key == 'timestamp') continue;
        out.addAll(_collectSearchStrings(entry.value, depth: depth + 1));
      }
      return out;
    }
    return const [];
  }

  /// Returns a snippet of [text] if it matches [query], or null if no match.
  ///
  /// Matching strategy (most-specific first):
  /// 1. Exact substring (case-insensitive) — highest fidelity, returns a
  ///    centred snippet.
  /// 2. Separator-normalised substring — spaces, underscores, hyphens and dots
  ///    are treated as equivalent (e.g. "demo copilot" matches "demo_copilot").
  /// 3. All-words anywhere — every whitespace-token in the query appears
  ///    somewhere in the normalised text (order-independent).
  String? _matchSnippet(String text, String query) {
    final haystack = text.toLowerCase();
    final needle = query.toLowerCase().trim();

    // 1. Exact substring match.
    final exactIdx = haystack.indexOf(needle);
    if (exactIdx >= 0) {
      return _buildSnippet(text, exactIdx, needle.length);
    }

    // Normalise both sides: replace _, -, . with space.
    final normHaystack = haystack.replaceAll(RegExp(r'[_\-.]'), ' ');
    final normNeedle = needle.replaceAll(RegExp(r'[_\-.]'), ' ');

    // 2. Separator-normalised substring match.
    final normIdx = normHaystack.indexOf(normNeedle);
    if (normIdx >= 0) {
      return _buildSnippet(text, normIdx, normNeedle.length);
    }

    // 3. All query words present anywhere (order-independent).
    final queryWords =
        normNeedle.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (queryWords.length > 1) {
      final allMatch = queryWords.every(
        (w) => normHaystack.contains(w),
      );
      if (allMatch) {
        // Find the first word match to anchor the snippet.
        final firstIdx = normHaystack.indexOf(queryWords.first);
        return _buildSnippet(
          text,
          firstIdx < 0 ? 0 : firstIdx,
          queryWords.first.length,
        );
      }
    }

    return null;
  }

  String _buildSnippet(String text, int matchIdx, int matchLen) {
    final start = (matchIdx - 48).clamp(0, text.length);
    final end = (matchIdx + matchLen + 72).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end).replaceAll('\n', ' ')}$suffix';
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

  // ── Widget routes ──────────────────────────────────────────────────────────

  Future<shelf.Response> _handleWidgets(
    String method,
    List<String> sub,
    shelf.Request request,
  ) async {
    final registry = WidgetRegistryService.instance;

    // GET /api/widgets — list all installed widgets
    if (sub.isEmpty && method == 'GET') {
      final widgets = await registry.loadAll();
      return _json({'widgets': widgets.map((m) => m.toJson()).toList()});
    }

    // POST /api/widgets/install  { path: "..." }
    if (sub.length == 1 && sub[0] == 'install' && method == 'POST') {
      final body = await _body(request);
      final srcPath = body['path'] as String?;
      if (srcPath == null || srcPath.trim().isEmpty) {
        return _error('Missing "path" field');
      }
      final manifest = await registry.install(srcPath.trim());
      if (manifest == null)
        return _error('Failed to install widget from: $srcPath');
      return _json({'ok': true, 'widget': manifest.toJson()});
    }

    // DELETE /api/widgets/:id
    if (sub.length == 1 && method == 'DELETE') {
      final id = sub[0];
      final removed = await registry.remove(id);
      return _json({'ok': removed, 'id': id});
    }

    // GET /api/widgets/:id — single widget details
    if (sub.length == 1 && method == 'GET') {
      final manifest = await registry.find(sub[0]);
      if (manifest == null) return _notFound('Widget not found: ${sub[0]}');
      return _json({'widget': manifest.toJson()});
    }

    return _notFound('Unknown widget route');
  }

  // ── App routes ─────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleApps(
    String method,
    List<String> sub,
    shelf.Request request,
  ) async {
    final registry = WidgetRegistryService.instance;
    final appRegistry = WidgetAppRegistry.instance;

    // GET /api/apps — list all installed widgets + which are currently active
    if (sub.isEmpty && method == 'GET') {
      final widgets = await registry.loadAll();
      final activeIds = appRegistry.activeIds();
      return _json({
        'apps':
            widgets
                .map((m) => {...m.toJson(), 'active': activeIds.contains(m.id)})
                .toList(),
        'activeIds': activeIds,
      });
    }

    // GET /api/apps/dev-skill — return the app development skill doc
    if (sub.length == 1 && sub[0] == 'dev-skill' && method == 'GET') {
      try {
        final content = await rootBundle.loadString(
          'docs/app-development-skill.md',
        );
        return shelf.Response.ok(
          content,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        );
      } catch (e) {
        return _error('Skill doc not found: $e');
      }
    }

    // GET /api/apps/demo — list installed demo apps with their file paths
    if (sub.length == 1 && sub[0] == 'demo' && method == 'GET') {
      final appsDir = Directory(
        '${Platform.environment['HOME']}/.config/yoloit/apps',
      );
      if (!await appsDir.exists()) {
        return _json({'demos': []});
      }
      final demos = <Map<String, Object?>>[];
      await for (final entry in appsDir.list()) {
        if (entry is! Directory) continue;
        final manifestFile = File('${entry.path}/manifest.json');
        if (!await manifestFile.exists()) continue;
        try {
          final raw = await manifestFile.readAsString();
          final manifest = jsonDecode(raw) as Map<String, dynamic>;
          demos.add({
            'id':
                manifest['id'] ?? entry.path.split(Platform.pathSeparator).last,
            'name': manifest['name'] ?? '',
            'description': manifest['description'] ?? '',
            'icon': manifest['icon'] ?? '',
            'network': manifest['network'] ?? false,
            'path': entry.path,
            'files': {
              'manifest': '${entry.path}/manifest.json',
              'widget': '${entry.path}/widget.js',
            },
          });
        } catch (_) {}
      }
      demos.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      return _json({'demos': demos});
    }

    // GET /api/apps/demo/:id — show manifest + widget.js content of a demo app
    if (sub.length == 2 && sub[0] == 'demo' && method == 'GET') {
      final id = sub[1];
      final appsDir = '${Platform.environment['HOME']}/.config/yoloit/apps';
      final appDir = Directory('$appsDir/$id');
      if (!await appDir.exists()) {
        return _error(
          'Demo app "$id" not found. Run app:demo to list available apps.',
        );
      }
      final manifestFile = File('${appDir.path}/manifest.json');
      final widgetFile = File('${appDir.path}/widget.js');
      final manifestContent =
          await manifestFile.exists()
              ? await manifestFile.readAsString()
              : null;
      final widgetContent =
          await widgetFile.exists() ? await widgetFile.readAsString() : null;
      Map<String, dynamic> manifest = {};
      try {
        if (manifestContent != null)
          manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
      } catch (_) {}
      return _json({
        'id': id,
        'path': appDir.path,
        'manifest': manifest,
        'manifestRaw': manifestContent,
        'widgetJs': widgetContent,
      });
    }

    // POST /api/apps/install-zip { zipPath: "..." }
    if (sub.length == 1 && sub[0] == 'install-zip' && method == 'POST') {
      final body = await _body(request);
      final zipPath = body['zipPath'] as String?;
      if (zipPath == null || zipPath.trim().isEmpty) {
        return _error('Missing "zipPath" field');
      }
      final zipFile = File(zipPath.trim());
      if (!await zipFile.exists()) {
        return _error('ZIP file not found: $zipPath');
      }
      try {
        final zipName = zipFile.path.split(Platform.pathSeparator).last;
        final appNameFromZip =
            zipName.endsWith('.zip')
                ? zipName.substring(0, zipName.length - 4)
                : zipName;
        final appsDir = Directory(
          '${Platform.environment['HOME']}/.config/yoloit/apps',
        );
        await appsDir.create(recursive: true);
        final extractDir = Directory(
          '${appsDir.path}${Platform.pathSeparator}__zip_extract_${DateTime.now().millisecondsSinceEpoch}',
        );
        await extractDir.create();
        final unzipResult = await Process.run('unzip', [
          '-q',
          zipFile.path,
          '-d',
          extractDir.path,
        ]);
        if (unzipResult.exitCode != 0) {
          await extractDir.delete(recursive: true);
          return _error('Failed to extract ZIP: ${unzipResult.stderr}');
        }
        // Find the directory containing widget.js or manifest.json
        Directory? appSource;
        await for (final entity in extractDir.list(recursive: true)) {
          if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last;
            if (name == 'widget.js' || name == 'manifest.json') {
              appSource = entity.parent;
              break;
            }
          }
        }
        appSource ??= extractDir;
        // Determine app name from manifest or zip filename
        String appName = appNameFromZip;
        final manifestFile = File(
          '${appSource.path}${Platform.pathSeparator}manifest.json',
        );
        if (await manifestFile.exists()) {
          try {
            final raw =
                jsonDecode(await manifestFile.readAsString())
                    as Map<String, dynamic>;
            appName = (raw['id'] as String?)?.trim() ?? appNameFromZip;
          } catch (_) {}
        }
        final destDir = Directory(
          '${appsDir.path}${Platform.pathSeparator}$appName',
        );
        if (await destDir.exists()) await destDir.delete(recursive: true);
        await Process.run('cp', ['-r', appSource.path, destDir.path]);
        await extractDir.delete(recursive: true);
        final manifest = await registry.find(appName);
        await registry.loadAll(); // refresh registry cache
        return _json({
          'ok': true,
          'appName': appName,
          'widget': manifest?.toJson(),
        });
      } catch (e) {
        return _error('ZIP install failed: $e');
      }
    }

    // /api/apps/:id/...
    if (sub.length >= 2) {
      final id = sub[0];
      final action = sub[1];

      // GET /api/apps/:id/snapshot — return current UI tree JSON
      if (action == 'snapshot' && method == 'GET') {
        final tree = appRegistry.tree(id);
        if (tree == null) {
          return _json({
            'ok': false,
            'message':
                'No render tree available for widget "$id". Is it running?',
          });
        }
        return _json({'ok': true, 'widgetId': id, 'tree': tree});
      }

      // POST /api/apps/:id/execute — call JS event
      if (action == 'execute' && method == 'POST') {
        final body = await _body(request);
        final actionId = body['action'] as String?;
        if (actionId == null || actionId.isEmpty) {
          return _error('Missing "action" field');
        }
        final engine = appRegistry.engine(id);
        if (engine == null) {
          return _json({
            'ok': false,
            'message': 'Widget "$id" is not currently running',
          });
        }
        final payload = body['payload'] as Map<String, dynamic>?;
        engine.callEvent(actionId, payload);
        return _json({'ok': true, 'widgetId': id, 'action': actionId});
      }

      // GET /api/apps/:id/logs — return console.log buffer
      if (action == 'logs' && method == 'GET') {
        final engine = appRegistry.engine(id);
        if (engine == null) {
          return _json({
            'ok': false,
            'message': 'App "$id" is not currently running',
            'logs': <Map<String, dynamic>>[],
          });
        }
        final logs = engine.peekLogs();
        return _json({'ok': true, 'widgetId': id, 'logs': logs});
      }

      // POST /api/apps/:id/reload — hot-reload widget JS without restarting the app
      if (action == 'reload' && method == 'POST') {
        final ok = await appRegistry.triggerReload(id);
        if (!ok) {
          return _json({
            'ok': false,
            'message': 'Widget "$id" is not currently running',
          });
        }
        return _json({
          'ok': true,
          'widgetId': id,
          'message': 'Widget reloaded',
        });
      }

      // POST /api/apps/:id/screenshot
      if (action == 'screenshot' && method == 'POST') {
        // TODO: implement full screenshot once BoardScreenshotService.capturePanel(panelId) is wired to widgetId lookup
        return _json({
          'ok': false,
          'message':
              'Widget screenshot requires the panel to be visible on screen. Use app:snapshot for the render tree.',
        });
      }
    }

    return _notFound('Unknown app route');
  }
}
