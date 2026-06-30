# Panel CLI / LLM Tools Audit Report

Date: 2026-06-27  
Scope: all 24 built-in panel types (`board.*`)

## Summary

| Metric | Count |
|---|---|
| Panel types | 24 |
| With local CLI handler | 24 |
| Critical bugs fixed | 6 |
| New CLI shortcuts | 14 |
| New LLM tools | 14 |
| UI drag bug | Fixed |

## Fixes applied in this pass

### Critical

1. **`board.run` handler mismatch** — was registered as `RunConfigsCliHandler` without panel-state actions. Added `RunPanelCliHandler` with `get`, `set-group`, `select-session`, `clear-session` while keeping RunBridge actions (`list`, `run`, `stop`, …).
2. **Missing handlers** — added `DiffPreviewCliHandler` (`board.diff.preview`) and `SetupGuideCliHandler` (`board.setup_guide`).
3. **Timer `pause`** — now recalculates `remaining` from `lastTick` (matches UI plugin).
4. **Checklist `rename`** — `text` is lookup-only; `newText`/`new`/`name` required for the new label (fixes no-op rename when only `text` passed).
5. **Webpage `click`** — accepts JS string `"true"` from WebView bridge.
6. **Files panel** — `get` returned wrong shape; added `list`/`add`/`remove` actions.

### UI

7. **Panel drag desync** — edge-pan during header drag shifted the viewport matrix without re-anchoring the board pointer, so the panel drifted from the cursor. Fixed in `board_view.dart` by computing delta before edge-pan, re-anchoring after pan, and scaling fallback drag delta by zoom.

### CLI / LLM gaps closed

| Command | Panel | Action |
|---|---|---|
| `run:set-group` | `board.run` | `set-group` |
| `run:select-session` | `board.run` | `select-session` |
| `run:clear-session` | `board.run` | `clear-session` |
| `diff:open` | `board.diff.preview` | `open` |
| `diff:set-root` | `board.diff.preview` | `set-root` |
| `setup:select` | `board.setup_guide` | `select` |
| `setup:unselect` | `board.setup_guide` | `unselect` |
| `panel-files:list` | `board.files` | `list` |
| `panel-files:add` | `board.files` | `add` |
| `panel-files:remove` | `board.files` | `remove` |
| `calendar:update-event` | `board.calendar` | `update-event` |
| `chart:get` | `board.chart` | `get` |
| `terminal:set-session` | `board.terminal` | `set-session` |

## Per-panel status

| Panel type | Handler | CLI shortcuts | LLM tools | Notes |
|---|---|---|---|---|
| `board.note.markdown` | NoteCliHandler | `note:*` | yes | OK |
| `board.sticky` | StickyNoteCliHandler | `sticky:*` | yes | OK |
| `board.shape` | ShapeCliHandler | `shape:*` | yes | OK |
| `board.kanban` | KanbanCliHandler | `kanban:*` | yes | OK |
| `board.webpage` | WebpageCliHandler | `web:*` | yes | click fix |
| `board.code.snippet` | CodeSnippetCliHandler | `snippet:*` | partial | via `do` |
| `board.checklist` | ChecklistCliHandler | `checklist:*` | yes | rename fix |
| `board.files` | FilesCliHandler | `panel-files:*` | yes | add/list/remove |
| `board.file.preview` | FilePreviewCliHandler | `files:preview` | yes | OK |
| `board.playlist` | PlaylistCliHandler | `play`, `playlist:*` | yes | OK |
| `board.run` | **RunPanelCliHandler** | `run:*` + panel state | yes | **fixed** |
| `board.run_configs` | RunConfigsCliHandler | `run:*` | yes | OK |
| `board.setup_guide` | **SetupGuideCliHandler** | `setup:*` | yes | **new** |
| `board.chat` | ChatCliHandler | `yolochat:*` | yes | OK |
| `board.terminal` | TerminalCliHandler | `terminal:*` | yes | set-session added |
| `board.filetree` | FileTreeCliHandler | `filetree:*` | yes | OK |
| `board.diff.preview` | **DiffPreviewCliHandler** | `diff:*` | yes | **new** |
| `board.yolo_assistant` | AssistantCliHandler | via `do` | partial | `send` queues message only (by design) |
| `board.widget.custom` | CustomWidgetCliHandler | `app:*` | yes | OK |
| `board.timer` | TimerCliHandler | `timer:*` | yes | pause fix |
| `board.calendar` | CalendarCliHandler | `calendar:*` | yes | update-event added |
| `board.table` | TableCliHandler | `table:*` | yes | OK |
| `board.chart` | ChartCliHandler | `chart:get` | yes | get shortcut added |
| `board.ui` | UiViewCliHandler | `ui:*` | yes | OK |

## Remaining low-priority gaps

- **`board.yolo_assistant`**: `send` does not auto-invoke LLM (message is appended to state; chat panel triggers generation). Documented in handler help.
- **`board.code.snippet`**: no dedicated LLM tool aliases (use `do` / panel context).
- **`setup:set-selected`**: handler exists; no bash shortcut yet (use `do` with JSON).
- **Table `get`**: handler has `get`; no `table:get` bash alias (use `do`).

## Verification

```bash
flutter test test/unit/core/cli/handlers/run_panel_handler_test.dart
flutter test test/unit/core/cli/handlers/diff_preview_handler_test.dart
flutter test test/unit/core/cli/handlers/setup_guide_handler_test.dart
flutter test test/unit/core/cli/handlers/timer_handler_test.dart
flutter test test/core/cli/handlers/checklist_handler_test.dart
flutter test test/core/cli/handlers/panel_handlers_test.dart
python3 scripts/check_panel_write_coverage.py
dart run tool/generate_auto_tools.dart --check
```
