import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> linkTools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'link:create',
    alias: 'lmk',
    description: 'Create panel link',
    group: 'link',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('from', 'Source panel id or title', required: true, shortKey: 'fr'),
      toolParam('to', 'Target panel id or title', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'link:delete',
    alias: 'ldl',
    description: 'Delete panel link',
    group: 'link',
    destructive: true,
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'link_id',
        'Link id',
        required: true,
        aliases: const ['id'],
        shortKey: 'lid',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'link:style',
    alias: 'lst',
    description: 'Set link style and geometry',
    group: 'link',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'link_id',
        'Link id',
        required: true,
        aliases: const ['id'],
        shortKey: 'lid',
      ),
      toolParam('style', 'arrow or line', required: true, shortKey: 'st'),
      toolParam('geometry', 'bezier, straight, or elbow', shortKey: 'geo'),
    ],
  ),

  YoloitCliTool(
    command: 'link:color',
    alias: 'lcl',
    description: 'Set link color',
    group: 'link',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'link_id',
        'Link id',
        required: true,
        aliases: const ['id'],
        shortKey: 'lid',
      ),
      toolParam('color', 'Color value', required: true, shortKey: 'cl'),
    ],
  ),

];
