#!/usr/bin/env python3
"""Generate training data and routing prompt from command catalog YAML files.

Usage:
    python3 tools/generate_catalog.py [--jsonl] [--prompt] [--stats] [--train]

Reads all YAML files from assets/command_catalog/ and generates:
  - training_data.jsonl: raw JSONL pairs (input→output)
  - training/train.jsonl: chat-format training data for MLX fine-tuning
  - training/valid.jsonl: chat-format validation data
  - routing_prompt.txt: compact system prompt for inference
"""

import yaml
import json
import os
import glob
import sys
import re
import random
import hashlib
from itertools import product as iter_product

CATALOG_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets', 'command_catalog')
TRAINING_DIR = os.path.join(CATALOG_DIR, 'training')

SYSTEM_PROMPT = 'Route user text to YoLoIT CLI command. Reply ONLY JSON: {"c":"CMD","a":["ARG"]}. No markdown, no thinking, no explanation.'

# Multiple sample values per parameter for augmentation
PARAM_SAMPLES = {
    'title': ['тест', 'покупки', 'Work', 'My Tasks', 'идеи', 'Проект', 'Sprint 1',
              'заметки', 'Backlog', 'Daily', 'Important', 'weekly report',
              'купить молоко', 'купить кефир', 'список дел', 'план на неделю',
              'заметки с митинга', 'grocery list', 'meeting notes', 'bug fixes',
              'сходить в магазин', 'позвонить маме', 'отправить отчёт'],
    'panel': ['p-123', 'Заметки', 'My Note', 'panel-chat', 'Dev Notes', 'Todo List',
              'Builds', 'p-42', 'Meeting Notes', 'Release Plan'],
    'board': ['MyBoard', '__SMOKE__', 'Work', 'Main Board', 'Planning', 'Retro',
              'Product', 'Sprint', 'Releases', 'Personal'],
    'text': ['hello world', 'купить молоко', 'remember this', 'fix bug #42',
             'call meeting at 3pm', 'review PR #123', 'send report',
             'заметки с митинга', 'обновить зависимости', 'check deploy status'],
    'item': ['молоко', 'хлеб', 'buy milk', 'call John', 'review PR',
             'fix tests', 'deploy', 'write docs', 'send email', 'update README',
             'купить кефир', 'позвонить маме', 'сходить за хлебом',
             'забрать посылку', 'оплатить счёт', 'pick up groceries',
             'book a meeting', 'check server logs'],
    'name': ['Work', 'Done', 'Проект', 'Sprint 1', 'Backlog', 'Archive',
             'In Progress', 'Blocked', 'Review', 'Testing'],
    'new_title': ['Новое', 'Updated', 'Задачи', 'Daily Notes', 'Sprint Plan',
                  'Release Notes', 'Итоги', 'Прогресс'],
    'new_name': ['Done', 'In Progress', 'Готово', 'Blocked', 'Review', 'Archive'],
    'x': ['100', '500', '0', '200', '800'],
    'y': ['200', '300', '0', '150', '600'],
    'width': ['400', '600', '800', '1024'],
    'height': ['300', '500', '400', '768'],
    'color': ['blue', 'red', 'green', '#FF0000', '#33aaff', 'yellow', 'purple', '#ffcc00'],
    'url': ['https://google.com', 'https://ya.ru', 'https://github.com',
            'https://example.com', 'https://docs.flutter.dev'],
    'file': ['song.mp3', 'video.mp4', 'demo.wav', 'podcast.mp3'],
    'duration': ['300', '60', '600', '1800', '120', '30'],
    'label': ['Break', 'Работа', 'timer', 'Focus', 'Обед', 'Meeting'],
    'session': ['ses-1', 'run-abc', 'flutter-app', 'dev-server', 'build-1'],
    'from': ['p-1', 'panel-1', 'Plan', 'Todo'],
    'to': ['p-2', 'panel-2', 'Build', 'Done'],
    'link_id': ['l-1', 'link-42', 'l-99'],
    'style': ['dashed', 'solid', 'arrow', 'dotted'],
    'geometry': ['curved', 'straight', 'elbow'],
    'column': ['Todo', 'Сделать', 'Backlog', 'In Progress'],
    'to_column': ['Done', 'Готово', 'Review', 'Blocked'],
    'card_id': ['c-1', 'card-123', 'card-7', 'c-99'],
    'id': ['my-app', 'weather', 'calculator', 'dashboard'],
    'id_or_path': ['my-app', '/path/to/app', 'weather-widget', 'counter'],
    'source': ['https://gist.github.com/x', 'https://github.com/user/repo'],
    'action': ['click', 'submit', 'refresh', 'reset'],
    'model_id': ['qwen3-0.6b-4bit', 'gemma4-e2b-it-4bit', 'qwen3-8b-4bit',
                 'llama3-8b-4bit'],
    'kind': ['chat', 'asr', 'tts'],
    'message': ['hello', 'привет', 'status update please', 'что нового'],
    'query': ['weather', 'news', 'docs', 'api'],
    'id_or_name': ['MyBoard', 'board-main', 'Work', '__SMOKE__'],
    'scale': ['1.0', '1.25', '0.5', '1.5', '2.0'],
    'format': ['detailed', 'short', 'mermaid', 'tools'],
    'new_title': ['Новое', 'Updated Title', 'Задачи', 'Sprint Plan'],
}

