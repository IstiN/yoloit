# YoLoIT CLI Reference

> Canonical full reference for all `yoloit` CLI commands. Designed for human use.
> The CLI communicates with the running YoLoIT app via HTTP on localhost (port auto-discovered from `~/.config/yoloit/cli.port`).
> For ultra-short LLM/operator shortcuts, use [`cli-llm.md`](./cli-llm.md).

## Prerequisites
- YoLoIT desktop app must be running
- `tools/yoloit` script must be executable: `chmod +x tools/yoloit`
- Add to PATH: `export PATH="$PATH:/path/to/yoloit/tools"`

## Help Commands
| Command | Description | Example |
|---|---|---|
| `help --format short` | Compact grouped help with params + examples | `yoloit help --format short` |
| `help --format detailed` | Verbose help (`description`, `parameters`, `format`, `example`) | `yoloit help --format detailed` |
| `help --format mermaid` | Mermaid command tree | `yoloit help --format mermaid` |
| `help --format tools` | JSON MCP-style tools schema | `yoloit help --format tools` |

## App Commands
| Command | Description | Example |
|---|---|---|
| `reload` | Hot reload the running Flutter app | `yoloit reload` |
| `restart` | Hot restart the running Flutter app | `yoloit restart` |

## Board Commands
| Command | Description | Example |
|---|---|---|
| `boards` | List all boards | `yoloit boards` |
| `board <id\|name>` | Show board details | `yoloit board "My Board"` |
| `board:create <name>` | Create a new board | `yoloit board:create "Sprint 12"` |
| `board:rename <id\|name> <newname>` | Rename board | `yoloit board:rename "old" "new"` |
| `board:delete <id\|name>` | Delete board | `yoloit board:delete "Board"` |
| `board:focus <id\|name>` | Switch active board | `yoloit board:focus "Sprint"` |
| `board:zoom <id\|name> <scale>` | Set viewport zoom | `yoloit board:zoom "Board" 0.5` |
| `board:translate <id\|name> <x> <y>` | Set viewport offset | `yoloit board:translate "Board" 100 200` |
| `board:fit <id\|name> [WxH]` | Fit all panels in view | `yoloit board:fit "Board" 1440x900` |
| `board:arrange <id\|name> [right\|down] [hGap] [vGap]` | Auto-layout panels as tree | `yoloit board:arrange "Board" right 80 60` |
| `board:apply <id\|name> [file\|-]` | Apply YAML bulk operations from file or stdin | `yoloit board:apply "Board" flow.yaml` |
| `board:snapshot <id\|name> [--format md\|mermaid]` | Get board snapshot as markdown or mermaid text | `yoloit board:snapshot "Board" --format mermaid` |
| `board:diagram <id\|name> [--format mermaid\|md]` | Alias for snapshot focused on diagram output | `yoloit board:diagram "Board"` |
| `board:screenshot <id\|name> [file.png]` | Save PNG screenshot | `yoloit board:screenshot "Board" out.png` |
| `board:svg <id\|name> [file.svg]` | Export SVG layout | `yoloit board:svg "Board" layout.svg` |

## Panel Commands
| Command | Description | Example |
|---|---|---|
| `panels <board>` | List all panels | `yoloit panels "Board"` |
| `panel <board> <panel>` | Show panel details & content | `yoloit panel "Board" "My Note"` |
| `panel:help <board> <panel>` | Show actions with args/help for panel type | `yoloit panel:help "Board" "Run"` |
| `panel:create <board> <type> <title>` | Create panel | `yoloit panel:create "Board" board.note.markdown "Ideas"` |
| `panel:types <board>` | List available panel types | `yoloit panel:types "Board"` |
| `panel:rename <board> <panel> <name>` | Rename panel | `yoloit panel:rename "Board" "Old" "New"` |
| `panel:move <board> <panel> <x> <y>` | Move panel | `yoloit panel:move "Board" "Panel" 100 200` |
| `panel:resize <board> <panel> <w> <h>` | Resize panel | `yoloit panel:resize "Board" "Panel" 400 300` |
| `panel:color <board> <panel> <color\|clear>` | Set tint color | `yoloit panel:color "Board" "Note" "#FF5733"` |
| `panel:hide <board> <panel>` | Hide panel | `yoloit panel:hide "Board" "Panel"` |
| `panel:show <board> <panel>` | Show hidden panel | `yoloit panel:show "Board" "Panel"` |
| `panel:delete <board> <panel>` | Delete panel | `yoloit panel:delete "Board" "Panel"` |
| `panel:focus <board> <panel>` | Focus/bring to front | `yoloit panel:focus "Board" "Panel"` |
| `do <board> <panel> <action> [args...]` | Run panel action (generic) | `yoloit do "Board" "Panel" get` |

