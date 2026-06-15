#!/usr/bin/env python3
"""Patch tools/yoloit to add top-level CLI wrappers for panel actions.

Reads tools/yoloit, appends new entries to the JSON help catalog and adds
bash case branches that delegate to `yoloit do <board> <panel> <action> <json>`.
"""
import ast
import pprint
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
YOLOIT_SCRIPT = REPO_ROOT / 'tools' / 'yoloit'


def _extract_first_python_heredoc(source: str) -> str:
    start = source.find("<<'PYEOF'")
    if start == -1:
        raise RuntimeError('PYEOF start not found')
    newline = source.find('\n', start)
    if newline == -1:
        raise RuntimeError('Malformed PYEOF start')
    end = source.find('\nPYEOF', newline)
    if end == -1:
        raise RuntimeError('PYEOF end not found')
    return source[newline + 1:end]


def _replace_heredoc(source: str, new_block: str) -> str:
    start = source.find("<<'PYEOF'")
    newline = source.find('\n', start)
    end = source.find('\nPYEOF', newline)
    return source[:newline + 1] + new_block + source[end:]


def _load_commands(source: str) -> list[dict]:
    py = _extract_first_python_heredoc(source)
    module = ast.parse(py)
    for node in ast.walk(module):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == 'commands':
                    return ast.literal_eval(node.value)
    raise RuntimeError('commands assignment not found')


def _replace_commands(source: str, commands: list[dict]) -> str:
    py_block = _extract_first_python_heredoc(source)
    match = re.search(r'commands\s*=\s*\[', py_block)
    if not match:
        raise RuntimeError('Could not locate commands assignment')
    start = match.start()
    bracket = 0
    in_string = None
    escape = False
    i = start
    while i < len(py_block):
        ch = py_block[i]
        if escape:
            escape = False
        elif ch == '\\':
            escape = True
        elif in_string:
            if ch == in_string:
                in_string = None
        elif ch in '"\'':
            in_string = ch
        elif ch == '[':
            bracket += 1
        elif ch == ']':
            bracket -= 1
            if bracket == 0:
                end = i + 1
                break
        i += 1
    else:
        raise RuntimeError('Could not find matching close bracket for commands')
    serialized = 'commands = ' + pprint.pformat(commands, width=120, sort_dicts=False)
    new_py_block = py_block[:start] + serialized + py_block[end:]
    return _replace_heredoc(source, new_py_block)


def _do_case(name: str, usage: str, action: str, body: str) -> str:
    return f'''  {name})
    {body}
    ;;'''


def _simple_do(action: str, json_expr: str = '{}') -> str:
    return f'''json=$(python3 -c "import json,sys; print(json.dumps({json_expr}))")
    "$0" do "$board" "$panel" {action} "$json"'''


def _board_panel_case(name: str, usage: str, action: str, json_expr: str = '{}') -> str:
    return _do_case(
        name, usage, action,
        f'''[[ $# -lt 2 ]] && {{ echo "Usage: yoloit {usage}" >&2; exit 1; }}
    board="$1"; panel="$2"; _use_board "$board"
    {_simple_do(action, json_expr)}''',
    )


def _positional_case(name: str, usage: str, action: str, param_name: str, json_expr: str) -> str:
    return _do_case(
        name, usage, action,
        f'''[[ $# -lt 3 ]] && {{ echo "Usage: yoloit {usage}" >&2; exit 1; }}
    board="$1"; panel="$2"; arg="$3"; _use_board "$board"
    json=$(python3 -c "import json,sys; print(json.dumps({json_expr}))" "$arg")
    "$0" do "$board" "$panel" {action} "$json"''',
    )


def _flag_case(name: str, usage: str, action: str, flags: list[tuple[str, str, str]]) -> str:
    """flags: [(python_key, shell_var, default_expr)]"""
    init = '\n    '.join(f'{var}={default}' for _, var, default in flags)
    parse_cases = '\n        '.join(
        f'{flag}) {var}="${{2:-}}"; shift 2 ;;'
        for flag, var, _ in flags
    )
    expr_items = ', '.join(f"'{key}': {var}" for key, var, _ in flags)
    return _do_case(
        name, usage, action,
        f'''[[ $# -lt 2 ]] && {{ echo "Usage: yoloit {usage}" >&2; exit 1; }}
    board="$1"; panel="$2"; shift 2
    _use_board "$board"
    {init}
    while [[ $# -gt 0 ]]; do
      case "$1" in
        {parse_cases}
        *) shift ;;
      esac
    done
    json=$(python3 -c "import json,sys; print(json.dumps({{{expr_items}}}))")
    "$0" do "$board" "$panel" {action} "$json"''',
    )


