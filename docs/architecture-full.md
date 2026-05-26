# YoLoIT — Full Architecture Reference

> Auto-generated. Contains Mermaid diagrams covering every major subsystem.

---

## 1. Top-Level Module Structure

```mermaid
graph TD
    subgraph lib["lib/"]
        core["core/\n─ cli/          CliServer, CliScript\n─ platform/     dirs, launcher, permissions\n─ services/     HookService, AgentHookService\n─ session/      SessionPrefs\n─ theme/        AppColors, AppColorScheme\n─ utils/"]
        features["features/\n─ board/        Board + Chat + Assistant + Panels\n─ editor/       Code/Markdown editor\n─ mindmap/      Mind-map panel\n─ preview/      Markdown preview\n─ runs/         Run configs\n─ settings/     Settings UI + data services\n─ terminal/     Embedded terminal\n─ search/       Global search\n─ snippets/"]
        ui["ui/\n─ Shell, shared widgets"]
        platform["platform/\n─ Platform-specific glue"]
    end
    core --> features
    features --> ui
```

---

## 2. Board System — Data Model & State

```mermaid
classDiagram
    class BoardState {
        +List~BoardDocument~ boards
        +String? activeBoardId
        +bool isLoaded
        +BoardDocument? activeBoard
    }

    class BoardDocument {
        +String id
        +String title
        +ViewportState viewport
        +List~BoardPanelInstance~ panels
        +List~BoardLink~ links
        +List~DrawingStroke~ drawings
        +Map metadata
        +toJson()
        +fromJson()
    }

    class BoardPanelInstance {
        +String id
        +String type
        +String title
        +PanelBounds bounds
        +Map params
        +Map state
        +int zIndex
        +bool hidden
        +bool locked
        +bool pinned
    }

    class BoardCubit {
        +BoardState state
        +load()
        +save()
        +createBoard()
        +deleteBoard()
        +setActiveBoard()
        +addPanel()
        +updatePanel()
        +removePanel()
        +focusPanel()
        +resizePanel()
        +movePanel()
        +createChatPanel()
        +createTerminalPanel()
        +createGenericPanel()
        -_persist()
        -SharedPreferences storage
    }

    class BoardPluginRegistry {
        +List~PanelPlugin~ plugins
        +markdown
        +kanban
        +webpage
        +codeSnippet
        +checklist
        +files
        +filePreview
        +playlist
        +run
        +runConfigs
        +chat
        +terminal
        +filetree
        +yoloAssistant
        +customWidget
        +timer
    }

    BoardState "1" *-- "many" BoardDocument
    BoardDocument "1" *-- "many" BoardPanelInstance
    BoardCubit --> BoardState : emits
    BoardCubit ..> BoardPluginRegistry : uses panel types
```

---

## 3. Board Persistence Flow

```mermaid
sequenceDiagram
    participant UI as BoardView (Flutter)
    participant Cubit as BoardCubit
    participant Prefs as SharedPreferences

    UI->>Cubit: addPanel(type, title, bounds)
    Cubit->>Cubit: update state
    Cubit->>Prefs: setString("board.documents.v1", json)
    Cubit->>Prefs: setString("board.active.id.v1", id)
    Cubit-->>UI: emit new BoardState

    Note over UI: Widget rebuild with new panel

    UI->>Cubit: updatePanel(panelId, newState)
    Cubit->>Prefs: setString("board.documents.v1", json)
    Cubit-->>UI: emit updated BoardState
```

---

## 4. Chat Panel — Full Lifecycle

