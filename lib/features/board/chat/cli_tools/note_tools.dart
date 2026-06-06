import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> noteTools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'note',
    alias: 'nst',
    description: 'Set markdown note text',
    group: 'note',
    humanVariants: const {
      'ru': [
        'запиши {text}',
        'обнови заметку {text}',
        'напиши в заметку {text}',
        'установи текст заметки {text}',
      ],
      'en': ['set note to {text}', 'write {text}', 'update note with {text}'],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('text', 'Markdown text', required: true, shortKey: 'tx'),
    ],
  ),

  YoloitCliTool(
    command: 'note:append',
    alias: 'nap',
    description: 'Append markdown note text',
    group: 'note',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('text', 'Markdown text', required: true, shortKey: 'tx'),
    ],
  ),

  YoloitCliTool(
    command: 'note:wrap',
    alias: 'nwr',
    description: 'Enable note auto-height wrapping',
    group: 'note',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'note:nowrap',
    alias: 'nnw',
    description: 'Disable note auto-height wrapping',
    group: 'note',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'note:add',
    alias: 'nadd',
    description: 'Append text to note — board and panel optional',
    group: 'note',
    humanVariants: const {
      'ru': [
        'допиши {text}',
        'добавь в заметку {text}',
        'припиши {text}',
        'дополни заметку {text}',
      ],
      'en': ['append {text} to note', 'add {text} to the note'],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('text', 'Text to append', required: true, shortKey: 'tx'),
    ],
  ),

  YoloitCliTool(
    command: 'note:create',
    alias: 'ncrt',
    description: 'Create a new note panel',
    group: 'note',
    humanVariants: const {
      'ru': [
        'создай заметку {title}',
        'добавь заметку {title}',
        'новая заметка {title}',
        'сделай заметку {title}',
      ],
      'en': [
        'create note {title}',
        'add a note {title}',
        'new note {title}',
        'make a note {title}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      toolParam('title', 'Note title', required: true, shortKey: 'ti'),
      toolParam('content', 'Markdown content', shortKey: 'c'),
    ],
  ),

  YoloitCliTool(
    command: 'checklist:add',
    alias: 'chad',
    description: 'Add checklist item',
    group: 'checklist',
    humanVariants: const {
      'ru': [
        'добавь в чеклист {item}',
        'добавь пункт {item}',
        'запиши в список {item}',
        'добавь задачу {item}',
      ],
      'en': [
        'add {item} to checklist',
        'add checklist item {item}',
        'add task {item}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'item',
        'Checklist item text',
        required: true,
        aliases: const ['text'],
        shortKey: 'it',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'checklist:check',
    alias: 'chck',
    description: 'Toggle checklist item state',
    group: 'checklist',
    humanVariants: const {
      'ru': [
        'отметь {item}',
        'выполни {item}',
        'сделано {item}',
        'отметь как сделано {item}',
      ],
      'en': [
        'check {item}',
        'mark {item} done',
        'complete {item}',
        'tick {item}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'item',
        'Item id or text',
        required: true,
        aliases: const ['id', 'text'],
        shortKey: 'it',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'checklist:uncheck',
    alias: 'chun',
    description: 'Toggle checklist item state',
    group: 'checklist',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'item',
        'Item id or text',
        required: true,
        aliases: const ['id', 'text'],
        shortKey: 'it',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'checklist:new',
    alias: 'cln',
    description: 'Create a new checklist panel',
    group: 'checklist',
    humanVariants: const {
      'ru': [
        'создай чеклист {title}',
        'новый чеклист {title}',
        'создай список {title}',
        'добавь чеклист {title}',
      ],
      'en': [
        'create checklist {title}',
        'new checklist {title}',
        'add checklist {title}',
      ],
    },
    params: <YoloitCliToolParam>[
      toolParam('title', 'Panel title', required: true, shortKey: 'ti'),
      boardParam(),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:columns',
    alias: 'kcls',
    description: 'List kanban columns',
    group: 'kanban',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'kanban:add-column',
    alias: 'kadc',
    description: 'Add kanban column',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('name', 'Column name', required: true, shortKey: 'n'),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:rename-column',
    alias: 'krnc',
    description: 'Rename kanban column',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('column', 'Column id or name', required: true, shortKey: 'col'),
      toolParam('name', 'New column name', required: true, shortKey: 'n'),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:remove-column',
    alias: 'krmc',
    description: 'Remove kanban column',
    group: 'kanban',
    destructive: true,
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('column', 'Column id or name', required: true, shortKey: 'col'),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:add-card',
    alias: 'kadk',
    description:
        'Add kanban card. Parse "in/into/to <column>" as the required `column` and "named/called/titled <text>" as `title`.',
    group: 'kanban',
    humanVariants: const {
      'ru': [
        'добавь карточку {title} в {column}',
        'создай карточку {title}',
        'новая карточка {title} в {column}',
      ],
      'en': [
        'add card {title} to {column}',
        'create card {title} in {column}',
        'new card {title}',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'column',
        'Target column name or id, for example Todo, Doing, Done',
        required: true,
        aliases: const <String>['column_name', 'lane', 'status', 'list'],
        shortKey: 'col',
      ),
      toolParam(
        'title',
        'Card title',
        required: true,
        aliases: const <String>['name', 'card_title'],
        shortKey: 't',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:move-card',
    alias: 'kmvk',
    description: 'Move kanban card',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'card_id',
        'Card id',
        required: true,
        aliases: const ['cardId', 'id'],
        shortKey: 'cid',
      ),
      toolParam(
        'to_column',
        'Destination column',
        required: true,
        aliases: const ['to'],
        shortKey: 'tc',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:remove-card',
    alias: 'krmk',
    description: 'Remove kanban card',
    group: 'kanban',
    destructive: true,
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'card_id',
        'Card id',
        required: true,
        aliases: const ['cardId', 'id'],
        shortKey: 'cid',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:update-card',
    alias: 'kudk',
    description: 'Update kanban card title',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'card_id',
        'Card id',
        required: true,
        aliases: const ['cardId', 'id'],
        shortKey: 'cid',
      ),
      toolParam('title', 'New card title', required: true, shortKey: 't'),
    ],
  ),

  YoloitCliTool(
    command: 'kanban:cards',
    alias: 'kkls',
    description: 'List kanban cards',
    group: 'kanban',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

];
