# YoLo Chat — LLM Request Flow

How a user message travels from Flutter UI → Dart → Swift (MLX) → back.

---

## Architecture overview

```mermaid
flowchart TD
    subgraph Flutter UI
        A[User types message\nor uses mic] --> B[_sendMessage\nyolo_assistant_widget.dart]
        B --> C[_buildMessagesForRequest\nBuilds structured messages list]
        C --> D[LmCompletionRequest\n{messages, tools, maxTokens, temperature}]
    end

    subgraph Dart Runtime Layer
        D --> E[NativeLmEngine.completeStreaming\nnative_engines.dart]
        E --> F[_lmGeneratePayload\nSerialises to JSON map]
        F --> G[_invokeFlmDispatch\nMethodChannel → Swift]
    end

    subgraph Swift  FlmMLXRuntime
        G --> H[flm_dispatch_json_stream\nFlmDispatch.swift]
        H --> I[handleLmGenerateStreaming]
        I --> J[parseMessagesPayload\nExtracts instructions, history, lastUserMessage]
        I --> K[parseToolsPayload\nExtracts ToolSpec array]
        J --> L[makeChatSessionWithHistory\nChatSession init with instructions + history + tools]
        K --> L
        L --> M[session.respond\nto: lastUserMessage]
        M -->|stream chunks| N[chunkCallback → Dart]
    end

    subgraph Dart UI update
        N --> O[onChunk → setState\nStreams assistant text]
        O --> P[_engine.lastNativeTimings\nSwift timing fields stored]
        P --> Q[_debugSessions\nDebug view updated]
    end
```

---

## What is in each layer

### 1. `_buildMessagesForRequest` (Dart)

Builds the `messages` list in OpenAI-style `[{role, content}]` format:

| Index | role | content |
|-------|------|---------|
| 0 | `system` | Full system prompt from `assets/prompts/yolo_chat_system_prompt.md` + current board/panel context snapshot |
| 1…n-1 | `user` / `assistant` / `tool` | Prior conversation turns stored in panel state |
| n | `user` | The new message being sent |

### 2. `LmCompletionRequest` (Dart)

```dart
LmCompletionRequest(
  modelPath: ...,   // Path to installed model directory
  manifest: ...,    // Model manifest (type, runtime adapter, etc.)
  messages: [...],  // Structured messages list (see above)
  maxTokens: 1024,
  temperature: 0.2,
  tools: [...],     // List<LocalTool> — enabled YoLoIT function tools
  onToolCall: ...,  // Dart async callback invoked when model calls a tool
)
```

### 3. `_lmGeneratePayload` (Dart → JSON wire)

The request is serialised to a `Map<String, Object?>` and sent over the Flutter MethodChannel:

```json
{
  "modelPath": "/path/to/model",
  "messages": [
    {"role": "system",    "content": "...system prompt..."},
    {"role": "user",      "content": "prior user turn"},
    {"role": "assistant", "content": "prior assistant reply"},
    {"role": "user",      "content": "new user message"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "yoloit_panel_create",
        "description": "...",
        "parameters": { ... }
      }
    }
  ],
  "maxTokens": 1024,
  "temperature": 0.2
}
```

> **Note:** `messages` and `tools` are sent as two _separate_ top-level keys.  
> Tools are NOT embedded inside the messages array.

### 4. `parseMessagesPayload` (Swift)

Walks the `messages` array and splits it into three parts:

- `instructions` — the `system` role entry → becomes `ChatSession(instructions:)`
- `history` — all entries except the last `user` turn → becomes `ChatSession(history:)` (KV-cache re-hydration)
- `lastUserMessage` — the last `user` entry → passed to `session.respond(to:)`

### 5. `makeChatSessionWithHistory` (Swift)

Creates an MLX `ChatSession` with the correct init depending on what's present:

```swift
ChatSession(
    modelContainer,
    instructions: instructions,  // system prompt → model's <|im_start|>system token
    history: history,            // prior turns → KV-cache pre-load
    generateParameters: generateParameters,
    tools: tools,                // ToolSpec array → model's tool calling header
    toolDispatch: toolDispatch   // Swift → Dart callback bridge
)
```

### 6. Tool calling bridge

When the model emits a tool call, MLX invokes `toolDispatch` (a Swift async closure). This closure calls the `NativeCallable` address embedded in the payload, which crosses back into Dart via `onToolCall`. Dart then executes the YoLoIT CLI command and returns the result as a string back through the same bridge.

```
Model emits tool call JSON
  → Swift toolDispatch closure
    → NativeCallable (Dart port)
      → onToolCall(name, arguments) in Dart
        → _handleToolCall → yoloit CLI
          → result String returned to Swift
            → Swift passes result back to ChatSession
              → model continues generating
```

---

## ASR (microphone) flow

ASR is a **separate path** and does NOT go through `LmCompletionRequest`:

```
Mic recording (record package)
  → _stopRecordingAndTranscribe
    → LocalAiModelsService.transcribeWithSelectedAsr(audioPath)
      → LocalAudioRunner.transcribeAudio
        → NativeAudioEngine.transcribe → flm_dispatch_json("audio.transcribe", ...)
          → FlmAudioMLX.transcribe (Swift, Qwen3-ASR only)
            → FlmQwenMLXRuntime.transcribe
              → returns text
  → text placed in _inputController
  → _sendMessage called normally
```

Only **Qwen3-ASR** models are supported natively in Swift. Whisper and VibeVoice ASR require the Python `mlx-audio` fallback (not currently wired up in the UI).

---

## Debug view tabs

The chat debug panel (`⚙ icon → debug sessions`) shows:

| Tab | What it shows |
|-----|--------------|
| **timings** | Dart-side timestamps (requestAt, promptSentAt, firstTokenAt, completedAt) + Swift MLX timing fields (cache hit, TTFT, generation ms) |
| **messages** | The exact `messages` JSON array sent to the model (structured `[{role, content}]`) |
| **tools** | The tool schemas (`toOpenAIJson()`) sent in the `tools` key + each tool call made during this session |
| **raw output** | The raw unprocessed text streamed back from the model |

---

## Key files

| File | Purpose |
|------|---------|
| `lib/features/board/assistant/yolo_assistant_widget.dart` | UI, `_buildMessagesForRequest`, `_sendMessage`, debug sessions |
| `lib/features/board/chat/local_llm_provider.dart` | Chat panel LLM provider, `_buildMessages` |
| `lib/features/settings/data/local_ai_models_service.dart` | Model selection, `transcribeWithSelectedAsr` |
| `third_party/.../lib/runtime/native_engines.dart` | `LmCompletionRequest`, `NativeLmEngine`, `_lmGeneratePayload` |
| `third_party/.../FlmDispatch.swift` | Swift entry point, `parseMessagesPayload`, `makeChatSessionWithHistory`, `handleLmGenerateStreaming` |
| `third_party/.../FlmAudioMLX.swift` | ASR/TTS Swift handlers |
| `assets/prompts/yolo_chat_system_prompt.md` | System prompt markdown loaded at runtime |
