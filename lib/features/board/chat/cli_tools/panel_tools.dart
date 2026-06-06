import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> panelTools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'panels',
    alias: 'pls',
    description: 'List panels on a board',
    group: 'panel',
    humanVariants: const {
      'ru': [
        'покажи панели',
        'список панелей',
        'что на борде',
        'какие панели есть',
      ],
      'en': [
        'show panels',
        'list panels',
        'what panels are there',
        'what is on the board',
      ],
    },
    params: <YoloitCliToolParam>[boardParam()],
  ),

  YoloitCliTool(
    command: 'panel:help',
    alias: 'phx',
    description: 'Show dynamic panel actions',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'panel:create',
    alias: 'pmk',
    description:
        'Create a panel. Always include the exact panel type id in `type`. '
        'If unsure, call `panel:types` first. '
        'For file trees/folder browser use type `board.filetree` (or `filetree:create`).',
    group: 'panel',
    humanVariants: const {
      'ru': [
        'создай панель {title}',
        'добавь панель {title}',
        'новая панель {title}',
      ],
      'en': ['create panel {title}', 'add panel {title}', 'new panel {title}'],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelTypeParam(),
      toolParam('title', 'Panel title', required: true, shortKey: 't'),
    ],
  ),

  YoloitCliTool(
    command: 'panel:rename',
    alias: 'prn',
    description: 'Rename a panel',
    group: 'panel',
    humanVariants: const {
      'ru': ['переименуй {panel} в {new_title}', 'назови {panel} {new_title}'],
      'en': ['rename {panel} to {new_title}', 'call {panel} {new_title}'],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'new_title',
        'New title',
        required: true,
        aliases: const ['new'],
        shortKey: 'nt',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'panel:move',
    alias: 'pmv',
    description: 'Move a panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('x', 'New x', required: true, kind: YoloitCliToolParamKind.number),
      toolParam('y', 'New y', required: true, kind: YoloitCliToolParamKind.number),
    ],
  ),

  YoloitCliTool(
    command: 'panel:resize',
    alias: 'psz',
    description:
        'Resize a panel. Supports explicit width/height or presets: '
        'small(420x300), medium(720x480), desktop(1200x800), '
        'large(1400x900), mobile(390x844), tablet(768x1024).',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'width',
        'New width',
        required: true,
        kind: YoloitCliToolParamKind.number,
        shortKey: 'w',
      ),
      toolParam(
        'height',
        'New height',
        required: true,
        kind: YoloitCliToolParamKind.number,
        shortKey: 'h',
      ),
    ],
    humanVariants: const {
      'ru': [
        'увеличь панель до desktop',
        'сделай панель small',
        'resize panel to desktop',
        'сделай мобильный размер панели',
      ],
      'en': [
        'resize panel to desktop',
        'set panel size to small',
        'set panel to mobile size',
        'resize panel to tablet',
      ],
    },
  ),

  YoloitCliTool(
    command: 'panel:z',
    alias: 'pzi',
    description:
        'Set panel depth/layer order. Use front/back or an explicit integer zIndex.',
    group: 'panel',
    humanVariants: const {
      'ru': [
        'подними панель {panel} наверх',
        'отправь панель {panel} назад',
        'поставь глубину панели {panel} {zIndex}',
      ],
      'en': [
        'bring panel {panel} to front',
        'send panel {panel} to back',
        'set panel {panel} z index {zIndex}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'front_or_back_or_zindex',
        'Move to front/back or set explicit integer zIndex',
        required: true,
        aliases: const ['front|back|zIndex', 'zIndex', 'depth'],
        shortKey: 'z',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'panel:delete',
    alias: 'pdl',
    description: 'Delete a panel',
    group: 'panel',
    destructive: true,
    humanVariants: const {
      'ru': [
        'удали {panel}',
        'удали панель {panel}',
        'убери {panel}',
        'удали все заметки',
        'удали заметку {panel}',
      ],
      'en': [
        'delete {panel}',
        'remove {panel}',
        'delete panel {panel}',
        'remove the note {panel}',
      ],
    },
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'panel:focus',
    alias: 'pfc',
    description:
        'Focus/scroll-to/zoom a panel to bring it into view. Use for "сделай фокус на", "фокус на", "покажи", "открой" any panel — notes, playlists, kanban, etc. Examples: "сделай фокус на плейлист", "focus playlist", "show note", "открой заметку".',
    group: 'panel',
    humanVariants: const {
      'ru': [
        'сфокусируйся на панели {panel}',
        'покажи заметку {panel}',
        'открой заметку {panel}',
        'сделай фокус на плейлист',
        'перейди к плейлисту',
      ],
      'en': [
        'focus panel {panel}',
        'show note {panel}',
        'open note {panel}',
        'focus playlist',
      ],
    },
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'panel:color',
    alias: 'pcl',
    description: 'Set or clear panel color',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('color', 'Color value or clear', required: true, shortKey: 'cl'),
    ],
  ),

  YoloitCliTool(
    command: 'panel:hide',
    alias: 'phd',
    description: 'Hide a panel',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'panel:show',
    alias: 'psh',
    description: 'Show a hidden panel',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'panel:screenshot',
    alias: 'psc',
    description:
        'Save PNG screenshot of a single panel (headless offscreen render)',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'file_png',
        'Output PNG path',
        aliases: const ['file', 'path'],
        shortKey: 'fp',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'panel:types',
    alias: 'ptp',
    description:
        'List all available panel/widget type ids on the board. '
        'Use this before panel:create when user asks for a specific widget type.',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam()],
  ),

  YoloitCliTool(
    command: 'do',
    alias: 'pdo',
    description: 'Execute a panel action',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('action', 'Action from panel:help', required: true, shortKey: 'a'),
      toolParam('json', 'Optional JSON body', shortKey: 'j'),
    ],
  ),

  YoloitCliTool(
    command: 'filetree:create',
    alias: 'ftc',
    description:
        'Create a File Tree panel on a board and set its root directory. '
        'Use this when the user asks to show a file tree, directory tree, folder browser, '
        'or "дерево файлов". The panel shows an interactive expandable file browser.',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'path',
        'Root directory path to display',
        required: true,
        shortKey: 'p',
      ),
      toolParam('title', 'Panel title (default: folder name)', shortKey: 't'),
    ],
  ),

  YoloitCliTool(
    command: 'filetree:set-root',
    alias: 'ftsr',
    description: 'Set the root directory path of an existing File Tree panel.',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('path', 'New root directory path', required: true, shortKey: 'p'),
    ],
  ),

  YoloitCliTool(
    command: 'sticky:create',
    alias: 'stk',
    description:
        'Create a Miro-style sticky note panel. Board is optional and defaults to the current board.',
    group: 'panel',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name (optional)', shortKey: 'b'),
      toolParam('title', 'Sticky title', required: true, shortKey: 't'),
      toolParam('text', 'Sticky note text', shortKey: 'tx'),
      toolParam(
        'color',
        'Background color as #RRGGBB',
        flag: '--color',
        shortKey: 'c',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'shape:create',
    alias: 'shp',
    description:
        'Create a geometric board panel: rectangle, circle, diamond, triangle, hexagon, or frame.',
    group: 'panel',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name (optional)', shortKey: 'b'),
      toolParam(
        'shape',
        'rectangle | circle | diamond | triangle | hexagon | frame',
        required: true,
        shortKey: 's',
      ),
      toolParam('title', 'Panel title', required: true, shortKey: 't'),
      toolParam('text', 'Centered label', flag: '--text', shortKey: 'tx'),
      toolParam('fill', 'Fill color as #RRGGBB', flag: '--fill', shortKey: 'f'),
      toolParam('stroke', 'Stroke color as #RRGGBB', flag: '--stroke', shortKey: 'st'),
    ],
  ),

  YoloitCliTool(
    command: 'frame:create',
    alias: 'frm',
    description:
        'Create a Miro-style frame panel for grouping a section of the board.',
    group: 'panel',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name (optional)', shortKey: 'b'),
      toolParam('title', 'Frame title', required: true, shortKey: 't'),
    ],
  ),

];