```mermaid
flowchart TD
    A[ChatPanelWidget.initState] --> B[ChatSessionManager.getOrCreate\npanelId + ChatSessionConfig]
    B --> C{Restore from state?}
    C -->|yes| D[Load persisted messages\n+ session IDs]
    C -->|no| E[Fresh session]
    D --> F[ChatSession ready]
    E --> F

    F --> G[User types / voice input]
    G --> H[_sendMessage]
    H --> I{injectCliHelp?}
    I -->|1st message & enabled| J[CliGuidanceService.prependGuidance\n= cli_agent_guidance.md\n+ yoloit help --format short\n+ board/panel context]
    I -->|already injected| K[raw message]
    J --> L[provider.sendMessage]
    K --> L

    L --> M{provider type}
    M -->|cloud| N[CloudLlmProvider\nOpenAI-compatible HTTP]
    M -->|local| O[LocalLlmProvider\nlocal_models_flutter]
    M -->|copilot| P[CopilotCliProvider\ncopilot --output-format json]
    M -->|opencode| Q[OpenCodeProvider\nopencode run --format json]
    M -->|cursor| R[CursorAgentProvider\ncursor-agent --stream-json]

    N --> S[ChatEvent stream]
    O --> S
    P --> S
    Q --> S
    R --> S

    S --> T{event type}
    T -->|assistantDelta| U[_replaceAssistantMessageContent]
    T -->|toolStart| V[_appendToolMessage]
    T -->|toolComplete| W[_updateToolMessage]
    T -->|result| X[finalize message]

    U --> Y[_updateState → widget.onUpdateState]
    V --> Y
    W --> Y
    X --> Y

    Y --> Z[BoardCubit.updatePanel\npersist to SharedPreferences]
    Y --> AA[ChatSessionHistory.upsert\npersist to disk JSON]
```

---

## 5. Provider Chain — Interface & Implementations

```mermaid
classDiagram
    class ChatProvider {
        <<interface>>
        +String providerId
        +String displayName
        +List availableModels
        +bool supportsImages
        +Stream~ChatEvent~ sendMessage(message, config, tools)
        +stop()
        +bool isRunning()
        +setSessionId(id)
        +getSessionId() String?
        +detach()
        +dispose()
    }

    class CloudLlmProvider {
        +CloudLlmConfig config
        -openai_compatible HTTP
        -tool-calling loop
        +sendMessage()
        +stop()
    }

    class LocalLlmProvider {
        -local_models_flutter engine
        -YoloitCliToolCatalog tools
        +sendMessage()
        +stop()
    }

    class CopilotCliProvider {
        -Process: copilot --output-format json --yolo
        -sub-agent event watcher
        -session resume/name
        +sendMessage()
        +stop()
    }

    class OpenCodeProvider {
        -Process: opencode run --format json
        -log file watcher
        +sendMessage()
        +stop()
    }

    class CursorAgentProvider {
        -Process: cursor-agent --stream-json
        +sendMessage()
        +stop()
    }

    ChatProvider <|.. CloudLlmProvider
    ChatProvider <|.. LocalLlmProvider
    ChatProvider <|.. CopilotCliProvider
    ChatProvider <|.. OpenCodeProvider
    ChatProvider <|.. CursorAgentProvider
```

---

## 6. Tool System — Definition to Execution

```mermaid
flowchart LR
    subgraph Definition["Tool Definition"]
        A[yoloit_cli_tools.dart\nYoloitCliToolParam\nYoloitCliTool\nYoloitCliToolCatalog]
        B[assets/command_catalog/*.yaml\nhuman-readable variants]
    end

    subgraph Export["Tool Export Formats"]
        C[toLocalTool()\nJSON for local LLM]
        D[compactToolsJson()\ncompact for cloud LLM]
        E[catalogJson()\nfor /api/catalog endpoint]
        F[tools/yoloit script\nshell commands per tool]
    end

    subgraph Execution["Execution"]
        G[YoloitToolExecutor\ninterface]
        H[YoloitCliToolExecutor\nimpl]
        I[_resolveYoloitExecutable\n~/.config/yoloit/yoloit\nor source tree tools/yoloit]
        J[Process.run\nyoloit <command> <args>]
        K[CliServer\nlocalhost:PORT\nHTTP fallback]
    end

    A --> C
    A --> D
    A --> E
    B --> A
    C --> G
    D --> G
    G --> H
    H --> I
    I --> J
    H --> K
```