## Panel Types
| Type ID | Display Name | Default Size |
|---|---|---|
| `board.note.markdown` | Markdown Note | 300×240 |
| `board.checklist` | Checklist | 280×360 |
| `board.kanban` | Kanban Board | 600×400 |
| `board.chat` | Chat | 360×480 |
| `board.playlist` | Playlist | 380×480 |
| `board.webpage` | Webpage | 640×480 |
| `board.code.snippet` | Code Snippet | 400×300 |
| `board.files` | Files | 320×400 |
| `board.file.preview` | File Preview | 400×400 |
| `board.terminal` | Terminal | 480×320 |
| `board.filetree` | File Tree | 320×500 |
| `board.run` | Run | 560×360 |
| `board.run_configs` | Run Configs | 600×400 |
| `board.yolo_assistant` | YoLo Assistant | 420×560 |

## Shorthand Commands
| Command | Description | Example |
|---|---|---|
| `note <board> <panel> <text>` | Set note content (markdown) | `yoloit note "Board" "Ideas" "# Title\n- item"` |
| `note:append <board> <panel> <text>` | Append to note | `yoloit note:append "Board" "Ideas" "\n- new item"` |
| `note:wrap <board> <panel>` | Enable auto-height for note | `yoloit note:wrap "Board" "Ideas"` |
| `note:nowrap <board> <panel>` | Disable auto-height for note | `yoloit note:nowrap "Board" "Ideas"` |
| `checklist:add <board> <panel> <item>` | Add checklist item | `yoloit checklist:add "Board" "Tasks" "Write tests"` |
| `checklist:check <board> <panel> <id\|text>` | Check item by id or text | `yoloit checklist:check "Board" "Tasks" "Write tests"` |
| `checklist:uncheck <board> <panel> <id\|text>` | Uncheck item by id or text | `yoloit checklist:uncheck "Board" "Tasks" item-123` |
| `kanban:columns <board> <panel>` | List columns | `yoloit kanban:columns "Board" "Kanban"` |
| `kanban:add-column <board> <panel> <name>` | Add kanban column | `yoloit kanban:add-column "Board" "Kanban" "In Review"` |
| `kanban:rename-column <board> <panel> <col> <name>` | Rename column | `yoloit kanban:rename-column "Board" "Kanban" "Todo" "Backlog"` |
| `kanban:remove-column <board> <panel> <col>` | Remove column + its cards | `yoloit kanban:remove-column "Board" "Kanban" "Done"` |
| `kanban:cards <board> <panel>` | List all columns+cards | `yoloit kanban:cards "Board" "Kanban"` |
| `kanban:add-card <board> <panel> <col> <title>` | Add card | `yoloit kanban:add-card "Board" "Kanban" "Todo" "Fix bug"` |
| `kanban:update-card <board> <panel> <cardId> <title>` | Update card title | `yoloit kanban:update-card "Board" "Kanban" card-123 "New title"` |
| `kanban:move-card <board> <panel> <cardId> <col>` | Move card to column | `yoloit kanban:move-card "Board" "Kanban" card-123 "Done"` |
| `kanban:remove-card <board> <panel> <cardId>` | Remove card | `yoloit kanban:remove-card "Board" "Kanban" card-123` |
| `run:list <board> <panel>` | List run configurations and sessions | `yoloit run:list "Board" "Run"` |
| `run:input <board> <panel> <sessionId\|id\|name> <text> [--enter]` | Send stdin to a running run session | `yoloit run:input "Board" "Run" preset_flutter_run_macos r` |
| `run:output <board> <panel> [sessionId\|id\|name]` | Get output of latest matching run session | `yoloit run:output "Board" "Run" preset_flutter_run_macos` |
| `run:detach <board> <panel> [sessionId\|id\|name]` | Detach run console from active/matching session | `yoloit run:detach "Board" "Run"` |
| `run:attach <board> <panel> [sessionId\|id\|name] [--any]` | Attach run console to running (or any) matching session | `yoloit run:attach "Board" "Run"` |
| `run:popout <board> <panel> [sessionId\|id\|name]` | Create a detached `board.run` panel and attach a session there | `yoloit run:popout "Board" "Run"` |
| `play <board> <panel> <file\|url>` | Add & play media | `yoloit play "Board" "Music" ~/song.mp3` |
| `web:open <board> <panel> <url>` | Open URL in browser panel | `yoloit web:open "Board" "Browser" https://example.com` |

