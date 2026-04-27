# Windows 11 Porting — Sequential Task List

Each task is self-contained and can be handed to a separate agent.
Run them **in order** — later tasks assume earlier ones are done.
Branch: `windows-compat` (created in Task 0).

---

## Task 0 — Create the working branch

**Goal:** All subsequent changes land on a dedicated branch, never on `main`.

**Steps:**
```bash
cd C:\Users\AliaksandrTarasevich\C\yoloit
git checkout main
git pull
git checkout -b windows-compat
```

**Done when:** `git branch --show-current` prints `windows-compat`.

---

## Task 1 — Fix SDK version constraint (build blocker)

**Context:** `pubspec.yaml` declares `sdk: '>=3.9.2 <4.0.0'`. The locally installed
Flutter ships Dart 3.7.x, so `flutter pub get` fails immediately with a constraint
error. The CI uses Flutter 3.35.3 (Dart 3.9.x) which satisfies the constraint, but
local development needs to work too. Widening the lower bound is the correct fix.

**File to change:** `pubspec.yaml` (repo root)

**Change:**
```yaml
# BEFORE
environment:
  sdk: '>=3.9.2 <4.0.0'

# AFTER
environment:
  sdk: '>=3.7.0 <4.0.0'
```

**Verification:**
```bash
flutter pub get   # must succeed with 0 errors
flutter analyze --no-pub   # must report 0 errors
```

---

## Task 2 — Guard `afplay` calls with platform check

**Context:** `lib/features/terminal/bloc/terminal_cubit.dart` calls
`Process.run('afplay', [...])` unconditionally at two places. `afplay` is a
macOS-only binary. On Windows `Process.run` throws `ProcessException: No such file
or directory`. The calls are fire-and-forget (no await) but the unhandled exception
still surfaces in debug mode and pollutes logs.

**File to change:** `lib/features/terminal/bloc/terminal_cubit.dart`

**Find both occurrences (around lines 455 and 496):**
```dart
Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
// and
Process.run('afplay', ['/System/Library/Sounds/Sosumi.aiff']);
```

**Wrap each with a platform guard:**
```dart
if (Platform.isMacOS) {
  Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
}
// and
if (Platform.isMacOS) {
  Process.run('afplay', ['/System/Library/Sounds/Sosumi.aiff']);
}
```

