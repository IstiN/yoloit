import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';

/// Manages tmux sessions as a backend for persistent terminal sessions.
///
/// When tmux is available and enabled, each terminal session runs inside a
/// named tmux session.  Closing the app detaches from tmux but does NOT kill
/// the session — the agent keeps running.  On next launch the cubit attaches
/// back to the existing session.
class TmuxService {
  TmuxService._();
  static final instance = TmuxService._();

  static const _enabledKey = 'tmux_enabled_v1';

  /// Candidate paths where tmux may be installed (macOS + Linux).
  static const _tmuxCandidates = [
    '/opt/homebrew/bin/tmux',   // Apple Silicon Homebrew
    '/usr/local/bin/tmux',      // Intel Homebrew
    '/usr/bin/tmux',            // system
    '/bin/tmux',
  ];

  String? _tmuxBin;

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _available = false;
  bool get available => _available;

  /// Full path to the tmux binary, or null if not found.
  String? get tmuxBin => _tmuxBin;

  /// Must be called once at startup before using any other methods.
  Future<void> init() async {
    if (Platform.isWindows) {
      _available = false;
      _enabled = false;
      return;
    }
    _tmuxBin = await _findTmux();
    _available = _tmuxBin != null;
    final prefs = await SharedPreferences.getInstance();
    // Enable by default if tmux is available and no explicit pref saved.
    _enabled = prefs.getBool(_enabledKey) ?? _available;
    // Persist the default so later reads are consistent.
    if (!prefs.containsKey(_enabledKey) && _available) {
      await prefs.setBool(_enabledKey, true);
    }
    if (_available) await _ensureConfig();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  bool get isActive => _enabled && _available;

  /// Returns the full path to tmux binary or null if not found.
  static Future<String?> _findTmux() async {
    // 1. Try known absolute paths first (reliable inside Flutter app sandbox).
    for (final path in _tmuxCandidates) {
      if (await File(path).exists()) return path;
    }
    // 2. Fall back to `which` (works when PATH includes Homebrew).
    try {
      final result = await Process.run('which', ['tmux']);
      if (result.exitCode == 0) {
        final p = (result.stdout as String).trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }

  /// Sanitises a session ID to be safe as a tmux session name.
  static String tmuxName(String sessionId) =>
      sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  /// Path to yoloit's tmux config — written on first use.
  static String get _configPath =>
      '${PlatformDirs.instance.configDir}/tmux.conf';

  /// Ensures the yoloit tmux config exists with status bar disabled.
  Future<void> _ensureConfig() async {
    final file = File(_configPath);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString([
        '# YoLoIT tmux config — auto-generated, do not edit manually',
        'set -g status off',          // hide the green status bar
        'set -g mouse on',            // enable mouse scroll
        'set -g history-limit 50000', // large scrollback
        'set -sg escape-time 0',      // no ESC delay (important for vim/editors)
      ].join('\n'));
    }
  }

  /// Creates or attaches to a named tmux session and returns a PTY connected
  /// to it.  Uses `new-session -A` which creates if absent, attaches if found.
  Pty launch({
    required String sessionId,
    required String workspacePath,
    required Map<String, String> env,
    int columns = 220,
    int rows = 50,
  }) {
    final bin = _tmuxBin!;
    return Pty.start(
      bin,
      arguments: [
        '-f', _configPath,    // use yoloit config (status off, etc.)
        'new-session',
        '-A', // create if absent, attach if present
        '-s', tmuxName(sessionId),
        '-c', workspacePath,
      ],
      environment: env,
      columns: columns,
      rows: rows,
    );
  }

  /// Kills the underlying tmux session (called when user explicitly closes a
  /// tab — NOT called on app exit, allowing the session to survive).
  Future<void> killSession(String sessionId) async {
    if (_tmuxBin == null) return;
    await Process.run(_tmuxBin!, ['kill-session', '-t', tmuxName(sessionId)]);
  }

  Future<List<String>> listSessions() async {
    if (_tmuxBin == null) return [];
    try {
      final result = await Process.run(
        _tmuxBin!,
        ['list-sessions', '-F', '#{session_name}'],
      );
      if (result.exitCode != 0) return [];
      return (result.stdout as String)
          .trim()
          .split('\n')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> sessionExists(String sessionId) async {
    final sessions = await listSessions();
    return sessions.contains(tmuxName(sessionId));
  }
}
