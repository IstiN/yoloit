#!/usr/bin/env python3
"""Generate training data and routing prompt from command catalog YAML files.

Usage:
    python3 tools/generate_catalog.py [--jsonl] [--prompt] [--stats]

Reads all YAML files from assets/command_catalog/ and generates:
  - training_data.jsonl: JSONL pairs for fine-tuning (input→output)
  - routing_prompt.txt: compact system prompt for few-shot inference
"""

import yaml
import json
import os
import glob
import sys
import re

CATALOG_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets', 'command_catalog')

PARAM_SAMPLES = {
    'title': ['тест', 'покупки', 'Work', 'My Tasks', 'идеи'],
    'panel': ['p-123', 'Заметки', 'My Note'],
    'board': ['MyBoard', '__SMOKE__', 'Work'],
    'text': ['hello world', 'купить молоко', 'remember this'],
    'item': ['молоко', 'хлеб', 'buy milk', 'call John'],
    'name': ['Work', 'Done', 'Проект'],
    'new_title': ['Новое', 'Updated', 'Задачи'],
    'new_name': ['Done', 'In Progress', 'Готово'],
    'x': ['100', '500'], 'y': ['200', '300'],
    'width': ['400', '600'], 'height': ['300', '500'],
    'color': ['blue', 'red', 'green', '#FF0000'],
    'url': ['https://google.com', 'https://ya.ru'],
    'file': ['song.mp3', 'video.mp4'],
    'duration': ['300', '60', '600'],
    'label': ['Break', 'Работа', 'timer'],
    'session': ['ses-1', 'run-abc'],
    'from': ['p-1', 'panel-1'], 'to': ['p-2', 'panel-2'],
    'link_id': ['l-1'], 'style': ['dashed', 'solid'],
    'geometry': ['curved', 'straight'],
    'column': ['Todo', 'Сделать'], 'to_column': ['Done', 'Готово'],
    'card_id': ['c-1', 'card-123'],
    'id': ['my-app', 'weather'], 'id_or_path': ['my-app', '/path/to/app'],
    'source': ['https://gist.github.com/x'],
    'action': ['click', 'submit'], 'model_id': ['qwen3-0.6b-4bit', 'gemma4-e2b-it-4bit'],
    'kind': ['chat', 'asr'], 'message': ['hello', 'привет'],
    'query': ['weather', 'news'],
}


def load_catalog():
    """Load all YAML catalog files and return list of command entries."""
    commands = []
    for f in sorted(glob.glob(os.path.join(CATALOG_DIR, '*.yaml'))):
        with open(f) as fh:
            data = yaml.safe_load(fh)
        if not data or 'commands' not in data:
            continue
        for cmd in data['commands']:
            cmd['_source'] = os.path.basename(f)
            commands.append(cmd)
    return commands


def fill_params(text, use_index=0):
    """Replace {param} placeholders with sample values. Returns (filled_text, args_list)."""
    args = []
    params = re.findall(r'\{(\w+)\}', text)
    result = text
    for p in params:
        samples = PARAM_SAMPLES.get(p, [p])
        val = samples[use_index % len(samples)]
        result = result.replace('{' + p + '}', val, 1)
        args.append(val)
    return result, args


def generate_jsonl(commands):
    """Generate JSONL training data."""
    lines = []
    for cmd in commands:
        for lang in ['ru', 'en']:
            variants = cmd.get('human', {}).get(lang, [])
            for vi, v in enumerate(variants):
                filled, args = fill_params(v, 0)
                line = {
                    'input': filled,
                    'output': json.dumps(
                        {'c': cmd['id'], 'a': args},
                        ensure_ascii=False
                    ),
                }
                lines.append(line)
    return lines


def generate_routing_prompt(commands):
    """Generate compact routing system prompt."""
    # Build command list
    cmd_ids = sorted(set(c['id'] for c in commands))
    
    # Select representative examples (mix of ru/en, with/without params)
    examples = [
        ('создай заметку покупки', 'note:create', ['покупки']),
        ('add a note reminders', 'note:create', ['reminders']),
        ('удали панель p-123', 'panel:delete', ['p-123']),
        ('покажи панели', 'panels', []),
        ('что на борде', 'panels', []),
        ('покажи борды', 'boards', []),
        ('добавь в чеклист молоко', 'checklist:add', ['молоко']),
        ('открой борд Work', 'board:open', ['Work']),
        ('поставь таймер 5 минут', 'timer:create', ['timer', '300']),
        ('перезагрузи', 'reload', []),
        ('открой сайт google.com', 'web:open', ['https://google.com']),
        ('покажи приложения', 'app:list', []),
        ('list apps', 'app:list', []),
        ('помощь', 'help', []),
        ('what can you do', 'help', []),
        ('покажи модели', 'models:list', []),
        ('create checklist groceries', 'checklist:new', ['groceries']),
        ('удали все заметки', 'panel:delete', ['all-notes']),
        ('add card "buy milk" to Todo', 'kanban:add-card', ['buy milk', 'Todo']),
        ('list models', 'models:list', []),
    ]
    
    lines = [
        'Route user text to CLI command. Reply ONLY valid JSON: {"c":"CMD","a":["ARG"]}',
        'No markdown, no explanation, no backticks. Just the JSON object.',
        '',
        'Commands (CMD ARGS):',
        '|'.join(cmd_ids),
        '',
        'Examples:',
    ]
    for text, cmd, args in examples:
        out = json.dumps({'c': cmd, 'a': args}, ensure_ascii=False)
        lines.append(f'"{text}"→{out}')
    
    return '\n'.join(lines)


def main():
    commands = load_catalog()
    
    flags = set(sys.argv[1:])
    do_all = not flags or flags == {'--all'}
    
    if do_all or '--stats' in flags:
        total_ru = sum(len(c.get('human', {}).get('ru', [])) for c in commands)
        total_en = sum(len(c.get('human', {}).get('en', [])) for c in commands)
        sources = set(c.get('_source', '') for c in commands)
        print(f'📊 Catalog stats:')
        print(f'   Commands: {len(commands)}')
        print(f'   Files: {len(sources)} ({", ".join(sorted(sources))})')
        print(f'   RU variants: {total_ru}')
        print(f'   EN variants: {total_en}')
        print(f'   Total variants: {total_ru + total_en}')
    
    if do_all or '--jsonl' in flags:
        jsonl = generate_jsonl(commands)
        out_path = os.path.join(CATALOG_DIR, 'training_data.jsonl')
        with open(out_path, 'w') as f:
            for line in jsonl:
                f.write(json.dumps(line, ensure_ascii=False) + '\n')
        print(f'✅ Generated {len(jsonl)} training examples → {out_path}')
    
    if do_all or '--prompt' in flags:
        prompt = generate_routing_prompt(commands)
        out_path = os.path.join(CATALOG_DIR, 'routing_prompt.txt')
        with open(out_path, 'w') as f:
            f.write(prompt)
        print(f'✅ Generated routing prompt ({len(prompt)} chars) → {out_path}')


if __name__ == '__main__':
    main()
