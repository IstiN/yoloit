import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> fileTools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'files:preview',
    alias: 'fpv',
    description:
        'Open a file as a preview panel on the board (supports markdown, images, text, code). '
        'Use this when user asks to "открой", "покажи", "preview" a file. '
        'Do NOT use note:create — use files:preview to show the actual file.',
    group: 'files',
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam(
        'path',
        'Absolute file path to preview',
        required: true,
        shortKey: 'p',
      ),
      toolParam(
        'title',
        'Panel title (default: filename)',
        flag: '--title',
        shortKey: 't',
      ),
    ],
    humanVariants: const {
      'ru': [
        'открой файл {path}',
        'покажи файл {path}',
        'открой превью {path}',
        'preview {path}',
        'открой readme',
        'покажи readme',
      ],
      'en': [
        'open file {path}',
        'preview file {path}',
        'show file {path}',
        'open preview {path}',
      ],
    },
  ),

  YoloitCliTool(
    command: 'files:search',
    alias: 'fsh',
    description:
        'Read-only search for files and folders on the local file system. '
        'If user names a folder/scope ("в папке ai.m", "in ~/project"), pass it via --root to restrict results.',
    group: 'files',
    params: <YoloitCliToolParam>[
      toolParam('query', 'File or folder name query', required: true, shortKey: 'q'),
      toolParam('root', 'Search root path', flag: '--root', shortKey: 'r'),
      toolParam('type', 'files, dirs, or all', flag: '--type', shortKey: 't'),
      toolParam(
        'limit',
        'Max results',
        flag: '--limit',
        kind: YoloitCliToolParamKind.number,
        shortKey: 'lim',
      ),
    ],
    humanVariants: const {
      'ru': [
        'найди файл {query}',
        'найди {query} в папке {root}',
        'поиск файла {query} в {root}',
      ],
      'en': [
        'find file {query}',
        'search {query} in folder {root}',
        'find {query} under {root}',
      ],
    },
  ),

  YoloitCliTool(
    command: 'files:list',
    alias: 'fls',
    description: 'Read-only list of directory entries for a file system path',
    group: 'files',
    params: <YoloitCliToolParam>[
      toolParam('path', 'Directory path', required: true, shortKey: 'p'),
    ],
  ),

  YoloitCliTool(
    command: 'files:read',
    alias: 'frd',
    description: 'Read-only display of a text file from the local file system',
    group: 'files',
    params: <YoloitCliToolParam>[
      toolParam('path', 'File path', required: true, shortKey: 'p'),
      toolParam(
        'lines',
        'Max lines to print',
        flag: '--lines',
        kind: YoloitCliToolParamKind.number,
        shortKey: 'ln',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'filetree:read',
    alias: 'ftr',
    description:
        'Read and print a directory tree as text (no panel required). '
        'Useful for agents to understand folder structure without creating a UI panel. '
        'Use this for "what files are in X", "show me the structure of X".',
    group: 'files',
    params: <YoloitCliToolParam>[
      toolParam('path', 'Directory path to read', required: true, shortKey: 'p'),
      toolParam('depth', 'Max depth (default 3)', shortKey: 'd'),
      toolParam(
        'all',
        'Show hidden files too',
        kind: YoloitCliToolParamKind.boolean,
        shortKey: 'a',
      ),
    ],
  ),

];
