# YoLoIT Board View — Architecture

This document describes how the Board View works, how panels are built, registered, and controlled via CLI.

---

## High-Level Architecture

```mermaid
graph TB
    subgraph App["Flutter App"]
        BV["BoardView<br/>(board_view.dart)"]
        BC["BoardCubit<br/>(BLoC state)"]
        PR["BoardPluginRegistry<br/>(singleton)"]
        CS["CLI Server<br/>(localhost)"]
    end

    BV -->|reads state| BC
    BV -->|looks up plugins| PR
    CS -->|dispatches actions| BC

    subgraph Plugins["Board Plugins"]
        P1["MarkdownNotePlugin"]
        P2["KanbanPlugin"]
        P3["ChatPanelPlugin"]
        P4["FileTreePlugin"]
        P5["RunConfigsPlugin"]
        P6["YoloAssistantPlugin"]
        P7["TerminalPlugin"]
        P8["...others"]
    end

    PR -->|registers| Plugins

    subgraph Handlers["CLI Handlers"]
        H1["NoteCliHandler"]
        H2["KanbanCliHandler"]
        H3["ChatCliHandler"]
        H4["FileTreeCliHandler"]
        H5["RunConfigsCliHandler"]
        H6["AssistantCliHandler"]
        H7["TerminalCliHandler"]
        H8["...others"]
    end

    CS -->|routes `do` command| Handlers
    Handlers -->|returns CliActionResult| CS
```

---

## Panel Lifecycle

```mermaid
sequenceDiagram
    participant U as User / CLI
    participant BV as BoardView
    participant BC as BoardCubit
    participant PR as PluginRegistry
    participant PW as Panel Widget

    U->>BC: panel:create type title
    BC->>PR: pluginFor(typeId)
    PR-->>BC: BoardPanelPlugin
    BC->>BC: create BoardPanelInstance<br/>(id, type, title, bounds, initialState)
    BC-->>BV: emit new BoardState
    BV->>PR: pluginFor(panel.type)
    PR-->>BV: plugin
    BV->>PW: plugin.buildContent(panel, onUpdateState)
    PW-->>BV: Widget tree
```

---

## Plugin Registration

All plugins are registered at startup in `BoardPluginRegistry._registerBuiltins()`:

```mermaid
classDiagram
    class BoardPanelPlugin {
        <<abstract>>
        +String typeId
        +String displayName
        +IconData icon
        +Size defaultSize
        +Map~String,dynamic~ initialState
        +Widget buildContent(panel, onUpdate)
        +Widget? buildIconWidget(context, size)?
        +Future~bool~ showEditor(context, panel)?
    }

    class FileTreePlugin {
        typeId = "board.filetree"
        displayName = "File Tree"
        icon = Icons.folder_open
        defaultSize = 320×500
    }

    class RunConfigsPlugin {
        typeId = "board.run_configs"
        displayName = "Run Configs"
        icon = Icons.play_circle_outline
        defaultSize = 600×400
    }

    class YoloAssistantPlugin {
        typeId = "board.yolo_assistant"
        displayName = "YoLo Assistant"
        icon = Icons.auto_awesome
        defaultSize = 420×560
        +buildIconWidget() → SVG
    }

    class BoardTerminalPanelPlugin {
        typeId = "board.terminal"
        displayName = "Terminal"
        icon = Icons.terminal
        defaultSize = 520×360
    }

    BoardPanelPlugin <|-- FileTreePlugin
    BoardPanelPlugin <|-- RunConfigsPlugin
    BoardPanelPlugin <|-- YoloAssistantPlugin
    BoardPanelPlugin <|-- BoardTerminalPanelPlugin
```

---

## CLI Handler Architecture

```mermaid
graph LR
    subgraph CLI["CLI Tool (shell)"]
        CMD["yoloit do BOARD PANEL action args..."]
    end

    subgraph Server["CLI Server (Flutter)"]
        RT["Router"]
        HM["Handler Map<br/>(typeId → handler)"]
    end

    subgraph Handler["PanelCliHandler"]
        GA["getContent(panel)"]
        HA["handleAction(action, args, panel)"]
        AH["actionHelp"]
    end

    CMD -->|HTTP POST| RT
    RT -->|lookup typeId| HM
    HM -->|dispatch| Handler
    Handler -->|CliActionResult| RT
    RT -->|JSON response| CMD
```