Make sure `dart:io` is already imported (it is).

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows: enable completion sound in settings, finish a session — no ProcessException in logs
```

---

## Task 3 — Guard tmux/run sessions on Windows (short-term) + document ConPTY future work

**Approach:** Option A — disable sessions gracefully on Windows with a clear message.
ConPtySessionBackend gets detailed implementation comments for future work (Option B).

**Files to change:**
1. `lib/features/terminal/data/tmux_service.dart` — early-exit Windows guard in `init()`
2. `lib/features/runs/data/run_service.dart` — Windows guard in `start()`, `reconnect()`; no-op in `stop()`/`_sendKeys()`
3. `lib/core/platform/terminal_session_backend.dart` — replace UnsupportedError stubs with graceful no-ops + detailed implementation comments for future ConPTY work

**For `TmuxService.init()`** — add at the very top of the method body:
```dart
if (Platform.isWindows) {
  _available = false;
  _enabled = false;
  return;
}
```

**For `RunService.start()`** — add at the very top:
```dart
if (Platform.isWindows) {
  onOutput('Run sessions are not available on Windows yet.', true);
  onExit(1);
  return;
}
```

**For `RunService.reconnect()`** — add at the very top:
```dart
if (Platform.isWindows) return false;
```

**For `ConPtySessionBackend`** — replace UnsupportedError throws with graceful stubs
and add a detailed doc comment describing the full implementation path:
```dart
/// Windows ConPTY backend — not yet implemented.
///
/// ## Future implementation guide
///
/// This class should replace the tmux backend on Windows using flutter_pty + ConPTY.
///
/// ### start()
/// Call `Pty.start(PlatformShell.instance.defaultShell, arguments: ['/K', command],
///   workingDirectory: workingDir, environment: env)`.
/// Store the Pty instance in a `_ptySessions` map keyed by sessionId.
/// Mirror output to a log file at `await logPath(sessionId)` for reconnect support.
///
/// ### reconnect()
/// Read the log file written by start(); emit all past output to the caller, then
/// resume tailing. Return true if the log exists and the process is still alive.
///
/// ### stop()
/// Call `_ptySessions[sessionId]?.kill()` and close/delete the log file.
///
/// ### sendKeys()
/// Call `_ptySessions[sessionId]?.write(Uint8List.fromList(utf8.encode(keys)))`.
///
/// ### logPath()
/// Return `path.join(PlatformDirs.instance.logsDir, 'session_$sessionId.log')`.
///
/// ### Output stream
/// Expose `_pty.output.transform(utf8.decoder)` as a `Stream<String>`.
///
/// ### Dependencies already available
/// - `flutter_pty: ^0.4.2` — already in pubspec, has ConPTY Windows support
/// - `PlatformShell.instance.defaultShell` — returns `cmd.exe` on Windows
/// - `PlatformDirs.instance.logsDir` — correct Windows path
class ConPtySessionBackend extends TerminalSessionBackend {
```

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows: opening a Run panel shows "Run sessions are not available on Windows yet."
# App does not crash on startup
```

---

## Task 4 — Replace direct `open -R` calls with `PlatformLauncher`

**Context:** Two UI files call `Process.run('open', ['-R', path])` directly instead
of going through the `PlatformLauncher` abstraction. `open` is macOS-only.
`WindowsPlatformLauncher.revealInFinder()` already has the correct Windows
implementation (`explorer /select, <path>`). The fix is to delete the raw calls and
use the abstraction.

**Files to change:**
1. `lib/features/mindmap/nodes/file_tree_node.dart` — around line 33
2. `lib/features/mindmap/nodes/presentation/file_tree_card.dart` — around line 202

**In each file, replace:**
```dart
Process.run('open', ['-R', path]);
// or
Process.run('open', ['-R', e.path]);
```
**With:**
```dart
PlatformLauncher.instance.revealInFinder(path);
// or
PlatformLauncher.instance.revealInFinder(e.path);
```

Import `package:yoloit/core/platform/platform_launcher.dart` if not already present.
Remove any now-unused `Process` import if `dart:io` is no longer needed in that file.

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows: right-click a file in the file tree → "Show in Explorer" → Explorer opens at that file
```

---

## Task 5 — Fix `AgentHookService` for Windows

**Context:** `lib/core/services/agent_hook_service.dart` installs Claude Code hooks
so agents can call back into the app. It currently:
- Reads `Platform.environment['HOME']` which is `null` on Windows (Windows uses `USERPROFILE`)
- Calls `Process.run('chmod', ['+x', ...])` which does not exist on Windows
- Writes a `#!/usr/bin/env bash` shell script — needs bash in PATH on Windows
- Creates filesystem symlinks — requires Developer Mode or admin on Windows

**File to change:** `lib/core/services/agent_hook_service.dart`

**Changes:**

1. **Home directory lookup** — wherever `Platform.environment['HOME']` is read, change to:
   ```dart
   Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ''
   ```

2. **chmod calls** — wrap every `Process.run('chmod', ...)` call:
   ```dart
   if (!Platform.isWindows) {
     await Process.run('chmod', ['+x', hookPath]);
   }
   ```

3. **Symlink creation** — wrap `Link.create()` calls:
   ```dart
   if (!Platform.isWindows) {
     await link.create(target);
   } else {
     // On Windows symlinks require Developer Mode; skip silently and log a warning
     // Users can enable Developer Mode in Settings → System → For developers
   }
   ```

4. **Hook script invocation** — the hook entry written to `hooks.json` uses
   `"bash .github/hooks/yoloit-hook.sh"`. On Windows this requires Git-for-Windows
   bash in PATH. Add a Windows-specific note in the log output explaining this dependency.
   No code change needed here — if `bash.exe` is in PATH (via Git for Windows), it works.

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows: create a workspace — no errors in the log for installHooks()
# Enable Developer Mode in Windows Settings for symlinks to work
```

---

## Task 6 — Implement Windows resource monitoring

**Context:** `lib/core/services/resource_monitor_service.dart` uses macOS-only
commands (`ps`, `vm_stat`, `sysctl`) without any platform guard. On Windows all these
calls fail silently (caught by `catch (_)`) and CPU/RAM always shows as 0. The class
comment even says "Polls macOS `ps` periodically."

**File to change:** `lib/core/services/resource_monitor_service.dart`

**In `_collect()` (process list)**, add a Windows branch before the existing `ps` call:
```dart
if (Platform.isWindows) {
  // tasklist /v /fo csv outputs: "Image Name","PID","Session Name","Session#","Mem Usage","Status","User Name","CPU Time","Window Title"
  final result = await Process.run('tasklist', ['/v', '/fo', 'csv', '/nh']);
  // parse CSV: fields[1]=pid, fields[0]=name, fields[4]=mem (e.g. "12,345 K")
  // CPU% is not available from tasklist; use 0.0 as placeholder
  // return List<ProcessInfo> built from parsed rows
}
```

**In `_collectHost()` (system stats)**, add a Windows branch:
```dart
if (Platform.isWindows) {
  // Memory via wmic
  final memResult = await Process.run(
    'wmic', ['OS', 'get', 'FreePhysicalMemory,TotalVisibleMemorySize', '/value'],
    runInShell: true,
  );
  // Parse "FreePhysicalMemory=XXXXX" and "TotalVisibleMemorySize=XXXXX" (in KB)
  // CPU load: use wmic cpu get LoadPercentage /value
  final cpuResult = await Process.run(
    'wmic', ['cpu', 'get', 'LoadPercentage', '/value'],
    runInShell: true,
  );
  // Build and return HostResourceSnapshot
}
```

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows: open the resource monitor panel — CPU% and RAM should show real values
```

---

## Task 7 — Fix ripgrep / grep discovery on Windows

**Context:** `lib/features/search/data/file_search_service.dart` searches for the
`rg` binary using hard-coded Unix paths (`/opt/homebrew/bin/rg` etc.) and a `which`
fallback. Neither works on Windows. The grep fallback also calls `Process.run('grep',
...)` which is not a native Windows command. File-name fuzzy search is pure Dart and
works fine.

**File to change:** `lib/features/search/data/file_search_service.dart`

**In `_findRg()`, add a Windows branch at the top:**
```dart
if (Platform.isWindows) {
  // Try PATH lookup via where.exe
  try {
    final result = await Process.run('where', ['rg'], runInShell: true);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim().split('\n').first.trim();
      if (path.isNotEmpty) return path;
    }
  } catch (_) {}
  return null; // rg not found; caller will use fallback
}
```

**In `_grepFallback()`, add a Windows guard:**
```dart
if (Platform.isWindows) {
  // grep is not available natively on Windows; return empty results
  // Users should install ripgrep (winget install BurntSushi.ripgrep.MSVC)
  return [];
}
```

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows with rg in PATH: file content search returns results
# On Windows without rg: search returns empty results gracefully (no crash)
```

---

## Task 8 — Fix tilde expansion to use USERPROFILE on Windows

**Context:** `lib/app.dart` expands `~` in paths by reading
`Platform.environment['HOME']`. On Windows, `HOME` is typically not set — the
equivalent is `USERPROFILE`. When `HOME` is null, the current code produces a path
prefixed with `"null"` (string concatenation with a null value that was coerced).

**File to change:** `lib/app.dart`

**Find all occurrences of:**
```dart
Platform.environment['HOME']
```

**Replace each with:**
```dart
(Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '')
```

There should be 1–3 occurrences in the workspace create / add-folder handlers.

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows: create a workspace using a path like ~/projects/foo
# Verify the resolved path starts with C:\Users\<name>\ not "null\projects\foo"
```

---

## Task 9 — Prefer Windows Terminal in `openTerminal`

**Context:** `lib/core/platform/platform_launcher.dart` —
`WindowsPlatformLauncher.openTerminal()` opens `cmd.exe`. Windows 11 ships with
Windows Terminal (`wt.exe`) by default. Most developers expect `wt.exe`.

**File to change:** `lib/core/platform/platform_launcher.dart`

**Replace the `WindowsPlatformLauncher.openTerminal` implementation:**
```dart
@override
Future<void> openTerminal(String workdir) async {
  // Try Windows Terminal first, fall back to cmd.exe
  try {
    await Process.run('wt.exe', ['-d', workdir]);
  } catch (_) {
    await Process.run('cmd', ['/c', 'start', 'cmd.exe', '/K', 'cd /d "$workdir"']);
  }
}
```

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows 11: right-click a folder → "Open in Terminal" → Windows Terminal opens at that directory
# On Windows 10 without wt.exe: cmd.exe opens instead
```

---

## Task 10 — Override `yoloitTempDir` in `WindowsPlatformDirs`

**Context:** The base class `PlatformDirs` defines:
```dart
String get yoloitTempDir => '${Directory.systemTemp.path}/yoloit_tmp';
```
This uses a forward slash. `WindowsPlatformDirs` in
`lib/core/platform/platform_dirs.dart` does not override this getter, so it inherits
the base implementation with mixed separators. Dart's `dart:io` normalises this at
runtime, but it is inconsistent with the rest of `WindowsPlatformDirs` which uses
`path.join` (backslash). Override it for consistency.

**File to change:** `lib/core/platform/platform_dirs.dart`

**Add to the `WindowsPlatformDirs` class:**
```dart
@override
String get yoloitTempDir =>
    path.join(Directory.systemTemp.path, 'yoloit_tmp');
```

(The `path` package is already imported in this file as `import 'package:path/path.dart' as path;`)

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
flutter test test/unit/core/platform/platform_dirs_test.dart
```

---

## Task 11 — Read real app version on Windows in `WindowsPlatformInstaller`

**Context:** `lib/core/platform/platform_installer.dart` —
`WindowsPlatformInstaller.getAppVersion()` returns the `fallback` string (`'0.0.0'`)
unconditionally because there is no Win32 version-info lookup. The macOS
implementation reads the `Info.plist`. On Windows the version is embedded in the
executable's VERSIONINFO resource.

**File to change:** `lib/core/platform/platform_installer.dart`

**Replace `WindowsPlatformInstaller.getAppVersion`:**
```dart
@override
Future<String> getAppVersion({String fallback = '0.0.0'}) async {
  try {
    final exePath = Platform.resolvedExecutable;
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        '(Get-Item \\"$exePath\\").VersionInfo.ProductVersion',
      ],
      runInShell: false,
    );
    if (result.exitCode == 0) {
      final version = (result.stdout as String).trim();
      if (version.isNotEmpty && version != '0.0.0.0') return version;
    }
  } catch (_) {}
  return fallback;
}
```

**Verification:**
```bash
flutter analyze --no-pub   # 0 errors
# On Windows release build: version shown in Settings matches the built .exe version
```

---

## Final Verification (run after all tasks complete)

```bash
# From the windows-compat branch:
flutter pub get
flutter analyze --no-pub       # must report 0 errors
flutter test test/unit/         # must pass 100%
flutter build windows --debug   # must produce a .exe without errors
# Launch the .exe on Windows 11 and verify:
#   - App opens without crash
#   - "Show in Explorer" works from file tree
#   - Terminal panel opens (cmd.exe or Windows Terminal)
#   - Sound settings do not crash the app
#   - Resource monitor shows non-zero values
#   - File content search works if rg is installed
```
