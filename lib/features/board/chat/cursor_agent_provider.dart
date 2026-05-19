import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

/// [ChatProvider] implementation that wraps the Cursor Agent CLI.
///
/// Runs `cursor-agent --print --output-format stream-json` and translates
/// the cursor-specific NDJSON events into [ChatEvent] objects understood
/// by the common chat panel.
class CursorAgentProvider extends ChatProvider {
  CursorAgentProvider();

  /// sessionName → cursor session_id (UUID captured from the init event).
  final Map<String, String> _sessionIds = {};
  final Map<String, Process> _processes = {};

  /// The generated id of the currently streaming assistant message.
  /// Non-null means we are mid-stream; null means the stream is idle.
  String? _currentStreamId;

  @override
  String get providerId => 'cursor';

  @override
  String get displayName => 'Cursor Agent';

  @override
  List<ChatModelInfo> get availableModels =>
      ProviderModelCatalogService.instance.modelsForProvider('cursor') ??
      kCursorModels;

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
    _currentStreamId = null;

    final args = <String>[
      '--print',
      '--output-format',
      'stream-json',
      '--stream-partial-output',
      '--yolo',
      '--model',
      config.model,
    ];

    if (config.workingDir.isNotEmpty) {
      args.addAll(['--workspace', config.workingDir]);
    }

    // Resume existing cursor session (not first message)
    if (!isFirstMessage) {
      final cursorSessionId = _sessionIds[config.sessionName];
      if (cursorSessionId != null) {
        args.addAll(['--resume', cursorSessionId]);
      }
    }

    // Agent mode (plan / ask)
    if (config.mode != null && config.mode!.isNotEmpty) {
      args.addAll(['--mode', config.mode!]);
    }

    // Autopilot mode
    if (config.autopilot) {
      args.add('--autopilot');
    }

    // Prompt as positional argument.
    // Cursor-agent has no --attachment flag — image paths are embedded in the
    // prompt text so the agent can read them via its shell/file tools.
    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;
    final promptParts = [effectiveMessage, ...attachments];
    args.add(promptParts.join(' '));

    debugPrint('[CursorAgent] Running: cursor-agent ${args.join(' ')}');
    debugPrint('[CursorAgent] cwd: ${config.workingDir}');

    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final enrichedPath = PlatformShell.instance.enrichedPath(
        baseEnv['PATH'] ?? '',
      );
      final process = await Process.start(
        'cursor-agent',
        args,
        workingDirectory:
            config.workingDir.isNotEmpty ? config.workingDir : null,
        environment: {...baseEnv, 'PATH': enrichedPath},
      );
      _processes[config.sessionName] = process;

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

                  // Capture cursor session_id from init event
                  if (json['type'] == 'system' &&
                      json['subtype'] == 'init' &&
                      json['session_id'] is String) {
                    _sessionIds[config.sessionName] =
                        json['session_id'] as String;
                    debugPrint(
                      '[CursorAgent] session_id: ${_sessionIds[config.sessionName]}',
                    );
                  }

