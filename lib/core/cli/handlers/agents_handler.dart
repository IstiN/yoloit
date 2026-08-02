import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/chat/chat_session_naming.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

Future<shelf.Response> handleAgents(
  String method,
  List<String> sub,
  shelf.Request request, {
  required BoardCubit? cubit,
  required TerminalCubit? terminalCubit,
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  required void Function() scheduleRebuild,
  required BoardPanelBounds Function(
    BoardDocument board, {
    required double preferredWidth,
    required double preferredHeight,
  })
  nextAvailableBoundsFor,
  AgentConfigService? agentConfigService,
  ChatSessionManager? chatSessionManager,
}) {
  final handler = _AgentsRouteHandler(
    method: method,
    sub: sub,
    request: request,
    cubit: cubit,
    terminalCubit: terminalCubit,
    body: body,
    json: json,
    error: error,
    notFound: notFound,
    scheduleRebuild: scheduleRebuild,
    nextAvailableBoundsFor: nextAvailableBoundsFor,
    service: agentConfigService ?? AgentConfigService.instance,
    sessionManager: chatSessionManager ?? ChatSessionManager.instance,
  );
  return handler.dispatch();
}

class _AgentsRouteHandler {
  const _AgentsRouteHandler({
    required this.method,
    required this.sub,
    required this.request,
    required this.cubit,
    required this.terminalCubit,
    required this.body,
    required this.json,
    required this.error,
    required this.notFound,
    required this.scheduleRebuild,
    required this.nextAvailableBoundsFor,
    required this.service,
    required this.sessionManager,
  });

  final String method;
  final List<String> sub;
  final shelf.Request request;
  final BoardCubit? cubit;
  final TerminalCubit? terminalCubit;
  final Future<Map<String, dynamic>> Function(shelf.Request) body;
  final shelf.Response Function(Object) json;
  final shelf.Response Function(String) error;
  final shelf.Response Function(String) notFound;
  final void Function() scheduleRebuild;
  final BoardPanelBounds Function(
    BoardDocument board, {
    required double preferredWidth,
    required double preferredHeight,
  })
  nextAvailableBoundsFor;
  final AgentConfigService service;
  final ChatSessionManager sessionManager;

  Future<shelf.Response> dispatch() async {
    final tc = terminalCubit;
    if (tc == null) return error('Terminal cubit not available');

    final routes = <(bool Function(), Future<shelf.Response> Function())>[
      (
        () =>
            (sub.isEmpty || (sub.length == 1 && sub[0] == 'list')) &&
            method == 'GET',
        () => _listAgents(tc),
      ),
      (
        () => sub.length == 1 && sub[0] == 'default' && method == 'POST',
        _setDefaultAgent,
      ),
      (
        () => sub.length == 1 && sub[0] == 'run' && method == 'POST',
        _runAgent,
      ),
      (
        () => sub.length == 1 && sub[0] == 'config' && method == 'POST',
        _updateAgentConfig,
      ),
    ];
    for (final (matches, run) in routes) {
      if (matches()) return run();
    }
    return notFound('Unknown agents route');
  }

  Future<shelf.Response> _listAgents(TerminalCubit tc) async {
    final configs = await service.load();
    final defaultId =
        service.defaultAgentId ?? AgentType.copilot.name;
    final state = tc.state;
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
    return json({
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

  Future<shelf.Response> _setDefaultAgent() async {
    final requestBody = await body(request);
    final id = requestBody['id'] as String?;
    if (id != null &&
        AgentType.values.every((type) => type.name != id) &&
        id.isNotEmpty) {
      return error('Unknown agent id: $id');
    }
    await service.setDefaultAgentId(id);
    return json({
      'ok': true,
      'defaultAgentId': id ?? AgentType.copilot.name,
    });
  }

  Future<shelf.Response> _runAgent() async {
    final requestBody = await body(request);
    final agentId =
        (requestBody['agent'] as String?) ??
        (requestBody['id'] as String?) ??
        service.defaultAgentType.name;
    final workspacePath =
        (requestBody['path'] as String?) ??
        (requestBody['workspacePath'] as String?) ??
        Directory.current.path;
    final task = requestBody['task'] as String?;
    final rawName = (requestBody['name'] as String?)?.trim();
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
    final configs = await service.load();
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
    final boardCubit = cubit;
    if (boardCubit == null) return error('Board cubit not available');
    final board = boardCubit.state.activeBoard ?? boardCubit.state.boards.firstOrNull;
    if (board == null) return error('No active board');
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
    final bounds = nextAvailableBoundsFor(
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
    await boardCubit.addPanel(panel, boardId: board.id);
    if (boardCubit.state.activeBoardId != board.id) {
      await boardCubit.setActiveBoard(board.id);
    }
    await boardCubit.focusPanel(panel.id, boardId: board.id);
    scheduleRebuild();

    // Send initial task directly via ChatSessionManager — no UI dependency.
    // When the panel widget mounts it picks up this existing session.
    var taskSent = false;
    if (trimmedTask != null && trimmedTask.isNotEmpty) {
      final session = sessionManager.getOrCreate(
        panelId,
        config,
      );
      taskSent = await session.sendMessage(text: trimmedTask);
    }

    return json({
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
  Future<shelf.Response> _updateAgentConfig() async {
    final requestBody = await body(request);
    final agentId = requestBody['id'] as String?;
    if (agentId == null || agentId.isEmpty) {
      return error('Missing required field: id');
    }
    final configs = await service.load();
    final idx = configs.indexWhere((c) => c.id == agentId);
    if (idx < 0) return error('Unknown agent id: $agentId');

    var config = configs[idx];
    if (requestBody.containsKey('defaultModel')) {
      config = config.copyWith(
        defaultModel:
            (requestBody['defaultModel'] as String?)?.trim().isEmpty == true
                ? null
                : requestBody['defaultModel'] as String?,
      );
    }
    if (requestBody.containsKey('asrMode')) {
      final mode = requestBody['asrMode'] as String?;
      if (mode != null &&
          mode != 'default' &&
          mode != 'local' &&
          mode != 'cloud') {
        return error('asrMode must be "default", "local", or "cloud"');
      }
      config = config.copyWith(asrMode: mode ?? 'default');
    }
    if (requestBody.containsKey('asrCloudConfigId')) {
      config = config.copyWith(
        asrCloudConfigId:
            (requestBody['asrCloudConfigId'] as String?)?.trim().isEmpty == true
                ? null
                : requestBody['asrCloudConfigId'] as String?,
      );
    }
    if (requestBody.containsKey('asrCloudModel')) {
      config = config.copyWith(
        asrCloudModel:
            (requestBody['asrCloudModel'] as String?)?.trim().isEmpty == true
                ? null
                : requestBody['asrCloudModel'] as String?,
      );
    }
    configs[idx] = config;
    await service.save(configs);
    return json({
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
}