### CLI Handler Interface

```mermaid
classDiagram
    class PanelCliHandler {
        <<abstract>>
        +String typeId
        +List~String~ supportedActions
        +Map~String,dynamic~ getContent(panel)
        +Future~CliActionResult~ handleAction(action, args, panel)
        +Map~String,CliActionHelp~ actionHelp
    }

    class CliActionResult {
        +String? message
        +Map~String,dynamic~? stateUpdate
        +bool success
    }

    class FileTreeCliHandler {
        typeId = "board.filetree"
        actions: list, open, expand, collapse, set-root, refresh
    }

    class RunConfigsCliHandler {
        typeId = "board.run_configs"
        actions: list, add, remove, run, stop, input, output, config
    }

    class AssistantCliHandler {
        typeId = "board.yolo_assistant"
        actions: send, messages, clear, skills, add-skill, remove-skill, mode, voice-start, voice-stop
    }

    class TerminalCliHandler {
        typeId = "board.terminal"
        actions: config, set-dir
    }

    PanelCliHandler <|-- FileTreeCliHandler
    PanelCliHandler <|-- RunConfigsCliHandler
    PanelCliHandler <|-- AssistantCliHandler
    PanelCliHandler <|-- TerminalCliHandler
```

---

## How to Add a New Panel

### Step 1 — Create the Plugin

Create `lib/features/board/plugins/builtin/my_plugin.dart`:

```dart
class MyPlugin extends BoardPanelPlugin {
  const MyPlugin();

  @override String get typeId => 'board.my_panel';
  @override String get displayName => 'My Panel';
  @override IconData get icon => Icons.widgets;
  @override Size get defaultSize => const Size(400, 300);
  @override Map<String, dynamic> get initialState => {'key': 'value'};

  @override
  Widget buildContent(BoardPanelInstance panel, ValueChanged<Map<String, dynamic>> onUpdateState) {
    return MyPanelWidget(panel: panel, onUpdateState: onUpdateState);
  }
}
```

### Step 2 — Register the Plugin

In `lib/features/board/plugins/board_plugin_registry.dart`, add to `_registerBuiltins()`:

```dart
register(const MyPlugin());
```

### Step 3 — Add to genericTypes

In `lib/features/board/ui/board_view.dart` ~line 3587, add the typeId to `genericTypes`:

```dart
final genericTypes = [
  // ...existing types...
  'board.my_panel',
];
```

### Step 4 — Create CLI Handler (optional)

Create `lib/core/cli/handlers/my_handler.dart`:

```dart
class MyCliHandler extends PanelCliHandler {
  const MyCliHandler();

  @override String get typeId => 'board.my_panel';
  @override List<String> get supportedActions => ['get', 'set'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'key': panel.state['key'] ?? ''};
  }

  @override
  Future<CliActionResult> handleAction(String action, List<String> args, BoardPanelInstance panel) async {
    switch (action) {
      case 'set':
        return CliActionResult(message: 'Updated', stateUpdate: {'key': args.first});
      default:
        return CliActionResult.error('Unknown action: $action');
    }
  }
}
```

Register in `lib/app.dart`:

```dart
server.registerPanelHandler(const MyCliHandler());
```

### Step 5 — Write Tests

Create `test/unit/core/cli/handlers/my_handler_test.dart` covering:
- `typeId` matches
- `supportedActions` list
- `getContent()` with default and populated state
- Each action handler (success + error cases)

### Step 6 — Update Documentation

Add to `docs/cli-llm.md`:
- Panel type in the Types table
- Actions in the `do` Actions table

---

## Board View Layout

```mermaid
graph TB
    subgraph BoardView["BoardView (StatefulWidget)"]
        Stack["Stack"]

        subgraph Canvas["Canvas Layer"]
            Grid["Grid Background"]
            Links["Connection Links"]
            Panels["Panel Widgets<br/>(Positioned, draggable)"]
        end

        subgraph Overlay["Overlay Layer"]
            Sidebar["Sidebar Menu (+)"]
            Minimap["Mini Map"]
            Toolbar["Top Toolbar"]
            Badge["YOLO Badge<br/>+ Slide-out Chat"]
        end

        Stack --> Canvas
        Stack --> Overlay
    end
```