---

## 7. CLI Integration — Full Architecture

```mermaid
flowchart TD
    subgraph App["Flutter App"]
        CS["CliServer\nlocalhost:127.0.0.1\nephemeral port"]
        PF["~/.config/yoloit/cli.port\n(port file)"]
        SF["~/.config/yoloit/cli.vmservice\n(VM service URI)"]
        SH["~/.config/yoloit/yoloit\n(installed shell script)"]
        CS --> PF
        CS --> SF
        CS --> SH
    end

    subgraph Script["tools/yoloit shell script"]
        RC["Read cli.port"]
        CMD["yoloit <command> [args]"]
        HTTP["HTTP POST/GET\nlocalhost:PORT/..."]
    end

    subgraph Endpoints["CliServer Endpoints"]
        E1["GET /health"]
        E2["GET /api/vmservice"]
        E3["GET /api/catalog"]
        E4["GET /api/local-models/*"]
        E5["POST /api/lm/generate"]
        E6["GET|POST /api/yolochat/*"]
        E7["GET|POST /api/cloud-providers/*"]
        E8["GET|POST /api/voice-settings/*"]
        E9["GET|POST /boards/*"]
        E10["GET|POST /chats/*"]
        E11["GET|POST /agents/*\nagent:model, agent:asr\nagent:run, agent:config"]
        E12["GET|POST /panels/*"]
        E13["POST /tools/*\ntool invocation"]
        E14["GET|POST /search/*"]
        E15["GET|POST /apps/*\nwidget registry"]
    end

    CMD --> RC
    RC --> HTTP
    HTTP --> CS
    CS --> E1
    CS --> E2
    CS --> E3
    CS --> E4
    CS --> E5
    CS --> E6
    CS --> E7
    CS --> E8
    CS --> E9
    CS --> E10
    CS --> E11
    CS --> E12
    CS --> E13
    CS --> E14
    CS --> E15
```

---

## 8. UI ↔ CLI Interaction — Complete Flow

```mermaid
sequenceDiagram
    participant User
    participant FlutterApp as Flutter App\n(BoardView + ChatPanel)
    participant CliServer as CliServer\n(HTTP localhost:PORT)
    participant YoloitScript as yoloit script\n(~/.config/yoloit/yoloit)
    participant AgentCLI as Agent CLI\n(copilot/opencode/cursor)
    participant ToolExecutor as YoloitCliToolExecutor

    User->>FlutterApp: sends message in chat
    FlutterApp->>FlutterApp: inject CLI guidance\n(cli_agent_guidance.md\n+ yoloit help output\n+ board/panel context)
    FlutterApp->>AgentCLI: spawn process\n(copilot --yolo --output-format json)
    AgentCLI->>YoloitScript: calls tool: yoloit boards:list
    YoloitScript->>CliServer: GET /boards
    CliServer-->>YoloitScript: JSON response
    YoloitScript-->>AgentCLI: stdout JSON

    AgentCLI->>YoloitScript: calls tool: yoloit chat:send --board X
    YoloitScript->>CliServer: POST /chats/send
    CliServer->>FlutterApp: BoardCubit.updatePanel (state change)
    FlutterApp-->>User: UI updates

    AgentCLI-->>FlutterApp: streaming JSON events\n(assistantDelta, toolStart/Complete)
    FlutterApp-->>User: live streaming response

    Note over AgentCLI,ToolExecutor: For direct tool invocations (local/cloud LLM)
    FlutterApp->>ToolExecutor: invoke(toolName, args)
    ToolExecutor->>YoloitScript: Process.run(yoloit, [cmd, args])
    YoloitScript->>CliServer: HTTP request
    CliServer-->>YoloitScript: result JSON
    YoloitScript-->>ToolExecutor: stdout
    ToolExecutor-->>FlutterApp: tool result
```

