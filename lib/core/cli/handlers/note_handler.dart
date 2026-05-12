import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Markdown Note panels (`board.note.markdown`).
class NoteCliHandler extends PanelCliHandler {
  const NoteCliHandler();

  @override
  String get typeId => 'board.note.markdown';

  @override
  List<String> get supportedActions => ['set', 'get', 'append', 'wrap', 'nowrap'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'markdown': panel.state['markdown'] ?? '',
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(
          data: {'markdown': panel.state['markdown'] ?? ''},
        );
      case 'set':
        final text = args['text'] as String? ?? args['markdown'] as String?;
        if (text == null) {
          return const CliActionResult(ok: false, message: 'Missing "text" or "markdown" field');
        }
        return CliActionResult(
          message: 'Note updated',
          stateUpdate: {'markdown': text},
        );
      case 'append':
        final text = args['text'] as String?;
        if (text == null) {
          return const CliActionResult(ok: false, message: 'Missing "text" field');
        }
        final current = panel.state['markdown'] as String? ?? '';
        return CliActionResult(
          message: 'Text appended',
          stateUpdate: {'markdown': '$current\n$text'},
        );
      case 'wrap':
        return CliActionResult(
          message: 'Auto-height enabled — panel will resize to fit content',
          stateUpdate: {'autoHeight': true},
        );
      case 'nowrap':
        return CliActionResult(
          message: 'Auto-height disabled — panel has fixed height',
          stateUpdate: {'autoHeight': false},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(description: 'Get note markdown content'),
    'set': const CliActionHelp(
      description: 'Set note content',
      params: {'text': 'Markdown text to set'},
      example: 'yoloit board <id> panel <id> action --action set --text "# Hello"',
    ),
    'append': const CliActionHelp(
      description: 'Append text to note',
      params: {'text': 'Text to append'},
    ),
  };
}
