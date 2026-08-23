# YoLoIT Agent Guidance (`AGENTS.md`)

This guide outlines non-obvious developer commands, compilation pipelines, strict coding standards, and agent operational gotchas for this codebase.

---

## ⚡ Non-Obvious Commands & Local Workflows

- **Interactive macOS Launch & Hot-Reload**:
  - Requires **Flutter 3.44.4+** (Dart 3.12+) — `record` 7, `xml` 7, `json_serializable` 6.14+.
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
  - Submodules are used for `packages/mermaid_renderer_flutter`, `packages/xterm`, `packages/pty2` and `third_party/flutter_local_models`. Initialize them using:
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

## 💾 Settings & Board Migration (settings:export / settings:import)

YoLoIT user state is fragmented across **four roots** — a naive copy of `~/.config/yoloit/` will miss boards (which live in SharedPreferences) and workspace paths (which live in `~/.yoloit/`):

| Root | macOS | Contents |
|---|---|---|
| `PlatformDirs.configDir` | `~/.config/yoloit/` | configs, skills, templates, apps, credential mirror, `state.json` |
| `PlatformDirs.dataDir` | `~/Library/Application Support/yoloit/` | `boards_history/`, `chat_sessions/`, `calendar_events/` |
| `~/.yoloit/` | `~/.yoloit/` | `config.json`, `workspaces.json` (absolute paths) |
| `SharedPreferences` plist | `~/Library/Preferences/com.yoloit.yoloit.plist` | **all boards** + most app prefs |

Migration is done with two CLI commands (also exposed in Settings → **Backup & Migration**):

- `yoloit settings:export <path>` — packs all four roots into a tar archive.
  - Always AES-GCM-encrypted (PBKDF2-SHA256, 200k iterations). Pass the
    passphrase via `passphrase` in the body (UI) or `YOLOIT_ARCHIVE_PASSPHRASE`
    env var (CLI). Set `requirePassphrase=false` to export unencrypted.
  - Flags: `--include-secrets`, `--no-history`, `--no-chat-sessions`,
    `--no-calendar`, `--no-state-json`, `--no-passphrase`.
  - Excluded by default: `runtime/`, `templates/cache/`, `asr_samples/`,
    credentials mirror (unless `--include-secrets`).
- `yoloit settings:import <path>` — restores an archive. Defaults to
  `--dry-run` so you preview the diff first. Use `--no-dry-run` to apply.
  - `--mode merge|replace`, `--path-rewrite auto|ask|keep` (auto rewrites
    `/Users/olduser/...` → `/Users/newuser/...`), `--on-conflict keep|overwrite|rename|skip`,
    `--passphrase <pw>`, plus per-root `--no-prefs|--no-config|--no-data|--no-workspaces`.
  - The manifest records `sourceHome`; with `--path-rewrite auto` it is
    replaced by the destination's home so workspace paths, board
    `defaultFolder`, and panel `rootPath/workingDir` land on existing
    directories on the new machine.
  - Board id collisions are surfaced in the report; `--on-conflict`
    resolves them non-interactively (interactive per-conflict prompts are
    wired only in the UI today).

The implementation lives in `lib/core/services/user_data_archive.dart` with
the HTTP route in `lib/core/cli/handlers/settings_handler.dart`. Tests:
`test/unit/core/services/user_data_archive_test.dart` (18 cases) and
`test/unit/core/cli/handlers/settings_handler_test.dart` (6 cases).
The CLI coverage ratchet exempts both commands in
`scripts/cli_integration_exempt.json` because they require live
`SharedPreferences` + `PlatformDirs` (not available in headless `yoloitd`).

---

## 🧭 CodeGraph Usage: CLI Only

- **Do not rely on the CodeGraph MCP server for this repository.**
  - The repo is large enough that the CodeGraph file watcher can hit macOS file descriptor limits (`EMFILE: too many open files, watch`) and make MCP startup time out.
  - Prefer explicit `codegraph` CLI calls from the terminal. They are deterministic, easy to retry, and do not block Codex startup.