NEW_COMMANDS: list[dict] = []
BASH_CASES: list[str] = []


def add(cmd: dict, case: str) -> None:
    NEW_COMMANDS.append(cmd)
    BASH_CASES.append(case)


# Timer
add(
    {'group': 'timer', 'name': 'timer:status', 'description': 'Show timer status', 'params': [['board', 'Board id or name', True], ['panel', 'Timer panel id or title', True]], 'example': 'yoloit timer:status "My Board" "Timer"'},
    _board_panel_case('timer:status', 'timer:status <board> <panel>', 'status'),
)
add(
    {'group': 'timer', 'name': 'timer:set', 'description': 'Set timer duration and label without starting', 'params': [['board', 'Board id or name', True], ['panel', 'Timer panel id or title', True], ['duration', 'Duration in seconds', False], ['--label', 'Timer label text', False]], 'example': 'yoloit timer:set "My Board" "Timer" 600 --label "Pomodoro"'},
    _flag_case('timer:set', 'timer:set <board> <panel> [duration] [--label text]', 'set', [('duration', 'duration', '0'), ('label', 'label', '""')]),
)
add(
    {'group': 'timer', 'name': 'timer:start', 'description': 'Start (or restart) the timer', 'params': [['board', 'Board id or name', True], ['panel', 'Timer panel id or title', True], ['duration', 'Duration in seconds', False], ['--label', 'Timer label text', False]], 'example': 'yoloit timer:start "My Board" "Timer" 600'},
    _flag_case('timer:start', 'timer:start <board> <panel> [duration] [--label text]', 'start', [('duration', 'duration', '0'), ('label', 'label', '""')]),
)
add(
    {'group': 'timer', 'name': 'timer:pause', 'description': 'Pause the running timer', 'params': [['board', 'Board id or name', True], ['panel', 'Timer panel id or title', True]], 'example': 'yoloit timer:pause "My Board" "Timer"'},
    _board_panel_case('timer:pause', 'timer:pause <board> <panel>', 'pause'),
)
add(
    {'group': 'timer', 'name': 'timer:resume', 'description': 'Resume a paused timer', 'params': [['board', 'Board id or name', True], ['panel', 'Timer panel id or title', True]], 'example': 'yoloit timer:resume "My Board" "Timer"'},
    _board_panel_case('timer:resume', 'timer:resume <board> <panel>', 'resume'),
)
add(
    {'group': 'timer', 'name': 'timer:reset', 'description': 'Reset timer to full duration', 'params': [['board', 'Board id or name', True], ['panel', 'Timer panel id or title', True]], 'example': 'yoloit timer:reset "My Board" "Timer"'},
    _board_panel_case('timer:reset', 'timer:reset <board> <panel>', 'reset'),
)

