import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/sub_agent_event_watcher.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

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
  String? _cachedYoloitBin;

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
      if (!(configObj?.disableModel ?? false)) {
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
        RegExp(r'["“”]'),
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
    }

    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;
    final workingDir = _resolveWorkingDir(config.workingDir);

    // Prompt
    args.addAll(['-p', effectiveMessage]);

    var rawCommand = configObj?.launchCommand.trim() ?? '';
    if (rawCommand.isEmpty ||
        rawCommand == 'copilot' ||
        rawCommand == 'copilot --allow-all') {
      rawCommand = AgentConfigService.defaultBoardChatCommand(
        configObj?.streamAdapter ?? 'copilot',
      );
    }

    final cmdParts = _splitCommand(rawCommand);
    final executable = cmdParts.isNotEmpty ? cmdParts[0] : 'copilot';
    final extraCmdArgs =
        cmdParts.length > 1
            ? cmdParts.sublist(1).map(normaliseCopilotCommandArg).toList()
            : <String>[];

    debugPrint(
      '[CopilotCli] Running: $executable ${[...extraCmdArgs, ...args].join(' ')}',
    );
    debugPrint('[CopilotCli] cwd: $workingDir');

    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final yoloitBin = _resolveYoloitBin();
      final enrichedPath = _buildSessionPath(
        baseEnv['PATH'] ?? '',
        yoloitBin: yoloitBin,
      );
      final process = await _processStarter(
        executable,
        [...extraCmdArgs, ...args],
        workingDirectory: workingDir,
        environment: {
          ...baseEnv,
          'PATH': enrichedPath,
          if (yoloitBin != null) 'YOLOIT_BIN': yoloitBin,
        },
      );
      _processes[config.sessionName] = process;

      // Merge sub-agent events (from events.jsonl) into the main stream.
      // SubAgentEventWatcher discovers the session folder via the process PID
      // and tails events.jsonl in real-time.
      // Other providers (OpenCode, Cursor) should implement their own watcher
      // and merge into their controller the same way — the ChatPanelWidget
      // only depends on the subagent* ChatEventType values.
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
                  final json = jsonDecode(trimmed) as Map<String, dynamic>;
                  if (json['type'] == 'result' && json['sessionId'] is String) {
                    _sessionIds[config.sessionName] =
                        json['sessionId'] as String;
                  }
                  final event = ChatEvent.fromJson(json);
                  controller.add(event);
                } catch (e) {
                  debugPrint('[CopilotCli] Failed to parse line: $trimmed');
                  debugPrint('[CopilotCli] Error: $e');
                }
              }
            },
            onError: (Object error) {
              debugPrint('[CopilotCli] stdout error: $error');
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

      final stderrBuf = StringBuffer();
      final stderrDone = Completer<void>();
      process.stderr
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              debugPrint('[CopilotCli] stderr: $chunk');
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

      final exitCode = await process.exitCode;
      await stdoutDone.future;
      await stderrDone.future;
      debugPrint('[CopilotCli] Process exited with code: $exitCode');

      // Flush remaining buffer
      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        try {
          final json = jsonDecode(remaining) as Map<String, dynamic>;
          if (json['type'] == 'result' && json['sessionId'] is String) {
            _sessionIds[config.sessionName] = json['sessionId'] as String;
          }
          controller.add(ChatEvent.fromJson(json));
        } catch (_) {}
      }

      // If process exited with error and no events were emitted, surface stderr
      if (exitCode != 0) {
        final errText = stderrBuf.toString().trim();
        final recoveredSessionId =
            recoveryAttempted ? null : _recoverLatestSessionId(errText);
        if (recoveredSessionId != null) {
          _sessionIds[config.sessionName] = recoveredSessionId;
          debugPrint(
            '[CopilotCli] Recovering ambiguous session name '
            '"${config.sessionName}" with session ID $recoveredSessionId',
          );
          if (_processes[config.sessionName] == process) {
            _processes.remove(config.sessionName);
          }
          await subAgentSub?.cancel();
          await subAgentWatcher?.dispose();
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
          return;
        }
        controller.addError(
          errText.isNotEmpty
              ? errText
              : 'Copilot session resume failed (exit code $exitCode). '
                  'Start a new session if this one is no longer restorable.',
        );
      }

      // Only remove if this is still the active process (not replaced by a newer one)
      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      await subAgentSub?.cancel();
      await subAgentWatcher?.dispose();
      await controller.close();
    } catch (e, st) {
      debugPrint('[CopilotCli] Failed to start process: $e');
      debugPrint('[CopilotCli] Stack: $st');
      controller.addError(e);
      await controller.close();
    }
  }

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process != null) {
      debugPrint('[CopilotCli] Killing process for session: $sessionName');
      process.kill(ProcessSignal.sigterm);
      // Give SIGTERM up to 2 seconds; escalate to SIGKILL if still alive.
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
      if (exitCode == -1) {
        debugPrint(
          '[CopilotCli] SIGTERM ignored, sending SIGKILL: $sessionName',
        );
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

  String _resolveWorkingDir(String configuredDir) {
    final trimmed = configuredDir.trim();
    if (trimmed.isNotEmpty && Directory(trimmed).existsSync()) return trimmed;
    return Directory.current.path;
  }

  String _buildSessionPath(String existingPath, {required String? yoloitBin}) {
    final shell = PlatformShell.instance;
    final entries = <String>[
      if (yoloitBin != null) File(yoloitBin).parent.path,
      ...shell.splitPath(shell.enrichedPath(existingPath)),
    ];
    final deduped = <String>[];
    for (final entry in entries) {
      if (entry.isEmpty || deduped.contains(entry)) continue;
      deduped.add(entry);
    }
    return shell.joinPath(deduped);
  }

  String? _resolveYoloitBin() {
    final cached = _cachedYoloitBin;
    if (cached != null && File(cached).existsSync()) return cached;

    // Check the installed location first — written by CliServer on startup.
    final home = _homeDirectory;
    if (home.isNotEmpty) {
      final installed = File('$home/.config/yoloit/yoloit');
      if (installed.existsSync()) {
        _cachedYoloitBin = installed.path;
        return installed.path;
      }
    }

    final roots = <Directory>[];
    void addRoot(String path) {
      if (path.isEmpty) return;
      final dir = Directory(path).absolute;
      if (roots.any((existing) => existing.path == dir.path)) return;
      roots.add(dir);
    }

    addRoot(Directory.current.path);
    addRoot(File(Platform.resolvedExecutable).parent.path);

    for (final root in roots) {
      var current = root;
      for (var depth = 0; depth < 6; depth++) {
        final candidate = File(
          '${current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}yoloit',
        );
        if (candidate.existsSync()) {
          _cachedYoloitBin = candidate.path;
          return candidate.path;
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return null;
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

  List<String> _splitCommand(String command) {
    final parts = <String>[];
    final sb = StringBuffer();
    bool inDoubleQuotes = false;
    bool inSingleQuotes = false;
    for (int i = 0; i < command.length; i++) {
      final char = command[i];
      if (char == '"' && !inSingleQuotes) {
        inDoubleQuotes = !inDoubleQuotes;
      } else if (char == "'" && !inDoubleQuotes) {
        inSingleQuotes = !inSingleQuotes;
      } else if (char == ' ' && !inDoubleQuotes && !inSingleQuotes) {
        if (sb.isNotEmpty) {
          parts.add(sb.toString());
          sb.clear();
        }
      } else {
        sb.write(char);
      }
    }
    if (sb.isNotEmpty) {
      parts.add(sb.toString());
    }
    return parts;
  }
}