                  final events = _parseCursorEvent(json);
                  for (final event in events) {
                    controller.add(event);
                  }
                } catch (e) {
                  debugPrint('[CursorAgent] Failed to parse: $trimmed');
                  debugPrint('[CursorAgent] Error: $e');
                }
              }
            },
            onError: (Object error) {
              debugPrint('[CursorAgent] stdout error: $error');
              controller.addError(error);
            },
          );

      final stderrBuf = StringBuffer();
      process.stderr.transform(utf8.decoder).listen((chunk) {
        debugPrint('[CursorAgent] stderr: $chunk');
        stderrBuf.write(chunk);
      });

      final exitCode = await process.exitCode;
      debugPrint('[CursorAgent] Process exited: $exitCode');

      // Flush remaining buffer
      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        try {
          final json = jsonDecode(remaining) as Map<String, dynamic>;
          for (final event in _parseCursorEvent(json)) {
            controller.add(event);
          }
        } catch (_) {}
      }

      if (exitCode != 0) {
        final err = stderrBuf.toString().trim();
        controller.addError(
          err.isNotEmpty ? err : 'cursor-agent exited with code $exitCode',
        );
      }

      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      await controller.close();
    } catch (e, st) {
      debugPrint('[CursorAgent] Failed to start: $e\n$st');
      controller.addError(e);
      await controller.close();
    }
  }

  /// Translate a cursor-agent stream-json event into [ChatEvent]s.
  /// Returns empty list for events we intentionally ignore.
  List<ChatEvent> _parseCursorEvent(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final subtype = json['subtype'] as String?;

    switch (type) {
      case 'system':
        return [
          ChatEvent(
            type: ChatEventType.sessionStatus,
            rawType: 'cursor.system.$subtype',
            data: Map<String, dynamic>.from(json),
          ),
        ];

      case 'user':
        return [
          ChatEvent(
            type: ChatEventType.userMessage,
            rawType: 'cursor.user',
            data: const {},
          ),
        ];

      case 'thinking':
        return [];

      case 'assistant':
        final message = json['message'] as Map<String, dynamic>?;
        final content = _extractTextContent(message?['content']);
        final modelCallId = json['model_call_id'] as String?;
        final hasTimestamp = json.containsKey('timestamp_ms');

        if (hasTimestamp) {
          // Delta chunk (--stream-partial-output).
          // Use _currentStreamId == null to detect the first delta of a new
          // assistant turn (model_call_id is absent from delta events).
          final isFirst = _currentStreamId == null;

          if (isFirst) {
            final startId =
                modelCallId ??
                'cursor-${DateTime.now().millisecondsSinceEpoch}';
            _currentStreamId = startId;
            // Emit messageStart + first delta together
            return [
              ChatEvent(
                type: ChatEventType.assistantMessageStart,
                rawType: 'cursor.assistant.start',
                data: {'messageId': startId},
                id: startId,
              ),
              ChatEvent(
                type: ChatEventType.assistantDelta,
                rawType: 'cursor.assistant.delta',
                data: {'deltaContent': content},
              ),
            ];
          }
          return [
            ChatEvent(
              type: ChatEventType.assistantDelta,
              rawType: 'cursor.assistant.delta',
              data: {'deltaContent': content},
            ),
          ];
        } else {
          // Final complete message (no timestamp_ms) — end of this turn.
          final msgId =
              modelCallId ??
              _currentStreamId ??
              'cursor-${DateTime.now().millisecondsSinceEpoch}';
          _currentStreamId = null; // reset so next turn starts fresh
          return [
            ChatEvent(
              type: ChatEventType.assistantMessage,
              rawType: 'cursor.assistant',
              data: {'content': content, 'messageId': msgId},
              id: msgId,
            ),
          ];
        }

      case 'tool_call':
        if (subtype == 'started') {
          final callId = _sanitizeCallId(json['call_id'] as String? ?? '');
          final toolCall = json['tool_call'] as Map<String, dynamic>?;
          final (description, command) = _extractToolInfo(toolCall);
          return [
            ChatEvent(
              type: ChatEventType.toolStart,
              rawType: 'cursor.tool_call.started',
              data: {
                'toolCallId': callId,
                'toolName': description,
                'arguments': {'command': command},
              },
            ),
          ];
        } else if (subtype == 'completed') {
          final callId = _sanitizeCallId(json['call_id'] as String? ?? '');
          final toolCall = json['tool_call'] as Map<String, dynamic>?;
          final (isSuccess, output) = _extractToolResult(toolCall);
          return [
            ChatEvent(
              type: ChatEventType.toolComplete,
              rawType: 'cursor.tool_call.completed',
              data: {
                'toolCallId': callId,
                'success': isSuccess,
                'result': {'content': output},
              },
            ),
          ];
        }
        return [];

      case 'result':
        final usage = json['usage'] as Map<String, dynamic>?;
        return [
          ChatEvent(
            type: ChatEventType.result,
            rawType: 'cursor.result',
            data: {
              'usage': {
                'outputTokens': (usage?['outputTokens'] as num?)?.toInt() ?? 0,
                'totalApiDurationMs':
                    (json['duration_ms'] as num?)?.toInt() ?? 0,
              },
            },
          ),
        ];

      default:
        return [];
    }
  }

  /// Extract concatenated text from a cursor message content array.
  String _extractTextContent(dynamic content) {
    if (content is List) {
      return content
          .whereType<Map<String, dynamic>>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'] as String? ?? '')
          .join('');
    }
    if (content is String) return content;
    return '';
  }

  /// Extract tool description and primary argument from cursor tool_call JSON.
  /// Cursor supports many tool types (shellToolCall, readFile, editFile, …).
  (String description, String command) _extractToolInfo(
    Map<String, dynamic>? toolCall,
  ) {
    if (toolCall == null) return ('tool call', '');
    for (final key in toolCall.keys) {
      final nested = toolCall[key] as Map<String, dynamic>?;
      if (nested == null) continue;
      final description =
          nested['description'] as String? ?? _toolKeyToName(key);
      final args = nested['args'] as Map<String, dynamic>?;
      final command =
          args?['command'] as String? ??
          nested['path'] as String? ??
          nested['filePath'] as String? ??
          '';
      return (description, command);
    }
    return ('tool call', '');
  }

  /// Extract success/output from cursor tool_call completed JSON.
  (bool isSuccess, String output) _extractToolResult(
    Map<String, dynamic>? toolCall,
  ) {
    if (toolCall == null) return (true, '');
    for (final key in toolCall.keys) {
      final nested = toolCall[key] as Map<String, dynamic>?;
      if (nested == null) continue;
      final result = nested['result'] as Map<String, dynamic>?;
      if (result == null) return (true, '');
      if (result.containsKey('success')) {
        final successData = result['success'] as Map<String, dynamic>?;
        final exitCode = (successData?['exitCode'] as num?)?.toInt() ?? 0;
        final output =
            successData?['interleavedOutput'] as String? ??
            successData?['stdout'] as String? ??
            successData?['content'] as String? ??
            '';
        return (exitCode == 0, output);
      }
      if (result.containsKey('failure')) {
        final failData = result['failure'] as Map<String, dynamic>?;
        final msg = failData?['message'] as String? ?? '';
        return (false, msg);
      }
      // Unknown result format — treat as success
      return (true, result.toString());
    }
    return (true, '');
  }

  /// Convert camelCase cursor tool key to a human-readable label.
  String _toolKeyToName(String key) => switch (key) {
    'shellToolCall' => 'Shell',
    'readFile' => 'Read File',
    'editFile' => 'Edit File',
    'listDir' => 'List Dir',
    'searchFiles' => 'Search Files',
    'createFile' => 'Create File',
    'deleteFile' => 'Delete File',
    'moveFile' => 'Move File',
    _ => key,
  };

  /// Cursor call_ids can contain newline characters — sanitize for use as keys.
  String _sanitizeCallId(String id) => id.replaceAll('\n', '_');

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process != null) {
      debugPrint('[CursorAgent] Killing process for: $sessionName');
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
  /// Called when the board is switched away. In-flight cursor processes
  /// continue running and persist their session state; the user can resume
  /// from the next message when they switch back.
  @override
  void detach() {
    _processes.clear();
  }
}
