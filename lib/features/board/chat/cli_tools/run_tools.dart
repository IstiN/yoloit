import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

final List<YoloitCliTool> runTools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'run:list',
    alias: 'rls',
    description:
        'List run configs and sessions. If the user names a panel, pass that exact panel title.',
    group: 'run',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'run:input',
    alias: 'rin',
    description: 'Send stdin to a run session',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'session',
        'Session id, config id, or name',
        required: true,
        shortKey: 's',
      ),
      toolParam('text', 'Input text', required: true, shortKey: 'tx'),
      toolParam(
        'enter',
        'Append newline',
        flag: '--enter',
        kind: YoloitCliToolParamKind.boolean,
        shortKey: 'e',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'run:output',
    alias: 'rot',
    description: 'Read run session output',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('session', 'Session id, config id, or name', shortKey: 's'),
    ],
  ),

  YoloitCliTool(
    command: 'terminal:output',
    alias: 'tout',
    description:
        'Read the latest output from an interactive terminal panel. '
        'Pass the panel title or id; the session is resolved automatically.',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'session',
        'Optional terminal session id override',
        shortKey: 's',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'terminal:set-dir',
    alias: 'tsd',
    description: 'Set the working directory of an interactive terminal panel',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'dir',
        'Working directory path',
        required: true,
        shortKey: 'd',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'terminal:set-session',
    description: 'Attach a terminal panel to an existing session id',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('sessionId', 'Terminal session id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'run:detach',
    alias: 'rdt',
    description: 'Detach run session from panel',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('session', 'Session id, config id, or name', shortKey: 's'),
    ],
  ),

  YoloitCliTool(
    command: 'run:attach',
    alias: 'rat',
    description: 'Attach run console to a session',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('session', 'Session id, config id, or name', shortKey: 's'),
      toolParam(
        'any',
        'Allow stopped sessions',
        flag: '--any',
        kind: YoloitCliToolParamKind.boolean,
        shortKey: 'ay',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'run:popout',
    alias: 'rpo',
    description: 'Open detached session in a new Run panel',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('session', 'Session id, config id, or name', shortKey: 's'),
    ],
  ),

  YoloitCliTool(
    command: 'run:set-group',
    description:
        'Set the run session group scope for a board.run panel (not run_configs)',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('group', 'Group id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'run:select-session',
    description: 'Focus a run session tab in a board.run panel',
    group: 'run',
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam('sessionId', 'Run session id', required: true),
    ],
  ),

  YoloitCliTool(
    command: 'run:clear-session',
    description: 'Clear the focused run session tab in a board.run panel',
    group: 'run',
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'play',
    alias: 'play',
    description:
        'START or RESUME music/audio playback in a playlist panel. Use ONLY when the user wants to START playing — not for pause, stop, listing tracks, or showing the panel. Examples: "включи музыку", "play music", "resume", "продолжи воспроизведение".',
    group: 'playlist',
    humanVariants: const {
      'ru': [
        'включи музыку',
        'воспроизведи плейлист',
        'продолжи музыку',
        'запусти плейлист',
      ],
      'en': [
        'play music',
        'start playlist',
        'resume playlist',
        'continue playback',
      ],
    },
    params: <YoloitCliToolParam>[
      boardParam(),
      panelParam(),
      toolParam(
        'file_or_url',
        'Media file path or URL',
        required: false,
        aliases: const ['path', 'url'],
        shortKey: 'u',
      ),
    ],
  ),

  YoloitCliTool(
    command: 'pause',
    alias: 'pause',
    description:
        'PAUSE music playback (temporary stop, can be resumed). Use for "пауза", "поставь на паузу", "поставь музыку на паузу", "pause music", "приостанови". NOT for stopping completely or showing playlist.',
    group: 'playlist',
    humanVariants: const {
      'ru': [
        'поставь на паузу',
        'пауза музыка',
        'приостанови воспроизведение',
        'поставь музыку на паузу',
      ],
      'en': ['pause music', 'pause playback', 'pause playlist'],
    },
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'stop',
    alias: 'stop',
    description:
        'STOP music playback completely (resets to beginning). Use for "останови", "выключи музыку", "стоп", "stop music". NOT for pause or listing tracks.',
    group: 'playlist',
    humanVariants: const {
      'ru': ['останови музыку', 'стоп музыка', 'выключи музыку'],
      'en': ['stop music', 'stop playback', 'stop playlist'],
    },
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'next',
    alias: 'next',
    description: 'Skip to the next track in the playlist',
    group: 'playlist',
    humanVariants: const {
      'ru': ['следующая песня', 'следующий трек', 'переключи на следующую'],
      'en': ['next song', 'next track', 'skip to next'],
    },
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'prev',
    alias: 'prev',
    description: 'Go to the previous track in the playlist',
    group: 'playlist',
    humanVariants: const {
      'ru': ['предыдущая песня', 'предыдущий трек', 'переключи на предыдущую'],
      'en': ['previous song', 'previous track', 'go back a song'],
    },
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

  YoloitCliTool(
    command: 'playlist:list',
    alias: 'pll',
    description:
        'SHOW/LIST tracks in a playlist panel. Use for "покажи плейлист", "что в плейлисте", "список треков", "show playlist", "list tracks". NOT for playing music.',
    group: 'playlist',
    humanVariants: const {
      'ru': ['покажи плейлист', 'что в плейлисте', 'список треков'],
      'en': ['show playlist', 'list playlist', 'what is in playlist'],
    },
    params: <YoloitCliToolParam>[boardParam(), panelParam()],
  ),

];
