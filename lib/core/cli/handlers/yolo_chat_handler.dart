import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';

Future<shelf.Response> handleYoloChat(
  String method,
  List<String> sub,
  shelf.Request request,
  BoardCubit cubit, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  required void Function() scheduleRebuild,
  required Future<shelf.Response> Function(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  )
  panelAction,
}) async {
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
    return json({'ok': true, 'items': out});
  }

  if (sub.length == 1 && sub[0] == 'send' && method == 'POST') {
    final requestBody = await body(request);
    final text = requestBody['text'] as String? ?? requestBody['message'] as String?;
    if (text == null || text.trim().isEmpty) {
      return error('Missing "text" field');
    }
    final target = _resolveTarget(
      cubit,
      boardHint: requestBody['board'] as String? ?? requestBody['boardId'] as String?,
      panelHint: requestBody['panel'] as String? ?? requestBody['panelId'] as String?,
      type: 'board.chat',
    );
    if (target == null) {
      return error('No board.chat panel found (or target not found)');
    }
    // Inject global cloud provider if no explicit provider specified
    if (!requestBody.containsKey('provider')) {
      final service = CloudLlmSettingsService.instance;
      final providerType = await service.loadAssistantProviderType();
      if (providerType == 'cloud') {
        final activeId = await service.loadActiveConfigId();
        if (activeId != null) {
          requestBody['provider'] = 'cloud:$activeId';
        }
      }
    }
    final actionBody = <String, dynamic>{
      ...requestBody,
      'action': 'send',
      'text': text,
    };
    return panelAction(cubit, target.board, target.panel, actionBody);
  }

  if (sub.length == 1 &&
      (sub[0] == 'terminal' || sub[0] == 'terminal-input') &&
      method == 'POST') {
    final requestBody = await body(request);
    final text = requestBody['text'] as String? ?? requestBody['input'] as String?;
    if (text == null || text.isEmpty) {
      return error('Missing "text" field');
    }
    final appendNewline =
        requestBody['appendNewline'] as bool? ?? requestBody['enter'] as bool? ?? true;
    final explicitSession =
        requestBody['sessionId'] as String? ?? requestBody['session'] as String?;
    var sessionId = explicitSession?.trim() ?? '';
    ({BoardDocument board, BoardPanelInstance panel})? target;

    if (sessionId.isEmpty) {
      target = _resolveTarget(
        cubit,
        boardHint: requestBody['board'] as String? ?? requestBody['boardId'] as String?,
        panelHint: requestBody['panel'] as String? ?? requestBody['panelId'] as String?,
        type: 'board.terminal',
      );
      if (target == null) {
        return error('No board.terminal panel found (or target not found)');
      }
      final config = _terminalConfigForPanel(target.panel);
      if (!config.isConfigured || config.sessionId.trim().isEmpty) {
        return error('Target terminal panel is not configured');
      }
      await BoardTerminalSessionManager.instance.ensureSession(config);
      sessionId = config.sessionId;
    }

    final payload = appendNewline ? '$text\n' : text;
    TerminalBackendService.instance.write(sessionId, payload);
    return json({
      'ok': true,
      'sessionId': sessionId,
      'bytes': payload.length,
      'appendNewline': appendNewline,
      if (target != null)
        'target': {
          'boardId': target.board.id,
          'boardName': target.board.name,
          'panelId': target.panel.id,
          'panelTitle': target.panel.title,
        },
    });
  }

  if (sub.length == 1 && sub[0] == 'messages' && method == 'GET') {
    final boardHint = request.url.queryParameters['board'];
    final panelHint = request.url.queryParameters['panel'];
    final limitRaw = request.url.queryParameters['limit'];
    final target = _resolveTarget(
      cubit,
      boardHint: boardHint,
      panelHint: panelHint,
      type: 'board.chat',
    );
    if (target == null) {
      return error('No board.chat panel found (or target not found)');
    }
    final actionBody = <String, dynamic>{'action': 'messages'};
    final limit = int.tryParse(limitRaw ?? '');
    if (limit != null && limit > 0) {
      actionBody['limit'] = limit;
    }
    return panelAction(cubit, target.board, target.panel, actionBody);
  }

  // POST /yolochat/clear
  if (sub.length == 1 && sub[0] == 'clear' && method == 'POST') {
    final requestBody = await body(request);
    final target = _resolveTarget(
      cubit,
      boardHint: requestBody['board'] as String?,
      panelHint: requestBody['panel'] as String?,
      type: 'board.chat',
    );
    if (target == null) {
      return error('No board.chat panel found (or target not found)');
    }
    return panelAction(cubit, target.board, target.panel, {
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
    return json({'ok': true, 'sessions': sessions});
  }

  if (sub.length == 1 && sub[0] == 'history' && method == 'GET') {
    final entries = await ChatSessionHistory.instance.loadAll();
    return json({
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
    final requestBody = await body(request);
    final sessionId = requestBody['sessionId'] as String? ?? requestBody['id'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      return error('Missing "sessionId" field');
    }
    final entries = await ChatSessionHistory.instance.loadAll();
    final entry = entries.where((item) => item.id == sessionId).firstOrNull;
    if (entry == null) {
      return error('Saved session not found: $sessionId');
    }
    final messages = await ChatSessionHistory.instance.loadMessages(
      sessionId,
    );
    final target = _resolveTarget(
      cubit,
      boardHint: requestBody['board'] as String?,
      panelHint: requestBody['panel'] as String?,
      type: 'board.chat',
    );
    if (target == null) {
      return error('No board.chat panel found (or target not found)');
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
    scheduleRebuild();
    return json({
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
    final target = _chatTarget(cubit, request);
    if (target == null) {
      return error('No board.chat panel found (or target not found)');
    }
    return panelAction(cubit, target.board, target.panel, {
      'action': 'status',
    });
  }

  // POST /yolochat/stop
  if (sub.length == 1 && sub[0] == 'stop' && method == 'POST') {
    final requestBody = await body(request);
    final boardHint = requestBody['board'] as String?;
    final panelHint = requestBody['panel'] as String?;
    final hasExplicitTarget =
        (boardHint?.trim().isNotEmpty ?? false) ||
        (panelHint?.trim().isNotEmpty ?? false);

    if (!hasExplicitTarget) {
      final stopped = await _stopAllActiveYoloChats();
      if (stopped > 0) {
        return json({
          'ok': true,
          'message': 'Stopped $stopped active chat stream(s)',
          'stopped': stopped,
        });
      }
    }

    final target = _resolveTarget(
      cubit,
      boardHint: boardHint,
      panelHint: panelHint,
      type: 'board.chat',
    );
    if (target == null) {
      return error(
        hasExplicitTarget
            ? 'No board.chat panel found (or target not found)'
            : 'No active chat stream to stop',
      );
    }
    return panelAction(cubit, target.board, target.panel, {
      'action': 'stop',
    });
  }

  // GET /yolochat/logs — full session log for debugging (copy-paste friendly)
  if (sub.length == 1 && sub[0] == 'logs' && method == 'GET') {
    final target = _chatTarget(cubit, request);
    if (target == null) {
      return error('No board.chat panel found (or target not found)');
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

  return notFound('Unknown yolochat route');
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

({BoardDocument board, BoardPanelInstance panel})? _chatTarget(
  BoardCubit cubit,
  shelf.Request request,
) => _resolveTarget(
  cubit,
  boardHint: request.url.queryParameters['board'],
  panelHint: request.url.queryParameters['panel'],
  type: 'board.chat',
);

({BoardDocument board, BoardPanelInstance panel})? _resolveTarget(
  BoardCubit cubit, {
  String? boardHint,
  String? panelHint,
  required String type,
}) {
  BoardDocument? board;
  if (boardHint != null && boardHint.trim().isNotEmpty) {
    board = findBoard(cubit, boardHint);
  } else {
    board = cubit.state.activeBoard ?? cubit.state.boards.firstOrNull;
  }
  if (board == null) return null;

  BoardPanelInstance? panel;
  if (panelHint != null && panelHint.trim().isNotEmpty) {
    panel = findPanel(board, panelHint);
    if (panel?.type != type) return null;
  } else {
    panel = board.panels.where((p) => p.type == type).firstOrNull;
  }
  if (panel == null) return null;
  return (board: board, panel: panel);
}

BoardTerminalConfig _terminalConfigForPanel(BoardPanelInstance panel) {
  final raw = panel.state['config'];
  if (raw is Map) {
    return BoardTerminalConfig.fromJson(Map<String, dynamic>.from(raw));
  }
  return const BoardTerminalConfig(
    sessionId: '',
    sessionName: '',
    workingDir: '',
  );
}