## Link Commands
| Command | Description | Example |
|---|---|---|
| `links <board>` | List all links | `yoloit links "Board"` |
| `link:create <board> <from-panel> <to-panel>` | Create link | `yoloit link:create "Board" "Step 1" "Step 2"` |
| `link:delete <board> <linkId>` | Delete link | `yoloit link:delete "Board" link-123` |
| `link:style <board> <linkId> <style> [geometry]` | Set link style | `yoloit link:style "Board" link-123 arrow bezier` |
| `link:color <board> <linkId> <color>` | Set link color | `yoloit link:color "Board" link-123 "#FF5733"` |

### Link styles: `arrow`, `line`
### Link geometries: `bezier`, `straight`, `elbow`

## Panel-Specific Actions (via `do`)

### Markdown Note (`board.note.markdown`)
| Action | Args | Description |
|---|---|---|
| `get` | — | Get current content |
| `set` | `text` | Replace content |
| `append` | `text` | Append to content |
| `wrap` | — | Enable auto-height wrapping |
| `nowrap` | — | Disable auto-height wrapping |

### Checklist (`board.checklist`)
| Action | Args | Description |
|---|---|---|
| `items` | — | List all items |
| `add` | `text` | Add item |
| `check` | `index` \| `id` \| `text` | Check item |
| `uncheck` | `index` \| `id` \| `text` | Uncheck item |
| `remove` | `id` | Delete item |
| `rename` | `id`, `text` | Rename item |

### Kanban Board (`board.kanban`)
| Action | Args | Description |
|---|---|---|
| `columns` | — | List columns |
| `cards` | — | List all columns+cards |
| `add-column` | `name` | Add column |
| `rename-column` | `columnId\|name`, `name` | Rename column |
| `remove-column` | `columnId\|name` | Delete column |
| `add-card` | `column`, `title`, `description?`, `color?` | Add card |
| `move-card` | `cardId`, `to` | Move card to column |
| `remove-card` | `cardId` | Delete card |
| `update-card` | `cardId`, `title?`, `description?`, `color?` | Update card |

### Chat (`board.chat`)
| Action | Args | Description |
|---|---|---|
| `send` | `message\|text`, `attachments?`, `config?`, `provider?`, `model?`, `sessionName?`, `workingDir?` | Send a message (optionally updating chat config first) |
| `messages` | — | Get chat history |
| `config` | `config?`, `provider?`, `model?`, `sessionName?`, `workingDir?` | Get or update AI/session config |
| `clear` | — | Clear chat history |

### Playlist (`board.playlist`)
| Action | Args | Description |
|---|---|---|
| `list` | — | List tracks |
| `add` | `path`, `name?` | Add track |
| `remove` | `id` | Remove track |
| `play` | `index?` | Play (current or index) |
| `pause` | — | Pause |
| `stop` | — | Stop |
| `next` | — | Next track |
| `prev` | — | Previous track |

### Webpage (`board.webpage`)
| Action | Args | Description |
|---|---|---|
| `open` | `url` | Open URL |
| `get` | — | Get current URL |

### Code Snippet (`board.code.snippet`)
| Action | Args | Description |
|---|---|---|
| `get` | — | Get code content |
| `set` | `code`, `language?` | Set code content |

### Files (`board.files`)
| Action | Args | Description |
|---|---|---|
| `get` | — | Get current path |
| `open` | `path` | Open directory |

### File Preview (`board.file.preview`)
| Action | Args | Description |
|---|---|---|
| `get` | — | Get current preview file path |
| `open` | `path` | Open file in preview panel |

### Terminal (`board.terminal`)
| Action | Args | Description |
|---|---|---|
| `config` | — | Get terminal config |
| `set-dir` | `path` | Set working directory |

### File Tree (`board.filetree`)
| Action | Args | Description |
|---|---|---|
| `list` | `path?` | List files in current/given dir |
| `set-root` | `path` | Set root directory |
| `expand` | `path` | Expand directory node |
| `collapse` | `path` | Collapse directory node |
| `open` | `path` | Open file (creates linked preview panel) |
| `refresh` | — | Refresh tree from disk |

