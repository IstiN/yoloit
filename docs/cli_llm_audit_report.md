# YoLoIT CLI — LLM Audit Report

Generated from `tools/yoloit help --format registry` (244 commands) + LLM tool catalog in `lib/features/board/chat/cli_tools/`.

## Methodology

1. Enumerate all CLI commands and aliases from bash registry.
2. For each command, infer what an LLM agent would expect from name + description + params.
3. Compare with handler/bash implementation (`lib/core/cli/handlers/`, `tools/yoloit`).
4. Flag mismatches: bugs (wrong behavior), confusion (misleading docs), doc-only.

## How an LLM should invoke YoLoIT

- **board**: Most commands: board from runtime context or explicit. board:use sets default only (no UI). board:focus switches UI.
- **panel**: panel:create needs exact type id (panel:types). Smart groups (note/checklist/kanban/ui): omit panel → auto-resolve by type.
- **do**: yoloit do <board> <panel> <action> <json> — fallback when no dedicated tool. Prefer typed commands.
- **app**: Custom widgets: app:run <path|id> not panel:create. app:execute for JS events.
- **ui**: board.ui declarative JSON: ui:create → ui:render(tree object). Scripts: ui:set-scripts.
- **agent**: agent:run = new board.chat + task. yolochat:terminal = type into terminal panel.

## Fixes applied in this session

| Priority | Type | Command | Issue | Fix |
|---|---|---|---|---|
| P0 | bug | `checklist:check / note / checklist:add` | LLM injects board without panel → bash treats board name as panel hint | Fixed: omit board in _buildCliArgs for smart groups; optionalPanelParam |
| P0 | bug | `agent:run` | Described as terminal agent; creates board.chat + sends via ChatSessionManager | Fixed descriptions in app_tools + tools/yoloit |
| P1 | bug | `checklist:check` | LLM tool said toggle; handler only marks done. Index not sent in bash | Fixed descriptions + index in bash |
| P1 | confusion | `panel:create board.widget.custom` | Creates empty panel; app:run loads widget | Doc: use app:run (panel_tools already warns) |
| P1 | confusion | `board:apply` | LLM generates inline YAML but tool only had file param | Fixed: yaml param + temp file in executor |
| P1 | confusion | `draw:svg vs ui:render svg` | draw:svg = canvas; ui svg = in-panel | Fixed draw:svg description |
| P2 | confusion | `yolochat:send after agent:run` | Double-send; first chat panel picked | Fixed description; agent:run returns STOP |
| P2 | confusion | `ui:edit` | Claims opens editor; only focuses panel | Fixed description |
| P2 | confusion | `do` | Registry says generic; LLM says fallback only. Bare string → {text:...} | Registry still generic; prefer dedicated tools |
| P2 | confusion | `sticky:get/set` | Require board+panel; sticky:create is smart | Consider smart-parse parity |
| P2 | confusion | `note:get / checklist:items` | Strict board+panel unlike checklist:check | Document or add smart-parse |
| P3 | doc | `panelParam` | Said defaults to chat panel | Fixed tool_helpers description |
| P3 | bug | `invoke() double-normalize` | Providers normalize with userMessage; invoke re-normalized with '' | Fixed argumentsPreNormalized flag |
| P3 | doc | `106 description mismatches` | CLI registry shorter than LLM tool descriptions | LLM descriptions are source of truth for agents |

## Open issues (not fixed yet)

| Priority | Type | Command | Issue |
|---|---|---|---|
| P1 | confusion | `panel:create + board.widget.custom` | Empty widget panel without app:run |
| P2 | confusion | `ui:render` | Auto-creates board.ui panel when missing — can surprise LLM |
| P2 | confusion | `do / _merge_action_body` | Bare JSON string defaults to {text:...} — breaks tree/state actions |
| P2 | confusion | `panel:help vs panel` | Normalizer may redirect panel:help → panel without user message |
| P2 | confusion | `sticky:* mutate` | No smart-parse unlike sticky:create |
| P3 | doc | `114 short CLI descriptions` | Registry help text <35 chars; LLM tools more detailed |
| P3 | bug | `app:screenshot` | TODO in apps_handler — not fully wired |

## Command catalog (expectation vs implementation)

