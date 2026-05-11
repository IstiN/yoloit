# YoLoIT CLI Commands

The YoLoIT CLI lets you control boards, panels, and panel content from the terminal.
The desktop app runs a local HTTP server; the `tools/yoloit` shell script wraps `curl` calls.

## Setup

```bash
# Add to PATH (or symlink)
export PATH="$PATH:/path/to/yoloit/tools"
```

The app writes its port to `~/.config/yoloit/cli.port` on startup.

---

## Board Commands

| Command | Description | Status |
|---------|-------------|--------|
| `yoloit boards` | List all boards | ✅ Implemented |
| `yoloit board <id\|name>` | Show board details | ✅ Implemented |
| `yoloit board:create <name>` | Create a new board | ✅ Implemented |
| `yoloit board:rename <id\|name> <new>` | Rename a board | ✅ Implemented |
| `yoloit board:delete <id\|name>` | Delete a board | ✅ Implemented |
| `yoloit board:focus <id\|name>` | Switch active board | ✅ Implemented |
| `yoloit board:snapshot <id\|name>` | Markdown snapshot of layout | ✅ Implemented |

## Panel Commands

| Command | Description | Status |
|---------|-------------|--------|
| `yoloit panels <board>` | List panels on a board | ✅ Implemented |
| `yoloit panel <board> <panel>` | Show panel details + content | ✅ Implemented |
| `yoloit panel:create <board> <type> <title>` | Create a panel | ✅ Implemented |
| `yoloit panel:rename <board> <panel> <new>` | Rename a panel | ✅ Implemented |
| `yoloit panel:move <board> <panel> <x> <y>` | Move panel position | ✅ Implemented |
| `yoloit panel:resize <board> <panel> <w> <h>` | Resize panel | ✅ Implemented |
| `yoloit panel:delete <board> <panel>` | Delete a panel | ✅ Implemented |

## Panel Actions

Actions are panel-type-specific. Use `yoloit do <board> <panel> <action> [json]`.

### Note (`board.note.markdown`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `get` | — | Get markdown content | ✅ Implemented |
| `set` | `{"content":"# Hello"}` | Set markdown content | ✅ Implemented |
| `append` | `{"content":"\nMore text"}` | Append to content | ✅ Implemented |

### Chat (`board.chat`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `send` | `{"message":"Hi!"}` | Send a chat message | ✅ Implemented |
| `messages` | — | Get all messages | ✅ Implemented |
| `config` | — | Get chat config (provider, model) | ✅ Implemented |
| `clear` | — | Clear chat history | ✅ Implemented |

### Kanban (`board.kanban`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `columns` | — | List all columns | ✅ Implemented |
| `cards` | `{"column":"Todo"}` | List cards in column | ✅ Implemented |
| `add-column` | `{"name":"Done"}` | Add a column | ✅ Implemented |
| `rename-column` | `{"column":"Old","name":"New"}` | Rename a column | ✅ Implemented |
| `remove-column` | `{"column":"Done"}` | Remove a column | ✅ Implemented |
| `add-card` | `{"column":"Todo","title":"Task"}` | Add a card | ✅ Implemented |
| `move-card` | `{"card":"Task","to":"Done"}` | Move card between columns | ✅ Implemented |
| `remove-card` | `{"column":"Todo","card":"Task"}` | Remove a card | ✅ Implemented |
| `update-card` | `{"column":"Todo","card":"Old","title":"New"}` | Update card title | ✅ Implemented |

### Webpage/Browser (`board.webpage`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `get` | — | Get current URL | ✅ Implemented |
| `open` | `{"url":"https://..."}` | Open a URL | ✅ Implemented |

### Playlist (`board.playlist`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `list` | — | List all tracks | ✅ Implemented |
| `add` | `{"path":"/music/song.mp3"}` | Add a track | ✅ Implemented |
| `remove` | `{"index":0}` | Remove a track | ✅ Implemented |
| `play` | `{"index":0}` (optional) | Play track | ✅ Implemented |
| `pause` | — | Pause playback | ✅ Implemented |
| `stop` | — | Stop playback | ✅ Implemented |
| `next` | — | Next track | ✅ Implemented |
| `prev` | — | Previous track | ✅ Implemented |

