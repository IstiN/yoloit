import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

/// [ChatProvider] implementation that wraps the Cursor Agent CLI.
///
/// Runs `cursor-agent --print --output-format stream-json` and translates
/// the cursor-specific NDJSON events into [ChatEvent] objects understood
/// by the common chat panel.
class CursorAgentProvider extends CliProviderBase {
  CursorAgentProvider({
    super.agentId = 'cursor',
    super.processStarter,
  });

  @override
  String get debugPrefix => '[CursorAgent]';

  @override
  String get displayName => 'Cursor Agent';

  @override
  String get defaultLaunchCommand => 'cursor-agent';

  @override
  List<ChatModelInfo> get availableModels {
    final catalogModels = ProviderModelCatalogService.instance
        .modelsForProvider(agentId);
    if (catalogModels != null && catalogModels.isNotEmpty) {
      return catalogModels;
    }
    return ProviderModelCatalogService.instance.modelsForProvider('cursor') ??
        kCursorModels;
  }

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool get passSessionArgs => false;

  /// The generated id of the currently streaming assistant message.
  /// Non-null means we are mid-stream; null means the stream is idle.
  String? _currentStreamId;

  /// Accumulated text from the current streaming turn.
  /// cursor-agent can emit both incremental token chunks and periodic
  /// cumulative snapshots (full text so far); we use this accumulator to
  /// normalize both into true UI deltas.
  String _cumulativeContent = '';

  @override
  Future<Map<String, String>> buildEnvironment({
    required Map<String, String> baseEnv,
    required ChatSessionConfig config,
  }) async {
    // On macOS, cursor-agent hardcodes `/usr/bin/security` to access the
    // login keychain. When spawned from a GUI app the security context
    // lacks a default keychain → exit 154 (errSecNoDefaultKeychain), which
    // cursor-agent throws as a hard error before checking the
    // CURSOR_API_KEY env-var fallback.
    //
    // Setting AGENT_CLI_CREDENTIAL_STORE=memory makes cursor-agent use an
    // in-memory credential store (no keychain access at all). The auth
    // flow then naturally falls back to CURSOR_API_KEY from the process
    // environment, which the user can export from their shell profile or
    // store in macOS Keychain via `security add-generic-password`.
    return {
      if (Platform.isMacOS) 'AGENT_CLI_CREDENTIAL_STORE': 'memory',
    };
  }

