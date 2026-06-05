import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/core/cli/panel_getset_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class ShapeCliHandler extends PanelCliHandler with PanelGetSetCliHandler {
  const ShapeCliHandler();

  @override
  String get typeId => 'board.shape';

  @override
  List<String> get supportedActions => ['get', 'set'];

  @override
  List<String> get settableKeys => [
    'shape',
    'text',
    'fillColor',
    'strokeColor',
    'textColor',
    'strokeWidth',
    'textHAlign',
    'textVAlign',
    'textOrientation',
  ];

  @override
  String get settableName => 'Shape';

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'shape': panel.state['shape'] ?? 'rectangle',
    'text': panel.state['text'] ?? '',
    'fillColor': panel.state['fillColor'] ?? '#00000000',
    'strokeColor': panel.state['strokeColor'] ?? '#93C5FD',
    'textColor': panel.state['textColor'] ?? '#E2E8F0',
    'strokeWidth': panel.state['strokeWidth'] ?? 3.0,
    'textHAlign': panel.state['textHAlign'] ?? 'center',
    'textVAlign': panel.state['textVAlign'] ?? 'center',
    'textOrientation': panel.state['textOrientation'] ?? 'horizontal',
  };

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
        'textHAlign': 'left | center | right',
        'textVAlign': 'top | center | bottom',
        'textOrientation': 'horizontal | vertical',
      },
      example:
          'yoloit do "<board>" "<shape>" set \'{"shape":"diamond","text":"Decision","textHAlign":"left"}\'',
    ),
  };
}
