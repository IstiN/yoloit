# YoLoIT

![CRAP](badges/crap.svg)

YoLoIT is a Flutter desktop application for orchestrating AI coding CLIs inside a workspace-aware developer environment. It combines multi-repository workspaces, embedded agent terminals, code review, a built-in editor, run configurations, search, setup checks, and release updates in one app.

## What YoLoIT is for

YoLoIT is built for developers who want AI agents and project tooling to live next to the codebase instead of being scattered across terminal windows, editors, git clients, and helper scripts.

The app focuses on a few core workflows:

- manage multiple repositories as a single workspace
- start and restore AI agent sessions inside embedded terminals
- review diffs and stage or unstage files
- open and edit files without leaving the app
- run project commands and reconnect to active runs
- keep setup, hotkeys, themes, and agent defaults configurable from the UI

## Core capabilities

### 1. Workspace management

YoLoIT supports named workspaces that can contain one or more folder paths. Each workspace keeps its own:

- active selection
- git branch and diff summary
- expanded file tree state
- editor tabs
- terminal session state
- workspace-scoped secrets

Behind the scenes, YoLoIT maintains a dedicated workspace directory structure and syncs symlinks for the configured paths.

### 2. Embedded AI agent terminals

The terminal subsystem is one of the main product surfaces. YoLoIT can spawn embedded PTY sessions for built-in agent types and plain shell sessions:

| Agent | Default launch command |
| --- | --- |
| GitHub Copilot | `copilot --allow-all` |
| Claude Code | `claude` |
| Gemini CLI | `gemini` |
| Cursor Agent | `cursor-agent` |
| Pi | `pi` |
| Terminal | plain shell |

Agent launch commands, visibility, labels, and the default agent can be customized in **Settings → AI Agents**.

When `tmux` is enabled, sessions survive app restarts and are restored per workspace. YoLoIT also writes terminal logs and keeps inactive sessions attached to their workspace instead of destroying them when you switch context.

### 3. Worktree-aware agent sessions

For multi-repo or branch-heavy workflows, YoLoIT can create a new agent session against selected git worktrees. The app:

- lists available branches per repository
- creates missing worktrees when needed
- builds an agent-specific directory with symlinks to the selected worktree paths
- injects workspace secrets into the spawned session environment

This makes it possible to run separate agents against isolated branches without manually creating extra terminal setups.

### 4. Built-in review panel

The review module loads changed files from git, displays a file tree, and lets you inspect both:

- diff hunks
- full file content

From the review panel you can:

- browse the workspace tree
- switch between diff and file views
- stage files
- unstage files
- keep directory expansion state across restarts

### 5. Built-in editor

YoLoIT includes a tabbed file editor designed for fast in-app changes during agent-driven workflows.

Current editor features include:

- multi-tab editing with restore on restart
- debounced auto-save
- syntax highlighting
- diff tabs
- markdown and SVG preview mode
- find / replace
- go to line
- outline view
- line operations such as comment toggle, duplicate, delete, move, indent, outdent
- git gutter markers
- font scaling and persisted editor layout

The editor also reloads files from disk when appropriate and avoids overwriting local changes on focus restore.

### 6. Run configurations and process sessions

YoLoIT has a dedicated run subsystem for common development commands.

It supports:

- saved run configurations per workspace
- live process output
- reconnecting to running sessions after restart
- output retention with line limits
- hot reload / hot restart helpers for Flutter runs

For Flutter projects, YoLoIT can seed sensible default configurations such as:

- `flutter run -d macos`
- `flutter test`
- `flutter build macos`

### 7. Search across workspaces

The search overlay supports:

- fuzzy file search
- content search
- multi-workspace results

When available, YoLoIT uses `ripgrep` for content search and falls back to `grep` when necessary.

### 8. Settings, setup, and quality-of-life features

The settings surface covers:

- appearance and theme selection
- AI agent configuration
- session persistence options
- keyboard shortcut customization
- first-run setup guide
- about screen and update preferences

The setup guide checks tool availability for dependencies and supported agent CLIs, including Git, Node.js, `tmux`, GitHub Copilot, Claude Code, Gemini CLI, and Cursor Agent.

### 9. Updates

Release builds can check GitHub Releases for new versions. The update flow is designed to:

- check for updates automatically on a schedule
- open the release page when needed
- support in-app install flows through the platform installer where available

## Architecture overview

YoLoIT is organized as a Flutter desktop app with feature-first modules and a shared platform abstraction layer.

High-level structure:

- `lib/features/workspaces/` — workspace definitions, git metadata, worktree support, secrets
- `lib/features/terminal/` — PTY sessions, persistence, logging, tmux integration
- `lib/features/review/` — file tree, diff loading, staging / unstaging
- `lib/features/editor/` — tabbed editor and editor state
- `lib/features/runs/` — run configurations and run session management
- `lib/features/search/` — fuzzy file search and content search
- `lib/features/settings/` — agent settings, theme, shortcuts, setup guide
- `lib/features/updates/` — release detection and install flow
- `lib/core/platform/` — platform-specific filesystem, launcher, shell, installer, and terminal backend abstractions

State is managed primarily with `Cubit`/`Bloc`, while persistence is split between shared preferences, secure storage, filesystem-backed config files, logs, and platform-aware app directories.

## Platform support

The repository includes desktop targets for macOS, Linux, and Windows, and the platform layer is explicitly structured to support all three.

Current status:

- **macOS** — most complete implementation today
- **Linux** — many flows are present, but some platform-specific paths and behaviors are still evolving
- **Windows** — desktop target and setup logic exist, while some platform services are still being completed

If you are contributing to platform behavior, keep all platform checks and shell/launcher/install logic inside `lib/core/platform/`.

## Getting started

### Prerequisites

- Flutter SDK compatible with Dart `^3.9.2`
- Git
- Node.js for npm-based AI CLIs
- at least one supported AI CLI, or use the plain terminal mode
- `tmux` recommended for persistent terminal sessions

### Run locally

```bash
flutter pub get
flutter run -d macos
```

You can also target other desktop platforms supported by your local Flutter environment.

### Recommended external tools

YoLoIT becomes much more useful when the following are available on your machine:

- `git`
- `tmux`
- `rg` (ripgrep)
- GitHub Copilot CLI
- Claude Code
- Gemini CLI
- Cursor Agent

The in-app setup guide helps verify and install missing tools where supported.

## Development

Useful commands:

```bash
flutter analyze --no-pub
flutter test
```

Platform-focused changes should also be covered with targeted unit tests under `test/unit/core/platform/`.

## Repository layout

```text
lib/
  app.dart
  core/
    platform/
  features/
    editor/
    review/
    runs/
    search/
    settings/
    terminal/
    updates/
    workspaces/
  ui/

test/
  unit/
  widget/
  integration_test/
```

## Open source

YoLoIT is published as an Apache 2.0 open source project.

Repository-level open source files:

- `LICENSE` — Apache License 2.0 text
- `NOTICE` — project notice file for redistribution
- `CONTRIBUTING.md` — contribution guide and contribution licensing terms

## License

Licensed under the **Apache License, Version 2.0**. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE) for details.