# Prefixes to prepend for augmentation (used sparingly)
RU_PREFIXES = ['', 'пожалуйста ', 'ну ']
EN_PREFIXES = ['', 'please ', 'can you ']

# Case/punctuation transforms
def augment_text(text, lang):
    """Generate augmented versions of text."""
    variants = [text]
    # Lowercase
    low = text.lower()
    if low != text:
        variants.append(low)
    # No trailing punctuation
    stripped = text.rstrip('.!?')
    if stripped != text:
        variants.append(stripped)
    # Add punctuation variants (period, exclamation, question)
    base = text.rstrip('.!?')
    if not text.endswith('.'):
        variants.append(base + '.')
    if not text.endswith('!') and random.random() < 0.3:
        variants.append(base + '!')
    return list(set(variants))


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


def count_param_combos(text):
    """Count how many parameter combinations are possible for a template."""
    params = re.findall(r'\{(\w+)\}', text)
    if not params:
        return 1
    combos = 1
    for p in params:
        combos *= len(PARAM_SAMPLES.get(p, [p]))
    return combos


def generate_all_param_combos(text, max_combos=6):
    """Generate multiple parameter fill variants for a template."""
    params = re.findall(r'\{(\w+)\}', text)
    if not params:
        return [(text, [])]

    param_values = [PARAM_SAMPLES.get(p, [p]) for p in params]

    # If total combos is small, use all; otherwise sample
    total = 1
    for pv in param_values:
        total *= len(pv)

    if total <= max_combos:
        combos = list(iter_product(*param_values))
    else:
        combos_set = set()
        # Always include index 0
        combos_set.add(tuple(pv[0] for pv in param_values))
        attempts = 0
        while len(combos_set) < max_combos and attempts < max_combos * 10:
            combo = tuple(random.choice(pv) for pv in param_values)
            combos_set.add(combo)
            attempts += 1
        combos = list(combos_set)

    results = []
    for combo in combos:
        result = text
        args = []
        for p, val in zip(params, combo):
            result = result.replace('{' + p + '}', val, 1)
            args.append(val)
        results.append((result, list(args)))
    return results


def make_chat_example(user_text, cmd_id, args):
    """Create a chat-format training example."""
    output = json.dumps({'c': cmd_id, 'a': args}, ensure_ascii=False)
    return {
        'messages': [
            {'role': 'system', 'content': SYSTEM_PROMPT},
            {'role': 'user', 'content': user_text},
            {'role': 'assistant', 'content': output},
        ]
    }


def generate_training_data(commands):
    """Generate comprehensive training data with augmentation."""
    examples = []
    seen = set()

    for cmd in commands:
        cmd_id = cmd['id']
        for lang in ['ru', 'en']:
            variants = cmd.get('human', {}).get(lang, [])
            prefixes = RU_PREFIXES if lang == 'ru' else EN_PREFIXES

            for template in variants:
                # Generate multiple param combos per template
                has_params = bool(re.findall(r'\{(\w+)\}', template))
                max_c = 3 if has_params else 1
                param_fills = generate_all_param_combos(template, max_combos=max_c)

                for filled, args in param_fills:
                    # Generate augmented text variants
                    text_variants = augment_text(filled, lang)

                    for text in text_variants:
                        # Base text always included
                        key = hashlib.md5(text.encode()).hexdigest()
                        if key not in seen:
                            seen.add(key)
                            examples.append(make_chat_example(text, cmd_id, args))
                        # Add one random prefix variant (not all)
                        if prefixes and random.random() < 0.3:
                            prefix = random.choice([p for p in prefixes if p])
                            full_text = prefix + text
                            key2 = hashlib.md5(full_text.encode()).hexdigest()
                            if key2 not in seen:
                                seen.add(key2)
                                examples.append(make_chat_example(full_text, cmd_id, args))

    random.shuffle(examples)
    return examples