# Webpage
add(
    {'group': 'webpage', 'name': 'web:get', 'description': 'Get webpage panel state', 'params': [['board', 'Board id or name', True], ['panel', 'Web panel id or title', True]], 'example': 'yoloit web:get "My Board" "Web"'},
    _board_panel_case('web:get', 'web:get <board> <panel>', 'get'),
)
add(
    {'group': 'webpage', 'name': 'web:exec', 'description': 'Execute JavaScript in the panel WebView', 'params': [['board', 'Board id or name', True], ['panel', 'Web panel id or title', True], ['js', 'JavaScript source', True]], 'example': 'yoloit web:exec "My Board" "Web" "document.title"'},
    _positional_case('web:exec', 'web:exec <board> <panel> <js>', 'exec', 'js', "{'js': sys.argv[1]}"),
)
add(
    {'group': 'webpage', 'name': 'web:content', 'description': 'Return the current page HTML', 'params': [['board', 'Board id or name', True], ['panel', 'Web panel id or title', True]], 'example': 'yoloit web:content "My Board" "Web"'},
    _board_panel_case('web:content', 'web:content <board> <panel>', 'content'),
)
add(
    {'group': 'webpage', 'name': 'web:title', 'description': 'Return the current page title', 'params': [['board', 'Board id or name', True], ['panel', 'Web panel id or title', True]], 'example': 'yoloit web:title "My Board" "Web"'},
    _board_panel_case('web:title', 'web:title <board> <panel>', 'title'),
)
add(
    {'group': 'webpage', 'name': 'web:url', 'description': 'Return the current live URL from the WebView', 'params': [['board', 'Board id or name', True], ['panel', 'Web panel id or title', True]], 'example': 'yoloit web:url "My Board" "Web"'},
    _board_panel_case('web:url', 'web:url <board> <panel>', 'url'),
)
add(
    {'group': 'webpage', 'name': 'web:scroll', 'description': 'Scroll the page to or by coordinates', 'params': [['board', 'Board id or name', True], ['panel', 'Web panel id or title', True], ['x', 'Horizontal offset (default 0)', False], ['y', 'Vertical offset (default 0)', False], ['--by', 'Use scrollBy instead of scrollTo', False]], 'example': 'yoloit web:scroll "My Board" "Web" 0 500'},
    _flag_case('web:scroll', 'web:scroll <board> <panel> [x] [y] [--by]', 'scroll', [('x', 'x', '0'), ('y', 'y', '0'), ('by', 'by_mode', 'false')]),
)
add(
    {'group': 'webpage', 'name': 'web:click', 'description': 'Click the first element matching a CSS selector', 'params': [['board', 'Board id or name', True], ['panel', 'Web panel id or title', True], ['selector', 'CSS selector', True]], 'example': 'yoloit web:click "My Board" "Web" "button.submit"'},
    _positional_case('web:click', 'web:click <board> <panel> <selector>', 'click', 'selector', "{'selector': sys.argv[1]}"),
)

# Terminal
add(
    {'group': 'panel', 'name': 'terminal:output', 'description': 'Read terminal output', 'params': [['board', 'Board id or name', True], ['panel', 'Terminal panel id or title', True], ['session', 'Session id or name', False]], 'example': 'yoloit terminal:output "My Board" "Terminal"'},
    _positional_case('terminal:output', 'terminal:output <board> <panel> [session]', 'output', 'sessionId', "{'sessionId': sys.argv[1]}"),
)
add(
    {'group': 'panel', 'name': 'terminal:config', 'description': 'Get terminal configuration', 'params': [['board', 'Board id or name', True], ['panel', 'Terminal panel id or title', True]], 'example': 'yoloit terminal:config "My Board" "Terminal"'},
    _board_panel_case('terminal:config', 'terminal:config <board> <panel>', 'config'),
)
add(
    {'group': 'panel', 'name': 'terminal:set-dir', 'description': 'Set terminal working directory', 'params': [['board', 'Board id or name', True], ['panel', 'Terminal panel id or title', True], ['dir', 'Working directory', True]], 'example': 'yoloit terminal:set-dir "My Board" "Terminal" ~/project'},
    _positional_case('terminal:set-dir', 'terminal:set-dir <board> <panel> <dir>', 'set-dir', 'dir', "{'dir': sys.argv[1]}"),
)

