import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> boardTools = <YoloitCliTool>[
  const YoloitCliTool(
    command: 'boards',
    alias: 'bls',
    description: 'List all boards',
    group: 'board',
    humanVariants: {
      'ru': ['покажи борды', 'список бордов', 'какие борды есть', 'мои доски'],
      'en': [
        'show boards',
        'list boards',
        'what boards do I have',
        'my boards',
      ],
    },
  ),

  YoloitCliTool(
    command: 'board:create',
    alias: 'bmk',
    description: 'Create a board, optionally from a template',
    group: 'board',
    humanVariants: const {
      'ru': [
        'создай борд {name}',
        'создай доску {name}',
        'новый борд {name}',
        'новая доска {name}',
      ],
      'en': ['create board {name}', 'new board {name}', 'add board {name}'],
    },
    params: <YoloitCliToolParam>[
      toolParam('name', 'New board name', required: true, shortKey: 'n'),
      toolParam(
        'template',
        'Template id to instantiate',
        flag: '--template',
        shortKey: 't',
      ),
      toolParam(
        'params',
        'Template parameters as JSON object or comma-separated key=value pairs',
        flag: '--params',
        shortKey: 'p',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:rename',
    alias: 'brn',
    description: 'Rename a board',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'new_name',
        'New board name',
        required: true,
        aliases: const ['new'],
        shortKey: 'nn',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:folder',
    alias: 'bfold',
    description:
        'Set or clear the board default folder used by new chats, terminals, and file trees',
    group: 'board',
    humanVariants: const {
      'ru': [
        'установи папку борда {path}',
        'задай дефолтную папку борда {path}',
        'папка по умолчанию для доски {path}',
      ],
      'en': [
        'set board default folder {path}',
        'set default folder for board {path}',
        'use folder {path} for this board',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'path',
        "Folder path, or 'clear' to remove the default",
        required: true,
        shortKey: 'p',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:icon',
    alias: 'bico',
    description:
        'Set or reset the board icon shown in the boards overview and toolbar. '
        'Use "auto" to re-detect from the default folder (e.g. a Flutter app '
        'icon), "emoji:<char>" for an emoji, "builtin:<name>" for a bundled '
        'preset (yoloit, yoloit_logo, yolo_assistant, copilot, voice), or a '
        'path to a PNG/JPG/SVG image file.',
    group: 'board',
    humanVariants: const {
      'ru': [
        'поставь иконку борда {icon}',
        'установи иконку доски {icon}',
        'смени иконку борда на {icon}',
      ],
      'en': [
        'set board icon {icon}',
        'change board icon to {icon}',
        'reset board icon to auto',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'icon',
        "Icon: 'auto', 'emoji:<char>', 'builtin:<name>' or image path",
        required: true,
        shortKey: 'i',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:delete',
    alias: 'bdl',
    description: 'Delete a board',
    group: 'board',
    destructive: true,
    humanVariants: const {
      'ru': ['удали борд {board}', 'удали доску {board}', 'убери борд {board}'],
      'en': ['delete board {board}', 'remove board {board}'],
    },
    params: <YoloitCliToolParam>[boardParam('id_or_name')],
  ),

  YoloitCliTool(
    command: 'board:archive',
    alias: 'barch',
    description: 'Archive a board (hide from overview and previews)',
    group: 'board',
    humanVariants: const {
      'ru': ['заархивируй борд {board}', 'архивируй доску {board}'],
      'en': ['archive board {board}', 'hide board {board}'],
    },
    params: <YoloitCliToolParam>[boardParam('id_or_name')],
  ),

  YoloitCliTool(
    command: 'board:unarchive',
    alias: 'bunarch',
    description: 'Restore an archived board',
    group: 'board',
    humanVariants: const {
      'ru': ['разархивируй борд {board}', 'верни доску {board} из архива'],
      'en': ['unarchive board {board}', 'restore board {board}'],
    },
    params: <YoloitCliToolParam>[boardParam('id_or_name')],
  ),

  YoloitCliTool(
    command: 'board:focus',
    alias: 'bfc',
    description: 'Focus a board in the UI',
    group: 'board',
    humanVariants: const {
      'ru': [
        'открой борд {board}',
        'переключись на {board}',
        'покажи борд {board}',
        'перейди на {board}',
      ],
      'en': [
        'open board {board}',
        'show board {board}',
        'switch to {board}',
        'go to {board}',
      ],
    },
    params: <YoloitCliToolParam>[boardParam('id_or_name')],
  ),

  YoloitCliTool(
    command: 'board:undo',
    alias: 'bundo',
    description:
        'Undo the latest panel history batch on a board. Resize and drag bursts are coalesced into one undo.',
    group: 'board',
    humanVariants: const {
      'ru': [
        'отмени последнее изменение на борде',
        'откати последнее изменение панели',
        'верни предыдущий размер панели',
        'undo на борде',
      ],
      'en': [
        'undo latest board change',
        'undo latest panel change',
        'revert panel resize',
        'restore previous panel size',
      ],
    },
    params: <YoloitCliToolParam>[boardParam('id_or_name')],
  ),

  YoloitCliTool(
    command: 'board:redo',
    alias: 'bredo',
    description:
        'Redo the latest undone panel history batch on a board. Works after board:undo until a new panel change is made.',
    group: 'board',
    humanVariants: const {
      'ru': [
        'верни отменённое изменение на борде',
        'повтори отменённое изменение панели',
        'redo на борде',
      ],
      'en': [
        'redo latest board change',
        'redo latest panel change',
        'restore undone panel resize',
      ],
    },
    params: <YoloitCliToolParam>[boardParam('id_or_name')],
  ),

  YoloitCliTool(
    command: 'board:use',
    alias: 'buse',
    description: 'Set default board for subsequent commands (no UI switch)',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name', required: true, shortKey: 'b'),
    ],
  ),

  const YoloitCliTool(
    command: 'board:current',
    alias: 'bcur',
    description: 'Show current board',
    group: 'board',
  ),

  YoloitCliTool(
    command: 'board:apply',
    alias: 'bap',
    description:
        'Apply YAML bulk operations to a board (create/move/rename panels). '
        'Pass inline `yaml` string or a `file` path.',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'yaml',
        'Inline YAML operations (preferred for LLM). Written to a temp file server-side.',
        required: false,
      ),
      toolParam('file', "YAML file path or '-' for stdin", required: false),
    ],
  ),

  YoloitCliTool(
    command: 'board:snapshot',
    alias: 'bsn',
    description: 'Text snapshot of board layout',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam('format', 'md or mermaid', flag: '--format', shortKey: 'fmt'),
    ],
  ),

  YoloitCliTool(
    command: 'board:diagram',
    alias: 'bdg',
    description: 'Mermaid-focused board diagram',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam('format', 'mermaid or md', flag: '--format', shortKey: 'fmt'),
    ],
  ),

  YoloitCliTool(
    command: 'board:screenshot',
    alias: 'bsc',
    description: 'Save PNG screenshot',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'file_png',
        'Output PNG path',
        aliases: const ['file', 'path'],
        shortKey: 'fp',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:svg',
    alias: 'bsv',
    description: 'Export SVG layout',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'file_svg',
        'Output SVG path',
        aliases: const ['file', 'path'],
        shortKey: 'fs',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:zoom',
    alias: 'bzm',
    description:
        'Set board zoom/scale level. Use for "уменьши зум", "увеличь зум", "zoom in", "zoom out", "приблизь", "отдали". Pass absolute scale: 0.5 = 50%, 1.0 = 100%, 2.0 = 200%.',
    group: 'board',
    humanVariants: const {
      'ru': [
        'уменьши зум',
        'увеличь зум',
        'zoom out',
        'zoom in',
        'приблизь',
        'отдали',
      ],
      'en': [
        'zoom in',
        'zoom out',
        'set zoom',
        'increase zoom',
        'decrease zoom',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'scale',
        'Zoom scale',
        required: true,
        kind: YoloitCliToolParamKind.number,
        shortKey: 'sc',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:fit',
    alias: 'bft',
    description: 'Fit board to viewport',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'size',
        'Viewport size like 1280x800',
        aliases: const ['wxh'],
        shortKey: 'sz',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:arrange',
    alias: 'bar',
    description: 'Arrange visible panels',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam('direction', 'right or down', shortKey: 'dir'),
      toolParam(
        'h_spacing',
        'Horizontal spacing',
        kind: YoloitCliToolParamKind.number,
        aliases: const <String>['horizontal_spacing', 'horizontal', 'hSpacing'],
        shortKey: 'hs',
      ),
      toolParam(
        'v_spacing',
        'Vertical spacing',
        kind: YoloitCliToolParamKind.number,
        aliases: const <String>['vertical_spacing', 'vertical', 'vSpacing'],
        shortKey: 'vs',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:grid',
    alias: 'bgr',
    description:
        'Toggle, reset or configure grid view for a board. '
        'Use "on" to enable, "off" to disable, or "reset" to restore defaults.',
    group: 'board',
    humanVariants: const {
      'ru': [
        'включи сетку на борде',
        'выключи сетку',
        'сбрось сетку',
        'упорядочи панели по сетке',
      ],
      'en': [
        'enable grid',
        'disable grid',
        'reset grid',
        'snap panels to grid',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam('id_or_name'),
      toolParam(
        'on_or_off_or_reset',
        'Enable, disable or reset grid view',
        required: true,
        enumValues: const <String>['on', 'off', 'reset'],
      ),
      toolParam(
        'cell',
        'Grid cell size in pixels',
        flag: '--cell',
        kind: YoloitCliToolParamKind.number,
      ),
      toolParam(
        'spacing',
        'Gap between cells in pixels',
        flag: '--spacing',
        kind: YoloitCliToolParamKind.number,
      ),
      toolParam(
        'arrange',
        'Re-arrange panels into the default cloud',
        flag: '--arrange',
        kind: YoloitCliToolParamKind.boolean,
      ),
      toolParam(
        'group',
        'Arrange panels into type blocks',
        flag: '--group',
        kind: YoloitCliToolParamKind.boolean,
      ),
    ],
  ),

  YoloitCliTool(
    command: 'board:translate',
    alias: 'btr',
    description: 'Move board viewport',
    group: 'board',
    params: <YoloitCliToolParam>[
      boardParam('board'),
      toolParam(
        'x',
        'Viewport x',
        required: true,
        kind: YoloitCliToolParamKind.number,
      ),
      toolParam(
        'y',
        'Viewport y',
        required: true,
        kind: YoloitCliToolParamKind.number,
      ),
    ],
  ),

  YoloitCliTool(
    command: 'draw:list',
    alias: 'drl',
    description:
        'List all drawings (freehand strokes / shapes) on a board. '
        'Returns id, position, size, strokeColor, zIndex for each element.',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name (defaults to active board)', shortKey: 'b'),
    ],
  ),

  YoloitCliTool(
    command: 'draw:add',
    alias: 'dra',
    description:
        'Add a shape drawing to a board. '
        'Supports BOTH positional and named-flag syntax. '
        'POSITIONAL (preferred for brevity): '
        '"draw:add <boardId> <type> <params...>" — '
        'circle: draw:add board-123 circle <cx> <cy> <r>; '
        'line: draw:add board-123 line <x1> <y1> <x2> <y2>; '
        'arrow: draw:add board-123 arrow <x1> <y1> <x2> <y2>; '
        'rect: draw:add board-123 rect <x> <y> <width> <height>; '
        'freehand: draw:add board-123 freehand <points-json>. '
        'Board defaults to active board. Returns the new drawing id.',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name (defaults to active board)', shortKey: 'b'),
      toolParam(
        'type',
        'Shape type: line | circle | rect | arrow | freehand | svg',
        shortKey: 's',
      ),
      toolParam(
        'color',
        'Stroke color as #RRGGBB hex (default #FFFFFF)',
        shortKey: 'c',
      ),
      toolParam('width', 'Stroke width in pixels (default 3)', shortKey: 'w'),
      toolParam('x1', 'Start X (line/arrow)'),
      toolParam('y1', 'Start Y (line/arrow)'),
      toolParam('x2', 'End X (line/arrow)'),
      toolParam('y2', 'End Y (line/arrow)'),
      toolParam('cx', 'Center X (circle)'),
      toolParam('cy', 'Center Y (circle)'),
      toolParam('r', 'Radius (circle)'),
      toolParam('x', 'Top-left X (rect/freehand/svg origin)'),
      toolParam('y', 'Top-left Y (rect/freehand/svg origin)'),
      toolParam(
        'rw',
        'Shape width for rect (default 200). Use "rw" not "width" to avoid conflict with stroke width.',
      ),
      toolParam('height', 'Height (rect, default 100)'),
      toolParam('points', 'JSON array of [x,y] pairs for freehand'),
      toolParam('d', 'SVG path data string (for svg type)'),
    ],
  ),

  YoloitCliTool(
    command: 'draw:remove',
    alias: 'drr',
    description: 'Remove a specific drawing from a board by its id.',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name', required: true, shortKey: 'b'),
      toolParam('id', 'Drawing id (from draw:list)', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'draw:clear',
    alias: 'drc',
    description: 'Remove ALL drawings from a board.',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name', required: true, shortKey: 'b'),
    ],
  ),

  YoloitCliTool(
    command: 'draw:svg',
    alias: 'drsvg',
    description:
        'Draw SVG path data on the board canvas as a free-floating drawing (M/L/C/Q/Z). '
        'NOT for images inside board.ui cards — use ui:render with {"type":"svg",...} instead.',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name', required: true, shortKey: 'b'),
      toolParam('d', 'SVG path data (e.g. "M 10 10 L 100 100 Z")', required: true),
      toolParam('x', 'X origin offset for the path (default 100)'),
      toolParam('y', 'Y origin offset for the path (default 100)'),
      toolParam('color', 'Stroke color as #RRGGBB hex', shortKey: 'c'),
      toolParam('width', 'Stroke width in pixels', shortKey: 'w'),
    ],
  ),

  YoloitCliTool(
    command: 'draw:export',
    alias: 'drex',
    description:
        'Export all drawings on a board as SVG. '
        'Prints SVG to stdout or saves to a file. '
        'Agents can read this to understand what has been drawn.',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name (defaults to active board)', shortKey: 'b'),
      toolParam('out', 'Output file path (stdout if omitted)', shortKey: 'o'),
    ],
  ),

  YoloitCliTool(
    command: 'draw:file',
    alias: 'drf',
    description:
        'Render an SVG file as drawings on a board. '
        'All path elements in the SVG file are drawn as strokes. '
        'Use to import diagrams, icons, or illustrations from .svg files.',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Board id or name', required: true, shortKey: 'b'),
      toolParam('file', 'Path to SVG file', required: true, shortKey: 'f'),
      toolParam('x', 'X position offset (default 100)'),
      toolParam('y', 'Y position offset (default 100)'),
      toolParam('color', 'Stroke color override as #RRGGBB hex', shortKey: 'c'),
      toolParam('width', 'Stroke width in pixels', shortKey: 'w'),
    ],
  ),

  const YoloitCliTool(
    command: 'template:list',
    alias: 'tls',
    description: 'List available board templates',
    group: 'template',
    humanVariants: {
      'ru': ['покажи шаблоны', 'список шаблонов', 'какие шаблоны есть'],
      'en': ['show templates', 'list templates', 'what templates are available'],
    },
  ),

  YoloitCliTool(
    command: 'template:sync',
    alias: 'tsy',
    description: 'Refresh templates from all configured sources',
    group: 'template',
    humanVariants: const {
      'ru': ['обнови шаблоны', 'синхронизируй шаблоны'],
      'en': ['sync templates', 'refresh templates'],
    },
    params: <YoloitCliToolParam>[
      toolParam(
        'source',
        'Optional source id to sync only one source',
        flag: '--source',
        shortKey: 's',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'template:info',
    alias: 'tinfo',
    description: 'Show template details and parameters',
    group: 'template',
    humanVariants: const {
      'ru': ['инфо о шаблоне {id}', 'параметры шаблона {id}'],
      'en': ['template info {id}', 'template parameters {id}'],
    },
    params: <YoloitCliToolParam>[
      toolParam('id', 'Template id', required: true),
    ],
  ),

];