---

## 9. CLI Help Injection — Detail

```mermaid
flowchart TD
    subgraph Trigger["When is help injected?"]
        T1["CopilotCliProvider.sendMessage\n(isFirstMessage = true)"]
        T2["OpenCodeProvider.sendMessage\n(isFirstMessage = true)"]
        T3["CursorAgentProvider.sendMessage\n(isFirstMessage = true)"]
    end

    subgraph Service["CliGuidanceService.prependGuidance()"]
        S1["Load asset:\nassets/prompts/cli_agent_guidance.md\n(static system prompt)"]
        S2["_fetchHelp()\n= Process.run(yoloit, help --format short)\ntimeout 4s"]
        S3["Cache result in _cachedHelp\n(cleared when settings change)"]
        S4["Resolve board context:\n- boardId\n- boardName\n- panelId\n- panelTitle"]
    end

    subgraph Output["Injected System Message"]
        O1["=== cli_agent_guidance.md ===\n(instructions for using yoloit tools)"]
        O2["Available yoloit commands:\n```\nyoloit boards:list\nyoloit chat:send ...\nyoloit panels:create ...\n...\n```"]
        O3["Current YoLoIT UI context:\n- Current board id: xxx\n- Current board name: xxx\n- Current chat panel id: xxx\n- Current chat panel title: xxx"]
        O4["User request:\n<actual user message>"]
        O1 --> O2 --> O3 --> O4
    end

    T1 --> Service
    T2 --> Service
    T3 --> Service
    S1 --> Output
    S2 --> S3 --> Output
    S4 --> Output
```

---

## 10. Yolo Assistant — Architecture

```mermaid
flowchart TD
    subgraph YoloAssistant["YoloAssistantWidget (voice-first panel)"]
        UA["User input\n(text or voice)"]
        MIC["Mic recording\nRecord package\n→ PCM bytes"]
        ASR["ASR: CloudAsrService\nor local whisper"]
        MSG["_sendMessage(text, audioContent?)"]
        STATE["_updateState(patch)\n_pendingStateOverrides merge\nprevents stale writes"]
        DRAFT["_messageDraft\n(in-flight message buffer)"]
        OVERLAY["VoiceOverlay sync\n_syncOverlayState()"]
        HISTORY["_persistToHistory()\nChatSessionHistory.upsert()\nid: yolo-<timestamp>"]
        BAR["Session bar\n[History 🕐] [New +] [Clear 🗑]"]
    end

    subgraph Providers["Provider (same as ChatPanel)"]
        P1["CloudLlmProvider\n(cloud:openai, cloud:openrouter…)"]
        P2["LocalLlmProvider\n(local MLX)"]
    end

    subgraph Tools["Tool Execution"]
        TE["_AssistantToolExecutor\n(wraps YoloitCliToolExecutor)"]
        FOCUS["onFocusPanel callback\n→ yoloit_panel_focus tool"]
    end

    UA --> MSG
    MIC --> ASR --> MSG
    MSG --> P1
    MSG --> P2
    P1 --> STATE
    P2 --> STATE
    STATE --> DRAFT
    STATE --> OVERLAY
    STATE --> HISTORY
    TE --> FOCUS

    BAR --> HISTORY_DLG["_AssistantHistoryDialog\nlist past yolo-* sessions\nrestore / delete"]
```

---

## 11. Voice & ASR Pipeline