# Run configs
add(
    {'group': 'run', 'name': 'run:add', 'description': 'Add a run configuration', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['name', 'Configuration name', True], ['command', 'Shell command', True], ['--working-dir', 'Working directory', False], ['--flutter', 'Mark as flutter run', False]], 'example': 'yoloit run:add "My Board" "Run" "Test" "flutter test"'},
    _flag_case('run:add', 'run:add <board> <panel> <name> <command> [--working-dir path] [--flutter]', 'add', [('name', 'name', '""'), ('command', 'command', '""'), ('workingDir', 'working_dir', '""'), ('isFlutterRun', 'is_flutter', 'false')]),
)
add(
    {'group': 'run', 'name': 'run:update', 'description': 'Update a run configuration', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['id|name', 'Configuration id or name', True], ['--name', 'New name', False], ['--command', 'New command', False], ['--working-dir', 'Working directory', False], ['--flutter', 'Mark as flutter run', False]], 'example': 'yoloit run:update "My Board" "Run" "Test" --command "flutter test integration_test"'},
    _flag_case('run:update', 'run:update <board> <panel> <id|name> [--name text] [--command text] [--working-dir path] [--flutter]', 'update', [('id', 'id', '""'), ('newName', 'new_name', 'None'), ('command', 'command', 'None'), ('workingDir', 'working_dir', 'None'), ('isFlutterRun', 'is_flutter', 'None')]),
)
add(
    {'group': 'run', 'name': 'run:remove', 'description': 'Remove a run configuration', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['id|name', 'Configuration id or name', True]], 'example': 'yoloit run:remove "My Board" "Run" "Test"'},
    _positional_case('run:remove', 'run:remove <board> <panel> <id|name>', 'remove', 'id', "{'id': sys.argv[1]}"),
)
add(
    {'group': 'run', 'name': 'run:run', 'description': 'Start a run configuration', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['id|name', 'Configuration id or name', True]], 'example': 'yoloit run:run "My Board" "Run" "macOS"'},
    _positional_case('run:run', 'run:run <board> <panel> <id|name>', 'run', 'id', "{'id': sys.argv[1]}"),
)
add(
    {'group': 'run', 'name': 'run:stop', 'description': 'Stop a running session', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['sessionId|id|name', 'Session or config selector', True]], 'example': 'yoloit run:stop "My Board" "Run" "macOS"'},
    _positional_case('run:stop', 'run:stop <board> <panel> <sessionId|id|name>', 'stop', 'id', "{'id': sys.argv[1]}"),
)
add(
    {'group': 'run', 'name': 'run:config', 'description': 'Show run configuration details', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['id|name', 'Configuration id or name', True]], 'example': 'yoloit run:config "My Board" "Run" "macOS"'},
    _positional_case('run:config', 'run:config <board> <panel> <id|name>', 'config', 'id', "{'id': sys.argv[1]}"),
)
add(
    {'group': 'run', 'name': 'run:close', 'description': 'Remove a run session tab from the panel', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['sessionId|id|name', 'Session or config selector', True]], 'example': 'yoloit run:close "My Board" "Run" sess_123'},
    _positional_case('run:close', 'run:close <board> <panel> <sessionId|id|name>', 'close', 'id', "{'sessionId': sys.argv[1], 'id': sys.argv[1], 'name': sys.argv[1]}"),
)
add(
    {'group': 'run', 'name': 'run:logs', 'description': 'Read the full output of a run session', 'params': [['board', 'Board id or name', True], ['panel', 'Run panel id or title', True], ['sessionId|id|name', 'Session or config selector', True], ['--limit', 'Maximum number of output lines', False]], 'example': 'yoloit run:logs "My Board" "Run" sess_123 --limit 100'},
    _do_case(
        'run:logs',
        'run:logs <board> <panel> <sessionId|id|name> [--limit N]',
        'logs',
        '''[[ $# -lt 3 ]] && { echo "Usage: yoloit run:logs <board> <panel> <sessionId|id|name> [--limit N]" >&2; exit 1; }
    board="$1"; panel="$2"; target="$3"; shift 3
    _use_board "$board"
    limit="null"
    if [[ "$1" == "--limit" && -n "$2" ]]; then limit="$2"; shift 2; fi
    json=$(python3 -c "import json,sys; print(json.dumps({'sessionId': sys.argv[1], 'id': sys.argv[1], 'name': sys.argv[1], 'limit': int(sys.argv[2]) if sys.argv[2] != 'null' else None}))" "$target" "$limit")
    "$0" do "$board" "$panel" logs "$json"''',
    ),
)

# Note
add(
    {'group': 'note', 'name': 'note:get', 'description': 'Read note content', 'params': [['board', 'Board id or name', True], ['panel', 'Note panel id or title', True]], 'example': 'yoloit note:get "My Board" "Notes"', 'alias_override': 'n:g'},
    _board_panel_case('note:get|n:g', 'note:get <board> <panel>', 'get'),
)