### YOLO Badge Behavior

```mermaid
stateDiagram-v2
    [*] --> Hidden: App starts
    Hidden --> BadgeVisible: 300ms delay
    BadgeVisible --> ChatOpen: Click badge
    ChatOpen --> BadgeVisible: Click X / badge
    
    state BadgeVisible {
        [*] --> RightEdge
        note right of RightEdge: Vertical "YOLO" tab\nflush to window right edge
    }
    
    state ChatOpen {
        [*] --> PanelSlideIn
        PanelSlideIn --> FullyOpen: ClipRect animation
        note right of FullyOpen: YoloAssistantWidget\n(same as board panel)\nBadge becomes X tab
    }
```

---

## File Structure

```
lib/features/board/
├── ui/
│   └── board_view.dart          # Main board rendering (~5600 lines)
├── bloc/
│   ├── board_cubit.dart         # BLoC state management
│   └── board_state.dart         # State classes
├── model/
│   ├── board_models.dart        # BoardPanelInstance, BoardPanelBounds
│   └── chat_models.dart         # Chat-specific models
├── plugins/
│   ├── board_plugin.dart        # Abstract plugin base class
│   ├── board_plugin_registry.dart  # Singleton registry
│   └── builtin/
│       ├── filetree_plugin.dart
│       ├── run_configs_plugin.dart
│       ├── yolo_assistant_plugin.dart
│       ├── file_preview_plugin.dart
│       ├── webpage_plugin.dart
│       ├── kanban_plugin.dart
│       ├── checklist_plugin.dart
│       ├── code_snippet_plugin.dart
│       ├── files_plugin.dart
│       └── playlist_plugin.dart
├── assistant/
│   ├── yolo_assistant_widget.dart    # Assistant UI (text + voice)
│   └── assistant_voice_visualizer.dart
├── chat/
│   ├── chat_panel_plugin.dart
│   └── chat_panel_widget.dart
├── terminal/
│   ├── board_terminal_panel_plugin.dart
│   └── board_terminal_panel_widget.dart
└── tools/
    └── board_tool.dart          # Board interaction tools

lib/core/cli/
├── cli_server.dart              # HTTP server for CLI
├── panel_cli_handler.dart       # Abstract handler base
└── handlers/
    ├── filetree_handler.dart
    ├── run_configs_handler.dart
    ├── assistant_handler.dart
    ├── terminal_handler.dart
    ├── note_handler.dart
    ├── chat_handler.dart
    ├── kanban_handler.dart
    ├── checklist_handler.dart
    ├── code_snippet_handler.dart
    ├── files_handler.dart
    ├── playlist_handler.dart
    └── webpage_handler.dart
```

---

## All Panel Types

| Type ID | Display Name | Icon | Default Size | CLI Actions |
|---------|-------------|------|-------------|-------------|
| `board.note.markdown` | Markdown Note | 📝 | 300×240 | get, set, append, wrap, nowrap |
| `board.checklist` | Checklist | ✅ | 280×360 | items, add, check, uncheck, remove, rename |
| `board.kanban` | Kanban | 📊 | 600×400 | columns, cards, add-column, rename-column, remove-column, add-card, move-card, remove-card, update-card |
| `board.chat` | Chat | 💬 | 360×480 | send, messages, config, clear |
| `board.playlist` | Playlist | 🎵 | 380×480 | list, add, remove, play, pause, stop, next, prev |
| `board.webpage` | Webpage | 🌐 | 640×480 | open, get |
| `board.code.snippet` | Code Snippet | 💻 | 400×300 | get, set |
| `board.files` | Files | 📁 | 320×400 | get, open |
| `board.file.preview` | File Preview | 🖼️ | 400×400 | get, open |
| `board.terminal` | Terminal | ⌨️ | 520×360 | config, set-dir |
| `board.filetree` | File Tree | 🌳 | 320×500 | list, set-root, expand, collapse, open, refresh |
| `board.run_configs` | Run Configs | ▶️ | 600×400 | list, add, remove, run, stop, input, output, config |
| `board.yolo_assistant` | YoLo Assistant | 🤖 | 420×560 | send, messages, clear, skills, add-skill, remove-skill, mode, voice-start, voice-stop |
