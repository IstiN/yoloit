import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> appTools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'help',
    alias: 'hlp',
    description: 'Show CLI help',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam(
        'format',
        'short, detailed, mermaid, or tools',
        flag: '--format',
        shortKey: 'fmt',
      ),
    ],
  ),

  const YoloitCliTool(
    command: 'reload',
    alias: 'rl',
    description: 'Hot reload the running Flutter app',
    group: 'app',
  ),

  const YoloitCliTool(
    command: 'restart',
    alias: 'rs',
    description: 'Hot restart the running Flutter app',
    group: 'app',
  ),

  YoloitCliTool(
    command: 'remote:connect',
    alias: 'rcon',
    description: 'Connect the CLI to a remote yoloitd daemon',
    group: 'remote',
    humanVariants: const {
      'ru': [
        'подключись к удаленному yoloitd',
        'подключи удаленные борды',
        'connect remote boards',
      ],
      'en': ['connect remote boards', 'connect to remote yoloitd'],
    },
    params: <YoloitCliToolParam>[
      toolParam('url', 'Remote base URL', required: true),
      toolParam('token', 'Bearer token', required: false),
    ],
  ),

  const YoloitCliTool(
    command: 'remote:disconnect',
    alias: 'rdisc',
    description: 'Disconnect remote yoloitd and use local desktop server',
    group: 'remote',
  ),

  const YoloitCliTool(
    command: 'remote:status',
    alias: 'rst',
    description: 'Show active remote yoloitd connection',
    group: 'remote',
  ),

  YoloitCliTool(
    command: 'board',
    alias: 'bgt',
    description: 'Show board details',
    group: 'board',
    params: <YoloitCliToolParam>[boardParam('id_or_name')],
  ),

  YoloitCliTool(
    command: 'boards:snapshot',
    alias: 'bss',
    description: 'Snapshot all boards and panels as Mermaid graph',
    group: 'board',
    params: <YoloitCliToolParam>[
      toolParam('format', 'mermaid or md', flag: '--format', shortKey: 'fmt'),
    ],
  ),

  YoloitCliTool(
    command: 'panel',
    alias: 'pgt',
    description:
        'Show panel details and content. Use this to inspect note markdown when searching by content.',
    group: 'panel',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  const YoloitCliTool(
    command: 'agent:list',
    alias: 'agl',
    description:
        'List configured agents, default agent, and live agent sessions',
    group: 'agents',
  ),

  YoloitCliTool(
    command: 'agent:default',
    alias: 'agd',
    description:
        'Get or set the default agent id for agent:run (board.chat provider, default: copilot)',
    group: 'agents',
    params: <YoloitCliToolParam>[toolParam('agent', 'Agent id to set', shortKey: 'a')],
  ),

  YoloitCliTool(
    command: 'agent:run',
    alias: 'agr',
    description:
        'Start an agent session: creates a board.chat panel in the folder and sends the initial task. '
        'When task is sent the response includes STOP — do not call yolochat:send again. '
        'For typing into an existing terminal panel use yolochat:terminal.',
    group: 'agents',
    params: <YoloitCliToolParam>[
      toolParam('agent', 'Agent id (e.g. copilot)', shortKey: 'a'),
      toolParam(
        'path',
        'Workspace or folder path',
        required: true,
        shortKey: 'pth',
      ),
      toolParam(
        'task',
        'Initial task/prompt — typed into the agent terminal automatically',
        shortKey: 'tsk',
      ),
      toolParam('name', 'Optional session name', flag: '--name', shortKey: 'n'),
    ],
  ),

  YoloitCliTool(
    command: 'agent:model',
    alias: 'agm',
    description: 'Get or set the default LLM model for an agent',
    group: 'agents',
    params: <YoloitCliToolParam>[
      toolParam(
        'agent_id',
        'Agent id (copilot, cursor, opencode, ...)',
        required: true,
        shortKey: 'a',
      ),
      toolParam(
        'model_id',
        'Optional model id to set (omit to read current)',
        shortKey: 'm',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'agent:asr',
    alias: 'aga',
    description: 'Get or set the ASR (transcription) config for an agent',
    group: 'agents',
    params: <YoloitCliToolParam>[
      toolParam('agent_id', 'Agent id', required: true, shortKey: 'a'),
      toolParam(
        'mode',
        'ASR mode: local or cloud (omit to read current)',
        shortKey: 'mo',
      ),
      toolParam(
        'provider',
        'Cloud provider config id (required when mode=cloud)',
        shortKey: 'pr',
      ),
      toolParam(
        'model',
        'Cloud ASR model, e.g. whisper-1 (optional for cloud)',
        shortKey: 'ml',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'search',
    alias: 'srh',
    description:
        'Search text across all boards, panels, active chats, and saved chat sessions',
    group: 'search',
    params: <YoloitCliToolParam>[
      toolParam('query', 'Search text', required: true, shortKey: 'q'),
      toolParam(
        'scope',
        'Search scope: all, boards, active-chats, sessions',
        flag: '--scope',
        shortKey: 's',
      ),
    ],
  ),

  const YoloitCliTool(
    command: 'yolochat:panels',
    alias: 'cls',
    description: 'List all board.chat panels',
    group: 'yolochat',
  ),

  YoloitCliTool(
    command: 'yolochat:send',
    alias: 'csd',
    description:
        'Send a message to a YoLo chat panel — non-blocking, returns immediately '
        'with status:processing. Use yolochat:messages to read the response. '
        'Always pass --panel when multiple board.chat panels exist. '
        'Do NOT call after agent:run with task (task already sent).',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      toolParam('text', 'Message text', required: true, shortKey: 'tx'),
      boardFlagParam(),
      panelFlagParam(),
      toolParam(
        'provider',
        'Provider override (for example cloud:<config-id>)',
        flag: '--provider',
        shortKey: 'pr',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'yolochat:terminal',
    alias: 'ctm',
    description:
        'Send literal text to an existing terminal panel and press Enter. '
        'The `text` parameter is the command/characters to type (e.g. "npm test", not an agent name). '
        'Use --no-enter to type without pressing Enter.',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      toolParam(
        'text',
        'Literal text to type into the terminal',
        required: true,
        shortKey: 'tx',
      ),
      boardFlagParam(),
      panelFlagParam(),
      toolParam(
        'session',
        'Terminal session id override',
        flag: '--session',
        shortKey: 'sid',
      ),
      toolParam(
        'no_enter',
        'Send raw text without trailing Enter',
        flag: '--no-enter',
        kind: YoloitCliToolParamKind.boolean,
        shortKey: 'ne',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'yolochat:messages',
    alias: 'cms',
    description: 'Read YoLo chat messages',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      boardFlagParam(),
      panelFlagParam(),
      toolParam(
        'limit',
        'Max messages',
        flag: '--limit',
        kind: YoloitCliToolParamKind.number,
        shortKey: 'lim',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'yolochat:clear',
    alias: 'ccl',
    description: 'Clear YoLo chat messages',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      boardFlagParam(),
      panelFlagParam(),
    ],
  ),

  const YoloitCliTool(
    command: 'yolochat:sessions',
    alias: 'css',
    description: 'List active YoLo chat sessions',
    group: 'yolochat',
  ),

  const YoloitCliTool(
    command: 'yolochat:history',
    alias: 'chy',
    description: 'List saved YoLo chat sessions from chat history',
    group: 'yolochat',
  ),

  YoloitCliTool(
    command: 'yolochat:restore',
    alias: 'crs',
    description: 'Restore a saved YoLo chat session into a chat panel',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      toolParam('session_id', 'Saved session id', required: true, shortKey: 'sid'),
      boardFlagParam(),
      panelFlagParam(),
    ],
  ),

  YoloitCliTool(
    command: 'yolochat:status',
    alias: 'cst',
    description: 'Show YoLo chat status',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      boardFlagParam(),
      panelFlagParam(),
    ],
  ),

  YoloitCliTool(
    command: 'yolochat:stop',
    alias: 'csp',
    description: 'Stop active YoLo chat streaming (target panel or any active)',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      toolParam('board', 'Target board (optional)', flag: '--board', shortKey: 'b'),
      toolParam(
        'panel',
        'Target chat panel (optional)',
        flag: '--panel',
        shortKey: 'p',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'yolochat:logs',
    alias: 'clg',
    description: 'Dump full YoLo chat log for debugging',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      boardFlagParam(),
      panelFlagParam(),
    ],
  ),

  const YoloitCliTool(
    command: 'cloud:list',
    alias: 'clp',
    description: 'List cloud LLM providers and active config',
    group: 'cloud',
  ),

  YoloitCliTool(
    command: 'cloud:add',
    alias: 'cpa',
    description: 'Add a cloud LLM provider config',
    group: 'cloud',
    params: <YoloitCliToolParam>[
      toolParam('name', 'Provider display name', required: true, shortKey: 'n'),
      toolParam('url', 'API base URL', required: true, flag: '--url', shortKey: 'u'),
      toolParam('key', 'API key', required: true, flag: '--key', shortKey: 'k'),
      toolParam(
        'model',
        'Model identifier',
        required: true,
        flag: '--model',
        shortKey: 'm',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'cloud:remove',
    alias: 'cpr',
    description: 'Remove a cloud provider config by id',
    group: 'cloud',
    destructive: true,
    params: <YoloitCliToolParam>[
      toolParam('id', 'Config id', required: true, shortKey: 'id'),
    ],
  ),

  YoloitCliTool(
    command: 'cloud:select',
    alias: 'cps',
    description: 'Set the active cloud provider config',
    group: 'cloud',
    params: <YoloitCliToolParam>[
      toolParam('id', 'Config id', required: true, shortKey: 'id'),
    ],
  ),

  YoloitCliTool(
    command: 'cloud:update',
    alias: 'cpu',
    description: 'Update fields of an existing cloud provider config',
    group: 'cloud',
    params: <YoloitCliToolParam>[
      toolParam('id', 'Config id', required: true, shortKey: 'id'),
      toolParam('name', 'New display name', flag: '--name', shortKey: 'n'),
      toolParam('url', 'New base URL', flag: '--url', shortKey: 'u'),
      toolParam('key', 'New API key', flag: '--key', shortKey: 'k'),
      toolParam('model', 'New model id', flag: '--model', shortKey: 'm'),
    ],
  ),

  YoloitCliTool(
    command: 'cloud:provider',
    alias: 'cpp',
    description: 'Get or set assistant provider type (cloud only)',
    group: 'cloud',
    params: <YoloitCliToolParam>[
      toolParam(
        'provider',
        'Provider type (omit to show current)',
        enumValues: const <String>['cloud'],
        shortKey: 'p',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'links',
    alias: 'lls',
    description: 'List links on a board',
    group: 'link',
    params: <YoloitCliToolParam>[boardParam()],
  ),

  YoloitCliTool(
    command: 'web:open',
    alias: 'wop',
    description: 'Open URL in webpage panel',
    group: 'webpage',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('url', 'URL to open', required: true, shortKey: 'u'),
    ],
  ),

  YoloitCliTool(
    command: 'timer:create',
    alias: 'tmr',
    description: 'Create and optionally start a timer',
    group: 'timer',
    humanVariants: const {
      'ru': [
        'поставь таймер на {duration} секунд',
        'таймер {duration}',
        'засеки {duration}',
        'создай таймер {label}',
      ],
      'en': [
        'set timer for {duration} seconds',
        'timer {duration}',
        'start a timer {label}',
        'create timer {label}',
      ],
    },
    params: <YoloitCliToolParam>[
      toolParam('duration', 'Duration in seconds (default 300)', shortKey: 'd'),
      toolParam('label', 'Timer label text', shortKey: 'l'),
      toolParam('start', 'Start timer immediately', shortKey: 's'),
    ],
  ),

  const YoloitCliTool(
    command: 'app:list',
    alias: 'myapps',
    description: 'List installed apps and which are currently running',
    group: 'app',
  ),

  YoloitCliTool(
    command: 'app:install',
    alias: 'wgi',
    description: 'Install an app from a local path or URL',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam(
        'source',
        'Path to app directory or .js file, or URL',
        required: true,
        shortKey: 's',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'app:remove',
    alias: 'wgrm',
    description: 'Remove an installed app by id',
    group: 'app',
    destructive: true,
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id', required: true, shortKey: 'i'),
    ],
  ),

  YoloitCliTool(
    command: 'app:run',
    alias: 'wgo',
    description:
        'Open an app in a new panel on a board. '
        'Then use app:help, app:state, or app:snapshot to read app data.',
    group: 'app',
    humanVariants: const {
      'ru': [
        'запусти приложение {id_or_path}',
        'открой {id_or_path}',
        'запусти {id_or_path}',
        'покажи погоду',
        'какая погода',
      ],
      'en': [
        'run app {id_or_path}',
        'open app {id_or_path}',
        'launch {id_or_path}',
        'show weather',
        'what is the weather',
      ],
    },
    params: <YoloitCliToolParam>[
      toolParam(
        'id_or_path',
        'App id or local directory path',
        required: true,
        shortKey: 'i',
      ),
      boardParam(),
      toolParam('panel_title', 'Panel title (optional)', shortKey: 'pt'),
    ],
  ),

  YoloitCliTool(
    command: 'app:create',
    alias: 'wgnew',
    description: 'Scaffold a new app in the apps directory',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('name', 'App id/name', required: true, shortKey: 'n'),
      toolParam(
        'template',
        'Template: basic|network|yoloit (default: basic)',
        shortKey: 't',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'app:help',
    alias: 'aphlp',
    description:
        'Show CLI commands, events, and examples for a specific app. '
        'Call this before app:execute when unsure which events exist.',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id', required: true, shortKey: 'i'),
    ],
  ),

  YoloitCliTool(
    command: 'app:state',
    alias: 'apst',
    description:
        'Read structured state (yoloit.exportState) and visible text from a running app. '
        'Preferred over app:snapshot for weather, prices, calculator values.',
    group: 'app',
    humanVariants: const {
      'ru': [
        'сколько градусов',
        'какая температура',
        'температура в {city}',
        'погода в {city}',
      ],
      'en': [
        'how many degrees',
        'what is the temperature',
        'weather in {city}',
      ],
    },
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id', required: true, shortKey: 'i'),
    ],
  ),

  YoloitCliTool(
    command: 'app:execute',
    alias: 'apexec',
    description:
        'Execute a JS event in a running app. '
        'Weather city change: set_city \'{"city":"Grodno"}\' then app:state.',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id', required: true, shortKey: 'i'),
      toolParam(
        'action',
        'Action id (e.g. btn_5, refresh)',
        required: true,
        shortKey: 'a',
      ),
      toolParam('payload', 'JSON payload string (optional)', shortKey: 'p'),
    ],
  ),

  YoloitCliTool(
    command: 'app:reload',
    alias: 'apref',
    description: 'Hot-reload a running app (re-reads JS from disk)',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id', required: true, shortKey: 'i'),
    ],
  ),

  YoloitCliTool(
    command: 'app:logs',
    alias: 'aplog',
    description: 'Show console.log output from a running app',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id or local directory path', required: true, shortKey: 'i'),
      toolParam('f', 'Follow/stream logs continuously', shortKey: 'f'),
    ],
  ),

  YoloitCliTool(
    command: 'app:snapshot',
    alias: 'apsnap',
    description:
        'Get the JSON render tree of a running app plus extracted text lines. '
        'Use app:state first when the app exports structured data.',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id', required: true, shortKey: 'i'),
    ],
  ),

  YoloitCliTool(
    command: 'app:screenshot',
    alias: 'apss',
    description:
        'Save a PNG screenshot of a running app panel (panel must be visible on screen). '
        'Prefer app:snapshot for the JSON render tree when headless.',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('id', 'App id', required: true, shortKey: 'i'),
      toolParam('output', 'Output PNG path (default: /tmp/<id>.png)', shortKey: 'o'),
    ],
  ),

  const YoloitCliTool(
    command: 'app:dev-skill',
    alias: 'apdocs',
    description:
        'Print the full YoLoIT app development guide (JS API, node types, examples). Useful for AI agents writing apps.',
    group: 'app',
  ),

  const YoloitCliTool(
    command: 'app:demo',
    alias: 'apdemo',
    description:
        'List built-in demo apps with their local paths. Use app:demo-view <id> to read a full example.',
    group: 'app',
  ),

  YoloitCliTool(
    command: 'app:demo-view',
    alias: 'apdemov',
    description:
        'Show the full source (manifest.json + widget.js) of a built-in demo app. Great for learning patterns before writing a new app.',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam(
        'id',
        'Demo app id (from app:demo list)',
        required: true,
        shortKey: 'i',
      ),
    ],
  ),

  const YoloitCliTool(
    command: 'theme',
    alias: 'thm',
    description: 'Show current theme info (preset, brightness, overrides)',
    group: 'app',
  ),

  const YoloitCliTool(
    command: 'theme:presets',
    alias: 'thmp',
    description: 'List all available theme presets (built-in and custom)',
    group: 'app',
  ),

  YoloitCliTool(
    command: 'theme:set',
    alias: 'thms',
    description:
        'Set the active theme preset. '
        'Use preset id for built-in themes or custom id for user-imported themes.',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam(
        'preset',
        'Preset id or custom theme id',
        required: true,
        shortKey: 'p',
        enumValues: <String>[
          'neonPurple',
          'cyberGreen',
          'deepBlue',
          'solarOrange',
          'crimsonRed',
          'islandsDark',
          'islandsLight',
        ],
      ),
    ],
  ),

  YoloitCliTool(
    command: 'theme:brightness',
    alias: 'thmb',
    description: 'Set theme brightness mode',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam(
        'brightness',
        'Brightness mode',
        required: true,
        shortKey: 'b',
        enumValues: <String>['dark', 'light'],
      ),
    ],
  ),

  YoloitCliTool(
    command: 'theme:color',
    alias: 'thmc',
    description:
        'Set a color override for a specific theme slot. '
        'Use theme:slots to see available slot names.',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam(
        'slot',
        'Color slot name (e.g. primary, accentGreen)',
        required: true,
        shortKey: 's',
      ),
      toolParam('color', 'Hex color (e.g. #548AF7)', required: true, shortKey: 'c'),
    ],
  ),

  YoloitCliTool(
    command: 'theme:reset-color',
    alias: 'thmrc',
    description: 'Remove a color override, reverting slot to theme default',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('slot', 'Color slot name', required: true, shortKey: 's'),
    ],
  ),

  const YoloitCliTool(
    command: 'theme:reset-all',
    alias: 'thmra',
    description: 'Clear all color overrides, reverting to base theme',
    group: 'app',
  ),

  YoloitCliTool(
    command: 'theme:save',
    alias: 'thmsa',
    description:
        'Save current theme (with any overrides) as a named custom preset',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('name', 'Name for the new preset', required: true, shortKey: 'n'),
    ],
  ),

  const YoloitCliTool(
    command: 'theme:export',
    alias: 'thmex',
    description: 'Export current theme as JSON to stdout',
    group: 'app',
  ),

  YoloitCliTool(
    command: 'theme:import',
    alias: 'thmim',
    description: 'Import a theme file (JSON, ICLS, or XML) and activate it',
    group: 'app',
    params: <YoloitCliToolParam>[
      toolParam('path', 'Path to theme file', required: true, shortKey: 'p'),
    ],
  ),

  YoloitCliTool(
    command: 'theme:delete',
    alias: 'thmd',
    description: 'Delete a custom theme by id',
    group: 'app',
    destructive: true,
    params: <YoloitCliToolParam>[toolParam('id', 'Custom theme id', required: true)],
  ),

  const YoloitCliTool(
    command: 'theme:colors',
    alias: 'thmcl',
    description: 'Show all effective color values for the current theme',
    group: 'app',
  ),

  const YoloitCliTool(
    command: 'theme:slots',
    alias: 'thmsl',
    description: 'Show available color slot names grouped by category',
    group: 'app',
  ),

];