### Run Configs (`board.run_configs`)
| Action | Args | Description |
|---|---|---|
| `list` | `group?` | List configurations in panel/current group |
| `add` | `name`, `command`, `group?`, `workingDir?`, `env?`, `isFlutterRun?`, `quickActions?` | Add configuration |
| `update` | `id\|name`, `group?`, `newName?`, `command?`, `workingDir?`, `env?`, `isFlutterRun?`, `quickActions?` | Update configuration |
| `remove` | `id\|name`, `group?` | Remove configuration |
| `run` | `id\|name`, `group?` | Start configuration |
| `stop` | `sessionId?\|id?\|name?`, `group?` | Stop the latest matching running session |
| `detach` | `sessionId?\|id?\|name?`, `group?` | Detach console from session (process keeps running) |
| `attach` | `sessionId?\|id?\|name?`, `group?`, `runningOnly?` | Attach console to matching session |
| `input` | `text`, `appendNewline?`, `sessionId?\|id?\|name?`, `group?` | Send stdin text to latest matching running session |
| `output` | `sessionId?\|id?\|name?`, `group?` | Get output of the latest matching run session |
| `config` | `id\|name`, `group?` | Get config details |

`quickActions` format:
```json
[
  {
    "label": "Hot Reload",
    "icon": "local_fire_department",
    "command": "r",
    "appendNewline": false
  }
]
```

Supported icon names: `bolt`, `local_fire_department`, `restart_alt`, `play_arrow`, `pause`, `stop`.

### YoLo Assistant (`board.yolo_assistant`)
| Action | Args | Description |
|---|---|---|
| `send` | `text` | Send message to assistant |
| `messages` | — | Get conversation history |
| `clear` | — | Clear conversation |
| `skills` | — | List active skills |
| `add-skill` | `skill` | Activate a skill |
| `remove-skill` | `skill` | Deactivate a skill |
| `mode` | `text\|voice` | Switch interaction mode |
| `voice-start` | — | Start voice listening |
| `voice-stop` | — | Stop voice listening |

## YAML Bulk Apply

`board:apply` accepts a YAML document from a file or stdin. The document can
either be a list of operations or a map with an `operations:` key.

```yaml
operations:
  - op: panel.create
    id: temp-note
    ref: temp-note
    type: board.note.markdown
    title: Temp note
    x: 120
    y: 80
    width: 320
    height: 180
    state:
      markdown: |
        # Hello
        - bulk
  - op: panel.update
    panel: temp-note
    color: "#8B5CF6"
    state:
      autoHeight: true
  - op: link.create
    from: temp-note
    to: "2. Идти в магазин"
  - op: board.fit
    viewportWidth: 1440
    viewportHeight: 900
```

Supported `op` values:
- `panel.create`, `panel.update`, `panel.move`, `panel.resize`, `panel.delete`,
  `panel.focus`, `panel.color`, `panel.hide`, `panel.show`, `panel.action`
- `link.create`, `link.delete`, `link.update` (`link.style`, `link.color`)
- `board.focus`, `board.fit`, `board.zoom`, `board.translate`, `board.arrange`

Use `id:` or `panelId:` on create operations when you want deterministic ids in
the same YAML document. `ref:` also works for reusing generated panel/link ids.

## Color Reference
Named colors supported in `panel:color` and `link:color`:
`red`, `green`, `blue`, `yellow`, `purple`, `pink`, `orange`, `teal`, `gray`, `white`, `clear` (remove color)

Hex format: `#RRGGBB` (e.g. `#FF5733`) or `#AARRGGBB` (with alpha)

## Workflow Examples

### Create a complete project board
```bash
b="My Project"
yoloit board:create "$b"
yoloit board:focus "$b"
yoloit panel:create "$b" board.kanban "Sprint Tasks"
yoloit panel:create "$b" board.note.markdown "README"
yoloit panel:create "$b" board.chat "AI Assistant"
yoloit note "$b" "README" "# My Project\n\nProject overview here."
yoloit kanban:add-column "$b" "Sprint Tasks" "To Do"
yoloit kanban:add-column "$b" "Sprint Tasks" "In Progress"
yoloit kanban:add-column "$b" "Sprint Tasks" "Done"
yoloit kanban:add-card "$b" "Sprint Tasks" "To Do" "Setup CI/CD"
yoloit board:fit "$b"
```

### Mind-map style flow
```bash
b="Workflow"
yoloit panel:create "$b" board.note.markdown "Step 1"
yoloit panel:create "$b" board.note.markdown "Step 2"
yoloit panel:create "$b" board.note.markdown "Step 3"
yoloit link:create "$b" "Step 1" "Step 2"
yoloit link:create "$b" "Step 2" "Step 3"
yoloit board:arrange "$b" right
yoloit board:fit "$b"
```