```mermaid
sequenceDiagram
    participant User
    participant Widget as YoloAssistantWidget\nor ChatPanelWidget
    participant Recorder as Record package\n(microphone)
    participant AsrService as CloudAsrService
    participant CloudAPI as Cloud Provider\n(OpenAI /audio/transcriptions\nor inline audio)
    participant LLM as LLM Provider

    User->>Widget: hold mic button
    Widget->>Recorder: start recording (PCM stream)
    Recorder-->>Widget: amplitude stream → visualizer
    User->>Widget: release mic button
    Widget->>Recorder: stop() → get audio bytes
    Widget->>AsrService: transcribeFromBytes(bytes, voiceSettings)
    AsrService->>AsrService: convert to MP3 (ffmpeg)
    AsrService->>CloudAPI: POST /audio/transcriptions\nor multipart audio in /chat/completions
    CloudAPI-->>AsrService: transcript text
    AsrService-->>Widget: transcript string
    Widget->>LLM: sendMessage(transcript)
    LLM-->>Widget: streaming response
```

---

## 12. Settings & Configuration — Data Services

```mermaid
classDiagram
    class AgentConfig {
        +String id
        +String displayName
        +String iconLabel
        +String launchCommand
        +bool visible
        +bool isBuiltIn
        +String? defaultModel
        +String asrMode  [default|local|cloud]
        +String? asrCloudConfigId
        +String? asrCloudModel
        +copyWith()
        +toJson()
        +fromJson()
    }

    class AgentConfigService {
        +List~AgentConfig~ configs
        +String? defaultAgentId
        +String defaultAsrMode
        +String? defaultAsrCloudConfigId
        +String? defaultAsrCloudModel
        +load() List~AgentConfig~
        +save(configs)
        +setDefaultAgentId(id)
        +saveDefaultAsr(mode, configId, model)
        +effectiveAsr(agentId) AsrConfig
        -_savePrefs()
        -agent_configs.json
        -agent_prefs.json
    }

    class CloudLlmConfig {
        +String id
        +String name
        +String baseUrl
        +String apiKey
        +String model
        +bool isValid
    }

    class CloudLlmSettingsService {
        +List~CloudLlmConfig~ configs
        +String? activeConfigId
        +String assistantProviderType  [local|cloud]
        +VoiceSettings voiceSettings
        +loadConfigs() List~CloudLlmConfig~
        +saveConfigs(configs)
        +loadActiveConfig() CloudLlmConfig?
        +setActiveConfigId(id)
        +setAssistantProvider(type)
        +loadVoiceSettings() VoiceSettings
        +saveVoiceSettings(settings)
        -SecureStorage key: cloud_llm_configs_v1
    }

    class VoiceSettings {
        +String asrMode  [local|cloud]
        +String? asrCloudConfigId
        +String? asrCloudModel
    }

    AgentConfigService "1" *-- "many" AgentConfig
    CloudLlmSettingsService "1" *-- "many" CloudLlmConfig
    CloudLlmSettingsService "1" *-- "1" VoiceSettings
    AgentConfig --> VoiceSettings : asrMode resolves to
```

---

## 13. Session History — Storage Model

```mermaid
flowchart LR
    subgraph Sources["Who writes history?"]
        CP["ChatPanelWidget\n_persistMessages()\non every message update"]
        YA["YoloAssistantWidget\n_persistToHistory()\nafter each reply + newSession"]
    end

    subgraph Service["ChatSessionHistory.instance"]
        UP["upsert(entry, messages)\n─ update metadata list\n─ keep last 50 sessions\n─ save messages to disk"]
        LA["loadAll()\n→ List~ChatSessionEntry~ (metadata only)"]
        LM["loadMessages(id)\n→ List~Map~ (full messages)"]
        DEL["delete(id)\n→ remove metadata + disk file"]
    end

    subgraph Storage["Storage"]
        SP["SharedPreferences\nkey: chat_session_history\n(JSON list of ChatSessionEntry)"]
        DISK["<appSupportDir>/chat_sessions/<id>.json\n(full message history per session)"]
    end

    subgraph Consumers["Who reads history?"]
        SHD["_SessionHistoryDialog\n(board chat panels)"]
        AHD["_AssistantHistoryDialog\n(yolo assistant)\nfilters: id starts with yolo-"]
        CLI["CliServer\nGET /chats/history\nPOST /chats/restore"]
    end

    CP --> Service
    YA --> Service
    UP --> SP
    UP --> DISK
    LA --> SP
    LM --> DISK
    DEL --> SP
    DEL --> DISK
    Service --> Consumers
```