Legend: **OK** = matches expectation; **DOC** = works but description unclear; **BUG** = known mismatch

### agents (5 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `agent:asr` | — | Get or set the ASR (transcription) config for an agent | OK |
| `agent:default` | — | Get or set the default agent id used by agent:run (board.chat provider, default: copilot) | DOC→fixed |
| `agent:list` | — | List configured agents, default agent, and live agent sessions | OK |
| `agent:model` | — | Get or set the default LLM model for an agent | OK |
| `agent:run` | — | Create a board.chat panel for an AI agent in a folder and send the initial task. | BUG→fixed |

### app (18 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `app:create` | widget:create, wg:new | Scaffold a new app in the apps directory | OK |
| `app:demo` | — | List built-in demo apps with their local paths. Use app:demo-view <id> to read a full example. | OK |
| `app:demo-view` | — | Show the full source (manifest.json + widget.js) of a built-in demo app. Great for learning patterns… | OK |
| `app:dev-skill` | app:skill, app:docs | Print the full YoLoIT app development guide (JS API, node types, examples). Useful for AI agents wri… | OK |
| `app:execute` | — | Execute a JS event in a running app. | OK |
| `app:help` | — | Show CLI commands, events, and examples for a specific app. | OK |
| `app:install` | widget:install, wg:i | Install an app from a local path or URL | OK |
| `app:list` | myapps, widget:list, wg:ls | List installed apps and which are currently running | OK |
| `app:logs` | — | Show console.log output from a running app | OK |
| `app:reload` | app:refresh, widget:reload | Hot-reload a running app (re-reads JS from disk) | OK |
| `app:remove` | widget:remove, wg:rm | Remove an installed app by id | OK |
| `app:run` | app:open, widget:open, wg:o | Open an app in a new panel on a board. | OK |
| `app:screenshot` | — | Save a screenshot of a running app panel to a PNG file | OK |
| `app:snapshot` | — | Get the JSON render tree of a running app plus extracted text lines. | OK |
| `app:state` | — | Read structured state (yoloit.exportState) and visible text from a running app. | OK |
| `help` | — | Show CLI help | OK |
| `reload` | — | Hot reload the running Flutter app | OK |
| `restart` | — | Hot restart the running Flutter app | OK |

### board (34 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `board` | — | Show board details | OK |
| `board:apply` | — | Apply YAML bulk operations to a board (create/move/rename panels). | BUG→fixed |
| `board:archive` | — | Archive a board (hide from overview and previews) | OK |
| `board:arrange` | — | Arrange visible panels | OK |
| `board:create` | — | Create a board, optionally from a template | OK |
| `board:current` | — | Show current board | OK |
| `board:delete` | — | Delete a board | OK |
| `board:diagram` | — | Mermaid-focused board diagram | OK |
| `board:fit` | — | Fit board to viewport | OK |
| `board:focus` | — | Focus a board in the UI | OK |
| `board:folder` | bfold | Set or clear the board default folder used by new chats, terminals, and file trees | OK |
| `board:grid` | — | Toggle, reset or configure grid view for a board. | OK |
| `board:rename` | — | Rename a board | OK |
| `board:screenshot` | — | Save PNG screenshot | OK |
| `board:snapshot` | — | Text snapshot of board layout | OK |
| `board:svg` | — | Export SVG layout | OK |
| `board:translate` | — | Move board viewport | OK |
| `board:unarchive` | — | Restore an archived board | OK |
| `board:undo` | bundo | Undo the latest panel history batch on a board. Resize and drag bursts are coalesced into one undo. | OK |
| `board:use` | — | Set default board for subsequent commands (no UI switch) | OK |
| `board:zoom` | — | Set board zoom/scale level. Use for "уменьши зум", "увеличь зум", "zoom in", "zoom out", "приблизь",… | OK |
| `boards` | — | List all boards | OK |
| `boards:snapshot` | — | Snapshot all boards and panels as Mermaid graph | OK |
| `draw:add` | dra | Add a shape drawing to a board. | OK |
| `draw:clear` | drc | Remove ALL drawings from a board. | OK |
| `draw:export` | drex | Export all drawings on a board as SVG. | OK |
| `draw:file` | drf | Render an SVG file as drawings on a board. | OK |
| `draw:list` | drl | List all drawings (freehand strokes / shapes) on a board. | OK |
| `draw:remove` | drr | Remove a specific drawing from a board by its id. | OK |
| `draw:svg` | drsvg | Draw an SVG path on the board canvas (not inside board.ui panels). | DOC→fixed |
| `frame:create` | frame:new | Create a Miro-style frame panel for grouping a section of the board. | OK |
| `select` | — | Select panels by ids or rectangle, or show current selection | OK |
| `shape:create` | shape:new | Create a geometric board panel: rectangle, circle, diamond, triangle, hexagon, or frame. | OK |
| `sticky:create` | sticky:new | Create a Miro-style sticky note panel. Board is optional and defaults to the current board. | OK |

