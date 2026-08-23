import 'dart:convert';
import 'dart:io';
import 'package:yoloit/features/terminal/data/pty_wrapper.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';

class PtyService {
  PtyService._();
  static final PtyService instance = PtyService._();

  final Map<String, Pty> _ptys = {};
  // Tracks which sessions are backed by tmux (should NOT be killed on app exit).
  final Set<String> _tmuxSessions = {};

  Pty? getPty(String sessionId) => _ptys[sessionId];

  Pty launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
  }) {
    _killExisting(sessionId);

    final env = _buildEnv(extraEnv: extraEnv);
    final shell = PlatformShell.instance.defaultShell;

    final pty = Pty.start(
      shell,
      workingDirectory: workspacePath,
      environment: env,
      columns: 220,
      rows: 50,
      // Backpressure: the native read thread waits for Pty.ackRead() after
      // each chunk (acked in TerminalProcess.fromPty), so a busy UI isolate
      // cannot be flooded faster than it processes output.
      ackRead: true,
    );

    return _registerPty(sessionId, pty, label: label, metadata: metadata);
  }

  Pty launchTmux({
    required String sessionId,
    required String workspacePath,
    required Pty Function({
      required String sessionId,
      required String workspacePath,
      required Map<String, String> env,
      int columns,
      int rows,
    })
    tmuxLauncher,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
  }) {
    _killExisting(sessionId);

    final pty = tmuxLauncher(
      sessionId: sessionId,
      workspacePath: workspacePath,
      env: _buildEnv(extraEnv: extraEnv),
      columns: 220,
      rows: 50,
    );

    _tmuxSessions.add(sessionId);
    return _registerPty(sessionId, pty, label: label, metadata: metadata);
  }

  void _killExisting(String sessionId) {
    final existing = _ptys[sessionId];
    if (existing != null) {
      existing.kill();
      _ptys.remove(sessionId);
    }
  }

  Map<String, String> _buildEnv({Map<String, String>? extraEnv}) {
    return <String, String>{
      ...Platform.environment,
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'PATH': _enrichedPath(),
      if (extraEnv != null) ...extraEnv,
    };
  }

  Pty _registerPty(
    String sessionId,
    Pty pty, {
    String? label,
    ResourceSessionMetadata? metadata,
  }) {
    _ptys[sessionId] = pty;
    ResourceMonitorService.instance.registerSession(
      pty.pid,
      label ?? sessionId,
      metadata: metadata,
    );
    return pty;
  }

  /// Builds a PATH that includes common tool locations missed by GUI apps.
  static String _enrichedPath() => PlatformShell.instance.enrichedPath(
    Platform.environment['PATH'] ?? '/usr/bin:/bin',
  );

  void write(String sessionId, String data) {
    final pty = _ptys[sessionId];
    if (pty == null) return;
    pty.write(const Utf8Encoder().convert(data));
  }

  void resize(String sessionId, int columns, int rows) {
    // flutter_pty Pty.resize(rows, cols) — note the order!
    _ptys[sessionId]?.resize(rows, columns);
  }

  /// Kills the PTY and, if it is a tmux session, also kills the tmux session.
  /// Use this when the user explicitly closes a tab.
  void kill(String sessionId, {Future<void> Function(String)? onKillTmux}) {
    final pty = _ptys[sessionId];
    if (pty != null) {
      ResourceMonitorService.instance.unregisterSession(pty.pid);
      _hangupAndTerminate(pty);
    }
    _ptys.remove(sessionId);
    if (_tmuxSessions.remove(sessionId) && onKillTmux != null) {
      onKillTmux(sessionId);
    }
  }

  /// Sends SIGHUP before SIGTERM, like a real terminal emulator closing its
  /// pty: shells and TUIs expect SIGHUP on terminal teardown and clean up
  /// (save history, restore terminal modes) on it, while SIGTERM alone often
  /// leaves orphaned children running.
  static void _hangupAndTerminate(Pty pty) {
    try {
      pty.kill(ProcessSignal.sighup);
    } catch (_) {
      // Platform does not support signals (Windows) or the process is
      // already gone — SIGTERM below is the fallback.
    }
    pty.kill();
  }

  /// Detaches all PTYs without killing tmux sessions (called on app exit).
  void killAll() {
    for (final entry in _ptys.entries) {
      ResourceMonitorService.instance.unregisterSession(entry.value.pid);
      entry.value.kill();
    }
    _ptys.clear();
    _tmuxSessions.clear();
  }
}