---

## 14. JS Widget Engine

```mermaid
flowchart TD
    subgraph Registry["WidgetRegistryService"]
        WR["Discovers widgets in\n~/.config/yoloit/apps/\nCopies bundled examples"]
        WM["WidgetEngineManager\ncreates one JsWidgetEngine per panel\nupdates BoardCubit on title/storage change"]
    end

    subgraph Engine["JsWidgetEngine (flutter_js)"]
        JS["Evaluates widget JS code\n(JavascriptCoreRuntime)"]
        B1["Bridge: render(tree)\n→ json_widget_renderer.dart\n→ Flutter widget tree"]
        B2["Bridge: fetchJson(url)\nasync HTTP fetch"]
        B3["Bridge: exec(cmd, args)\n→ Process.run"]
        B4["Bridge: storage.get/set\npersists in panel state"]
        B5["Bridge: secrets.get\nreads from secure storage"]
        B6["Bridge: panelTitle.set(t)\ncalls onUpdateTitle"]
        B7["Bridge: showError(msg)"]
        B8["Bridge: loadAsset(path)\n→ rootBundle.loadString"]
        B9["Timers: setInterval/setTimeout"]
        B10["requestAnimationFrame"]
        B11["console.log/error/warn"]
    end

    subgraph Renderer["json_widget_renderer.dart"]
        R1["type: center → Center"]
        R2["type: column → Column"]
        R3["type: text → Text"]
        R4["type: button → ElevatedButton"]
        R5["type: image → Image.network"]
        R6["... all Flutter widgets"]
    end

    WM --> Engine
    JS --> B1
    JS --> B2
    JS --> B3
    JS --> B4
    JS --> B5
    JS --> B6
    JS --> B7
    JS --> B8
    JS --> B9
    JS --> B10
    JS --> B11
    B1 --> Renderer
```

---

## 15. Hook System

```mermaid
flowchart TD
    subgraph HookFiles["Hook Files"]
        HF["~/.yoloit/hooks/*.json\npolled every 2 seconds"]
        HJ["hooks.json — hook registry\n~/.yoloit/bin symlink"]
    end

    subgraph Service["AgentHookService"]
        POLL["Poll loop\nevery 2s → read *.json\ndelete after read"]
        EMIT["emit HookEvent\n(event, phase, cwd, tool, ts)"]
    end

    subgraph Events["Hook Events"]
        EV1["sessionStart"]
        EV2["sessionEnd"]
        EV3["userPromptSubmitted"]
        EV4["preToolUse → phase: tool:<toolName>"]
        EV5["postToolUse"]
        EV6["errorOccurred"]
    end

    subgraph Phases["ThinkingPhase mapping"]
        PH1["ThinkingPhase — model thinking"]
        PH2["ToolPhase — tool execution"]
        PH3["DonePhase — response complete"]
        PH4["ErrorPhase — error"]
    end

    subgraph Consumers["Who reacts to hooks?"]
        C1["ChatPanelWidget\n→ update agent status indicator\n→ show tool activity"]
        C2["YoloAssistantWidget\n→ sync overlay status"]
        C3["BoardView\n→ particle / animation effects"]
    end

    HF --> POLL
    POLL --> EMIT
    EMIT --> EV1
    EMIT --> EV2
    EMIT --> EV3
    EMIT --> EV4
    EMIT --> EV5
    EMIT --> EV6
    EV4 --> PH2
    EV1 --> PH1
    EV6 --> PH4
    EMIT --> Consumers
```

---

## 16. Full System — Bird's Eye View

