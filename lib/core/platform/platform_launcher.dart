import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
});

/// Platform-aware OS-level commands: open URLs, reveal files, open terminals.
///
/// Usage:
/// ```dart
/// await PlatformLauncher.instance.openUrl('https://example.com');
/// await PlatformLauncher.instance.revealInFinder('/path/to/file');
/// ```
abstract class PlatformLauncher {
  const PlatformLauncher();

  /// Singleton — picks the right implementation based on the current OS.
  static PlatformLauncher? _instance;
  static PlatformLauncher get instance {
    _instance ??= _create();
    return _instance!;
  }

  /// Override the singleton (useful for testing).
  // ignore: use_setters_to_change_properties
  static void setInstance(PlatformLauncher instance) => _instance = instance;

  static PlatformLauncher _create() {
    if (Platform.isMacOS) return const MacosPlatformLauncher();
    if (Platform.isLinux) return const LinuxPlatformLauncher();
    if (Platform.isWindows) return const WindowsPlatformLauncher();
    return const LinuxPlatformLauncher();
  }

  /// Opens [url] in the default system browser / handler.
  Future<void> openUrl(String url);

  /// Reveals [path] in the system file manager (Finder, Files, Explorer).
  Future<void> revealInFinder(String path);

  /// Opens a new terminal window at [workdir].
  Future<void> openTerminal(String workdir);
}

// ── macOS ────────────────────────────────────────────────────────────────────

class MacosPlatformLauncher extends PlatformLauncher {
  const MacosPlatformLauncher({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  @override
  Future<void> openUrl(String url) async {
    await _run('open', [url]);
  }

  @override
  Future<void> revealInFinder(String path) async {
    await _run('open', ['-R', path]);
  }

  @override
  Future<void> openTerminal(String workdir) async {
    await _run('osascript', [
      '-e',
      'tell application "Terminal" to do script "cd \\"$workdir\\""',
    ]);
    await _run('osascript', [
      '-e',
      'tell application "Terminal" to activate',
    ]);
  }
}

// ── Linux ────────────────────────────────────────────────────────────────────

class LinuxPlatformLauncher extends PlatformLauncher {
  const LinuxPlatformLauncher({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  @override
  Future<void> openUrl(String url) async {
    await _run('xdg-open', [url]);
  }

  @override
  Future<void> revealInFinder(String path) async {
    // xdg-open on the parent directory is the closest Linux equivalent.
    final dir = File(path).parent.path;
    await _run('xdg-open', [dir]);
  }

  @override
  Future<void> openTerminal(String workdir) async {
    // Try common terminal emulators in order of preference.
    for (final term in ['gnome-terminal', 'xterm', 'konsole']) {
      final which = await _run('which', [term]);
      if (which.exitCode == 0) {
        await _run(term, ['--working-directory=$workdir']);
        return;
      }
    }
    // Log a warning — no terminal found.
    // ignore: avoid_print
    print('[YoLoIT] No terminal emulator found for openTerminal($workdir)');
  }
}

// ── Windows ──────────────────────────────────────────────────────────────────

class WindowsPlatformLauncher extends PlatformLauncher {
  const WindowsPlatformLauncher({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  @override
  Future<void> openUrl(String url) async {
    await _run('cmd', ['/c', 'start', '', url]);
  }

  @override
  Future<void> revealInFinder(String path) async {
    await _run('explorer', ['/select,', path]);
  }

  @override
  Future<void> openTerminal(String workdir) async {
    // Prefer Windows Terminal (wt.exe) — ships with Windows 11 by default.
    // Fall back to cmd.exe on Windows 10 or machines without wt.exe.
    try {
      final result = await _run('where', ['wt.exe'], runInShell: true);
      if (result.exitCode == 0) {
        await _run('wt.exe', ['-d', workdir]);
        return;
      }
    } catch (_) {}
    await _run('cmd', ['/c', 'start', 'cmd.exe', '/K', 'cd /d "$workdir"']);
  }
}
