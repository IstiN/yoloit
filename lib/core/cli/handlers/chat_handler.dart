import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Chat panels (`board.chat`).
class ChatCliHandler extends PanelCliHandler {
  const ChatCliHandler();

  @override
  String get typeId => 'board.chat';

  @override
  List<String> get supportedActions => ['send', 'messages', 'config', 'clear'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final messages = panel.state['messages'] as List<dynamic>? ?? [];
    return {
      'config': panel.state['config'] ?? const <String, dynamic>{},
      'messageCount': messages.length,
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
        final text = args['text'] as String? ?? args['message'] as String?;
        if (text == null || text.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "text" field',
          );
        }
        final mergedConfig = _mergeConfig(panel, args);
        final attachments = args['attachments'] as List<dynamic>? ?? [];
        final messages = List<Map<String, dynamic>>.from(
          (panel.state['messages'] as List<dynamic>?) ?? [],
        );
        messages.add({
          'id': 'cli-${DateTime.now().millisecondsSinceEpoch}',
          'role': 'user',
          'content': text,
          if (attachments.isNotEmpty) 'attachments': attachments,
          'timestamp': DateTime.now().toIso8601String(),
        });
        return CliActionResult(
          message: 'Message queued for sending',
          stateUpdate: {
            'config': mergedConfig,
            'configured': true,
            'messages': messages,
            '_cliPendingMessage': text,
            if (attachments.isNotEmpty) '_cliPendingAttachments': attachments,
          },
        );
      case 'messages':
        final msgs = panel.state['messages'] as List<dynamic>? ?? [];
        final limit = args['limit'] as int? ?? msgs.length;
        final filtered =
            msgs.length > limit ? msgs.sublist(msgs.length - limit) : msgs;
        return CliActionResult(
          data: {'total': msgs.length, 'messages': filtered},
        );
      case 'config':
        final configPatch = _extractConfigPatch(args);
        if (configPatch.isNotEmpty) {
          final merged = _mergeConfig(panel, args);
          return CliActionResult(
            message: 'Chat config updated',
            data: {'config': merged},
            stateUpdate: {'config': merged, 'configured': true},
          );
        }
        return CliActionResult(
          data: {'config': panel.state['config'] ?? const <String, dynamic>{}},
        );
      case 'clear':
        return CliActionResult(
          message: 'Chat cleared',
          stateUpdate: {'messages': <dynamic>[]},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  Map<String, dynamic> _mergeConfig(
    BoardPanelInstance panel,
    Map<String, dynamic> args,
  ) {
    final current = Map<String, dynamic>.from(
      panel.state['config'] as Map? ?? const {},
    );
    final patch = _extractConfigPatch(args);
    return {...current, ...patch};
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
    return patch;
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'send': const CliActionHelp(
      description: 'Send a message to the chat',
      params: {
        'text': 'Message text',
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
  };
}
