# Skill: Information Compression Protocol (ICP) for LLM References

## Purpose

Generate ultra-compressed reference files using ICP — emojis as semantic markers,
math notation, structural shorthand. Target: 80-90% compression with full clarity.
Output is optimized for LLM context windows, not human reading.

## When to Use

- Creating `*-llm.md` reference files for any CLI, API, or tool
- Compressing existing human-readable docs into LLM-consumable format
- Building cheat sheets where every token must carry maximum information density

## Core Principles

1. **Emojis = semantic markers chosen by MEANING**, not decoration
2. **Ambiguous emoji/symbol → ADD Legend block** `L:{🔣=meaning}`
3. **Obvious emojis need NO legend:** ✅❌⚠️📁💾🔍➕➖🔒📊
4. **No prose.** Zero human sentences, no explanations
5. **One line = one concept.** Self-contained compressed reference
6. **Group related commands:** `cmd:{create|rename|delete}`
7. **Inline defaults in parens:** `type(300×240)`

## Symbol Reference

| Symbol | Meaning |
|--------|---------|
| `→` | flow / produces / leads to |
| `\|` | alternative / separator |
| `;` | group separator |
| `/` | OR within a value |
| `{a\|b\|c}` | alternatives group |
| `{...}*` | loop / repeat |
| `<>` | required parameter |
| `[]` | optional / contains |
| `()` | inline default or note |
| `~` | optional / approx |
| `✓/✓✓` | required / critical |
| `✗` | forbidden |
| `⚠️` | warning / caveat |
| `Δ` | delta / change |
| `Σ` | sum / aggregate |
| `¬` | not / without |
| `\|\|` | parallel |
| `+=` | accumulate / add to |
| `↕↑↓` | resize / increase / decrease |

## Emoji Selection Rules

```
Using emoji X:
├─ Universal? (✅❌⚠️📁💾🔍) → NO legend
├─ Visual match? (🌐=web, 📊=chart, 🎵=music) → NO legend  
├─ Context obvious? (CLI doc: 💬=chat panel) → NO legend
├─ Repurposed? (🎣=hook, 🦴=model) → ADD legend
├─ Math/logic? (∀∃∈λ) → ADD legend
└─ Ambiguous? (🔴=error?stop?record?) → ADD legend
```

## Legend Formats

```
# Block legend at top:
L:{🦴=Model;🎨=View;🎮=Controller}

# Inline on first use:
🎣(=useEffect)→cleanup

# Section header:
## 🏥Medical [🧑‍⚕️=doc;🤒=patient;💊=rx]
```

## Structure Template

```
🔣ToolName
L:{emoji=meaning;emoji=meaning}  ← only if ambiguous

Req: ✓✓prereqs; cfg: path/to/config

## 📋Category
`cmd`→result | `cmd:{sub1|sub2} <arg>`
emoji:`shorthand <b> <p> <val>`

## 🔄Flow
step1→{Δmutate→✅|❌→fix}*
```

## Example: Before (Human Docs)

```markdown
## Board Commands

### List Boards
Shows all available boards.
Usage: `yoloit boards`

### Create Board  
Creates a new board with the given name.
Usage: `yoloit board:create <name>`
```

## Example: After (ICP Compressed)

```
## 📋Board
`boards`→📋list | `board:{create|delete} <name>`
```

## Process

1. **Read** the full human reference
2. **Identify** domain emojis by visual meaning (📝=note, ☑️=checklist, 📊=kanban, etc.)
3. **Build legend** for any non-obvious emoji mappings
4. **Group** commands by category with emoji headers
5. **Merge** commands sharing prefix: `prefix:{a|b|c}`
6. **Tag** each shorthand line with its type emoji
7. **Add flow section** using `→` chains and `{...}*` loops
8. **Verify** every command from source appears in output
9. **Target:** 80-90% compression, file size 5-15% of source

## Quality Checklist

- [ ] No human sentences in the output
- [ ] Every command from source docs is represented
- [ ] Emojis chosen by semantic meaning, not randomly
- [ ] Legend present for all ambiguous/repurposed emojis
- [ ] No legend for universal emojis (✅❌⚠️📁)
- [ ] Alternatives use `{a|b|c}` grouping
- [ ] Params use `<required>` and `[optional]`
- [ ] Defaults inline: `type(WxH)`
- [ ] Agent flow section with `→` chains
- [ ] An LLM reading this can reconstruct full invocations

## Reference

- Source: `cli-reference.md` (canonical human docs)
- Output: `cli-llm.md` (ICP compressed)
- Protocol: [Information Compression Protocol](https://github.com/Germesych/ovchinnikov-semantic-core/blob/main/core.md)
