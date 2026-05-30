import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class ShapeCliHandler extends PanelCliHandler {
  const ShapeCliHandler();

  @override
  String get typeId => 'board.shape';

  @override
  List<String> get supportedActions => ['get', 'set'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'shape': panel.state['shape'] ?? 'rectangle',
    'text': panel.state['text'] ?? '',
    'fillColor': panel.state['fillColor'] ?? '#1E293B',
    'strokeColor': panel.state['strokeColor'] ?? '#93C5FD',
    'textColor': panel.state['textColor'] ?? '#E2E8F0',
    'strokeWidth': panel.state['strokeWidth'] ?? 3.0,
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
        final update = <String, dynamic>{};
        for (final key in [
          'shape',
          'text',
          'fillColor',
          'strokeColor',
          'textColor',
          'strokeWidth',
        ]) {
          if (args.containsKey(key)) update[key] = args[key];
        }
        if (update.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing shape fields to update',
          );
        }
        return CliActionResult(message: 'Shape updated', stateUpdate: update);
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(description: 'Read shape/frame panel state'),
    'set': const CliActionHelp(
      description: 'Update shape type, label, fill, stroke, or text color',
      params: {
        'shape': 'rectangle | circle | diamond | triangle | hexagon | frame',
        'text': 'Optional centered label',
        'fillColor': 'Fill color as #RRGGBB',
        'strokeColor': 'Stroke color as #RRGGBB',
        'textColor': 'Text color as #RRGGBB',
        'strokeWidth': 'Stroke width in pixels',
      },
      example:
          'yoloit do "<board>" "<shape>" set \'{"shape":"diamond","text":"Decision"}\'',
    ),
  };
}
