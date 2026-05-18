import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// [ChatProvider] implementation that wraps the OpenCode CLI.
///
/// Runs `opencode run --format json --dangerously-skip-permissions`
/// and parses the NDJSON output into [ChatEvent] objects, same pattern
/// as CopilotCliProvider and CursorAgentProvider.
class OpencodeProvider extends ChatProvider {
  OpencodeProvider();

  final Map<String, String> _sessionIds = {};
  final Map<String, Process> _processes = {};
  String? _cachedYoloitBin;

  @override
  String get providerId => 'opencode';

  @override
  String get displayName => 'OpenCode';

  @override
  List<ChatModelInfo> get availableModels => kOpencodeModels;

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
  }) async {
    await stop(config.sessionName);

    final args = <String>[
      'run',
      '--format',
      'json',
      '--dangerously-skip-permissions',
    ];

    // Model
    if (config.model.isNotEmpty) {
      args.addAll(['--model', config.model]);
    }

    // Reasoning effort / variant
    if (config.reasoningEffort != null &&
        config.reasoningEffort!.isNotEmpty) {
      args.addAll(['--variant', config.reasoningEffort!]);
    }

    // Agent mode
    if (config.mode != null && config.mode!.isNotEmpty) {
      args.addAll(['--agent', config.mode!]);
    }

    // Session resume
    if (!isFirstMessage) {
      final sessionID = _sessionIds[config.sessionName];
      if (sessionID != null) {
        args.addAll(['--session', sessionID]);
        debugPrint('[OpenCode] Resuming session: $sessionID');
      } else {
        debugPrint(
          '[OpenCode] No sessionID for ${config.sessionName}, creating new',
        );
      }
    }

    // Working directory
    if (config.workingDir.isNotEmpty) {
      args.addAll(['--dir', config.workingDir]);
    }

    // Attachments via --file
    for (final path in attachments) {
      args.addAll(['--file', path]);
    }

    // Custom args
    args.addAll(config.customArgs);

    // Title for session naming
    if (isFirstMessage && config.sessionName.isNotEmpty) {
      args.addAll(['--title', config.sessionName]);
    }

    // Prepend YoLoIT CLI guidance tree to first message
    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;

    // Prompt as final positional argument
    args.add(effectiveMessage);

    final workingDir = _resolveWorkingDir(config.workingDir);

    debugPrint('[OpenCode] Running: opencode ${args.join(' ')}');
    debugPrint('[OpenCode] cwd: $workingDir');

    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final yoloitBin = _resolveYoloitBin();
      final sessionPath = _buildSessionPath(
        baseEnv['PATH'] ?? '',
        yoloitBin: yoloitBin,
      );

      final process = await Process.start(
        'opencode',
        args,
        workingDirectory: workingDir,
        environment: {
          ...baseEnv,
          'PATH': sessionPath,
          if (yoloitBin != null) 'YOLOIT_BIN': yoloitBin,
        },
      );
      // Close stdin so opencode doesn't wait for interactive input
      process.stdin.close();
      _processes[config.sessionName] = process;

      // Emit user message event
      controller.add(
        const ChatEvent(
          type: ChatEventType.userMessage,
          rawType: 'opencode.user.message',
          data: {},
        ),
      );

      final buffer = StringBuffer();

      process.stdout
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              buffer.write(chunk);
              final lines = buffer.toString().split('\n');
              buffer.clear();
              buffer.write(lines.removeLast());

              for (final line in lines) {
                final trimmed = line.trim();
                if (trimmed.isEmpty) continue;
                try {
                  final json = jsonDecode(trimmed) as Map<String, dynamic>;

                  // Capture sessionID from first event (for first message)
                  if (isFirstMessage) {
                    final sid = json['sessionID'] as String?;
                    if (sid != null && !_sessionIds.containsKey(config.sessionName)) {
                      _sessionIds[config.sessionName] = sid;
                      debugPrint('[OpenCode] Captured sessionID: $sid');
                    }
                  }

                  final events = _parseOpenCodeEvent(json);
                  for (final event in events) {
                    controller.add(event);
                  }
                } catch (e) {
                  debugPrint('[OpenCode] Failed to parse: $trimmed');
                  debugPrint('[OpenCode] Error: $e');
                }
              }
            },
            onError: (Object error) {
              debugPrint('[OpenCode] stdout error: $error');
              controller.addError(error);
            },
          );

      final stderrBuf = StringBuffer();
      process.stderr.transform(utf8.decoder).listen((chunk) {
        debugPrint('[OpenCode] stderr: $chunk');
        stderrBuf.write(chunk);
      });

      final exitCode = await process.exitCode;
      debugPrint('[OpenCode] Process exited: $exitCode');

      // Flush remaining buffer
      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        try {
          final json = jsonDecode(remaining) as Map<String, dynamic>;
          for (final event in _parseOpenCodeEvent(json)) {
            controller.add(event);
          }
        } catch (_) {}
      }

      // Emit result
      controller.add(
        const ChatEvent(
          type: ChatEventType.result,
          rawType: 'opencode.result',
          data: {},
        ),
      );

      if (exitCode != 0) {
        final err = stderrBuf.toString().trim();
        if (err.isNotEmpty) {
          controller.addError(err);
        }
      }

      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      await controller.close();
    } catch (e, st) {
      debugPrint('[OpenCode] Failed to start: $e\n$st');
      controller.addError(e);
      await controller.close();
    }
  }

  // ── event mapping ──────────────────────────────────────────────────────

  /// Map an `opencode run --format json` NDJSON line to [ChatEvent]s.
  List<ChatEvent> _parseOpenCodeEvent(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';

    switch (type) {
      case 'step_start':
        return [
          ChatEvent(
            type: ChatEventType.assistantTurnStart,
            rawType: 'opencode.step_start',
            data: _extractData(json),
          ),
        ];

      case 'step_finish':
        final part = json['part'] as Map<String, dynamic>?;
        return [
          ChatEvent(
            type: ChatEventType.assistantTurnEnd,
            rawType: 'opencode.step_finish',
            data: {
              'cost': part?['cost'],
              'tokens': part?['tokens'],
              'finish': part?['reason'],
            },
          ),
        ];

      case 'text':
        final part = json['part'] as Map<String, dynamic>?;
        final text = part?['text'] as String? ?? '';
        final partId = part?['id'] as String? ?? '';
        return [
          ChatEvent(
            type: ChatEventType.assistantMessageStart,
            rawType: 'opencode.text.start',
            data: {'messageId': partId},
            id: partId,
          ),
          ChatEvent(
            type: ChatEventType.assistantMessage,
            rawType: 'opencode.text',
            data: {'content': text, 'messageId': partId},
            id: partId,
          ),
        ];

      case 'tool_use':
        final part = json['part'] as Map<String, dynamic>?;
        if (part == null) return const [];

        final callID = part['callID'] as String? ?? '';
        final tool = part['tool'] as String? ?? 'unknown';
        final state = part['state'] as Map<String, dynamic>?;
        final status = state?['status'] as String?;
        final input = state?['input'] as Map<String, dynamic>?;
        final output = state?['output'] as String?;
        final title = state?['title'] as String?;
        final error = state?['error'] as String?;

        return [
          ChatEvent(
            type: ChatEventType.toolStart,
            rawType: 'opencode.tool_use.start',
            data: {
              'toolCallId': callID,
              'toolName': title ?? tool,
              'arguments': input ?? const {},
            },
          ),
          ChatEvent(
            type: ChatEventType.toolComplete,
            rawType: 'opencode.tool_use.complete',
            data: {
              'toolCallId': callID,
              'success': status == 'completed',
              'result': {
                'content':
                    status == 'completed'
                        ? (output ?? '')
                        : (error ?? 'Tool execution failed'),
              },
            },
          ),
        ];

      case 'reasoning':
        final part = json['part'] as Map<String, dynamic>?;
        final text = part?['text'] as String? ?? '';
        final partId = part?['id'] as String? ?? '';
        return [
          ChatEvent(
            type: ChatEventType.assistantDelta,
            rawType: 'opencode.reasoning',
            data: {'deltaContent': text},
            id: partId,
          ),
        ];

      case 'error':
        final errorObj = json['error'] as Map<String, dynamic>?;
        final errorData = errorObj?['data'] as Map<String, dynamic>?;
        final message = errorData?['message'] as String? ??
            errorObj?['name'] as String? ??
            'Unknown error';
        // Emit as assistant message so it's visible in chat (sessionStatus is ignored by UI)
        return [
          ChatEvent(
            type: ChatEventType.assistantMessage,
            rawType: 'opencode.error',
            data: {'content': '❌ OpenCode error: $message', 'messageId': ''},
          ),
        ];

      default:
        return const [];
    }
  }

  Map<String, dynamic> _extractData(Map<String, dynamic> json) {
    final part = json['part'] as Map<String, dynamic>?;
    return part != null
        ? Map<String, dynamic>.from(part)
        : <String, dynamic>{};
  }

  // ── helpers ────────────────────────────────────────────────────────────

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
    final home = Platform.environment['HOME'] ?? '';
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

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process != null) {
      debugPrint('[OpenCode] Killing process for: $sessionName');
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }
  }

  @override
  void dispose() {
    for (final process in _processes.values) {
      process.kill(ProcessSignal.sigterm);
    }
    _processes.clear();
  }

  /// Drop process references without killing them.
  ///
  /// Called when the board is switched away. In-flight opencode processes
  /// continue running and persist their session state; the user can resume
  /// from the next message when they switch back.
  @override
  void detach() {
    _processes.clear();
  }
}