# Checklist
add(
    {'group': 'checklist', 'name': 'checklist:items', 'description': 'List checklist items', 'params': [['board', 'Board id or name', True], ['panel', 'Checklist panel id or title', True]], 'example': 'yoloit checklist:items "My Board" "Shopping"', 'alias_override': 'cl:ls'},
    _board_panel_case('checklist:items|cl:ls', 'checklist:items <board> <panel>', 'items'),
)
add(
    {'group': 'checklist', 'name': 'checklist:remove', 'description': 'Remove a checklist item', 'params': [['board', 'Board id or name', True], ['panel', 'Checklist panel id or title', True], ['item', 'Item text', True]], 'example': 'yoloit checklist:remove "My Board" "Shopping" "milk"', 'alias_override': 'cl:rm'},
    _positional_case('checklist:remove|cl:rm', 'checklist:remove <board> <panel> <item>', 'remove', 'item', "{'item': sys.argv[1]}"),
)
add(
    {'group': 'checklist', 'name': 'checklist:rename', 'description': 'Rename a checklist item', 'params': [['board', 'Board id or name', True], ['panel', 'Checklist panel id or title', True], ['old', 'Current item text', True], ['new', 'New item text', True]], 'example': 'yoloit checklist:rename "My Board" "Shopping" "milk" "oat milk"', 'alias_override': 'cl:rn'},
    _do_case(
        'checklist:rename|cl:rn',
        'checklist:rename <board> <panel> <old> <new>',
        'rename',
        '''[[ $# -lt 4 ]] && { echo "Usage: yoloit checklist:rename <board> <panel> <old> <new>" >&2; exit 1; }
    board="$1"; panel="$2"; old="$3"; new="$4"; _use_board "$board"
    json=$(python3 -c "import json,sys; print(json.dumps({'item': sys.argv[1], 'newItem': sys.argv[2]}))" "$old" "$new")
    "$0" do "$board" "$panel" rename "$json"''',
    ),
)

# Kanban
add(
    {'group': 'kanban', 'name': 'kanban:send-card-to-chat', 'description': 'Send a kanban card to a chat panel', 'params': [['board', 'Board id or name', True], ['panel', 'Kanban panel id or title', True], ['cardId', 'Card id', True]], 'example': 'yoloit kanban:send-card-to-chat "My Board" "Kanban" card_123', 'alias_override': 'k:sc'},
    _positional_case('kanban:send-card-to-chat|k:sc', 'kanban:send-card-to-chat <board> <panel> <cardId>', 'send-card-to-chat', 'cardId', "{'cardId': sys.argv[1]}"),
)

# Filetree
add(
    {'group': 'panel', 'name': 'filetree:list', 'description': 'List file tree nodes', 'params': [['board', 'Board id or name', True], ['panel', 'File tree panel id or title', True]], 'example': 'yoloit filetree:list "My Board" "Project Tree"'},
    _board_panel_case('filetree:list', 'filetree:list <board> <panel>', 'list'),
)
add(
    {'group': 'panel', 'name': 'filetree:open', 'description': 'Open a path in the file tree panel', 'params': [['board', 'Board id or name', True], ['panel', 'File tree panel id or title', True], ['path', 'File or folder path', True]], 'example': 'yoloit filetree:open "My Board" "Project Tree" lib/main.dart'},
    _positional_case('filetree:open', 'filetree:open <board> <panel> <path>', 'open', 'path', "{'path': sys.argv[1]}"),
)
add(
    {'group': 'panel', 'name': 'filetree:expand', 'description': 'Expand a file tree node', 'params': [['board', 'Board id or name', True], ['panel', 'File tree panel id or title', True], ['path', 'File or folder path', True]], 'example': 'yoloit filetree:expand "My Board" "Project Tree" lib'},
    _positional_case('filetree:expand', 'filetree:expand <board> <panel> <path>', 'expand', 'path', "{'path': sys.argv[1]}"),
)
add(
    {'group': 'panel', 'name': 'filetree:collapse', 'description': 'Collapse a file tree node', 'params': [['board', 'Board id or name', True], ['panel', 'File tree panel id or title', True], ['path', 'File or folder path', True]], 'example': 'yoloit filetree:collapse "My Board" "Project Tree" lib'},
    _positional_case('filetree:collapse', 'filetree:collapse <board> <panel> <path>', 'collapse', 'path', "{'path': sys.argv[1]}"),
)
add(
    {'group': 'panel', 'name': 'filetree:refresh', 'description': 'Refresh file tree contents', 'params': [['board', 'Board id or name', True], ['panel', 'File tree panel id or title', True]], 'example': 'yoloit filetree:refresh "My Board" "Project Tree"'},
    _board_panel_case('filetree:refresh', 'filetree:refresh <board> <panel>', 'refresh'),
)

