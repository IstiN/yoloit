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
    description:
        'List dynamic panel actions and parameter docs (use panel / pgt for panel content)',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'panel:create',
    alias: 'pmk',
    description:
        'Create a panel. Include exact panel type id (call panel:types first). '
        'For custom JS widget apps use app:run — NOT panel:create board.widget.custom. '
        'For folder browser use board.filetree or filetree:create.',
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
    command: 'panel:copy',
    alias: 'pcy',
    description:
        'Copy selected panel(s) to the clipboard. '
        'If no panel ids are given, copies the currently selected panel(s).',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'panels',
        'Comma-separated panel ids or titles (optional)',
        shortKey: 'ps',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'panel:paste',
    alias: 'ppt',
    description: 'Paste copied panels onto the board',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam()],
  ),

  YoloitCliTool(
    command: 'panel:duplicate',
    alias: 'pdp',
    description:
        'Duplicate selected panel(s). '
        'If no panel ids are given, duplicates the currently selected panel(s).',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'panels',
        'Comma-separated panel ids or titles (optional)',
        shortKey: 'ps',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:create',
    alias: 'ccr',
    description: 'Create a Calendar panel on a board',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('title', 'Panel title', required: true, shortKey: 't'),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:events',
    alias: 'cev',
    description: 'List events from a Calendar panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('start', 'Start date/time (ISO8601)', shortKey: 's'),
      toolParam('end', 'End date/time (ISO8601)', shortKey: 'e'),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:add-event',
    alias: 'cae',
    description: 'Add an event to a Calendar panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('title', 'Event title', required: true, shortKey: 't'),
      toolParam('start', 'Start date/time (ISO8601)', required: true),
      toolParam('end', 'End date/time (ISO8601)', shortKey: 'e'),
      toolParam('allDay', 'All day event', kind: YoloitCliToolParamKind.boolean),
      toolParam('description', 'Event description', shortKey: 'd'),
      toolParam('color', 'Event color (#RRGGBB)', shortKey: 'c'),
      toolParam('meetingUrl', 'Optional meeting / video call URL'),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:delete-event',
    alias: 'cde',
    description: 'Delete an event from a Calendar panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('eventId', 'Event id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:set-view',
    alias: 'csv',
    description: 'Switch Calendar panel view',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'view',
        'month | week | workWeek | day | threeDay | list',
        required: true,
        enumValues: const <String>[
          'month',
          'week',
          'workWeek',
          'day',
          'threeDay',
          'list',
        ],
      ),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:focus-date',
    alias: 'cfd',
    description: 'Set the focused date of a Calendar panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('date', 'Date (ISO8601)', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:scroll-to-time',
    alias: 'cstm',
    description: 'Scroll the Calendar timeline to a specific hour',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('hour', 'Hour 0-23', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:scroll-to-event',
    alias: 'cse',
    description: 'Focus and scroll to a Calendar event',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('eventId', 'Event id'),
      toolParam('title', 'Event title substring'),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:show-event',
    alias: 'csh',
    description: 'Show details of a Calendar event',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('eventId', 'Event id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'calendar:update-event',
    description: 'Update an existing calendar event by id',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('eventId', 'Event id', required: true),
      toolParam('title', 'New title'),
      toolParam('start', 'New start ISO datetime'),
      toolParam('end', 'New end ISO datetime'),
      toolParam('description', 'New description'),
      toolParam('color', 'New color'),
    ],
  ),

  YoloitCliTool(
    command: 'chart:get',
    description: 'Read chart panel configuration and data',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'diff:open',
    description: 'Open a file in a diff preview panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('path', 'Absolute file path', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'diff:set-root',
    description: 'Set repository root for a diff preview panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('rootPath', 'Absolute repository root', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'setup:select',
    description: 'Select a setup package in a setup guide panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('packageId', 'Package id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'setup:unselect',
    description: 'Unselect a setup package in a setup guide panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('packageId', 'Package id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'panel-files:list',
    description: 'List files attached to a board.files panel',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'panel-files:add',
    description: 'Attach a file path to a board.files panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('path', 'Absolute file path', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'panel-files:remove',
    description: 'Remove a file from a board.files panel by path or id',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('path', 'File path'),
      toolParam('id', 'File entry id'),
    ],
  ),

  YoloitCliTool(
    command: 'table:create',
    alias: 'tbc',
    description: 'Create a Table panel on a board',
    group: 'panel',
    humanVariants: const {
      'ru': [
        'создай таблицу {title}',
        'добавь таблицу {title}',
      ],
      'en': ['create table {title}', 'add table {title}'],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('title', 'Panel title', required: true, shortKey: 't'),
    ],
  ),

  YoloitCliTool(
    command: 'table:set',
    alias: 'tbs',
    description: 'Replace Table panel columns and rows (JSON)',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('columns', 'JSON array of columns', required: true, shortKey: 'c'),
      toolParam('rows', 'JSON array of rows', required: true, shortKey: 'r'),
    ],
  ),

  YoloitCliTool(
    command: 'table:add-row',
    alias: 'tbar',
    description: 'Add a row to a Table panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('cells', 'JSON object keyed by column id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'table:update-row',
    alias: 'tbur',
    description: 'Update a row in a Table panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('rowId', 'Row id', required: true),
      toolParam('cells', 'JSON object keyed by column id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'table:remove-row',
    alias: 'tbrr',
    description: 'Remove a row from a Table panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('rowId', 'Row id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'table:add-column',
    alias: 'tbac',
    description: 'Add a column to a Table panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('id', 'Column id', required: true),
      toolParam('title', 'Column title', required: true, shortKey: 't'),
      toolParam(
        'type',
        'text | number | date | select',
        enumValues: const <String>['text', 'number', 'date', 'select'],
      ),
      toolParam('options', 'Options for select type (JSON array)'),
    ],
  ),

  YoloitCliTool(
    command: 'table:remove-column',
    alias: 'tbrc',
    description: 'Remove a column from a Table panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('id', 'Column id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'table:clear',
    alias: 'tbcl',
    description: 'Remove all rows from a Table panel',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'chart:create',
    alias: 'chc',
    description: 'Create a Chart panel on a board',
    group: 'panel',
    humanVariants: const {
      'ru': [
        'создай график {title}',
        'добавь график {title}',
        'создай диаграмму {title}',
      ],
      'en': [
        'create chart {title}',
        'add chart {title}',
        'create graph {title}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('title', 'Panel title', required: true, shortKey: 't'),
      toolParam(
        'type',
        'line | bar | pie | scatter | radar | area',
        enumValues: const <String>[
          'line',
          'bar',
          'pie',
          'scatter',
          'radar',
          'area',
        ],
      ),
    ],
  ),

  YoloitCliTool(
    command: 'chart:set-data',
    alias: 'chsd',
    description: 'Set inline data for a Chart panel (JSON array)',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('data', 'JSON array of objects', required: true, shortKey: 'd'),
      toolParam('xKey', 'Field for X/category'),
      toolParam('yKey', 'Field for value'),
    ],
  ),

  YoloitCliTool(
    command: 'chart:set-type',
    alias: 'chst',
    description: 'Change Chart panel type',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'type',
        'line | bar | pie | scatter | radar | area',
        required: true,
        enumValues: const <String>[
          'line',
          'bar',
          'pie',
          'scatter',
          'radar',
          'area',
        ],
      ),
    ],
  ),

  YoloitCliTool(
    command: 'chart:link-table',
    alias: 'chlt',
    description: 'Link a Chart panel to a Table panel as its data source',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('tablePanelId', 'Table panel id', required: true, shortKey: 't'),
    ],
  ),

  YoloitCliTool(
    command: 'chart:refresh',
    alias: 'chfr',
    description: 'Snapshot linked Table panel data into Chart panel state',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('tablePanelId', 'Table panel id (optional if already linked)'),
    ],
  ),

  YoloitCliTool(
    command: 'do',
    alias: 'pdo',
    description:
        'Advanced fallback: run a raw panel action from panel:help when no dedicated '
        'YoLoIT tool exists (table row ops, terminal output, custom widget actions). '
        'Do NOT use for sticky/shape/note/checklist/kanban/board.ui when typed tools exist — '
        'use sticky:append, shape:set, note:append, checklist:add, kanban:add-card, uirnd, etc. '
        'JSON body must be an object like {"text":"..."}, never a bare JSON string.',
    group: 'panel',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'action',
        'Action name from panel:help — only when no dedicated tool exists',
        required: true,
        shortKey: 'a',
      ),
      toolParam(
        'json',
        'JSON object body for the action (not a bare string)',
        shortKey: 'j',
      ),
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
      toolParam(
        'text',
        'Centered label (clip .txt paths under yoloit_clip are read automatically)',
        flag: '--text',
        shortKey: 'tx',
      ),
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