### checklist (7 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `checklist:add` | cl:a | Add checklist item | OK |
| `checklist:check` | cl:ch, cl:c | Mark a checklist item done by text, id, or zero-based index. | BUG→fixed |
| `checklist:items` | cl:ls | List checklist items | OK |
| `checklist:new` | cl:n | Create a new checklist panel | OK |
| `checklist:remove` | cl:rm | Remove a checklist item | OK |
| `checklist:rename` | cl:rn | Rename a checklist item | OK |
| `checklist:uncheck` | cl:u | Mark a checklist item not done (by text, id, or index) | OK |

### cloud (6 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `cloud:add` | — | Add a cloud LLM provider config | OK |
| `cloud:list` | — | List cloud LLM providers and active config | OK |
| `cloud:provider` | — | Get or set assistant provider type (cloud only) | OK |
| `cloud:remove` | — | Remove a cloud provider config by id | OK |
| `cloud:select` | — | Set the active cloud provider config | OK |
| `cloud:update` | — | Update fields of an existing cloud provider config | OK |

### files (5 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `files:list` | — | Read-only list of directory entries for a file system path | OK |
| `files:preview` | — | Open a file as a preview panel on the board (supports markdown, images, text, code). | OK |
| `files:read` | — | Read-only display of a text file from the local file system | OK |
| `files:search` | — | Read-only search for files and folders on the local file system. | OK |
| `filetree:read` | ftr | Read and print a directory tree as text (no panel required). | OK |

### group (11 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `group:add` | — | Add panels to a group | OK |
| `group:collapse` | — | Collapse a group and hide its panels | OK |
| `group:color` | — | Set or clear a group color | OK |
| `group:create` | — | Create a named group of panels | OK |
| `group:cycle-focus` | — | Cycle the visible panel inside a collapsed group | OK |
| `group:delete` | — | Delete a group | OK |
| `group:expand` | — | Expand a collapsed group and show its panels | OK |
| `group:move` | — | Move every panel in a group by the given board delta | OK |
| `group:remove` | — | Remove panels from a group | OK |
| `group:rename` | — | Rename a group | OK |
| `groups` | — | List groups on a board | OK |

### kanban (11 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `kanban:add-card` | k:a, kanban:card | Add kanban card. Parse "in/into/to <column>" as the required `column` and "named/called/titled <text… | OK |
| `kanban:add-column` | k:c, k:ac | Add kanban column | OK |
| `kanban:cards` | k:ls | List kanban cards | OK |
| `kanban:columns` | k:col | List kanban columns | OK |
| `kanban:move-card` | k:mv, k:mc | Move kanban card | OK |
| `kanban:paste` | k:p | Create a kanban card from text — board and panel optional (alias: k:p) | OK |
| `kanban:remove-card` | k:rm | Remove kanban card | OK |
| `kanban:remove-column` | k:dc | Remove kanban column | OK |
| `kanban:rename-column` | k:rc | Rename kanban column | OK |
| `kanban:send-card-to-chat` | k:sc | Send a kanban card to a chat panel | OK |
| `kanban:update-card` | k:up, k:uc | Update kanban card title | OK |

### link (5 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `link:color` | — | Set link color | OK |
| `link:create` | — | Create panel link | OK |
| `link:delete` | — | Delete panel link | OK |
| `link:style` | — | Set link style and geometry | OK |
| `links` | — | List links on a board | OK |

