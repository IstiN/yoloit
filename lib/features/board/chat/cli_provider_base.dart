import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_resource_registration.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// Function signature for starting an OS process.
/// Allows injection of fake processes in tests.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Exception thrown by [CliProviderBase.parseLine] when a line represents a
/// business-logic error (e.g. a 'turn.failed' event from the CLI).
/// Unlike other throws, [CliParseError] is propagated to the stream as an
/// error rather than being logged and skipped.
class CliParseError implements Exception {
  CliParseError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Base class for chat providers that communicate with an external CLI.
///
/// Subclasses only need to implement:
/// - [buildArgs]          – command-line arguments for the CLI
/// - [parseLine]          – turn one stdout line into [ChatEvent]s
/// - [defaultLaunchCommand] – fallback CLI command (e.g. 'kimi')
///
/// Common concerns (process lifecycle, stdout line buffering, stderr
/// collection, exit-code handling, session-ID bookkeeping, working-dir
/// resolution, PATH enrichment) are handled here.
abstract class CliProviderBase extends ChatProvider {
  CliProviderBase({
    required this.agentId,
    ProcessStarter? processStarter,
  }) : _processStarter = processStarter ?? _defaultStartProcess;

  final String agentId;
  final ProcessStarter _processStarter;

  final Map<String, Process> _processes = {};
  final Map<String, String> _sessionIds = {};

  /// Tracks the last model used per session.  Subclasses that need to reset
  /// a session when the model changes can read / write this map.
  @protected
  final Map<String, String> sessionModels = {};

  /// Prefix used in [debugPrint] output, e.g. `'[KimiCli]'`.
  String get debugPrefix;

  /// Default CLI command when the user has not configured a custom one.
  String get defaultLaunchCommand;

  /// Whether the provider passes default arguments (model, session, etc.).
  bool get passDefaultArgs => true;

  /// Whether the provider adds `--session <id>` to [baseArgs] for resumed
  /// conversations. Override to `false` when the subclass handles session
  /// resumption itself inside [buildArgs].
  bool get passSessionArgs => true;

  @override
  String get providerId => agentId;

  @override
  bool isRunning(String sessionName) => _processes.containsKey(sessionName);

  @override
  void setSessionId(String sessionName, String sessionId) {
    _sessionIds[sessionName] = sessionId;
  }

  @override
  String? getSessionId(String sessionName) => _sessionIds[sessionName];

  // ---------------------------------------------------------------------------
  // Subclass hooks
  // ---------------------------------------------------------------------------

  /// Build the CLI argument list.
  ///
  /// [baseArgs] already contains model / session / custom args when
  /// [passDefaultArgs] is true. [extraCmdArgs] contains any words after the
  /// executable in the user's configured launch command. Subclasses may
  /// mutate, replace, or re-order both lists.
  Future<List<String>> buildArgs({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required List<String> baseArgs,
    List<String> extraCmdArgs = const [],
  }) async => [...extraCmdArgs, ...baseArgs];

  /// Parse a single non-empty stdout line into chat events.
  ///
  /// [sessionName] is the name of the active chat session (useful for
  /// tracking session IDs inside parsed metadata events).
  ///
  /// Return an empty list if the line should be ignored.
  /// Throwing causes the line to be logged and skipped.
  List<ChatEvent> parseLine(String line, String sessionName);

