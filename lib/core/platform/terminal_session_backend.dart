import 'dart:io';

/// Abstract backend for persistent terminal sessions.
///
/// Implementations:
/// - [TmuxSessionBackend] — macOS/Linux, backed by a tmux session.
/// - [ConPtySessionBackend] — Windows stub (not yet implemented).
///
/// Callers (`RunService`, `TmuxService`) interact with sessions via this
/// interface so that the underlying mechanism can be swapped per platform.
abstract class TerminalSessionBackend {
  const TerminalSessionBackend();

  /// Sanitises an arbitrary session ID to be safe as a backend session name.
  static String sanitiseName(String sessionId) =>
      sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  /// Starts a new terminal session running [command] in [workingDir].
  Future<void> start({
    required String sessionId,
    required String command,
    required String workingDir,
    Map<String, String> env = const {},
  });

  /// Attempts to reconnect to an existing session.
  /// Returns `true` if the session was found and reconnected.
  Future<bool> reconnect(String sessionId);

  /// Stops the session, cleaning up resources.
  Future<void> stop(String sessionId);

  /// Sends key input to the session (equivalent to typing in the terminal).
  Future<void> sendKeys(String sessionId, String keys);

  /// Returns the path to the log file for [sessionId], creating it if needed.
  Future<String> logPath(String sessionId);
}

// ── Windows ConPTY backend (stub — see implementation guide below) ────────────

/// Windows ConPTY backend — graceful no-op stub pending full implementation.
///
/// ## Implementation guide (Option B — full Windows terminal sessions)
///
/// Replace this stub with a real implementation using `flutter_pty` + ConPTY:
///
/// ### Dependencies (already in pubspec)
/// - `flutter_pty: ^0.4.2` — ConPTY support on Windows 10 1903+
/// - `PlatformShell.instance.defaultShell` — returns `cmd.exe` on Windows
/// - `PlatformDirs.instance.logsDir` — correct Windows log directory
///
/// ### start({sessionId, command, workingDir, env})
/// ```dart
/// final pty = Pty.start(
///   PlatformShell.instance.defaultShell,        // cmd.exe
///   arguments: ['/K', command],                  // /K keeps the window open
///   workingDirectory: workingDir,
///   environment: {...Platform.environment, ...env},
/// );
/// _ptySessions[sessionId] = pty;
/// // Mirror output to a log file for reconnect support:
/// final log = File(await logPath(sessionId));
/// pty.output.transform(utf8.decoder).listen((chunk) => log.writeAsStringSync(chunk, mode: FileMode.append));
/// ```
///
/// ### reconnect(sessionId)
/// Read the log file written by start(); emit all past output to the caller,
/// then resume tailing. Return `true` if the log exists and the process is
/// still alive (`_ptySessions[sessionId]?.exitCode == null`).
///
/// ### stop(sessionId)
/// ```dart
/// _ptySessions.remove(sessionId)?.kill();
/// // Optionally delete the log file.
/// ```
///
/// ### sendKeys(sessionId, keys)
/// ```dart
/// _ptySessions[sessionId]?.write(Uint8List.fromList(utf8.encode(keys)));
/// ```
///
/// ### logPath(sessionId)
/// ```dart
/// return path.join(PlatformDirs.instance.logsDir, 'session_$sessionId.log');
/// ```
///
/// ### Output stream (add to interface if needed)
/// ```dart
/// Stream<String> outputStream(String sessionId) =>
///     _ptySessions[sessionId]!.output.transform(utf8.decoder);
/// ```
class ConPtySessionBackend extends TerminalSessionBackend {
  const ConPtySessionBackend();

  @override
  Future<void> start({
    required String sessionId,
    required String command,
    required String workingDir,
    Map<String, String> env = const {},
  }) async {
    // Not yet implemented — TmuxService.init() returns early on Windows so
    // this method is never called in practice. See implementation guide above.
  }

  @override
  Future<bool> reconnect(String sessionId) async => false;

  @override
  Future<void> stop(String sessionId) async {}

  @override
  Future<void> sendKeys(String sessionId, String keys) async {}

  @override
  Future<String> logPath(String sessionId) async =>
      '${Directory.systemTemp.path}\\yoloit_session_$sessionId.log';
}
