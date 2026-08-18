# Board Pop-Out to Separate Window — Research Notes

**Status: ABANDONED (2026-08-18).** Feature does not work with either of the
two available Flutter multi-window packages. This document records what was
tried, why it failed, and what would be needed to make it work.

## What was wanted

A toolbar button to "pop out" the active board into a separate native macOS
window (e.g. to drag onto a second monitor). The popped-out board was to live
independently in its own window — no real-time state sync required. The main
window would only need to focus that window when the board is picked from the
board overview.

## Attempt 1: `desktop_multi_window` ^0.3.0 — FAILED

**What happened:** `DesktopMultiWindow.createWindow()` opens a native NSWindow
with a black/empty content area. The secondary Flutter engine never runs any
Dart code.

**Diagnosis (verified with marker files in /tmp):**
- `main()` in the secondary engine is **never invoked** (no entry-point log).
- The macOS plugin creates `FlutterDartProject()` + `FlutterViewController`
  in `MultiWindowManager.CreateWindow` and passes
  `dartEntrypointArguments = ["multi_window", windowId, arguments]`.
- In a **release AOT build** the secondary engine fails to start Dart. The
  window stays black. Works only on some projects' debug builds, and even
  then unreliably.
- `@pragma('vm:entry-point')` on `main`/`boardWindowMain` did NOT help.
- Registering `FlutterMultiWindowPlugin` manually in `MainFlutterWindow.swift`
  did NOT help.

**Known upstream issues:** the package has multiple open macOS issues
(MixinNetwork/flutter-plugins#319 etc.) and hasn't been updated in a long time.

## Attempt 2: `multiview_desktop` ^1.2.1 — FAILED (broke the main window)

**What happened:** This package uses Flutter's multi-view API (single engine,
single isolate, one window = one FlutterView). Integration requires replacing
the runner's engine setup (`MultiviewDesktopPlugin.prepareEngine(engine, window:)`
in `MainFlutterWindow.swift`, plus AppDelegate overrides).

After integration:
- The main window's custom titlebar broke — macOS traffic lights disappeared,
  the header layout was "перехерачено".
- `window_manager` plugin crashed:
  `WindowManagerPlugin.ensureInitialized() → mainWindow (nil) → force unwrap →
  SIGTRAP`. This is because multiview creates the engine before the window is
  registered, and window_manager's `mainWindow` getter force-unwraps nil.
- Removing `windowManager.ensureInitialized()` from `main.dart` fixed the crash
  but the titlebar/layout breakage remained.

**Root cause:** yoloit's shell depends deeply on `window_manager` (drag,
maximize/unmaximize, minimize, close, `WindowListener`) and on a custom
titlebar (`titlebarAppearsTransparent`, `fullSizeContentView`, floating
traffic lights). multiview_desktop requires owning the window lifecycle and
conflicts with both.

## What a future attempt would need

1. **Either** migrate the entire shell off `window_manager` onto
   multiview_desktop's own window APIs (big refactor: MainShell title bar,
   drag handling, window controls, all `WindowListener` usages) — the package
   itself is well-designed and the single-isolate model would let the pop-out
   `BoardView` share the existing `BoardCubit` directly via `globalScope`.
2. **Or** wait for official Flutter multi-window support (Canonical has been
   landing multi-view rendering; official windowing APIs are on their 2025+
   roadmap).
3. **Or** a web-based pop-out: open the existing collaboration web client in a
   separate native window (NSWindow + WKWebView) pointed at the local
   `CollaborationServer` — no new engine, reuses existing remote-board
   rendering. This was considered "fastest" but renders via WebView, not
   native Flutter.

## Where the code lived (all reverted in commit history)

- `lib/features/board/window/board_window.dart` — secondary-window entry point
- `lib/features/board/window/board_popout_service.dart` — pop-out call wrapper
- Toolbar button (`onPopOutBoard` param on `BoardToolbar`)
- `MainFlutterWindow.swift` / `AppDelegate.swift` engine setup changes

The full experiment history is in git: search commits mentioning
"multi-window", "pop-out", "desktop_multi_window", "multiview_desktop"
between 2026-08-13 and 2026-08-18, reverted in commit `bc68ac1a`.
