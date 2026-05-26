import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// CLI handler for Chat panels (`board.chat`).
class ChatCliHandler extends PanelCliHandler {
  ChatCliHandler({ChatSessionManager? sessionManager})
    : _sessionManager = sessionManager ?? ChatSessionManager.instance;

  final ChatSessionManager _sessionManager;

  @override
  String get typeId => 'board.chat';

  @override
  List<String> get supportedActions => [
    'send',
    'messages',
    'config',
    'clear',
    'status',
    'stop',
    'sessions',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final session = _sessionManager.get(panel.id);
    if (session != null) {
      final messages = session.messages;
      return {
        'config': session.config.toJson(),
        'messageCount': messages.length,
        'isProcessing': session.isProcessing,
        'messages':
            messages.map((m) {
              return {
                'role': m.role.name,
                'content': _truncate(m.content, 200),
                if (m.toolCalls.isNotEmpty)
                  'toolCalls': m.toolCalls.map((t) => t.toJson()).toList(),
                if (m.attachments.isNotEmpty) 'attachments': m.attachments,
              };
            }).toList(),
      };
    }

    final messages = panel.state['messages'] as List<dynamic>? ?? [];
    return {
      'config': panel.state['config'] ?? const <String, dynamic>{},
      'messageCount': messages.length,
      'isProcessing': false,
      'messages':
          messages.map((m) {
            final msg = m as Map<String, dynamic>;
            return {
              'role': msg['role'] ?? 'unknown',
              'content': _truncate(msg['content'] as String? ?? '', 200),
              if (msg['toolCalls'] != null) 'toolCalls': msg['toolCalls'],
              if (msg['attachments'] != null) 'attachments': msg['attachments'],
            };
          }).toList(),
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'send':
        return _handleSend(args, panel);
      case 'messages':
        return _handleMessages(args, panel);
      case 'config':
        return _handleConfig(args, panel);
      case 'clear':
        return _handleClear(panel);
      case 'status':
        return _handleStatus(panel);
      case 'stop':
        return _handleStop(panel);
      case 'sessions':
        return _handleSessions();
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  Future<CliActionResult> _handleSend(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final text = args['text'] as String? ?? args['message'] as String?;
    if (text == null || text.isEmpty) {
      return const CliActionResult(ok: false, message: 'Missing "text" field');
    }

    final mergedConfig = _mergeConfig(panel, args);
    final config = ChatSessionConfig.fromJson(mergedConfig);
    final session = _sessionManager.getOrCreate(panel.id, config);

    if (session.messages.isEmpty) {
      final savedConfig =
          panel.state['config'] is Map
              ? Map<String, dynamic>.from(panel.state['config'] as Map)
              : const <String, dynamic>{};
      final savedMessages = panel.state['messages'] as List<dynamic>?;
      if (savedMessages != null && savedMessages.isNotEmpty) {
        session.restoreMessages(savedMessages.cast<Map<String, dynamic>>());
      }
      session.restoreLastUsage(
        panel.state['lastUsage'] is Map
            ? Map<String, dynamic>.from(panel.state['lastUsage'] as Map)
            : null,
      );
      session.restoreOpencodeSessionId(
        (panel.state['opencodeSessionId'] as String?) ??
            (savedConfig['opencodeSessionId'] as String?),
      );
      session.restoreCopilotSessionId(
        (panel.state['copilotSessionId'] as String?) ??
            (savedConfig['copilotSessionId'] as String?),
      );
      session.restoreCursorSessionId(
        (panel.state['cursorSessionId'] as String?) ??
            (savedConfig['cursorSessionId'] as String?),
      );
    }

    final attachments =
        (args['attachments'] as List<dynamic>?)?.cast<String>() ?? [];

    // Always fire-and-forget — the CLI server never blocks on LLM completion.
    // Use yolochat:messages or yolochat:status to poll for results.
    final accepted = session.sendMessage(
      text: text,
      attachments: attachments,
      runtimeContext: ChatRuntimeContext(
        boardId: args['_boardId'] as String?,
        boardName: args['_boardName'] as String?,
        panelId: panel.id,
        panelTitle: panel.title,
        panelType: args['_panelType'] as String?,
        availableBoardsSummary: args['_availableBoardsSummary'] as String?,
        currentBoardPanelsSummary:
            args['_currentBoardPanelsSummary'] as String?,
      ),
    );

    if (!accepted) {
      return CliActionResult(
        ok: false,
        message:
            'Already processing a previous message — wait or call yolochat:stop first',
      );
    }

    // Persist config so the panel remembers provider/model on next open.
    return CliActionResult(
      data: {
        'status': 'processing',
        'totalMessages': session.messages.length,
        'panelId': panel.id,
        'NEXT':
            'Use yolochat:messages to read the response when ready, '
            'or yolochat:status to check progress.',
      },
      stateUpdate: {'config': mergedConfig, 'configured': true},
    );
  }

  CliActionResult _handleMessages(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final session = _sessionManager.get(panel.id);
    if (session != null) {
      final msgs = session.messages;
      final limit = args['limit'] as int? ?? msgs.length;
      final filtered =
          msgs.length > limit ? msgs.sublist(msgs.length - limit) : msgs;
      return CliActionResult(
        data: {
          'total': msgs.length,
          'messages': filtered.map((m) => m.toJson()).toList(),
        },
      );
    }

    final msgs = panel.state['messages'] as List<dynamic>? ?? [];
    final limit = args['limit'] as int? ?? msgs.length;
    final filtered =
        msgs.length > limit ? msgs.sublist(msgs.length - limit) : msgs;
    return CliActionResult(data: {'total': msgs.length, 'messages': filtered});
  }

  CliActionResult _handleConfig(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final configPatch = _extractConfigPatch(args);
    if (configPatch.isNotEmpty) {
      final merged = _mergeConfig(panel, args);
      final session = _sessionManager.get(panel.id);
      if (session != null) {
        session.updateConfig(ChatSessionConfig.fromJson(merged));
      }

      return CliActionResult(
        message: 'Chat config updated',
        data: {'config': merged},
        stateUpdate: {'config': merged, 'configured': true},
      );
    }

    final session = _sessionManager.get(panel.id);
    final config =
        session?.config.toJson() ??
        panel.state['config'] ??
        const <String, dynamic>{};
    return CliActionResult(data: {'config': config});
  }

  CliActionResult _handleClear(BoardPanelInstance panel) {
    final session = _sessionManager.get(panel.id);
    session?.clearMessages();
    return CliActionResult(
      message: 'Chat cleared',
      stateUpdate: session?.serializeState() ?? {'messages': <dynamic>[]},
    );
  }

  CliActionResult _handleStatus(BoardPanelInstance panel) {
    final session = _sessionManager.get(panel.id);
    if (session == null) {
      return const CliActionResult(
        data: {'hasSession': false, 'isProcessing': false},
      );
    }
    return CliActionResult(
      data: {
        'hasSession': true,
        'isProcessing': session.isProcessing,
        'messageCount': session.messages.length,
        'provider': session.config.provider,
        'model': session.config.model,
        'streamingContent':
            session.streamingContent.isNotEmpty
                ? _truncate(session.streamingContent, 500)
                : null,
      },
    );
  }

  Future<CliActionResult> _handleStop(BoardPanelInstance panel) async {
    final session = ChatSessionManager.instance.get(panel.id);
    if (session == null || !session.isProcessing) {
      return const CliActionResult(message: 'No active stream to stop');
    }
    await session.stopStreaming();
    return CliActionResult(
      message: 'Streaming stopped',
      stateUpdate: session.serializeState(),
    );
  }

  CliActionResult _handleSessions() {
    final ids = _sessionManager.activeSessionIds;
    final sessions = <Map<String, dynamic>>[];
    for (final id in ids) {
      final session = _sessionManager.get(id);
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
    return CliActionResult(data: {'sessions': sessions});
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  Map<String, dynamic> _mergeConfig(
    BoardPanelInstance panel,
    Map<String, dynamic> args,
  ) {
    final session = ChatSessionManager.instance.get(panel.id);
    final current =
        session != null
            ? session.config.toJson()
            : Map<String, dynamic>.from(
              panel.state['config'] as Map? ?? const {},
            );
    final patch = _extractConfigPatch(args);
    final merged = <String, dynamic>{...current, ...patch};
    final provider = merged['provider'];
    if (provider is String) {
      merged['provider'] = _normalizeProviderValue(provider);
    }
    return merged;
  }

  Map<String, dynamic> _extractConfigPatch(Map<String, dynamic> args) {
    final patch = <String, dynamic>{};
    if (args['config'] is Map) {
      patch.addAll(Map<String, dynamic>.from(args['config'] as Map));
    }
    const knownKeys = {
      'sessionName',
      'workingDir',
      'provider',
      'model',
      'reasoningEffort',
      'autopilot',
      'mode',
      'maxAutopilotContinues',
      'customArgs',
      'envGroupIds',
    };
    for (final key in knownKeys) {
      if (args.containsKey(key)) patch[key] = args[key];
    }
    final provider = patch['provider'];
    if (provider is String) {
      patch['provider'] = _normalizeProviderValue(provider);
    }
    return patch;
  }

  String _normalizeProviderValue(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('cloud:')) return value;
    if (value.startsWith('cloud-')) return 'cloud:$value';
    if (value == 'copilot' ||
        value == 'cursor' ||
        value == 'local' ||
        value == 'opencode') {
      return value;
    }
    return value;
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'send': const CliActionHelp(
      description:
          'Send a message to the chat — non-blocking, returns immediately. '
          'Use yolochat:messages to read the response when ready.',
      params: {
        'text': 'Message text (required)',
        'attachments': 'Optional file paths',
        'config': 'Optional config override map for this panel/session',
        'provider': 'Shortcut for config.provider',
        'model': 'Shortcut for config.model',
        'sessionName': 'Shortcut for config.sessionName',
        'workingDir': 'Shortcut for config.workingDir',
      },
    ),
    'messages': const CliActionHelp(
      description: 'Get chat messages',
      params: {'limit': 'Max messages to return'},
    ),
    'config': const CliActionHelp(
      description: 'Get or update chat configuration (provider, model, etc.)',
      params: {
        'config': 'Config map to merge',
        'provider': 'Shortcut for config.provider',
        'model': 'Shortcut for config.model',
        'sessionName': 'Shortcut for config.sessionName',
        'workingDir': 'Shortcut for config.workingDir',
      },
    ),
    'clear': const CliActionHelp(description: 'Clear all chat messages'),
    'status': const CliActionHelp(
      description: 'Get current session status (processing, messages, etc.)',
    ),
    'stop': const CliActionHelp(description: 'Stop any active streaming'),
    'sessions': const CliActionHelp(
      description: 'List all active chat sessions across panels',
    ),
  };
}