```mermaid
flowchart TB
    subgraph Flutter["Flutter App (macOS/Windows/Linux)"]
        subgraph UI["UI Layer"]
            BV["BoardView\n(main canvas)"]
            PP["Panel widgets\n(chat, terminal, markdown,\nkanban, yolo assistant…)"]
            SP["Settings Page\n(agents, cloud LLM,\nvoice, ASR)"]
        end

        subgraph State["State Layer"]
            BC["BoardCubit\n(Bloc)"]
            SH2["SharedPreferences\n(board JSON)"]
        end

        subgraph Chat["Chat Engine"]
            CPW["ChatPanelWidget"]
            YAW["YoloAssistantWidget"]
            PROV["Providers\nCloud/Local/Copilot\nOpenCode/Cursor"]
            CGS["CliGuidanceService\n(help injection)"]
            CSH["ChatSessionHistory\n(disk persistence)"]
        end

        subgraph ToolsLayer["Tool Layer"]
            TCat["YoloitCliToolCatalog\n(tool definitions)"]
            TExec["YoloitCliToolExecutor\n(tool invocation)"]
        end

        subgraph Services["Services"]
            CLISRV["CliServer\n(HTTP localhost:PORT)"]
            AGTSVC["AgentConfigService\n(agent_configs.json)"]
            CLDSVC["CloudLlmSettingsService\n(secure storage)"]
            HOOKS["AgentHookService\n(poll ~/.yoloit/hooks)"]
            JSENG["JsWidgetEngine\n(flutter_js)"]
        end
    end

    subgraph Disk["Disk / Config Files"]
        PORT["~/.config/yoloit/cli.port"]
        SCRIPT["~/.config/yoloit/yoloit\n(installed CLI script)"]
        VMURI["~/.config/yoloit/cli.vmservice"]
        ACFG["agent_configs.json"]
        APREFS["agent_prefs.json"]
        CSESS["<appSupport>/chat_sessions/*.json"]
        HOOKF["~/.yoloit/hooks/*.json"]
    end

    subgraph External["External Processes"]
        COPILOT["copilot CLI"]
        OPENCODE["opencode CLI"]
        CURSOR["cursor-agent CLI"]
        CLOUDAPI["Cloud LLM APIs\n(OpenAI, OpenRouter…)"]
        LOCALMLX["local_models MLX\n(embedded)"]
    end

    BV <--> BC
    BC <--> SH2
    PP --> CPW
    PP --> YAW
    CPW --> PROV
    YAW --> PROV
    PROV --> CGS
    PROV --> COPILOT
    PROV --> OPENCODE
    PROV --> CURSOR
    PROV --> CLOUDAPI
    PROV --> LOCALMLX
    CPW --> CSH
    YAW --> CSH
    CSH --> CSESS

    CLISRV --> PORT
    CLISRV --> SCRIPT
    CLISRV --> VMURI
    SCRIPT -.->|HTTP| CLISRV

    TExec --> SCRIPT
    PROV --> TExec
    TExec --> TCat

    AGTSVC --> ACFG
    AGTSVC --> APREFS
    CLDSVC -.-> SecureStorage

    HOOKS --> HOOKF
    HOOKS --> CPW
    HOOKS --> YAW
```

---

## 17. ASR Model Selection — Resolution Chain

```mermaid
flowchart TD
    A[ChatPanelWidget or YoloAssistantWidget\nneeds ASR for a given agent] --> B{agent.asrMode?}
    B -->|default| C[AgentConfigService.effectiveAsr\nagentId]
    B -->|local| D[Use local Whisper]
    B -->|cloud| E[Use cloud ASR config\nfrom agent.asrCloudConfigId\n+ agent.asrCloudModel]

    C --> F{defaultAsrMode?}
    F -->|local| D
    F -->|cloud| G[Use defaultAsrCloudConfigId\n+ defaultAsrCloudModel]

    D --> H[CloudAsrService\nasrMode=local\n→ local whisper model]
    E --> I[CloudAsrService\nasrMode=cloud\n→ CloudLlmConfig lookup\n→ POST /audio/transcriptions]
    G --> I
```