### note (15 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `code:get` | — | Get code snippet content | OK |
| `code:set` | — | Set code snippet content | OK |
| `note` | note | Set markdown note text | OK |
| `note:add` | n:a | Append text to note — board and panel optional | OK |
| `note:append` | n:ap | Append markdown note text | OK |
| `note:create` | n:c | Create a new note panel | OK |
| `note:get` | n:g | Read note content | OK |
| `note:nowrap` | n:n | Disable note auto-height wrapping | OK |
| `note:wrap` | n:w | Enable note auto-height wrapping | OK |
| `shape:get` | — | Get shape panel state | OK |
| `shape:set` | — | Set shape panel properties | OK |
| `sticky:append` | — | Append text to a sticky note | OK |
| `sticky:color` | — | Set sticky note color | OK |
| `sticky:get` | — | Read sticky note content | OK |
| `sticky:set` | — | Set sticky note text | OK |

### panel (51 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `calendar:add-event` | cae | Add an event to a Calendar panel | OK |
| `calendar:create` | ccr | Create a Calendar panel on a board | OK |
| `calendar:delete-event` | cde | Delete an event from a Calendar panel | OK |
| `calendar:events` | cev | List events from a Calendar panel | OK |
| `calendar:focus-date` | cfd | Set the focused date of a Calendar panel | OK |
| `calendar:scroll-to-event` | cse | Focus and scroll to a Calendar event | OK |
| `calendar:scroll-to-time` | cstm | Scroll the Calendar timeline to a specific hour | OK |
| `calendar:set-view` | csv | Switch Calendar panel view | OK |
| `calendar:show-event` | csh | Show details of a Calendar event | OK |
| `chart:create` | chc | Create a Chart panel on a board | OK |
| `chart:link-table` | chlt | Link a Chart panel to a Table panel as its data source | OK |
| `chart:refresh` | chfr | Snapshot linked Table panel data into Chart panel state | OK |
| `chart:set-data` | chsd | Set inline data for a Chart panel (JSON array) | OK |
| `chart:set-type` | chst | Change Chart panel type | OK |
| `do` | — | Advanced fallback: run a raw panel action from panel:help when no dedicated | DOC |
| `filetree:collapse` | — | Collapse a file tree node | OK |
| `filetree:create` | ftc | Create a File Tree panel on a board and set its root directory. | OK |
| `filetree:expand` | — | Expand a file tree node | OK |
| `filetree:list` | — | List file tree nodes | OK |
| `filetree:open` | — | Open a path in the file tree panel | OK |
| `filetree:refresh` | — | Refresh file tree contents | OK |
| `filetree:set-root` | ftsr | Set the root directory path of an existing File Tree panel. | OK |
| `panel` | — | Show panel details and content. Use this to inspect note markdown when searching by content. | OK |
| `panel:color` | — | Set or clear panel color | OK |
| `panel:copy` | pcy | Copy selected panel(s) to the clipboard. | OK |
| `panel:create` | — | Create a panel. Always include the exact panel type id in `type`. | DOC |
| `panel:delete` | — | Delete a panel | OK |
| `panel:duplicate` | pdp | Duplicate selected panel(s). | OK |
| `panel:focus` | — | Focus/scroll-to/zoom a panel to bring it into view. Use for "сделай фокус на", "фокус на", "покажи",… | OK |
| `panel:help` | — | Show dynamic panel actions | OK |
| `panel:hide` | — | Hide a panel | OK |
| `panel:move` | — | Move a panel | OK |
| `panel:paste` | ppt | Paste copied panels onto the board | OK |
| `panel:rename` | — | Rename a panel | OK |
| `panel:resize` | — | Resize a panel. Supports explicit width/height or presets: | OK |
| `panel:screenshot` | psc | Save PNG screenshot of a single panel (headless offscreen render) | OK |
| `panel:show` | — | Show a hidden panel | OK |
| `panel:types` | — | List all available panel/widget type ids on the board. | OK |
| `panel:z` | panel:front, panel:back | Set panel depth/layer order. Use front/back or an explicit integer zIndex. | OK |
| `panels` | — | List panels on a board | OK |
| `table:add-column` | tbac | Add a column to a Table panel | OK |
| `table:add-row` | tbar | Add a row to a Table panel | OK |
| `table:clear` | tbcl | Remove all rows from a Table panel | OK |
| `table:create` | tbc | Create a Table panel on a board | OK |
| `table:remove-column` | tbrc | Remove a column from a Table panel | OK |
| `table:remove-row` | tbrr | Remove a row from a Table panel | OK |
| `table:set` | tbs | Replace Table panel columns and rows (JSON) | OK |
| `table:update-row` | tbur | Update a row in a Table panel | OK |
| `terminal:config` | — | Get terminal configuration | OK |
| `terminal:output` | — | Read the latest output from an interactive terminal panel. | OK |
| `terminal:set-dir` | — | Set the working directory of an interactive terminal panel | OK |

