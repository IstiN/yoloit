#!/usr/bin/env python3
"""Quality gate: every panel type must have a test that exercises a write path.

The script:
  1. Extracts panel type IDs from built-in plugin files.
  2. Parses // covers-write: type1, type2, ... annotations in test files.
  3. Validates scripts/panel_write_exempt.json (mandatory reason per exempt type).
  4. Fails if any panel type is neither covered nor exempt.

Add a test and annotate it with e.g.:
    // covers-write: board.note.markdown, board.sticky
Or, for panel types that cannot be exercised headlessly, add an exemption
with a clear reason to scripts/panel_write_exempt.json.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_DIR = ROOT / 'lib/features/board/plugins/builtin'
EXTRA_PLUGIN_FILES = [
    ROOT / 'lib/features/board/chat/chat_panel_plugin.dart',
    ROOT / 'lib/features/board/terminal/board_terminal_panel_plugin.dart',
]
TEST_DIRS = [
    ROOT / 'test/integration',
    ROOT / 'test/widget',
    ROOT / 'test/unit',
    ROOT / 'test/core',
]
EXEMPT_FILE = ROOT / 'scripts/panel_write_exempt.json'

TYPE_ID_RE = re.compile(r"static const(?:\s+\w+)?\s+kTypeId\s*=\s*['\"]([^'\"]+)['\"]")
ANNOTATION_RE = re.compile(r'//\s*covers-write:\s*(.+)')
SPLIT_RE = re.compile(r'[\s,]+')


def discover_panel_types() -> set[str]:
    types: set[str] = set()
    for path in PLUGIN_DIR.glob('*_plugin.dart'):
        text = path.read_text()
        for match in TYPE_ID_RE.finditer(text):
            types.add(match.group(1))
    for path in EXTRA_PLUGIN_FILES:
        text = path.read_text()
        for match in TYPE_ID_RE.finditer(text):
            types.add(match.group(1))
    return types


def parse_annotations() -> set[str]:
    covered: set[str] = set()
    for test_dir in TEST_DIRS:
        if not test_dir.exists():
            continue
        for path in test_dir.rglob('*.dart'):
            text = path.read_text()
            for match in ANNOTATION_RE.finditer(text):
                for token in SPLIT_RE.split(match.group(1).strip()):
                    if token:
                        covered.add(token)
    return covered


def load_exemptions() -> dict[str, str]:
    if not EXEMPT_FILE.exists():
        return {}
    data = json.loads(EXEMPT_FILE.read_text())
    if not isinstance(data, list):
        sys.exit(f'{EXEMPT_FILE} must be a JSON list of {{"type":..., "reason":...}}')
    result: dict[str, str] = {}
    for entry in data:
        t = entry.get('type')
        reason = entry.get('reason', '').strip()
        if not t or not isinstance(t, str):
            sys.exit(f'{EXEMPT_FILE} entry missing valid "type": {entry}')
        if not reason:
            sys.exit(f'{EXEMPT_FILE} entry missing "reason" for type {t}')
        result[t] = reason
    return result


def main() -> int:
    all_types = discover_panel_types()
    covered = parse_annotations()
    exempt = load_exemptions()

    invalid_exempt = set(exempt) - all_types
    if invalid_exempt:
        print(f'ERROR: {EXEMPT_FILE} contains unknown panel types:')
        for t in sorted(invalid_exempt):
            print(f'  - {t}')
        return 1

    missing = sorted(all_types - covered - set(exempt))

    print('=' * 70)
    print('Panel write-coverage report')
    print('=' * 70)
    print(f'  Total panel types : {len(all_types)}')
    print(f'  Covered           : {len(covered & all_types)}')
    print(f'  Exempt            : {len(exempt)}')
    print(f'  Missing           : {len(missing)}')
    print('=' * 70)

    if missing:
        print('\nMISSING PANEL WRITE COVERAGE:')
        for t in missing:
            print(f'  - {t}')
        print(
            '\nAdd a test annotated with // covers-write: <type> or add an '
            f'exemption with reason to {EXEMPT_FILE}.'
        )
        return 1

    print('\nAll panel types have write coverage or a documented exemption.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
