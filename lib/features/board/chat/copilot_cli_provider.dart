import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_resource_registration.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/chat/cli_yoloit_resolver.dart';
import 'package:yoloit/features/board/chat/sub_agent_event_watcher.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

typedef CopilotProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

final _multiSessionIdRe = RegExp(
  r'^\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s*$',
  caseSensitive: false,
  multiLine: true,
);

List<String> extractCopilotMultiSessionIds(String errorText) {
  return _multiSessionIdRe
      .allMatches(errorText)
      .map((match) => match.group(1)!)
      .toList(growable: false);
}

String? pickMostRecentCopilotSessionId(
  Iterable<String> sessionIds, {
  required String sessionStateRoot,
}) {
  String? latestId;
  DateTime? latestModifiedAt;
  final ids = sessionIds.toList(growable: false);
  for (final sessionId in ids) {
    final sessionDir = Directory('$sessionStateRoot/$sessionId');
    if (!sessionDir.existsSync()) continue;
    final modifiedAt = _copilotSessionModifiedAt(sessionDir);
    if (latestModifiedAt == null ||
        modifiedAt.isAfter(latestModifiedAt) ||
        modifiedAt.isAtSameMomentAs(latestModifiedAt)) {
      latestId = sessionId;
      latestModifiedAt = modifiedAt;
    }
  }
  if (latestId != null) return latestId;
  return ids.isNotEmpty ? ids.last : null;
}

DateTime _copilotSessionModifiedAt(Directory sessionDir) {
  final fileCandidates = [
    File('${sessionDir.path}/session.db'),
    File('${sessionDir.path}/events.jsonl'),
    File('${sessionDir.path}/workspace.yaml'),
  ];
  DateTime latest = sessionDir.statSync().modified;
  for (final candidate in fileCandidates) {
    if (!candidate.existsSync()) continue;
    final modifiedAt = candidate.statSync().modified;
    if (modifiedAt.isAfter(latest)) {
      latest = modifiedAt;
    }
  }
  return latest;
}

@visibleForTesting
String normaliseCopilotCommandArg(String arg) {
  // Early alpha builds could persist this typo in custom launch commands.
  // Normalize at launch time so saved settings don't break chat startup.
  return arg == '--yollo' ? '--yolo' : arg;
}

/// [ChatProvider] implementation that wraps the GitHub Copilot CLI.
///
/// Runs `copilot` with `--output-format json` and parses
/// the NDJSON output into [ChatEvent] objects.
class CopilotCliProvider extends ChatProvider {
  CopilotCliProvider({
    this.agentId = 'copilot',
    CopilotProcessStarter? processStarter,
    String? homeDirectory,
    String? sessionStateRoot,
    bool enableSubAgentWatcher = true,
  }) : _processStarter = processStarter ?? _defaultProcessStarter,
       _homeDirectory = homeDirectory ?? (Platform.environment['HOME'] ?? ''),
       _sessionStateRoot = sessionStateRoot,
       _enableSubAgentWatcher = enableSubAgentWatcher;

  final String agentId;
  final Map<String, Process> _processes = {};
  final Map<String, String> _sessionIds = {};
  final CopilotProcessStarter _processStarter;
  final String _homeDirectory;
  final String? _sessionStateRoot;
  final bool _enableSubAgentWatcher;

  @override
  String get providerId => agentId;

  @override
  String get displayName => 'GitHub Copilot';

