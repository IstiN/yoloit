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

  /// Prefix used in [debugPrint] output, e.g. `'[KimiCli]'`.
  String get debugPrefix;

  /// Default CLI command when the user has not configured a custom one.
  String get defaultLaunchCommand;

  /// Whether the provider passes default arguments (model, session, etc.).
  bool get passDefaultArgs => true;

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
  /// [passDefaultArgs] is true.  Subclasses may mutate or replace it.
  Future<List<String>> buildArgs({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required List<String> baseArgs,
  }) async => baseArgs;

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
      if (!isFirstMessage) {
        final sessionId = _sessionIds[config.sessionName];
        if (sessionId != null && sessionId.isNotEmpty) {
          baseArgs.addAll(['--session', sessionId]);
        }
      }
      baseArgs.addAll(config.customArgs);
    }

    // 2. Let subclass tweak args.
    final args = await buildArgs(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      attachments: attachments,
      runtimeContext: runtimeContext,
      baseArgs: baseArgs,
    );

    // 3. Resolve executable & working dir.
    var rawCommand = configObj?.launchCommand.trim() ?? '';
    if (rawCommand.isEmpty || rawCommand == defaultLaunchCommand) {
      rawCommand = AgentConfigService.defaultBoardChatCommand(
        configObj?.streamAdapter ?? defaultLaunchCommand,
      );
    }
    final cmdParts = _splitCommand(rawCommand);
    final executable = cmdParts.isNotEmpty ? cmdParts[0] : defaultLaunchCommand;
    final extraCmdArgs = cmdParts.length > 1 ? cmdParts.sublist(1) : <String>[];
    final workingDir = _resolveWorkingDir(config.workingDir);

    debugPrint(
      '$debugPrefix Running: '
      '$executable ${[...extraCmdArgs, ...args].join(' ')}',
    );
    debugPrint('$debugPrefix cwd: $workingDir');

    // 4. Start process.
    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final process = await _processStarter(
        executable,
        [...extraCmdArgs, ...args],
        workingDirectory: workingDir,
        environment: {
          ...baseEnv,
          'PATH': PlatformShell.instance.enrichedPath(baseEnv['PATH'] ?? ''),
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
          debugPrint('$debugPrefix Failed to close stdin: $error');
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
      await controller.close();
    } catch (error, stack) {
      debugPrint('$debugPrefix Failed to start process: $error');
      debugPrint('$debugPrefix Stack: $stack');
      if (!controller.isClosed) controller.addError(error);
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
    } catch (error) {
      debugPrint('$debugPrefix Failed to parse line: $trimmed');
      debugPrint('$debugPrefix Error: $error');
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
  }

  @override
  void detach() {
    _processes.clear();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _resolveWorkingDir(String configuredDir) {
    final trimmed = configuredDir.trim();
    if (trimmed.isNotEmpty && Directory(trimmed).existsSync()) return trimmed;
    return Directory.current.path;
  }

  static List<String> _splitCommand(String command) {
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
