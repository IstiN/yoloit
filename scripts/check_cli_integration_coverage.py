#!/usr/bin/env python3
"""CLI integration-test coverage gate.

This script enumerates every command (and alias) registered in the YoLoIT CLI,
expects each one to be either:

1. explicitly covered by an integration test in test/integration/ via a
   `// covers: <command>, <command>, ...` annotation, or
2. listed in scripts/cli_integration_exempt.json with a mandatory reason.

If any command is neither covered nor exempt, the script exits with a non-zero
status and prints a report, blocking the commit.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
CLI_TOOL = REPO_ROOT / 'tools' / 'yoloit'
EXEMPT_FILE = REPO_ROOT / 'scripts' / 'cli_integration_exempt.json'
INTEGRATION_DIR = REPO_ROOT / 'test' / 'integration'

COVERS_RE = re.compile(r'//\s*covers:\s*(.+)')
SPLIT_RE = re.compile(r'[\s,]+')


def load_registry() -> List[dict]:
    """Return the CLI command registry as a list of command entries."""
    result = subprocess.run(
        ['bash', str(CLI_TOOL), 'help', '--format', 'registry'],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f'ERROR: failed to load CLI registry: {result.stderr}', file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(f'ERROR: invalid registry JSON: {exc}', file=sys.stderr)
        sys.exit(1)


def parse_coverage_annotations(test_dir: Path) -> Set[str]:
    """Collect canonical command names/aliases mentioned in // covers: lines."""
    covered: Set[str] = set()
    if not test_dir.exists():
        return covered
    for path in test_dir.rglob('*.dart'):
        text = path.read_text(encoding='utf-8')
        for match in COVERS_RE.finditer(text):
            for token in SPLIT_RE.split(match.group(1).strip()):
                if token:
                    covered.add(token)
    return covered


def load_exemptions(path: Path) -> Tuple[Dict[str, str], List[str]]:
    """Return a mapping of canonical command -> reason, plus validation errors."""
    if not path.exists():
        return {}, []
    try:
        raw = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as exc:
        return {}, [f'{path}: invalid JSON: {exc}']
    if not isinstance(raw, list):
        return {}, [f'{path}: expected a JSON list of exemptions']
    mapping: Dict[str, str] = {}
    errors: List[str] = []
    for idx, entry in enumerate(raw):
        if not isinstance(entry, dict):
            errors.append(f'{path}[{idx}]: expected an object')
            continue
        command = entry.get('command')
        reason = entry.get('reason')
        if not command or not isinstance(command, str):
            errors.append(f'{path}[{idx}]: missing or invalid "command"')
            continue
        if not reason or not isinstance(reason, str) or not reason.strip():
            errors.append(f'{path}[{idx}]: missing or invalid "reason" for {command}')
            continue
        mapping[command.strip()] = reason.strip()
    return mapping, errors


def main() -> int:
    registry = load_registry()

    canonical_by_name: Dict[str, dict] = {}
    alias_to_canonical: Dict[str, str] = {}
    for entry in registry:
        name = entry.get('name')
        if not name:
            continue
        canonical_by_name[name] = entry
        for alias in entry.get('aliases', []) or []:
            alias_to_canonical[alias] = name

    all_canonical = set(canonical_by_name.keys())

    raw_exempt, exempt_errors = load_exemptions(EXEMPT_FILE)
    exempt_canonical: Dict[str, str] = {}
    for command, reason in raw_exempt.items():
        canonical = alias_to_canonical.get(command, command)
        if canonical not in canonical_by_name:
            exempt_errors.append(
                f'{EXEMPT_FILE}: unknown command "{command}" in exemptions'
            )
            continue
        exempt_canonical[canonical] = reason

    covered_tokens = parse_coverage_annotations(INTEGRATION_DIR)
    covered_canonical: Set[str] = set()
    for token in covered_tokens:
        canonical = alias_to_canonical.get(token, token)
        if canonical in canonical_by_name:
            covered_canonical.add(canonical)

    missing = sorted(all_canonical - covered_canonical - set(exempt_canonical.keys()))
    only_exempt = sorted(set(exempt_canonical.keys()))
    only_covered = sorted(covered_canonical)

    if exempt_errors:
        print('ERROR: invalid exemption file:')
        for error in exempt_errors:
            print(f'  - {error}')
        return 1

    width = 72
    print('=' * width)
    print('CLI integration-test coverage report')
    print('=' * width)
    print(f'  Total CLI commands : {len(all_canonical)}')
    print(f'  Covered            : {len(only_covered)}')
    print(f'  Exempt             : {len(only_exempt)}')
    print(f'  Missing            : {len(missing)}')
    print('=' * width)

    if missing:
        print()
        print('UNCOVERED COMMANDS (add a test or an exemption):')
        for name in missing:
            entry = canonical_by_name[name]
            aliases = entry.get('aliases', []) or []
            alias_str = f"  (aliases: {', '.join(aliases)})" if aliases else ''
            print(f'  - {name}{alias_str}')
        print()
        print('To fix:')
        print('  1. Add an integration test in test/integration/ and annotate it with')
        print('     // covers: <command>, <command>, ...')
        print('  OR')
        print('  2. Add an entry to scripts/cli_integration_exempt.json with a reason.')
        return 1

    if only_exempt:
        print()
        print('EXEMPT COMMANDS (review periodically):')
        for name in only_exempt:
            print(f'  - {name}: {exempt_canonical[name]}')

    print()
    print('All CLI commands are covered by integration tests or have an exemption.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