### playlist (8 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `next` | next | Skip to the next track in the playlist | OK |
| `pause` | pause | PAUSE music playback (temporary stop, can be resumed). Use for "пауза", "поставь на паузу", "поставь… | OK |
| `play` | — | START or RESUME music/audio playback in a playlist panel. Use ONLY when the user wants to START play… | OK |
| `playlist:add` | — | Add a track to a playlist | OK |
| `playlist:list` | pll | SHOW/LIST tracks in a playlist panel. Use for "покажи плейлист", "что в плейлисте", "список треков",… | OK |
| `playlist:remove` | — | Remove a track from a playlist | OK |
| `prev` | prev | Go to the previous track in the playlist | OK |
| `stop` | stop | STOP music playback completely (resets to beginning). Use for "останови", "выключи музыку", "стоп", … | OK |

### remote (3 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `remote:connect` | rcon | Connect the CLI to a remote yoloitd daemon | OK |
| `remote:disconnect` | rdisc | Disconnect remote yoloitd and use local desktop server | OK |
| `remote:status` | rst | Show active remote yoloitd connection | OK |

### run (14 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `run:add` | — | Add a run configuration | OK |
| `run:attach` | — | Attach run console to a session | OK |
| `run:close` | — | Remove a run session tab from the panel | OK |
| `run:config` | — | Show run configuration details | OK |
| `run:detach` | — | Detach run session from panel | OK |
| `run:input` | — | Send stdin to a run session | OK |
| `run:list` | — | List run configs and sessions. If the user names a panel, pass that exact panel title. | OK |
| `run:logs` | — | Read the full output of a run session | OK |
| `run:output` | — | Read run session output | OK |
| `run:popout` | — | Open detached session in a new Run panel | OK |
| `run:remove` | — | Remove a run configuration | OK |
| `run:run` | — | Start a run configuration | OK |
| `run:stop` | — | Stop a running session | OK |
| `run:update` | — | Update a run configuration | OK |

### search (1 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `search` | — | Search text across all boards, panels, active chats, and saved chat sessions | OK |

### template (3 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `template:info` | — | Show template details and parameters | OK |
| `template:list` | — | List available board templates | OK |
| `template:sync` | — | Refresh templates from all configured sources | OK |

### theme (13 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `theme` | — | Show current theme info (preset, brightness, overrides) | OK |
| `theme:brightness` | — | Set theme brightness mode | OK |
| `theme:color` | — | Set a color override for a specific theme slot. | OK |
| `theme:colors` | — | Show all effective color values for the current theme | OK |
| `theme:delete` | — | Delete a custom theme by id | OK |
| `theme:export` | — | Export current theme as JSON to stdout | OK |
| `theme:import` | — | Import a theme file (JSON, ICLS, or XML) and activate it | OK |
| `theme:presets` | — | List all available theme presets (built-in and custom) | OK |
| `theme:reset-all` | — | Clear all color overrides, reverting to base theme | OK |
| `theme:reset-color` | — | Remove a color override, reverting slot to theme default | OK |
| `theme:save` | — | Save current theme (with any overrides) as a named custom preset | OK |
| `theme:set` | — | Set the active theme preset. | OK |
| `theme:slots` | — | Show available color slot names grouped by category | OK |

### timer (7 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `timer:create` | — | Create and optionally start a timer | OK |
| `timer:pause` | — | Pause the running timer | OK |
| `timer:reset` | — | Reset timer to full duration | OK |
| `timer:resume` | — | Resume a paused timer | OK |
| `timer:set` | — | Set timer duration and label without starting | OK |
| `timer:start` | — | Start (or restart) the timer | OK |
| `timer:status` | — | Show timer status | OK |