def generate_jsonl(commands):
    """Generate simple JSONL training data (legacy format)."""
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
    cmd_ids = sorted(set(c['id'] for c in commands))

    examples = [
        ('создай заметку покупки', 'note:create', ['покупки']),
        ('add a note reminders', 'note:create', ['reminders']),
        ('удали панель p-123', 'panel:delete', ['p-123']),
        ('покажи панели', 'panels', []),
        ('что на борде', 'panels', []),
        ('покажи борды', 'boards', []),
        ('добавь в чеклист молоко', 'checklist:add', ['молоко']),
        ('открой борд Work', 'board:focus', ['Work']),
        ('поставь таймер 5 минут', 'timer:create', ['Break', '300']),
        ('перезагрузи', 'reload', []),
        ('открой сайт google.com', 'web:open', ['https://google.com']),
        ('покажи приложения', 'app:list', []),
        ('list apps', 'app:list', []),
        ('помощь', 'help', []),
        ('what can you do', 'help', []),
        ('покажи модели', 'models:list', []),
        ('create checklist groceries', 'checklist:new', ['groceries']),
        ('add card buy milk to Todo', 'kanban:add-card', ['buy milk', 'Todo']),
        ('list models', 'models:list', []),
        ('rename board Work to Planning', 'board:rename', ['Work', 'Planning']),
        ('текущий борд', 'board:current', []),
        ('напиши в чат привет', 'yolochat:send', ['привет']),
        ('покажи связи', 'links', []),
        ('скриншот борда Work', 'board:screenshot', ['Work']),
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
    random.seed(42)
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
        print(f'   Total raw variants: {total_ru + total_en}')

    if do_all or '--jsonl' in flags:
        jsonl = generate_jsonl(commands)
        out_path = os.path.join(CATALOG_DIR, 'training_data.jsonl')
        with open(out_path, 'w') as f:
            for line in jsonl:
                f.write(json.dumps(line, ensure_ascii=False) + '\n')
        print(f'✅ Generated {len(jsonl)} raw training examples → {out_path}')

    if do_all or '--train' in flags:
        os.makedirs(TRAINING_DIR, exist_ok=True)
        all_examples = generate_training_data(commands)
        total = len(all_examples)

        # 90/10 train/valid split
        split = int(total * 0.9)
        train = all_examples[:split]
        valid = all_examples[split:]

        train_path = os.path.join(TRAINING_DIR, 'train.jsonl')
        valid_path = os.path.join(TRAINING_DIR, 'valid.jsonl')
        for path, data in [(train_path, train), (valid_path, valid)]:
            with open(path, 'w') as f:
                for ex in data:
                    f.write(json.dumps(ex, ensure_ascii=False) + '\n')

        # Stats per command
        cmd_counts = {}
        for ex in all_examples:
            out = json.loads(ex['messages'][2]['content'])
            c = out['c']
            cmd_counts[c] = cmd_counts.get(c, 0) + 1

        print(f'✅ Generated {total} augmented training examples')
        print(f'   Train: {len(train)} → {train_path}')
        print(f'   Valid: {len(valid)} → {valid_path}')
        print(f'   Commands covered: {len(cmd_counts)}')
        # Show low-coverage commands
        low = [(c, n) for c, n in sorted(cmd_counts.items()) if n < 15]
        if low:
            print(f'   ⚠️  Low coverage (<15 examples):')
            for c, n in low:
                print(f'      {c}: {n}')

    if do_all or '--prompt' in flags:
        prompt = generate_routing_prompt(commands)
        out_path = os.path.join(CATALOG_DIR, 'routing_prompt.txt')
        with open(out_path, 'w') as f:
            f.write(prompt)
        print(f'✅ Generated routing prompt ({len(prompt)} chars) → {out_path}')


if __name__ == '__main__':
    main()