- **Use CodeGraph CLI for structural code questions before falling back to text search:**
  - Symbol or API context: `codegraph context "task or area"`
  - Symbol lookup: `codegraph query "SymbolName"`
  - Callers: `codegraph callers "SymbolName"`
  - Callees: `codegraph callees "SymbolName"`
  - Impact analysis: `codegraph impact "SymbolName"`
  - File list from index: `codegraph files`
  - Index health: `codegraph status --json`
- **Keep the index fresh manually:**
  - Run `codegraph sync` after meaningful edits before asking structural questions.
  - If the index looks stale or locked, run `codegraph status` first and follow its output; do not start or debug the MCP server.
- **When using CLI output in answers or implementation work:**
  - Treat CodeGraph CLI results as the structural source of truth for definitions, call relationships, and impact.
  - Use `rg` only for literal text, comments, log messages, config keys, and after CodeGraph has already identified specific files.

---

## 📦 Repomix Code Snapshots

A pre-configured `repomix.config.json` lives at the repo root. It excludes `third_party`, `packages` (submodules), generated Dart files (`.g.dart`, `.freezed.dart`, `.mocks.dart`), and training data (`assets/command_catalog/**/*.jsonl`).

- **Install** (one-time): `npm install -g repomix`
- **Full project snapshot**: `repomix .`
  - Output: `snapshots/repomix-output.xml` (~500K tokens, ~2 MB, ~1.5s)
- **Dart-only snapshot**:
  ```bash
  find lib test -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.mocks.dart' | repomix --stdin --compress --output snapshots/dart-only.xml
  ```
- **Single / multiple specific files** (e.g., after `rg`/`codegraph` search):
  ```bash
  # One file
  echo 'lib/features/board/ui/board_view.dart' | repomix --stdin --compress --output snapshots/target.xml

  # Several files
  printf 'lib/app.dart\nlib/main.dart\n' | repomix --stdin --compress --output snapshots/target.xml
  ```
  > ⚠️ Multiple `--include` flags do **not** work reliably — always use `--stdin` for specific file lists.
- **Tips**:
  - `--compress` uses Tree-sitter to keep signatures and replace method bodies with `⋮----`. It captures **all** methods (public, private, protected).
  - `snapshots/` is `.gitignore`d — never commit generated XML files.

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

## ⚡ Performance Optimization Rules

- **Prefer `withAlpha` over `withOpacity`**:
  - `withOpacity` triggers a save-layer compositing pass. Use `withAlpha` (or `withValues(alpha: ...)`) for static/partial transparency instead.
- **Use `MediaQuery.sizeOf(context)` instead of `MediaQuery.of(context).size`**:
  - `MediaQuery.of` rebuilds on any MediaQuery change. `sizeOf` only rebuilds when the size actually changes.
- **Use `Visibility` instead of binary `Opacity` (`opacity: 0.0 / 1.0`)**:
  - `Visibility` removes the subtree from the render tree when hidden, avoiding compositing cost entirely.
- **Add `isComplex: true` to heavy `CustomPaint` widgets**:
  - Grid painters, link painters, minimap painters, and shape painters should set `isComplex: true` so Flutter raster-caches the output.
- **Add `gaplessPlayback: true` to `Image.memory` / `Image.network` / `Image.file`**:
  - Prevents flickering when the image bytes change.
