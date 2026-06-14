import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> groupTools = <YoloitCliTool>[
  const YoloitCliTool(
    command: 'groups',
    alias: 'gls',
    description: 'List groups on a board',
    group: 'group',
  ),

  YoloitCliTool(
    command: 'group:create',
    alias: 'gmk',
    description: 'Create a named group of panels',
    group: 'group',
    humanVariants: const {
      'en': [
        'create group {name} on {board}',
        'group panels as {name}',
        'new group {name}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('name', 'Group name', required: true, shortKey: 'n'),
      toolParam(
        'panels',
        'Comma-separated panel ids or titles to include',
        shortKey: 'p',
      ),
      toolParam(
        'color',
        'Group color as hex (#RRGGBB) or named color, or "clear"',
        shortKey: 'c',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'group:delete',
    alias: 'gdl',
    description: 'Delete a group',
    group: 'group',
    destructive: true,
    humanVariants: const {
      'en': ['delete group {group}', 'remove group {group}'],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('group', 'Group id or name', required: true, shortKey: 'g'),
    ],
  ),

  YoloitCliTool(
    command: 'group:rename',
    alias: 'grn',
    description: 'Rename a group',
    group: 'group',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('group', 'Group id or name', required: true, shortKey: 'g'),
      toolParam(
        'new_name',
        'New group name',
        required: true,
        aliases: const ['new'],
        shortKey: 'nn',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'group:color',
    alias: 'gco',
    description: 'Set or clear a group color',
    group: 'group',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('group', 'Group id or name', required: true, shortKey: 'g'),
      toolParam(
        'color',
        'Group color as hex (#RRGGBB) or named color, or "clear"',
        required: true,
        shortKey: 'c',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'group:add',
    alias: 'gadd',
    description: 'Add panels to a group',
    group: 'group',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('group', 'Group id or name', required: true, shortKey: 'g'),
      toolParam(
        'panels',
        'Comma-separated panel ids or titles',
        required: true,
        shortKey: 'p',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'group:remove',
    alias: 'grm',
    description: 'Remove panels from a group',
    group: 'group',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('group', 'Group id or name', required: true, shortKey: 'g'),
      toolParam(
        'panels',
        'Comma-separated panel ids or titles',
        required: true,
        shortKey: 'p',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'group:collapse',
    alias: 'gcol',
    description: 'Collapse a group and hide its panels',
    group: 'group',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('group', 'Group id or name', required: true, shortKey: 'g'),
    ],
  ),

  YoloitCliTool(
    command: 'group:expand',
    alias: 'gexp',
    description: 'Expand a collapsed group and show its panels',
    group: 'group',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('group', 'Group id or name', required: true, shortKey: 'g'),
    ],
  ),
];
