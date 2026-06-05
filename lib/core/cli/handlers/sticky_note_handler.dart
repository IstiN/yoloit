import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/core/cli/panel_getset_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class StickyNoteCliHandler extends PanelCliHandler with PanelGetSetCliHandler {
  const StickyNoteCliHandler();

  @override
  String get typeId => 'board.sticky';

  @override
  List<String> get supportedActions => ['get', 'set', 'append', 'color'];

  @override
  List<String> get settableKeys => ['text', 'color', 'textColor', 'fontSize'];

  @override
  String get settableName => 'Sticky note';

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'text': panel.state['text'] ?? '',
    'color': panel.state['color'] ?? '#FEF08A',
    'textColor': panel.state['textColor'] ?? '#1F2937',
    'fontSize': panel.state['fontSize'] ?? 18.0,
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
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
            if (args['fontSize'] != null) 'fontSize': args['fontSize'],
          },
        );
      default:
        return super.handleAction(action, args, panel);
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(description: 'Read sticky note text and colors'),
    'set': const CliActionHelp(
      description: 'Update sticky note text, colors, or text size',
      params: {
        'text': 'New sticky note text',
        'color': 'Background color as #RRGGBB',
        'textColor': 'Text color as #RRGGBB',
        'fontSize': 'Text size in pixels',
      },
      example:
          'yoloit do "<board>" "<sticky>" set \'{"text":"Idea","color":"#FEF08A","fontSize":22}\'',
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
        'fontSize': 'Text size in pixels',
      },
    ),
  };
}
