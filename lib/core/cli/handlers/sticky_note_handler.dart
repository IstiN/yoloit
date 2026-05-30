import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class StickyNoteCliHandler extends PanelCliHandler {
  const StickyNoteCliHandler();

  @override
  String get typeId => 'board.sticky';

  @override
  List<String> get supportedActions => ['get', 'set', 'append', 'color'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'text': panel.state['text'] ?? '',
    'color': panel.state['color'] ?? '#FEF08A',
    'textColor': panel.state['textColor'] ?? '#1F2937',
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(data: getContent(panel));
      case 'set':
        final text = args['text'] as String?;
        if (text == null) {
          return const CliActionResult(ok: false, message: 'Missing "text"');
        }
        return CliActionResult(
          message: 'Sticky note updated',
          stateUpdate: {'text': text},
        );
      case 'append':
        final text = args['text'] as String?;
        if (text == null) {
          return const CliActionResult(ok: false, message: 'Missing "text"');
        }
        final current = panel.state['text'] as String? ?? '';
        final next = current.trim().isEmpty ? text : '$current\n$text';
        return CliActionResult(
          message: 'Text appended',
          stateUpdate: {'text': next},
        );
      case 'color':
        final color = args['color'] as String? ?? args['fillColor'] as String?;
        final textColor = args['textColor'] as String?;
        if (color == null && textColor == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "color" or "textColor"',
          );
        }
        return CliActionResult(
          message: 'Sticky note colors updated',
          stateUpdate: {
            if (color != null) 'color': color,
            if (textColor != null) 'textColor': textColor,
          },
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(description: 'Read sticky note text and colors'),
    'set': const CliActionHelp(
      description: 'Replace sticky note text',
      params: {'text': 'New sticky note text'},
      example: 'yoloit do "<board>" "<sticky>" set \'{"text":"Idea"}\'',
    ),
    'append': const CliActionHelp(
      description: 'Append a new line to sticky note text',
      params: {'text': 'Text to append'},
    ),
    'color': const CliActionHelp(
      description: 'Set sticky note background and optional text color',
      params: {
        'color': 'Background color as #RRGGBB',
        'textColor': 'Text color as #RRGGBB',
      },
    ),
  };
}
