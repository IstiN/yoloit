#!/usr/bin/env python3
"""Generate the built-in yoloit skill from the CLI help data.

The skill content is derived from tools/yoloit so that new commands added to the
CLI help automatically appear in the skill shipped with the app.
"""
import argparse
import ast
import json
import re
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
YOLOIT_SCRIPT = REPO_ROOT / 'tools' / 'yoloit'
DEFAULT_OUT_FILE = REPO_ROOT / 'assets' / 'skills' / 'yoloit' / 'SKILL.md'


def _extract_first_python_heredoc(source: str) -> str:
    """Extract the first <<'PYEOF' ... PYEOF block (the help renderer)."""
    start = source.find("<<'PYEOF'")
    if start == -1:
        raise RuntimeError('PYEOF start not found in tools/yoloit')
    newline = source.find('\n', start)
    if newline == -1:
        raise RuntimeError('Malformed PYEOF start')
    end = source.find('\nPYEOF', newline)
    if end == -1:
        raise RuntimeError('PYEOF end not found in tools/yoloit')
    return source[newline + 1:end]


def _find_assign_value(module: ast.Module, name: str) -> object:
    for node in ast.walk(module):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == name:
                    return ast.literal_eval(node.value)
    raise RuntimeError(f'Assignment to {name} not found in help renderer')


def _load_commands() -> tuple[list[dict], list[str]]:
    source = YOLOIT_SCRIPT.read_text(encoding='utf-8')
    py = _extract_first_python_heredoc(source)
    module = ast.parse(py)
    commands = _find_assign_value(module, 'commands')
    group_order = _find_assign_value(module, 'group_order')
    return commands, group_order


def _param_key(name: str) -> str:
    raw = name.strip().split()[0].lstrip('-')
    raw = raw.replace('|', '_or_')
    key = re.sub(r'[^a-zA-Z0-9_]+', '_', raw)
    key = re.sub(r'_+', '_', key).strip('_').lower()
    return key or 'arg'


def _build_skill(commands: list[dict], group_order: list[str]) -> str:
    by_group: dict[str, list[dict]] = defaultdict(list)
    for c in commands:
        by_group[c.get('group', 'other')].append(c)

    lines: list[str] = []
    lines.append('---')
    lines.append('name: yoloit')
    lines.append('description: YoLoIT CLI-first board and panel automation skill')
    lines.append('---')
    lines.append('')
    lines.append('# YoLoIT')
    lines.append('')
    lines.append(
        'YoLoIT is a CLI-first desktop workspace. Everything — boards, panels, '
        'widgets, runs, chats — can be created, read, updated, and driven '
        'through the `yoloit` terminal command. Use this skill when you need to '
        'interact with the YoLoIT app on behalf of the user.'
    )
    lines.append('')
    lines.append('## Core concepts')
    lines.append('')
    lines.append(
        '- **Board**: an infinite canvas that contains panels. '
        '`yoloit boards`, `yoloit board:create`, `yoloit board:use`, '
        '`yoloit board:current`.'
    )
    lines.append(
        '- **Panel**: a typed widget on a board (note, terminal, kanban, chat, '
        'file tree, run configs, playlist, webpage, timer, drawing, etc.). '
        'Create with `yoloit panel:create <board> <type-id> <title>`.'
    )
    lines.append(
        '- **Group**: a visual/logical collection of panels. '
        '`yoloit group:create`, `yoloit group:collapse`, '
        '`yoloit group:expand`.'
    )
    lines.append(
        '- **App / Widget**: a custom JavaScript panel type. Develop with '
        '`yoloit app:dev-skill`, run with `yoloit app:run .`, reload with '
        '`yoloit app:reload .`.'
    )
    lines.append(
        '- **Run panel**: persistent long-running shell processes. Start via '
        'the panel actions discovered with '
        '`yoloit panel:help <board> <panel>`.'
    )
    lines.append(
        '- **AI Chat panel**: chat with local or cloud models. Send messages '
        'with `yoloit yolochat:send`.'
    )
    lines.append('')
    lines.append('## Command map')
    lines.append('')
    lines.append('```mermaid')
    lines.append('graph LR')
    lines.append('  root[yoloit]')
    for group in group_order:
        items = by_group.get(group, [])
        if not items:
            continue
        gid = f'g_{group}'
        lines.append(f'  root --> {gid}(("{group}"))')
        for i, c in enumerate(items):
            cid = f'{gid}_{i}'
            aliases = c.get('aliases', [])
            name_str = c['name']
            if aliases:
                name_str += f' · {" · ".join(aliases)}'
            name_str = name_str.replace('"', '\\"')
            lines.append(f'  {gid} --> {cid}["{name_str}"]')
    lines.append('```')
    lines.append('')
    lines.append('## Common commands')
    lines.append('')
    for group in group_order:
        items = by_group.get(group, [])
        if not items:
            continue
        lines.append(f'### {group}')
        for c in items:
            aliases = c.get('aliases', [])
            alias_str = f' *(aliases: {", ".join(aliases)})*' if aliases else ''
            lines.append(
                f'- **`{c["name"]}`**{alias_str} — {c["description"]}'
            )
            params = c.get('params')
            if params:
                param_str = ', '.join(
                    f'{p[0]}{"*" if p[2] else ""}' for p in params
                )
                lines.append(f'  - params: {param_str}')
            lines.append(f'  - example: `{c["example"]}`')
        lines.append('')
    lines.append('## Tool schemas')
    lines.append('')
    lines.append(
        'Run `yoloit help --format tools` for a machine-readable JSON catalog '
        'of every command with its aliases and input JSON schema. This is '
        'useful when exposing YoLoIT commands as LLM tools.'
    )
    lines.append('')
    lines.append('## Working patterns')
    lines.append('')
    lines.append(
        '1. Before creating an unknown panel type, call '
        '`yoloit panel:types "<board>"`.'
    )
    lines.append(
        '2. Discover dynamic actions for a panel with '
        '`yoloit panel:help "<board>" "<panel>"`, then execute with '
        '`yoloit do "<board>" "<panel>" <action> \'{...}\'`.'
    )
    lines.append(
        '3. Prefer `yoloit board:apply "<board>" flow.yaml` for multi-step '
        'mutations.'
    )
    lines.append(
        '4. Use `yoloit board:snapshot "<board>" --format mermaid` to '
        'understand layout.'
    )
    lines.append(
        '5. Long-running processes should be created as Run panels and started '
        'with `yoloit do`, not by blocking the terminal.'
    )
    lines.append('')
    return '\n'.join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Generate the built-in yoloit skill from tools/yoloit',
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=DEFAULT_OUT_FILE,
        help='Output SKILL.md path',
    )
    args = parser.parse_args()

    commands, group_order = _load_commands()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(_build_skill(commands, group_order), encoding='utf-8')
    print(f'Generated {args.output} ({len(commands)} commands)')


if __name__ == '__main__':
    main()
