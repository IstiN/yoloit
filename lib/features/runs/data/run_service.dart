import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/platform_shell.dart';

typedef OutputCallback = void Function(String line, bool isError);
typedef ExitCallback = void Function(int exitCode);

class RunService {
  RunService._();
  static final instance = RunService._();

  final Map<String, String> _sessionTmux = {};
  final Map<String, Timer> _pollers = {};
  final Map<String, RandomAccessFile> _logFiles = {};
  final Map<String, String> _lineBuffers = {};
  String? _tmuxPath;

  static String tmuxName(String configId) =>
      'yoloit_run_${configId.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "_")}';

  static Future<String> logPath(String configId) async {
    final dir = Directory('${PlatformDirs.instance.configDir}/runs');
    await dir.create(recursive: true);
    return "${dir.path}/${tmuxName(configId)}.log";
  }

  /// Builds PATH with common GUI-app-missing tool dirs, including flutter.
  static String _enrichedPath() =>
      PlatformShell.instance.enrichedPath(
        Platform.environment['PATH'] ?? '/usr/bin:/bin',
      );

  /// Resolves the full path to an executable by searching the enriched PATH.
  /// Falls back to the bare name if not found (preserves existing behaviour on
  /// Linux where tmux is already in the system PATH, and on Windows where tmux
  /// is not used).
  static Future<String> _findExecutable(String name) async {
    final enrichedPath = _enrichedPath();
    final sep = Platform.isWindows ? ';' : ':';
    final ext = Platform.isWindows ? '.exe' : '';
    for (final dir in enrichedPath.split(sep)) {
      if (dir.isEmpty) continue;
      final file = File('$dir${Platform.pathSeparator}$name$ext');
      if (await file.exists()) return file.path;
    }
    return name;
  }

  /// Returns the cached tmux executable path, resolving it on first call.
  Future<String> _tmux() async => _tmuxPath ??= await _findExecutable('tmux');

  Future<void> start({
    required String sessionId,
    required String configId,
    required String command,
    required String workingDir,
    Map<String, String> env = const {},
    required OutputCallback onOutput,
    required ExitCallback onExit,
  }) async {
    if (Platform.isWindows) {
      onOutput('Run sessions are not available on Windows yet.', true);
      onExit(1);
      return;
    }
    final name = tmuxName(configId);
    final log = await logPath(configId);
    _sessionTmux[sessionId] = name;

    final tmux = await _tmux();

    await File(log).writeAsString("");
    await Process.run(tmux, ["kill-session", "-t", name]);

    final envStr = env.entries
        .map((e) => "export ${e.key}=\"${e.value}\"")
        .join("; ");
    final prefix = envStr.isNotEmpty ? "$envStr; " : "";
    // Inline workingDir and log directly into the bash string so they are
    // available even when the tmux server does not inherit the client's env.
    final enrichedPath = _enrichedPath();
    final bash = "export PATH=\"$enrichedPath\"; "
        "${prefix}cd \"$workingDir\" && $command 2>&1 | tee \"$log\"; "
        "echo \"__YOLOIT_EXIT_\$?\" >> \"$log\"";

    final result = await Process.run(
      tmux,
      ["new-session", "-d", "-s", name, "-x", "220", "-y", "50",
       "bash", "-c", bash],
      environment: {
        ...Platform.environment,
        "PATH": enrichedPath,
      },
    );

    if (result.exitCode != 0) {
      onOutput("Failed to start tmux session: ${result.stderr}", true);
      onExit(1);
      return;
    }

    await _tailLog(
      sessionId: sessionId, log: log, fromStart: true,
      onOutput: onOutput, onExit: onExit,
    );
  }

  Future<bool> reconnect({
    required String sessionId,
    required String configId,
    required OutputCallback onOutput,
    required ExitCallback onExit,
  }) async {
    if (Platform.isWindows) return false;
    final name = tmuxName(configId);
    final check = await Process.run(await _tmux(), ["has-session", "-t", name]);
    if (check.exitCode != 0) return false;
    _sessionTmux[sessionId] = name;
    final log = await logPath(configId);
    await _tailLog(
      sessionId: sessionId, log: log, fromStart: true,
      onOutput: onOutput, onExit: onExit,
    );
    return true;
  }

  /// Polls the log file every 50ms using Dart's RandomAccessFile — no process
  /// spawning, no stdio pipe buffering. New bytes are decoded and split into
  /// lines immediately as they arrive.
  Future<void> _tailLog({
    required String sessionId,
    required String log,
    required bool fromStart,
    required OutputCallback onOutput,
    required ExitCallback onExit,
  }) async {
    final file = File(log);
    // Wait for the file to appear (tmux may not have created it yet).
    for (var i = 0; i < 20; i++) {
      if (await file.exists()) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!await file.exists()) {
      onOutput('[log file not found: $log]', true);
      onExit(1);
      return;
    }

    final raf = await file.open(mode: FileMode.read);
    if (!fromStart) {
      // Start from current end so only new output is shown.
      await raf.setPosition(await raf.length());
    }
    _logFiles[sessionId] = raf;
    _lineBuffers[sessionId] = '';

    _pollers[sessionId] = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) async {
        final raf = _logFiles[sessionId];
        if (raf == null) return;
        try {
          final bytes = await raf.read(65536);
          if (bytes.isEmpty) return;
          final chunk = utf8.decode(bytes, allowMalformed: true);
          final buffered = (_lineBuffers[sessionId] ?? '') + chunk;
          final lines = buffered.split('\n');
          // Last element may be an incomplete line — keep it in the buffer.
          _lineBuffers[sessionId] = lines.removeLast();
          for (final line in lines) {
            final trimmed = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
            if (trimmed.startsWith('__YOLOIT_EXIT_')) {
              final code = int.tryParse(trimmed.substring('__YOLOIT_EXIT_'.length)) ?? 0;
              _cleanup(sessionId);
              onExit(code);
              return;
            }
            onOutput(trimmed, false);
          }
        } catch (_) {
          // File may have been truncated/replaced; ignore silently.
        }
      },
    );
  }

  void stop(String sessionId) {
    final name = _sessionTmux[sessionId];
    if (name != null) {
      final tmux = _tmuxPath ?? 'tmux';
      Process.run(tmux, ["kill-session", "-t", name]);
    }
    _cleanup(sessionId);
  }

  void sendHotReload(String sessionId) => _sendKeys(sessionId, "r");
  void sendHotRestart(String sessionId) => _sendKeys(sessionId, "R");
  void sendStdin(String sessionId, String text) => _sendKeys(sessionId, text);

  void _sendKeys(String sessionId, String keys) {
    final name = _sessionTmux[sessionId];
    if (name != null) {
      final tmux = _tmuxPath ?? 'tmux';
      Process.run(tmux, ["send-keys", "-t", name, keys]);
    }
  }

  bool isRunning(String sessionId) => _pollers.containsKey(sessionId);

  void _cleanup(String sessionId) {
    _pollers.remove(sessionId)?.cancel();
    _logFiles.remove(sessionId)?.close();
    _lineBuffers.remove(sessionId);
    _sessionTmux.remove(sessionId);
  }
}
