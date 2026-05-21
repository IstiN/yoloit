# YoLoIT Command Catalog

## Purpose

Training data for a **tiny command router model** — instant voice/text → CLI command mapping (Siri-like UX).

## Architecture

```
User voice/text
       │
       ▼
┌─────────────────┐
│  Router Model    │  ← tiny (0.5-1B), fine-tuned, no thinking
│  (< 200ms)      │     Input: natural phrase
│                  │     Output: {command, params}
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  yoloit CLI      │  ← executes the command
└─────────────────┘
```

If the router returns `null` / low confidence → fall back to the full LLM (opencode/copilot).

## Single Source of Truth

Human variants live **inside `YoloitCliTool.humanVariants`** in Dart — same `_tools` list
that generates help, registry, tool schemas, and local function calls.

**When you add a new command, add `humanVariants`** right there. No separate file to forget.

```dart
YoloitCliTool(
  command: 'note:create',
  description: 'Create a new note panel',
  group: 'note',
  humanVariants: const {
    'ru': ['создай заметку {title}', 'добавь заметку {title}'],
    'en': ['create note {title}', 'add a note {title}'],
  },
  params: [_p('title', 'Note title', required: true)],
),
```

## Generating the Catalog

```bash
yoloit help --format catalog
```

This calls `GET /api/catalog` on the Dart server, which reads all `_tools` and
outputs JSON with commands that have `humanVariants` + coverage stats:

```json
{
  "commands": [
    {
      "command": "note:create",
      "group": "note",
      "description": "Create a new note panel",
      "params": [{"name": "title", "required": true, "description": "Note title"}],
      "human": {
        "ru": ["создай заметку {title}", "добавь заметку {title}"],
        "en": ["create note {title}", "add a note {title}"]
      }
    }
  ],
  "coverage": {
    "total": 92,
    "withVariants": 17,
    "missing": ["help", "reload", ...]
  }
}
```

## How to Fine-Tune

1. **Generate training pairs** from catalog JSON:
   ```
   Input:  "создай заметку Покупки"
   Output: {"command": "note:create", "params": {"title": "Покупки"}}
   ```

2. **Augment** with LLM-generated paraphrases for variety.

3. **Fine-tune** a small model (qwen3-0.6b, gemma-2b, phi-3-mini) with LoRA.

4. **Deploy** via the local LLM engine we already have.

## Coverage Check

Run `yoloit help --format catalog | python3 -c "import json,sys; d=json.load(sys.stdin); c=d['coverage']; print(f'{c[\"withVariants\"]}/{c[\"total\"]} commands have human variants'); print('Missing:', ', '.join(c['missing'][:10]), '...' if len(c['missing'])>10 else '')"`
