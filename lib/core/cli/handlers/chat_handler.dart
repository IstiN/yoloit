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
      'config': panel.state['config'] ?? {},
      'messageCount': messages.length,
      'messages': messages.map((m) {
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
          return const CliActionResult(ok: false, message: 'Missing "text" field');
        }
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
            'messages': messages,
            '_cliPendingMessage': text,
            if (attachments.isNotEmpty)
              '_cliPendingAttachments': attachments,
          },
        );
      case 'messages':
        final msgs = panel.state['messages'] as List<dynamic>? ?? [];
        final limit = args['limit'] as int? ?? msgs.length;
        final filtered = msgs.length > limit
            ? msgs.sublist(msgs.length - limit)
            : msgs;
        return CliActionResult(
          data: {
            'total': msgs.length,
            'messages': filtered,
          },
        );
      case 'config':
        return CliActionResult(
          data: {'config': panel.state['config'] ?? {}},
        );
      case 'clear':
        return CliActionResult(
          message: 'Chat cleared',
          stateUpdate: {'messages': []},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'send': const CliActionHelp(
      description: 'Send a message to the chat',
      params: {'text': 'Message text', 'attachments': 'Optional file paths'},
    ),
    'messages': const CliActionHelp(
      description: 'Get chat messages',
      params: {'limit': 'Max messages to return'},
    ),
    'config': const CliActionHelp(
      description: 'Get chat configuration (provider, model, etc.)',
    ),
    'clear': const CliActionHelp(description: 'Clear all chat messages'),
  };
}
