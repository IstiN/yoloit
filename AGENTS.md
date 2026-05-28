# YoLoIT Agent Guidance (`AGENTS.md`)

This guide outlines non-obvious developer commands, compilation pipelines, strict coding standards, and agent operational gotchas for this codebase.

---

## ⚡ Non-Obvious Commands & Local Workflows

- **Interactive macOS Launch & Hot-Reload**:
  - Run: `./run.sh` (starts Flutter with a FIFO pipe at `/tmp/yoloit_flutter_stdin`).
  - Hot Reload: `./hot_reload.sh` (triggers hot-reload on the running instance by writing `r` to the pipe).
- **Dual Target & Web Client Compilation**:
  - Desktop app uses `lib/main.dart`.
  - Collaboration web client uses `lib/main_web.dart` and must be built via:
    `flutter build web --release --target lib/main_web.dart`
- **Windows Build Patch**:
  - Windows builds have a known Cargokit symlink resolution bug. **Always** run this patch before compiling on Windows:
    `.\windows\flutter\tools\patch_cargokit.ps1`
- **Git Submodules**:
  - Submodules are used for `packages/mermaid_renderer_flutter` and `third_party/flutter_local_models`. Initialize them using:
    `git submodule update --init --recursive --depth=1`

---

## 🛠️ YoLoIT CLI & App Development Workflows

- **CLI-First Development Philosophy**:
  - All features, actions, and state mutations must be designed **CLI-first**. Everything in the application—including managing and interacting with widgets on the boards—must be fully controllable via the `yoloit` CLI.
  - New functionality must expose commands that map seamlessly to both the terminal CLI and LLM Tools.
  - Every command must include a clear, concise, and **human-friendly description** so both humans and agents can easily discover, understand, and use them.
- **Long-Running Dev Processes**:
  - Never run long-running servers or builders directly in the chat foreground. Use the `yoloit` CLI:
    `yoloit panel:create "<board>" board.run "Run"` to create a runner panel, then:
    `yoloit do "<board>" "<panel>" run '{"id":"..."}'` to start the process persistently.
- **Multi-Step Board Mutations**:
  - Prefer `yoloit board:apply` with a YAML specification instead of sending many imperative single commands.
- **Custom JS App (Widget) Development**:
  - Always run `yoloit app:dev-skill` first to read the JavaScript API and UI rules.
  - **No Local Install Needed**: Develop `widget.js` and `manifest.json` in the current working directory, and control/test them directly:
    `yoloit app:run .` (open) | `yoloit app:reload .` (hot-reload) | `yoloit app:logs .` (stream console)

---

## 🛡️ Coding Conventions & Strict Analysis Constraints

- **Strict Analysis Rules** (Violations are treated as build/CI errors):
  - **Quotes**: Single quotes **only** (`prefer_single_quotes: true`). Double quotes fail linter checks.
  - **Imports**: Package-relative imports **only** (`always_use_package_imports: true`). e.g., `import 'package:yoloit/...';` (no relative imports).
  - **Strict Types**: Strict casts, strict inference, and strict raw types are enabled. Avoid `dynamic` type casting/calls.
  - **Unused Code**: Unused imports (`unused_import`) and unused variables (`unused_local_variable`) are treated as **errors**. Keep code completely clean before committing or running checks.
- **Platform Abstraction Rules**:
  - Do **not** use `Platform.isMacOS` or perform native OS processes (such as `osascript` or `open`) inside UI or BLoC feature code.
  - All platform-specific behaviors must be encapsulated within classes in `lib/core/platform/` with separate macOS, Linux, and Windows implementations.
- **Testing & FakeProcessRunner**:
  - Platform operations must have unit tests inside `test/unit/core/platform/` that use `FakeProcessRunner` to intercept command executions.
- **Headless & Offscreen Rendering Constraints**:
  - Offscreen rendering is performed via `BoardOffscreenRenderer` and `BoardCanvasPreview`.
  - **No `View.of()` Ancestors**: Headless trees lack a parent `View` widget. Wrap trees in `ScrollConfiguration(behavior: const HeadlessScrollBehavior())` and use `HeadlessScrollPhysics` to bypass the `ScrollAwareImageProvider` `View.of()` lookup. Avoid adding raw `SelectionArea` widgets offscreen.
  - **Smart Adaptive Polling**: Do NOT use artificial delays. Register loading states (JS engine startup, Mermaid diagram SVG-to-PNG compilation) to `HeadlessRenderRegistry.activeTasks`. The offscreen loop polls every 50ms, pumping builds and layouts, and completes once the task set has been completely empty for 4 consecutive turns (200ms debounce), preventing sequential async task transitions from being skipped.
  - **Single-Pass Painting**: For performance, do NOT call `flushCompositingBits` or `flushPaint` inside the polling loop. Only invoke them once at the very end of the loop, right before `toImage()`.
  - **Background Capture Cancel**: Always set `_cancelBgCapture = true` during board transitions or overview closing to immediately terminate any running offscreen captures and guarantee buttery-smooth transition animations.

---

## 🚨 Critical Agent Gotchas

- **No Heredocs (`cat << 'EOF'`)**:
  - **NEVER** use heredocs in bash commands. They consistently freeze the persistent agent bash session. Instead, write files using `printf` or `python3` (e.g., `python3 -c "open('file.txt', 'w').write(...)"`).