  @override
  List<ChatModelInfo> get availableModels {
    final catalogModels = ProviderModelCatalogService.instance
        .modelsForProvider(agentId);
    if (catalogModels != null && catalogModels.isNotEmpty) {
      return catalogModels;
    }
    return ProviderModelCatalogService.instance.modelsForProvider('copilot') ??
        kCopilotModels;
  }

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool isRunning(String sessionName) => _processes.containsKey(sessionName);

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride, // ignored
  }) {
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
    String? resumeOverrideId,
    bool recoveryAttempted = false,
  }) async {
    // Kill any existing process for this session
    await stop(config.sessionName);

    final configObj = AgentConfigService.instance.configForAgent(agentId);
    final passDefault = configObj?.passDefaultArgs ?? true;

    final args = <String>[];
    if (passDefault) {
      args.addAll(
        _buildDefaultArgs(
          config: config,
          isFirstMessage: isFirstMessage,
          attachments: attachments,
          disableModel: configObj?.disableModel ?? false,
          resumeOverrideId: resumeOverrideId,
        ),
      );
    }

    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;
    final workingDir = CliProviderBase.resolveWorkingDir(config.workingDir);

    // Prompt
    args.addAll(['-p', effectiveMessage]);

    final cmdParts = CliProviderBase.splitCommand(
      _resolveRawCommand(configObj),
    );
    final executable = cmdParts.isNotEmpty ? cmdParts[0] : 'copilot';
    final extraCmdArgs =
        cmdParts.length > 1
            ? cmdParts.sublist(1).map(normaliseCopilotCommandArg).toList()
            : <String>[];

    assert(() {
      debugPrint(
      '[CopilotCli] Running: $executable ${[...extraCmdArgs, ...args].join(' ')}',
    );
      return true;
    }());
    assert(() { debugPrint('[CopilotCli] cwd: $workingDir'); return true; }());

    try {
      final process = await _startSessionProcess(
        executable,
        [...extraCmdArgs, ...args],
        workingDir,
        config,
        runtimeContext,
      );

      // Merge sub-agent events (from events.jsonl) into the main stream.
      // SubAgentEventWatcher discovers the session folder via the process PID
      // and tails events.jsonl in real-time.
      final subAgentWatcher =
          _enableSubAgentWatcher
              ? SubAgentEventWatcher(pid: process.pid)
              : null;
      final subAgentSub = subAgentWatcher?.events.listen((event) {
        if (!controller.isClosed) controller.add(event);
      }, onError: (_) {});

      // Buffer for incomplete JSON lines
      final buffer = StringBuffer();

      final stdoutDone = Completer<void>();
      _attachStdoutListener(process, config, controller, buffer, stdoutDone);

      final stderrBuf = StringBuffer();
      final stderrDone = Completer<void>();
      _attachStderrListener(process, stderrBuf, stderrDone);

      final exitCode = await process.exitCode;
      await stdoutDone.future;
      await stderrDone.future;
      assert(() { debugPrint('[CopilotCli] Process exited with code: $exitCode'); return true; }());

      // Flush remaining buffer
      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        try {
          _emitJsonLine(remaining, config.sessionName, controller);
        } catch (_) {}
      }

      // If process exited with error and no events were emitted, surface stderr
      if (exitCode != 0) {
        final retried = await _handleExitError(
          process: process,
          exitCode: exitCode,
          errText: stderrBuf.toString().trim(),
          message: message,
          config: config,
          isFirstMessage: isFirstMessage,
          attachments: attachments,
          runtimeContext: runtimeContext,
          controller: controller,
          recoveryAttempted: recoveryAttempted,
          subAgentSub: subAgentSub,
          subAgentWatcher: subAgentWatcher,
        );
        if (retried) return;
      }

      // Only remove if this is still the active process (not replaced by a newer one)
      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      unregisterChatProcessResource(process);
      await subAgentSub?.cancel();
      await subAgentWatcher?.dispose();
      await controller.close();
    } catch (e, st) {
      assert(() { debugPrint('[CopilotCli] Failed to start process: $e'); return true; }());
      assert(() { debugPrint('[CopilotCli] Stack: $st'); return true; }());
      controller.addError(e);
      await controller.close();
    }
  }

  List<String> _buildDefaultArgs({
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required bool disableModel,
    required String? resumeOverrideId,
  }) {
    final args = <String>[];
    if (!disableModel) {
      args.addAll(['--model', config.model]);
    }

    // Reasoning effort
    if (config.reasoningEffort != null) {
      args.addAll(['--reasoning-effort', config.reasoningEffort!]);
    }

    // Autopilot mode
    if (config.autopilot) {
      args.addAll([
        '--autopilot',
        '--max-autopilot-continues',
        '${config.maxAutopilotContinues}',
      ]);
    }

    // Agent mode
    if (config.mode != null && config.mode!.isNotEmpty) {
      args.addAll(['--mode', config.mode!]);
    }

    // Session name/resume — copilot binary rejects double quotes in --name.
    // Also normalize typographic quotes to avoid provider-side validation errors.
    final safeSessionName = config.sessionName.replaceAll(
      RegExp(r'["""]'),
      "'",
    );
    final resumeKey =
        resumeOverrideId ??
        _sessionIds[config.sessionName] ??
        safeSessionName;
    final useResume = !isFirstMessage;
    if (!useResume) {
      args.addAll(['--name', safeSessionName]);
    } else {
      args.addAll(['--resume', resumeKey]);
    }

    // Attachments
    for (final path in attachments) {
      args.addAll(['--attachment', path]);
    }

    // Custom args
    args.addAll(config.customArgs);
    return args;
  }

  String _resolveRawCommand(AgentConfig? configObj) {
    var rawCommand = configObj?.launchCommand.trim() ?? '';
    if (rawCommand.isEmpty ||
        rawCommand == 'copilot' ||
        rawCommand == 'copilot --allow-all') {
      rawCommand = AgentConfigService.defaultBoardChatCommand(
        configObj?.streamAdapter ?? 'copilot',
      );
    }
    return rawCommand;
  }

  Future<Process> _startSessionProcess(
    String executable,
    List<String> args,
    String workingDir,
    ChatSessionConfig config,
    ChatRuntimeContext? runtimeContext,
  ) async {
    final extraEnv = await GlobalEnvGroupsService.instance
        .resolveSelectedGroups(config.envGroupIds);
    final baseEnv = {...Platform.environment, ...extraEnv};
    final yoloitBin = CliYoloitResolver.resolve();
    final enrichedPath = CliYoloitResolver.buildSessionPath(
      baseEnv['PATH'] ?? '',
      yoloitBin: yoloitBin,
    );
    final process = await _processStarter(
      executable,
      args,
      workingDirectory: workingDir,
      environment: {
        ...baseEnv,
        'PATH': enrichedPath,
        if (yoloitBin != null) 'YOLOIT_BIN': yoloitBin,
      },
    );
    _processes[config.sessionName] = process;
    registerChatProcessResource(
      process: process,
      providerId: agentId,
      config: config,
      runtimeContext: runtimeContext,
    );
    return process;
  }

  void _emitJsonLine(
    String trimmed,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    if (json['type'] == 'result' && json['sessionId'] is String) {
      _sessionIds[sessionName] = json['sessionId'] as String;
    }
    controller.add(ChatEvent.fromJson(json));
  }

  void _attachStdoutListener(
    Process process,
    ChatSessionConfig config,
    StreamController<ChatEvent> controller,
    StringBuffer buffer,
    Completer<void> stdoutDone,
  ) {
    process.stdout
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            buffer.write(chunk);
            final lines = buffer.toString().split('\n');
            // Keep the last incomplete line in the buffer
            buffer.clear();
            buffer.write(lines.removeLast());

            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              try {
                _emitJsonLine(trimmed, config.sessionName, controller);
              } catch (e) {
                assert(() { debugPrint('[CopilotCli] Failed to parse line: $trimmed'); return true; }());
                assert(() { debugPrint('[CopilotCli] Error: $e'); return true; }());
              }
            }
          },
          onError: (Object error) {
            assert(() { debugPrint('[CopilotCli] stdout error: $error'); return true; }());
            if (!controller.isClosed) {
              controller.addError(error);
            }
            if (!stdoutDone.isCompleted) {
              stdoutDone.complete();
            }
          },
          onDone: () {
            if (!stdoutDone.isCompleted) {
              stdoutDone.complete();
            }
          },
        );
  }

  void _attachStderrListener(
    Process process,
    StringBuffer stderrBuf,
    Completer<void> stderrDone,
  ) {
    process.stderr
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            assert(() { debugPrint('[CopilotCli] stderr: $chunk'); return true; }());
            stderrBuf.write(chunk);
          },
          onError: (_) {
            if (!stderrDone.isCompleted) {
              stderrDone.complete();
            }
          },
          onDone: () {
            if (!stderrDone.isCompleted) {
              stderrDone.complete();
            }
          },
        );
  }

  /// Handles a non-zero exit: attempts session-recovery retries and surfaces
  /// stderr when no retry is possible.
  ///
  /// Returns true when the message was retried via a recursive [_runProcess]
  /// call (the caller must return without touching the controller).
  Future<bool> _handleExitError({
    required Process process,
    required int exitCode,
    required String errText,
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required StreamController<ChatEvent> controller,
    required bool recoveryAttempted,
    required StreamSubscription<ChatEvent>? subAgentSub,
    required SubAgentEventWatcher? subAgentWatcher,
  }) async {
    final recoveredSessionId =
        recoveryAttempted ? null : _recoverLatestSessionId(errText);
    if (recoveredSessionId != null) {
      _sessionIds[config.sessionName] = recoveredSessionId;
      assert(() {
        debugPrint(
        '[CopilotCli] Recovering ambiguous session name '
        '"${config.sessionName}" with session ID $recoveredSessionId',
      );
        return true;
      }());
      await _cleanupBeforeRetry(
        process,
        config.sessionName,
        subAgentSub,
        subAgentWatcher,
      );
      await _runProcess(
        message: message,
        config: config,
        isFirstMessage: isFirstMessage,
        attachments: attachments,
        runtimeContext: runtimeContext,
        controller: controller,
        resumeOverrideId: recoveredSessionId,
        recoveryAttempted: true,
      );
      return true;
    }
    final shouldCreateReplacementSession =
        !recoveryAttempted &&
        !isFirstMessage &&
        _isMissingCopilotSessionError(errText);
    if (shouldCreateReplacementSession) {
      _sessionIds.remove(config.sessionName);
      assert(() {
        debugPrint(
        '[CopilotCli] Resume target for "${config.sessionName}" is stale; '
        'creating a replacement named session.',
      );
        return true;
      }());
      await _cleanupBeforeRetry(
        process,
        config.sessionName,
        subAgentSub,
        subAgentWatcher,
      );
      await _runProcess(
        message: message,
        config: config,
        isFirstMessage: true,
        attachments: attachments,
        runtimeContext: runtimeContext,
        controller: controller,
        recoveryAttempted: true,
      );
      return true;
    }
    controller.addError(
      errText.isNotEmpty
          ? errText
          : 'Copilot session resume failed (exit code $exitCode). '
              'Start a new session if this one is no longer restorable.',
    );
    return false;
  }

  Future<void> _cleanupBeforeRetry(
    Process process,
    String sessionName,
    StreamSubscription<ChatEvent>? subAgentSub,
    SubAgentEventWatcher? subAgentWatcher,
  ) async {
    if (_processes[sessionName] == process) {
      _processes.remove(sessionName);
    }
    unregisterChatProcessResource(process);
    await subAgentSub?.cancel();
    await subAgentWatcher?.dispose();
  }

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process != null) {
      assert(() { debugPrint('[CopilotCli] Killing process for session: $sessionName'); return true; }());
      unregisterChatProcessResource(process);
      process.kill(ProcessSignal.sigterm);
      // Give SIGTERM up to 2 seconds; escalate to SIGKILL if still alive.
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
      if (exitCode == -1) {
        assert(() {
          debugPrint(
          '[CopilotCli] SIGTERM ignored, sending SIGKILL: $sessionName',
        );
          return true;
        }());
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(
          const Duration(seconds: 1),
          onTimeout: () => -1,
        );
      }
    }
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

  /// Drop process references without killing them.
  ///
  /// Called when the board is switched away. In-flight copilot processes
  /// continue running and persist their session state; the user can resume
  /// from the next message when they switch back.
  @override
  void detach() {
    _processes.clear();
  }

  @override
  void setSessionId(String sessionName, String sessionId) {
    _sessionIds[sessionName] = sessionId;
  }

  @override
  String? getSessionId(String sessionName) {
    return _sessionIds[sessionName];
  }

  String? _recoverLatestSessionId(String errorText) {
    if (!errorText.contains('Multiple sessions match the name')) return null;
    final matches = extractCopilotMultiSessionIds(errorText);
    if (matches.isEmpty) return null;
    final sessionStateRoot =
        _sessionStateRoot ??
        (_homeDirectory.isNotEmpty
            ? '$_homeDirectory/.copilot/session-state'
            : '');
    if (sessionStateRoot.isEmpty) return null;
    return pickMostRecentCopilotSessionId(
      matches,
      sessionStateRoot: sessionStateRoot,
    );
  }

  bool _isMissingCopilotSessionError(String errorText) {
    final normalized = errorText.toLowerCase();
    return normalized.contains('no session, task, or name matched') ||
        normalized.contains('to start a new session with id');
  }

  static Future<Process> _defaultProcessStarter(
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
}