### ui (6 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `ui:create` | uicrt | Create a declarative UI View panel (board.ui) for JSON-driven layouts | OK |
| `ui:edit` | uiedt | Focus a UI View panel only — user must open the JSON editor from the panel menu manually | DOC→fixed |
| `ui:get` | uiget | Read JSON tree, resolvedTree, storage, scripts, and text lines | OK |
| `ui:render` | uirnd | Render a declarative JSON UI tree on a UI View panel. | DOC |
| `ui:set-scripts` | uisc | Set onTap JS handlers map. Example: {"bump":"yoloit.inc(\\"taps\\");"} | OK |
| `ui:set-state` | uist | Merge storage for {{bindings}} in UI labels. Example: {"taps":3,"message":"Hi"} | OK |

### webpage (8 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `web:click` | — | Click the first element matching a CSS selector | OK |
| `web:content` | — | Return the current page HTML | OK |
| `web:exec` | — | Execute JavaScript in the panel WebView | OK |
| `web:get` | — | Get webpage panel state | OK |
| `web:open` | — | Open URL in webpage panel | OK |
| `web:scroll` | — | Scroll the page to or by coordinates | OK |
| `web:title` | — | Return the current page title | OK |
| `web:url` | — | Return the current live URL from the WebView | OK |

### yolochat (13 commands)

| Command | Aliases | LLM expectation | Status |
|---|---|---|---|
| `yolochat:clear` | — | Clear YoLo chat messages | OK |
| `yolochat:config` | — | Get chat panel configuration | OK |
| `yolochat:follow-up` | — | Set follow-up question suggestions | OK |
| `yolochat:history` | — | List saved YoLo chat sessions from chat history | OK |
| `yolochat:logs` | — | Dump full YoLo chat log for debugging | OK |
| `yolochat:messages` | — | Read YoLo chat messages | OK |
| `yolochat:panels` | — | List all board.chat panels | OK |
| `yolochat:restore` | — | Restore a saved YoLo chat session into a chat panel | OK |
| `yolochat:send` | — | Send a message to a YoLo chat panel — non-blocking, returns immediately | DOC→fixed |
| `yolochat:sessions` | — | List active YoLo chat sessions | OK |
| `yolochat:status` | — | Show YoLo chat status | OK |
| `yolochat:stop` | — | Stop active YoLo chat streaming (target panel or any active) | OK |
| `yolochat:terminal` | chat:terminal, terminal:send, term:send | Send literal text to an existing terminal panel and press Enter. | OK |

## Explicit code bugs found during review

1. **`_buildCliArgs` board injection** (`yoloit_cli_tools.dart`): runtime board + omitted panel produced `cmd board item` where bash parses board as panel hint.
2. **`agent:run` naming** (`agents_handler.dart:145-220`): creates `board.chat`, not terminal session.
3. **`checklist:check` bash** (`tools/yoloit`): numeric index sent as id/text, not `index` field.
4. **`invoke` double normalization** (`yoloit_cli_tools.dart`): wiped user-message-based redirects from providers.
5. **`board:apply` LLM gap**: no way to pass generated YAML except file path.
6. **`app:screenshot` stub** (`apps_handler.dart:320`): TODO — panel screenshot not fully wired.
7. **`ui:edit` false promise** (`tools/yoloit`): only focusPanel, no editor open.
8. **`ScrollableCardRegion` lock** (unrelated board scroll bug, fixed separately).

## Синхронизация описаний

Источник правды: `lib/features/board/chat/cli_tools/*.dart` (YoloitCliToolCatalog).

Синхронизация в bash registry:

```bash
python3 tool/sync_cli_descriptions.py
python3 tool/sync_cli_descriptions.py --check
```

1. Add smart-parse to `sticky:get/set/append` and `note:get` / `checklist:items`.
2. Sync CLI registry descriptions with LLM tool text (or generate registry from Dart).
3. `panel:create` should reject or auto-call `app:run` for `board.widget.custom`.
4. Surface `agent:run` STOP field in tool result UI so LLM stops calling yolochat:send.
5. Add integration test: LLM executor builds `checklist:check` with board only + item.