# Playlist
add(
    {'group': 'playlist', 'name': 'playlist:add', 'description': 'Add a track to a playlist', 'params': [['board', 'Board id or name', True], ['panel', 'Playlist panel id or title', True], ['path', 'Track file or URL', True]], 'example': 'yoloit playlist:add "My Board" music ~/song.mp3'},
    _positional_case('playlist:add', 'playlist:add <board> <panel> <path>', 'add', 'path', "{'path': sys.argv[1]}"),
)
add(
    {'group': 'playlist', 'name': 'playlist:remove', 'description': 'Remove a track from a playlist', 'params': [['board', 'Board id or name', True], ['panel', 'Playlist panel id or title', True], ['index', 'Track index', True]], 'example': 'yoloit playlist:remove "My Board" music 2'},
    _positional_case('playlist:remove', 'playlist:remove <board> <panel> <index>', 'remove', 'index', "{'index': int(sys.argv[1])}"),
)

# Sticky note
add(
    {'group': 'note', 'name': 'sticky:get', 'description': 'Read sticky note content', 'params': [['board', 'Board id or name', True], ['panel', 'Sticky panel id or title', True]], 'example': 'yoloit sticky:get "My Board" "Idea"'},
    _board_panel_case('sticky:get', 'sticky:get <board> <panel>', 'get'),
)
add(
    {'group': 'note', 'name': 'sticky:set', 'description': 'Set sticky note text', 'params': [['board', 'Board id or name', True], ['panel', 'Sticky panel id or title', True], ['text', 'Note text', True]], 'example': 'yoloit sticky:set "My Board" "Idea" "Buy milk"'},
    _positional_case('sticky:set', 'sticky:set <board> <panel> <text>', 'set', 'text', "{'text': sys.argv[1]}"),
)
add(
    {'group': 'note', 'name': 'sticky:append', 'description': 'Append text to a sticky note', 'params': [['board', 'Board id or name', True], ['panel', 'Sticky panel id or title', True], ['text', 'Text to append', True]], 'example': 'yoloit sticky:append "My Board" "Idea" " tomorrow"'},
    _positional_case('sticky:append', 'sticky:append <board> <panel> <text>', 'append', 'text', "{'text': sys.argv[1]}"),
)
add(
    {'group': 'note', 'name': 'sticky:color', 'description': 'Set sticky note color', 'params': [['board', 'Board id or name', True], ['panel', 'Sticky panel id or title', True], ['color', 'Hex color', True]], 'example': 'yoloit sticky:color "My Board" "Idea" #FEF08A'},
    _positional_case('sticky:color', 'sticky:color <board> <panel> <color>', 'color', 'color', "{'color': sys.argv[1]}"),
)

# Shape
add(
    {'group': 'note', 'name': 'shape:get', 'description': 'Get shape panel state', 'params': [['board', 'Board id or name', True], ['panel', 'Shape panel id or title', True]], 'example': 'yoloit shape:get "My Board" "Diamond"'},
    _board_panel_case('shape:get', 'shape:get <board> <panel>', 'get'),
)
add(
    {'group': 'note', 'name': 'shape:set', 'description': 'Set shape panel properties', 'params': [['board', 'Board id or name', True], ['panel', 'Shape panel id or title', True], ['--text', 'Label text', False], ['--fill', 'Fill color', False], ['--stroke', 'Stroke color', False], ['--stroke-width', 'Stroke width', False]], 'example': 'yoloit shape:set "My Board" "Diamond" --text "Go"'},
    _flag_case('shape:set', 'shape:set <board> <panel> [--text text] [--fill #RRGGBB] [--stroke #RRGGBB] [--stroke-width N]', 'set', [('text', 'text', 'None'), ('fill', 'fill', 'None'), ('stroke', 'stroke', 'None'), ('strokeWidth', 'stroke_width', 'None')]),
)

