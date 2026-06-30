import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> uiTools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'ui:create',
    alias: 'uicrt',
    description:
        'Create a declarative UI View panel (board.ui) for JSON-driven layouts',
    group: 'ui',
    humanVariants: const {
      'ru': [
        'создай ui view {title}',
        'создай ui панель {title}',
        'добавь карточку ui {title}',
        'нарисуй ui {title}',
      ],
      'en': [
        'create ui view {title}',
        'create ui panel {title}',
        'add ui card {title}',
        'draw custom ui {title}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('title', 'Panel title', required: true, shortKey: 't'),
    ],
  ),

  YoloitCliTool(
    command: 'ui:render',
    alias: 'uirnd',
    description:
        'Render declarative JSON UI on a board.ui panel (auto-creates panel if none). '
        'SVG inside a card: {"type":"svg","data":"<svg>...</svg>"} or {"type":"svg","path":"M..."} — '
        'NOT draw:svg (that draws on the board canvas). '
        'Buttons: {"type":"button","data":"Label","onTap":"actionId"}. '
        'textField id → yoloit.get("id"). Scripts: ui:set-scripts. Full JS apps: app:run.',
    group: 'ui',
    humanVariants: const {
      'ru': [
        'нарисуй ui',
        'покажи карточку',
        'обнови ui панель',
        'сделай ui из json',
      ],
      'en': [
        'render ui',
        'show ui card',
        'update ui panel',
        'draw json ui',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'panel',
        'Panel id or title. Omit to use the only/first UI View panel on the board.',
        aliases: const <String>['panel_id', 'panel_title', 'id'],
        shortKey: 'p',
      ),
      toolParam(
        'tree',
        'Root JSON node object (type, children, text, …). Pass as object, not a string.',
        required: true,
        shortKey: 'j',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'ui:get',
    alias: 'uiget',
    description:
        'Read JSON tree, resolvedTree, storage, scripts, and text lines',
    group: 'ui',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'ui:set-state',
    alias: 'uist',
    description:
        'Merge storage for {{bindings}} in UI labels. Example: {"taps":3,"message":"Hi"}',
    group: 'ui',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('state', 'JSON object to merge into _storage', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'ui:set-scripts',
    alias: 'uisc',
    description:
        'Set onTap JS handlers map. Example: {"bump":"yoloit.inc(\\"taps\\");"}',
    group: 'ui',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('scripts', 'JSON map actionId→JavaScript', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'ui:edit',
    alias: 'uiedt',
    description:
        'Focus a UI View panel only — user must open the JSON editor from the panel menu manually',
    group: 'ui',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),
];