- **Wrap expensive content in `RepaintBoundary`**:
  - `CodeField`, `MarkdownBody`, `MarkdownDocumentPreview`, `TerminalView`, `SelectionArea`, `ShaderMask`, and WebView overlays should each be wrapped in `RepaintBoundary` to isolate their repaint cost from parent animations/pans.
  - **Never wrap `BoardPanelCard` (or any widget inside `InteractiveViewer`'s transform) in `RepaintBoundary`**: it causes the widget to disappear from the transformed canvas.
- **Debounce search `setState` in text fields**:
  - Do not call `setState` on every keystroke. Use a `Timer` with ~150ms debounce for search inputs.
- **Avoid `setState` inside animation listeners**:
  - Use `AnimatedBuilder` with a `child` parameter instead of calling `setState(() {})` every frame.

---

## 📦 Release Management

- **Versions are managed automatically via GitHub Actions**:
  - **Never bump `version` in `pubspec.yaml` manually.** The release workflow (`.github/workflows/release.yml`) auto-increments the patch version based on the latest GitHub Release tag.
  - To create a new release, trigger the workflow with `version=auto`:
    `gh workflow run release.yml --field version=auto`
  - The workflow builds all three platforms (macOS DMG, Windows ZIP, Linux tar.gz) in parallel and uploads them to a unified GitHub Release.

---

## 🧪 Pre-commit Hooks & Coverage Ratchets

- The pre-commit hook is located at `scripts/pre-commit` and is installed to `.git/hooks/pre-commit`.
- It includes a **CLI integration-test coverage ratchet**:
  - `python3 scripts/check_cli_integration_coverage.py` enumerates every command registered in `tools/yoloit`.
  - Each command must be either:
    - covered by an integration test in `test/integration/` (annotate the file with `// covers: cmd1, cmd2, ...`), or
    - explicitly listed in `scripts/cli_integration_exempt.json` with a mandatory reason.
  - If a command is neither covered nor exempt, the hook fails and blocks the commit.
- It also includes a **panel write-coverage ratchet**:
  - `python3 scripts/check_panel_write_coverage.py` enumerates every built-in panel type (`board.*`).
  - Each panel type must be either:
    - covered by a test that exercises a write/update path (annotate the file with `// covers-write: board.type1, board.type2, ...`), or
    - explicitly listed in `scripts/panel_write_exempt.json` with a mandatory reason.
  - If a panel type is neither covered nor exempt, the hook fails and blocks the commit.
- Install or refresh the hook with:
  ```bash
  cp scripts/pre-commit .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  # Optional: track hooks in the repo
  git config core.hooksPath scripts
  ```
- Run the coverage checks locally at any time:
  ```bash
  python3 scripts/check_cli_integration_coverage.py
  python3 scripts/check_panel_write_coverage.py
  ```

## 📊 CRAP Metric (crap4dart)

- [crap4dart](https://github.com/IstiN/crap4dart) tracks the CRAP score
  (complexity × coverage) of the codebase; config lives in `crap4dart.yaml`,
  the current max score is shown in `badges/crap.svg` (embedded in `README.md`).
- **Run it via `dart pub global`, never as a project dependency**: yoloit pins
  `dependency_overrides: analyzer: ^14.0.0`, while crap4dart is built for
  analyzer 7.x — inside the project graph it fails to compile. Install once with:
  `dart pub global activate crap4dart`
- Regenerate the badge (uses the existing `coverage/lcov.info`):
  `crap4dart analyze --badge badges/crap.svg`
- Current mode is **observe-only**: the threshold is the default 8.0 (the
  legacy max is far above it, so `analyze` exits 2 — expected, do not "fix"
  by raising the threshold), and all quality gates are `enabled: false` in
  `crap4dart.yaml`. Enable gates / ratchet via `--diff` only when the team
  starts actually reducing the score.

## 🚨 Critical Agent Gotchas

- **No Heredocs (`cat << 'EOF'`)**:
  - **NEVER** use heredocs in bash commands. They consistently freeze the persistent agent bash session. Instead, write files using `printf` or `python3` (e.g., `python3 -c "open('file.txt', 'w').write(...)")`).
- **Never skip pre-commit checks with `--no-verify` unless explicitly told to**:
  - If `git commit` fails due to pre-commit hooks (tests, lint, line-count), **fix the underlying issue** rather than bypassing it with `--no-verify`.
  - Only use `--no-verify` when the user explicitly approves it, or when the failure is a known infrastructure issue outside the current changes.
  - After using `--no-verify`, provide the user with a clear analysis of what failed and why it was skipped.
- **Pre-existing `jscpd` duplication failure**:
  - The pre-commit hook enforces `< 1%` code duplication. The baseline has been reduced to **~0.97%** (853 duplicated lines across ~88K lines) and should now pass.
  - If `git commit` fails with `Code duplication too high`, verify whether `jscpd` output shows new clones in files you modified before assuming it is pre-existing.
  - Remediation options: (1) refactor the duplicates reported by `jscpd`, or (2) use `--no-verify` with explicit user approval.