  /// Called immediately after the process is spawned.
  ///
  /// Use this hook to attach watchers (log watchers, timers, etc.).
  void onProcessStarted(
    Process process,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {}

  /// Called for every chunk received on stderr.
  void onStderrChunk(
    String chunk,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {}

  /// Called just before the controller is closed after the process exits.
  void onProcessExited(
    int exitCode,
    String stderr,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {}

  /// Called right before the stream controller is closed.
  ///
  /// Subclasses can override this to wait for any pending background
  /// work (e.g. log-file watchers) to finish before the event stream
  /// is sealed.
  Future<void> onBeforeControllerClose(String sessionName) async {}

  /// Subclass hook for environment-variable overrides.
  ///
  /// The returned map is merged on top of the base environment (which already
  /// includes platform env + global env groups + PATH enrichment).  Use this
  /// to add provider-specific variables such as `YOLOIT_BIN` or
  /// `AGENT_CLI_CREDENTIAL_STORE`.
  Future<Map<String, String>> buildEnvironment({
    required Map<String, String> baseEnv,
    required ChatSessionConfig config,
  }) async => const {};

  // ---------------------------------------------------------------------------
  // Protected helpers for subclasses
  // ---------------------------------------------------------------------------

  /// Store a session ID so it can be resumed later.
  void storeSessionId(String sessionName, String sessionId) {
    _sessionIds[sessionName] = sessionId;
  }

  /// Remove a session ID (e.g. when the model changes).
  void clearSessionId(String sessionName) {
    _sessionIds.remove(sessionName);
  }

  // ---------------------------------------------------------------------------
  // ChatProvider implementation
  // ---------------------------------------------------------------------------

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) {
    // ignore: close_sinks - closed by _runProcess after the CLI exits.
    final controller = StreamController<ChatEvent>();
    _runProcess(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      attachments: attachments,
      runtimeContext: runtimeContext,
      controller: controller,
    );
    return controller.stream;
  }

  Future<void> _runProcess({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required StreamController<ChatEvent> controller,
  }) async {
    await stop(config.sessionName);

    final configObj = AgentConfigService.instance.configForAgent(agentId);
    final passDefault = passDefaultArgs && (configObj?.passDefaultArgs ?? true);

    // 1. Build base args (model, session, custom args, …).
    final baseArgs = <String>[];
    if (passDefault) {
      if (!(configObj?.disableModel ?? false) && config.model.isNotEmpty) {
        baseArgs.addAll(['--model', config.model]);
      }
      if (passSessionArgs && !isFirstMessage) {
        final sessionId = _sessionIds[config.sessionName];
        if (sessionId != null && sessionId.isNotEmpty) {
          baseArgs.addAll(['--session', sessionId]);
        }
      }
      baseArgs.addAll(config.customArgs);
    }

    // 3. Resolve executable & working dir.
    var rawCommand = configObj?.launchCommand.trim() ?? '';
    if (rawCommand.isEmpty || rawCommand == defaultLaunchCommand) {
      rawCommand = AgentConfigService.defaultBoardChatCommand(
        configObj?.streamAdapter ?? defaultLaunchCommand,
      );
    }
    final cmdParts = splitCommand(rawCommand);
    final executable = cmdParts.isNotEmpty ? cmdParts[0] : defaultLaunchCommand;
    final extraCmdArgs = cmdParts.length > 1 ? cmdParts.sublist(1) : <String>[];
    final workingDir = resolveWorkingDir(config.workingDir);

    // 2. Let subclass tweak args (now with extraCmdArgs visible).
    final args = await buildArgs(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      attachments: attachments,
      runtimeContext: runtimeContext,
      baseArgs: baseArgs,
      extraCmdArgs: extraCmdArgs,
    );

    assert(() {
      debugPrint(
      '$debugPrefix Running: '
      '$executable ${args.join(' ')}',
    );
      return true;
    }());
    assert(() { debugPrint('$debugPrefix cwd: $workingDir'); return true; }());

    // Debug log file for CLI output (always available for user to copy).
    final logFileName =
        'yoloit_cli_${agentId}_${DateTime.now().millisecondsSinceEpoch}.log';
    final logFile = File('/tmp/$logFileName');
    IOSink? logSink;
    try {
      logSink = logFile.openWrite();
      logSink.writeln('Command: $executable ${args.join(' ')}');
      logSink.writeln('Cwd: $workingDir');
      logSink.writeln('---');
    } catch (_) {
      logSink = null;
    }

    // 4. Start process.
    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final hookEnv = await buildEnvironment(baseEnv: baseEnv, config: config);
      final process = await _processStarter(
        executable,
        args,
        workingDirectory: workingDir,
        environment: {
          ...baseEnv,
          'PATH': PlatformShell.instance.enrichedPath(baseEnv['PATH'] ?? ''),
          ...hookEnv,
        },
      );

      _processes[config.sessionName] = process;
      registerChatProcessResource(
        process: process,
        providerId: agentId,
        config: config,
        runtimeContext: runtimeContext,
      );

      unawaited(
        process.stdin.close().catchError((Object error) {
          assert(() { debugPrint('$debugPrefix Failed to close stdin: $error'); return true; }());
        }),
      );

      onProcessStarted(process, config.sessionName, controller);

      // 5. Stdout listener with line buffering.
      final buffer = StringBuffer();
      final stdoutDone = Completer<void>();
      process.stdout
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              logSink?.write(chunk);
              buffer.write(chunk);
              final lines = buffer.toString().split('\n');
              buffer.clear();
              buffer.write(lines.removeLast());
              for (final line in lines) {
                _dispatchLine(line, config.sessionName, controller);
              }
            },
            onError: (Object error) {
              if (!controller.isClosed) controller.addError(error);
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
            onDone: () {
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
          );

      // 6. Stderr listener.
      final stderrBuffer = StringBuffer();
      final stderrDone = Completer<void>();
      process.stderr
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              logSink?.write('[STDERR] $chunk');
              stderrBuffer.write(chunk);
              onStderrChunk(chunk, config.sessionName, controller);
            },
            onDone: () {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
            onError: (_) {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
          );

      // 7. Wait for exit.
      final exitCode = await process.exitCode;
      await stdoutDone.future;
      await stderrDone.future;

      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        _dispatchLine(remaining, config.sessionName, controller);
      }

      logSink?.writeln('---');
      logSink?.writeln('Exit code: $exitCode');
      await logSink?.close();
      debugPrint('$debugPrefix CLI log: ${logFile.path}');

      onProcessExited(
        exitCode,
        stderrBuffer.toString().trim(),
        config.sessionName,
        controller,
      );

      if (exitCode != 0 && !controller.isClosed) {
        final stderr = stderrBuffer.toString().trim();
        controller.addError(
          stderr.isNotEmpty
              ? stderr
              : '$agentId exited with code $exitCode',
        );
      }

      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      unregisterChatProcessResource(process);
      await onBeforeControllerClose(config.sessionName);
      await controller.close();
    } catch (error, stack) {
      assert(() { debugPrint('$debugPrefix Failed to start process: $error'); return true; }());
      assert(() { debugPrint('$debugPrefix Stack: $stack'); return true; }());
      logSink?.writeln('---');
      logSink?.writeln('Failed to start: $error');
      await logSink?.close();
      if (!controller.isClosed) controller.addError(error);
      await onBeforeControllerClose(config.sessionName);
      await controller.close();
    }
  }

