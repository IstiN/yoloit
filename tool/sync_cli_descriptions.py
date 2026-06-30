#!/usr/bin/env python3
"""Sync tools/yoloit registry descriptions from Dart YoloitCliTool definitions."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CLI_TOOLS_DIR = REPO / 'lib/features/board/chat/cli_tools'
YOLOIT = REPO / 'tools/yoloit'

BASH_ONLY = {
    'reload': 'Hot reload the running Flutter app',
    'restart': 'Hot restart the running Flutter app',
    'help': 'Show CLI help',
    'remote:connect': 'Connect this CLI to a remote yoloitd daemon',
    'remote:disconnect': 'Return CLI to the local desktop app server',
    'remote:status': 'Show current remote connection status',
}


def py_string(value: str) -> str:
    if "'" not in value:
        return f"'{value}'"
    return json.dumps(value, ensure_ascii=False)


def extract_description(block: str) -> str:
    m = re.search(
        r"description:\s*(.*?)(?:,\s*\n\s*(?:group|params|alias|humanVariants|destructive):)",
        block,
        re.S,
    )
    if not m:
        return ''
    chunk = m.group(1)
    if "'''" in chunk:
        tm = re.search(r"'''(.*?)'''", chunk, re.S)
        if tm:
            return tm.group(1).strip()
    parts = re.findall(r"'((?:\\'|[^'])*)'", chunk)
    return ''.join(p.replace("\\'", "'") for p in parts).strip()


def parse_dart_tools() -> dict[str, str]:
    descriptions: dict[str, str] = {}
    for path in sorted(CLI_TOOLS_DIR.glob('*.dart')):
        text = path.read_text(encoding='utf-8')
        for block in re.split(r'YoloitCliTool\(', text)[1:]:
            cm = re.search(r"command:\s*'([^']+)'", block)
            if not cm:
                continue
            cmd = cm.group(1)
            desc = extract_description(block)
            if desc:
                descriptions[cmd] = desc
    return descriptions


def patch_registry(content: str, descriptions: dict[str, str]) -> tuple[str, int, list[str]]:
    updated = 0
    missing: list[str] = []
    for name, desc in descriptions.items():
        patterns = [
            re.compile(
                r"('name':\s*'"
                + re.escape(name)
                + r"',\s*'description':\s*)(?:'(?:\\'|[^'])*'(?:\s*\n\s*'(?:\\'|[^'])*')*|\"(?:\\\"|[^\"])*\")"
            ),
            re.compile(
                r"(\{'name':\s*'"
                + re.escape(name)
                + r"',\s*'group':\s*'[^']+',\s*'description':\s*)(?:'(?:\\'|[^'])*'(?:\s*\n\s*'(?:\\'|[^'])*')*|\"(?:\\\"|[^\"])*\")"
            ),
        ]
        replaced = False
        for pattern in patterns:
            new_content, count = pattern.subn(r'\1' + py_string(desc), content, count=1)
            if count:
                content = new_content
                updated += 1
                replaced = True
                break
        if not replaced:
            missing.append(name)
    return content, updated, missing


def main() -> int:
    check_only = '--check' in sys.argv
    descriptions = {**BASH_ONLY, **parse_dart_tools()}
    original = YOLOIT.read_text(encoding='utf-8')
    patched, updated, missing = patch_registry(original, descriptions)

    if check_only:
        if patched != original:
            print('❌ tools/yoloit descriptions out of sync. Run: python3 tool/sync_cli_descriptions.py')
            return 1
        print(f'✅ CLI descriptions in sync ({updated} entries checked).')
        if missing:
            print('⚠️  Not in registry:', ', '.join(sorted(missing)[:20]))
        return 0

    YOLOIT.write_text(patched, encoding='utf-8')
    print(f'Synced {updated} descriptions into tools/yoloit')
    if missing:
        print('⚠️  Not in registry:', ', '.join(sorted(missing)[:30]))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
