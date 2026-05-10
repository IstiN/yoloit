import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

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

  /// Tracks model_call_ids that have started streaming (have seen first delta).
  final Set<String> _streamingTurns = {};

  /// The model_call_id (or generated id) of the currently streaming message.
  String? _currentStreamId;

  @override
  String get providerId => 'cursor';

  @override
  String get displayName => 'Cursor Agent';

  @override
  List<ChatModelInfo> get availableModels => kCursorModels;

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
  }) {
    final controller = StreamController<ChatEvent>();
    _runProcess(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      attachments: attachments,
      controller: controller,
    );
    return controller.stream;
  }

  Future<void> _runProcess({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required StreamController<ChatEvent> controller,
  }) async {
    await stop(config.sessionName);
    _streamingTurns.clear();
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

    // Prompt as positional argument.
    // Cursor-agent has no --attachment flag — image paths are embedded in the
    // prompt text so the agent can read them via its shell/file tools.
    final promptParts = [message, ...attachments];
    args.add(promptParts.join(' '));

    debugPrint('[CursorAgent] Running: cursor-agent ${args.join(' ')}');
    debugPrint('[CursorAgent] cwd: ${config.workingDir}');

    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final process = await Process.start(
        'cursor-agent',
        args,
        workingDirectory:
            config.workingDir.isNotEmpty ? config.workingDir : null,
        environment: {...Platform.environment, ...extraEnv},
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
          // Delta chunk (--stream-partial-output)
          final isFirst = !_streamingTurns.contains(modelCallId ?? '_');
          if (modelCallId != null) _streamingTurns.add(modelCallId);

          if (isFirst) {
            final startId =
                modelCallId ?? 'cursor-${DateTime.now().millisecondsSinceEpoch}';
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
          // Final complete message (no timestamp_ms)
          final msgId =
              modelCallId ??
              _currentStreamId ??
              'cursor-${DateTime.now().millisecondsSinceEpoch}';
          if (modelCallId != null) _streamingTurns.remove(modelCallId);
          _currentStreamId = null;
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
          final description =
              toolCall?['description'] as String? ?? 'tool call';
          final shellArgs =
              (toolCall?['shellToolCall'] as Map<String, dynamic>?)?['args']
                  as Map<String, dynamic>?;
          final command = shellArgs?['command'] as String? ?? '';
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
          final shellTool =
              toolCall?['shellToolCall'] as Map<String, dynamic>?;
          final result = shellTool?['result'] as Map<String, dynamic>?;
          final isSuccess = result?.containsKey('success') == true;
          final successData = result?['success'] as Map<String, dynamic>?;
          final exitCode = (successData?['exitCode'] as num?)?.toInt() ?? 0;
          final output =
              successData?['interleavedOutput'] as String? ??
              successData?['stdout'] as String? ??
              '';
          return [
            ChatEvent(
              type: ChatEventType.toolComplete,
              rawType: 'cursor.tool_call.completed',
              data: {
                'toolCallId': callId,
                'success': isSuccess && exitCode == 0,
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
}