  void _dispatchLine(
    String line,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      for (final event in parseLine(trimmed, sessionName)) {
        controller.add(event);
      }
    } on CliParseError catch (error) {
      if (!controller.isClosed) controller.addError(error);
    } catch (error) {
      assert(() { debugPrint('$debugPrefix Failed to parse line: $trimmed'); return true; }());
      assert(() { debugPrint('$debugPrefix Error: $error'); return true; }());
    }
  }

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process == null) return;
    unregisterChatProcessResource(process);
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  @override
  void dispose() {
    for (final process in _processes.values) {
      unregisterChatProcessResource(process);
      process.kill(ProcessSignal.sigterm);
    }
    _processes.clear();
    _sessionIds.clear();
    sessionModels.clear();
  }

  @override
  void detach() {
    _processes.clear();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Resolve a configured working directory, falling back to [Directory.current]
  /// when empty or non-existent.
  static String resolveWorkingDir(String configuredDir) {
    final trimmed = configuredDir.trim();
    if (trimmed.isNotEmpty && Directory(trimmed).existsSync()) return trimmed;
    return Directory.current.path;
  }

  /// Split a shell-style command string into tokens, respecting single and
  /// double quotes.  Used to parse user-configured launch commands.
  static List<String> splitCommand(String command) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
        continue;
      }
      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (char.trim().isEmpty && !inSingle && !inDouble) {
        if (buffer.isNotEmpty) {
          parts.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    return parts;
  }
}

Future<Process> _defaultStartProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}