### Checklist (`board.checklist`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `items` | — | List all items | ✅ Implemented |
| `add` | `{"text":"Buy milk"}` | Add an item | ✅ Implemented |
| `check` | `{"index":0}` | Check an item | ✅ Implemented |
| `uncheck` | `{"index":0}` | Uncheck an item | ✅ Implemented |
| `remove` | `{"index":0}` | Remove an item | ✅ Implemented |
| `rename` | `{"index":0,"text":"New text"}` | Rename an item | ✅ Implemented |

### Code Snippet (`board.code.snippet`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `get` | — | Get code + language | ✅ Implemented |
| `set` | `{"code":"print('hi')","language":"python"}` | Set code | ✅ Implemented |

### Files (`board.files`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `get` | — | Get selected path | ✅ Implemented |
| `open` | `{"path":"/home/user/docs"}` | Open a path | ✅ Implemented |

### File Preview (`board.file.preview`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `get` | — | Get previewed file | ✅ Implemented |
| `open` | `{"path":"/home/user/img.png"}` | Preview a file | ✅ Implemented |

### Terminal (`board.terminal`)

| Action | JSON Body | Description | Status |
|--------|-----------|-------------|--------|
| `config` | — | Get terminal config | ✅ Implemented |
| `set-dir` | `{"dir":"/home/user"}` | Set working directory | ✅ Implemented |

## Link Commands

| Command | Description | Status |
|---------|-------------|--------|
| `yoloit links <board>` | List all links | ✅ Implemented |
| `yoloit link:create <board> <from> <to>` | Create a link | ✅ Implemented |
| `yoloit link:delete <board> <from> <to>` | Delete a link | ✅ Implemented |

---

## Examples

```bash
# List boards
yoloit boards

# Create a board and add panels
yoloit board:create "My Workspace"
yoloit panel:create "My Workspace" board.note.markdown "Notes"
yoloit panel:create "My Workspace" board.kanban "Tasks"

# Write a note
yoloit do "My Workspace" "Notes" set '{"content":"# Project Plan\n\n- Step 1\n- Step 2"}'

# Add kanban columns and cards
yoloit do "My Workspace" "Tasks" add-column '{"name":"Todo"}'
yoloit do "My Workspace" "Tasks" add-column '{"name":"Done"}'
yoloit do "My Workspace" "Tasks" add-card '{"column":"Todo","title":"Write docs"}'

# Get a snapshot
yoloit board:snapshot "My Workspace"

# Send a chat message
yoloit do "My Workspace" "Chat" send '{"message":"Summarize the project"}'

# Open a URL in browser panel
yoloit do "My Workspace" "Browser" open '{"url":"https://github.com"}'
```

## Architecture

```
┌──────────────┐     curl/HTTP      ┌──────────────────┐
│  tools/yoloit│ ──────────────────▶ │  CliServer       │
│  (bash)      │     localhost:PORT  │  (shelf)         │
└──────────────┘                    ├──────────────────┤
                                    │  Board routes    │
                                    │  Panel routes    │
                                    │  Link routes     │
                                    ├──────────────────┤
                                    │  PanelCliHandler │
                                    │  registry        │
                                    ├──────────────────┤
                                    │  NoteHandler     │
                                    │  ChatHandler     │
                                    │  KanbanHandler   │
                                    │  WebpageHandler  │
                                    │  PlaylistHandler │
                                    │  ChecklistHandler│
                                    │  CodeSnippet...  │
                                    │  FilesHandler    │
                                    │  FilePreview...  │
                                    │  TerminalHandler │
                                    └──────────────────┘
                                            │
                                    ┌───────▼──────────┐
                                    │   BoardCubit     │
                                    │   (state mgmt)   │
                                    └──────────────────┘
```

The server writes its port to `~/.config/yoloit/cli.port`. Adding a new panel type:
1. Create a handler extending `PanelCliHandler` in `lib/core/cli/handlers/`
2. Register it in `_AutoHostShellState._startCliServer()` in `app.dart`
3. Add documentation to this file