  @override
  Future<List<String>> buildArgs({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required List<String> baseArgs,
    List<String> extraCmdArgs = const [],
  }) async {
    final args = <String>[...baseArgs];

    if (config.workingDir.isNotEmpty) {
      args.addAll(['--workspace', config.workingDir]);
    }

    // Resume existing cursor session only if the model hasn't changed.
    // Cursor ignores --model when --resume is passed (session stores its own
    // model), so a model switch must start a fresh session.
    if (!isFirstMessage) {
      final cursorSessionId = getSessionId(config.sessionName);
      final sessionModel = sessionModels[config.sessionName];
      final modelChanged =
          sessionModel != null && sessionModel != config.model;
      if (cursorSessionId != null && !modelChanged) {
        args.addAll(['--resume', cursorSessionId]);
      } else if (modelChanged) {
        // Clear the old session so the next init event registers the new one.
        clearSessionId(config.sessionName);
        sessionModels.remove(config.sessionName);
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

    return [...extraCmdArgs, ...args];
  }

  @override
  List<ChatEvent> parseLine(String line, String sessionName) {
    final json = jsonDecode(line) as Map<String, dynamic>;

    // Capture cursor session_id from init event and record the model.
    if (json['type'] == 'system' &&
        json['subtype'] == 'init' &&
        json['session_id'] is String) {
      storeSessionId(sessionName, json['session_id'] as String);
      // We don't have access to config.model here; the model is recorded
      // when args are built in the next message via sessionModels.
      assert(() {
        debugPrint(
        '[CursorAgent] session_id: ${getSessionId(sessionName)}',
      );
        return true;
      }());
    }

    return _parseCursorEvent(json);
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
          const ChatEvent(
            type: ChatEventType.userMessage,
            rawType: 'cursor.user',
            data: {},
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
          // cursor-agent sends a MIX of incremental token-level deltas AND
          // periodic cumulative snapshots (the full text so far).  We track
          // the accumulated text in _cumulativeContent and detect which kind
          // each event is to avoid duplicating text in the UI.
          final isFirst = _currentStreamId == null;

          String trueDelta;
          if (content == _cumulativeContent) {
            // Exact duplicate of accumulated content — skip entirely
            trueDelta = '';
          } else if (content.length > _cumulativeContent.length &&
              content.startsWith(_cumulativeContent)) {
            // Cumulative snapshot that extends past what we've seen — extract new portion
            trueDelta = content.substring(_cumulativeContent.length);
            _cumulativeContent = content;
          } else {
            // Incremental delta — append to accumulated text
            trueDelta = content;
            _cumulativeContent += content;
          }

          if (isFirst) {
            final startId =
                modelCallId ??
                'cursor-${DateTime.now().millisecondsSinceEpoch}';
            _currentStreamId = startId;
            return [
              ChatEvent(
                type: ChatEventType.assistantMessageStart,
                rawType: 'cursor.assistant.start',
                data: {'messageId': startId},
                id: startId,
              ),
              if (trueDelta.isNotEmpty)
                ChatEvent(
                  type: ChatEventType.assistantDelta,
                  rawType: 'cursor.assistant.delta',
                  data: {'deltaContent': trueDelta},
                ),
            ];
          }
          if (trueDelta.isEmpty) return [];
          return [
            ChatEvent(
              type: ChatEventType.assistantDelta,
              rawType: 'cursor.assistant.delta',
              data: {'deltaContent': trueDelta},
            ),
          ];
        } else {
          // Final complete message (no timestamp_ms) — end of this turn.
          final msgId =
              modelCallId ??
              _currentStreamId ??
              'cursor-${DateTime.now().millisecondsSinceEpoch}';
          _currentStreamId = null; // reset so next turn starts fresh
          _cumulativeContent = ''; // reset cumulative tracker
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
          final (description, _) = _extractToolInfo(toolCall);
          final (isSuccess, output) = _extractToolResult(toolCall);
          return [
            ChatEvent(
              type: ChatEventType.toolComplete,
              rawType: 'cursor.tool_call.completed',
              data: {
                'toolCallId': callId,
                'toolName': description,
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

  /// Runs `cursor-agent --list-models` and parses the output into
  /// [ChatModelInfo] entries.
  ///
  /// Requires `CURSOR_API_KEY` in [extraEnv] or platform environment.
  /// Returns `null` if cursor-agent is not installed or the command fails.
  static Future<List<ChatModelInfo>?> fetchModelsFromCli({
    Map<String, String> extraEnv = const {},
  }) async {
    try {
      final enrichedPath = PlatformShell.instance.enrichedPath(
        Platform.environment['PATH'] ?? '',
      );
      final env = {
        ...Platform.environment,
        ...extraEnv,
        'PATH': enrichedPath,
        if (Platform.isMacOS) 'AGENT_CLI_CREDENTIAL_STORE': 'memory',
      };
      final result = await Process.run('cursor-agent', [
        '--list-models',
      ], environment: env).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        assert(() { debugPrint('[CursorAgent] --list-models failed: ${result.stderr}'); return true; }());
        return null;
      }
      final output = (result.stdout as String).trim();
      return _parseModelList(output);
    } catch (e) {
      assert(() { debugPrint('[CursorAgent] fetchModelsFromCli error: $e'); return true; }());
      return null;
    }
  }

  /// Parses `cursor-agent --list-models` output.
  ///
  /// Format: one model per line, `id - Display Name`.
  /// First line is header ("Available models"), skipped.
  static List<ChatModelInfo> _parseModelList(String output) {
    final models = <ChatModelInfo>[];
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final dashIdx = trimmed.indexOf(' - ');
      if (dashIdx <= 0) continue;
      final id = trimmed.substring(0, dashIdx).trim();
      final displayName = trimmed.substring(dashIdx + 3).trim();
      if (id.isEmpty || displayName.isEmpty) continue;
      models.add(
        ChatModelInfo(
          id: id,
          displayName: displayName,
          isDefault: id == 'auto',
        ),
      );
    }
    assert(() { debugPrint('[CursorAgent] parsed ${models.length} models from CLI'); return true; }());
    return models;
  }
}