# Code snippet
add(
    {'group': 'note', 'name': 'code:get', 'description': 'Get code snippet content', 'params': [['board', 'Board id or name', True], ['panel', 'Code snippet panel id or title', True]], 'example': 'yoloit code:get "My Board" "Snippet"'},
    _board_panel_case('code:get', 'code:get <board> <panel>', 'get'),
)
add(
    {'group': 'note', 'name': 'code:set', 'description': 'Set code snippet content', 'params': [['board', 'Board id or name', True], ['panel', 'Code snippet panel id or title', True], ['code', 'Code text', True]], 'example': 'yoloit code:set "My Board" "Snippet" "print(1)"'},
    _positional_case('code:set', 'code:set <board> <panel> <code>', 'set', 'code', "{'code': sys.argv[1]}"),
)

# Chat panel
add(
    {'group': 'yolochat', 'name': 'yolochat:config', 'description': 'Get chat panel configuration', 'params': [['--board', 'Board id or name', False], ['--panel', 'Chat panel id or title', False]], 'example': 'yoloit yolochat:config --board "My Board" --panel "AI Chat"'},
    _flag_case('yolochat:config', 'yolochat:config [--board id|name] [--panel id|title]', 'config', [('board', 'board', '""'), ('panel', 'panel', '""')]),
)
add(
    {'group': 'yolochat', 'name': 'yolochat:sessions', 'description': 'List active chat sessions', 'params': [['--board', 'Board id or name', False], ['--panel', 'Chat panel id or title', False]], 'example': 'yoloit yolochat:sessions --board "My Board" --panel "AI Chat"'},
    _flag_case('yolochat:sessions', 'yolochat:sessions [--board id|name] [--panel id|title]', 'sessions', [('board', 'board', '""'), ('panel', 'panel', '""')]),
)
add(
    {'group': 'yolochat', 'name': 'yolochat:follow-up', 'description': 'Set follow-up question suggestions', 'params': [['--board', 'Board id or name', False], ['--panel', 'Chat panel id or title', False], ['questions', 'Space-separated questions', True]], 'example': 'yoloit yolochat:follow-up --board "My Board" --panel "AI Chat" "Q1" "Q2"'},
    _do_case(
        'yolochat:follow-up',
        'yolochat:follow-up [--board id|name] [--panel id|title] <question>...',
        'set-follow-up',
        '''board=""; panel=""; questions=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --board) board="$2"; shift 2 ;;
        --panel) panel="$2"; shift 2 ;;
        *) questions+=("$1"); shift ;;
      esac
    done
    json=$(python3 -c "import json,sys; print(json.dumps({'questions': sys.argv[1:]}))" "${questions[@]}")
    "$0" do "$board" "$panel" set-follow-up "$json"''',
    ),
)


def main() -> int:
    if not YOLOIT_SCRIPT.exists():
        print(f'Not found: {YOLOIT_SCRIPT}', file=sys.stderr)
        return 1
    source = YOLOIT_SCRIPT.read_text(encoding='utf-8')
    commands = _load_commands(source)
    existing = {c['name'] for c in commands}
    added = [c for c in NEW_COMMANDS if c['name'] not in existing]
    if not added:
        print('No new commands to add')
    else:
        for c in added:
            group = c['group']
            idx = -1
            for i, existing_cmd in enumerate(commands):
                if existing_cmd['group'] == group:
                    idx = i
            if idx == -1:
                commands.append(c)
            else:
                commands.insert(idx + 1, c)
        source = _replace_commands(source, commands)

    marker = '''  validate)
    # Validate that the command registry matches bash case handlers AND Dart LLM tools.'''
    if marker not in source:
        print('Could not find validate case marker', file=sys.stderr)
        return 1
    cases_block = '\n'.join(BASH_CASES) + '\n'
    if cases_block.strip() not in source:
        source = source.replace(marker, cases_block + marker)
    else:
        print('Bash cases already present')

    YOLOIT_SCRIPT.write_text(source, encoding='utf-8')
    print(f'Patched {YOLOIT_SCRIPT} ({len(added)} new commands)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
