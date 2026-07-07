import 'dart:async';
import 'dart:convert';

import 'package:yoloit/core/utils/http_client.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_catalog.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

/// Generic cloud LLM provider that works with any OpenAI-compatible API.
///
/// Supports tool calling via the standard function-calling protocol.
/// Configure with [CloudLlmConfig] — just a base URL, API key, and model.
/// Works with OpenRouter, Google Gemini, OpenAI, and any compatible endpoint.
class CloudLlmProvider extends ChatProvider {
  CloudLlmProvider({
    required CloudLlmConfig config,
    YoloitToolExecutor? toolExecutor,
  }) : _config = config,
       _deferredConfigId = null,
       _toolExecutor = toolExecutor ?? createYoloitToolExecutor();

  /// Creates a provider that loads its config lazily on first use.
  CloudLlmProvider.deferred({
    required String configId,
    YoloitToolExecutor? toolExecutor,
  }) : _config = null,
       _deferredConfigId = configId,
       _toolExecutor = toolExecutor ?? createYoloitToolExecutor();

  CloudLlmConfig? _config;
  final String? _deferredConfigId;
  final YoloitToolExecutor _toolExecutor;
  final Map<String, bool> _running = {};
  final Map<String, bool> _cancelRequested = {};
  final Map<String, List<Map<String, Object?>>> _history = {};
  int _toolCallSequence = 0;

  @override
  String get providerId => 'cloud:${_config?.id ?? _deferredConfigId ?? '?'}';

  /// Exposes the active config for debug/telemetry use.
  CloudLlmConfig? get config => _config;

  @override
  String get displayName => _config?.name ?? 'Cloud (loading…)';

  @override
  List<ChatModelInfo> get availableModels => const [];

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.base64;

  @override
  bool isRunning(String sessionName) => _running[sessionName] == true;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    // When set, the user message is sent as multimodal content (e.g. audio)
    // instead of the plain [message] string. The list entries are OpenAI-style
    // content items: [{'type':'input_audio','input_audio':{'data':...,'format':'wav'}}].
    List<Map<String, Object?>>? audioContentOverride,
  }) {
    final controller = StreamController<ChatEvent>();
    _run(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      controller: controller,
      runtimeContext: runtimeContext,
      audioContentOverride: audioContentOverride,
    );
    return controller.stream;
  }

  static const _maxIterations = 10;

  Future<void> _run({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required StreamController<ChatEvent> controller,
    required ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) async {
    final session = config.sessionName;
    _running[session] = true;
    _cancelRequested[session] = false;

    try {
      // Resolve deferred config if needed.
      if (_config == null && _deferredConfigId != null) {
        _config = await CloudLlmSettingsService.instance.loadConfigById(
          _deferredConfigId!,
        );
      }
      final cfg = _config;
      if (cfg == null || !cfg.isValid) {
        throw StateError(
          'Cloud provider is not configured. '
          'Set API key in Settings → Cloud Providers.',
        );
      }

      if (isFirstMessage) {
        _history[session] = [];
      }
      final sessionHistory = _history.putIfAbsent(
        session,
        () => <Map<String, Object?>>[],
      );
      final sanitizedSessionHistory = _sanitizeStoredHistory(sessionHistory);
      if (!identical(sanitizedSessionHistory, sessionHistory)) {
        sessionHistory
          ..clear()
          ..addAll(sanitizedSessionHistory);
      }

      final messageId = 'assistant-${DateTime.now().millisecondsSinceEpoch}';
      controller.add(
        ChatEvent(
          type: ChatEventType.assistantMessageStart,
          rawType: 'assistant.message_start',
          timestamp: DateTime.now(),
          data: {'messageId': messageId},
        ),
      );

      final stopwatch = Stopwatch()..start();
      var emitted = '';
      var streamedChunks = 0;
      var firstTokenMs = -1;
      var hadToolCalls = false;
      var retriedAfterEmptyResponse = false;

      final tools = YoloitCliToolCatalog.openAiToolDefinitions(
        disabledFunctionNames: config.disabledLocalToolNames,
      );
      final cliMermaidShort =
          await CliGuidanceService.instance.fetchMermaidShort();
      final messages = _buildMessages(
        sessionHistory,
        message,
        runtimeContext,
        cliMermaidShort: cliMermaidShort,
        audioContentOverride: audioContentOverride,
      );

      // Agentic loop — keep calling if the model requests tool calls.
      for (var iteration = 0; iteration < _maxIterations; iteration++) {
        if (_cancelRequested[session] == true) break;

        // Reset emitted each iteration — only keep final response text.
        emitted = '';

        // ignore: avoid_print
        print(
          '[CloudLlmProvider] ${cfg.name} model=${cfg.model} '
          'iteration=$iteration msgs=${messages.length}',
        );

        final response = await _callApi(
          config: cfg,
          messages: messages,
          tools: tools,
          onDelta: (delta) {
            if (_cancelRequested[session] == true) return;
            if (firstTokenMs < 0 && delta.trim().isNotEmpty) {
              firstTokenMs = stopwatch.elapsedMilliseconds;
            }
            streamedChunks++;
            emitted += delta;
            controller.add(
              ChatEvent(
                type: ChatEventType.assistantDelta,
                rawType: 'assistant.message_delta',
                timestamp: DateTime.now(),
                data: {'deltaContent': delta},
              ),
            );
          },
        );

        final toolCalls = response.toolCalls;
        if (toolCalls.isNotEmpty) {
          hadToolCalls = true;
          final resolvedToolCalls =
              toolCalls.map((tc) {
                final id = tc.id ?? 'tc-${_toolCallSequence++}';
                return _ParsedToolCall(
                  id: id,
                  functionName: tc.functionName,
                  arguments: Map<String, Object?>.from(tc.arguments),
                );
              }).toList();
          // Add assistant message with tool calls.
          messages.add({
            'role': 'assistant',
            'content': response.content ?? '',
            '_tool_calls_json': jsonEncode(
              resolvedToolCalls.map((tc) => tc.toJson()).toList(),
            ),
          });

          for (final tc in resolvedToolCalls) {
            if (_cancelRequested[session] == true) break;

            final resolvedName =
                YoloitCliToolArgumentNormalizer.normalizeFunctionName(
                  functionName: tc.functionName,
                  userMessage: message,
                );
            final normalizedArgs = YoloitCliToolArgumentNormalizer.normalize(
              functionName: resolvedName,
              arguments: Map<String, Object?>.from(tc.arguments),
              userMessage: message,
              runtimeContext: runtimeContext,
            );
            final toolCallId = tc.id!;

            controller.add(
              ChatEvent(
                type: ChatEventType.toolStart,
                rawType: 'tool.execution_start',
                timestamp: DateTime.now(),
                data: {
                  'toolCallId': toolCallId,
                  'toolName': resolvedName,
                  'arguments': normalizedArgs,
                },
              ),
            );

            String result;
            bool success;
            try {
              result = await _toolExecutor.invoke(
                resolvedName,
                normalizedArgs,
                runtimeContext: runtimeContext,
                argumentsPreNormalized: true,
              );
              success = _toolResultSucceeded(result);
            } catch (e) {
              result = jsonEncode({'ok': false, 'error': '$e'});
              success = false;
            }

            controller.add(
              ChatEvent(
                type: ChatEventType.toolComplete,
                rawType: 'tool.execution_complete',
                timestamp: DateTime.now(),
                data: {
                  'toolCallId': toolCallId,
                  'toolName': resolvedName,
                  'arguments': normalizedArgs,
                  'success': success,
                  'result': {'content': result},
                },
              ),
            );

            messages.add({
              'role': 'tool',
              'tool_call_id': toolCallId,
              'content': result,
            });
          }
          if (response.directReply != null &&
              response.directReply!.isNotEmpty) {
            emitted = response.directReply!;
            break;
          }
          continue;
        }

        // No tool calls — done.
        if (response.content != null && response.content!.isNotEmpty) {
          emitted = response.content!;
          break;
        }
        if (!retriedAfterEmptyResponse) {
          retriedAfterEmptyResponse = true;
          continue;
        }
        break;
      }

      stopwatch.stop();
      if (_cancelRequested[session] == true) return;

      var content = _stripThinkTags(emitted.trim());
      if (content.isEmpty) {
        if (hadToolCalls) {
          content = _looksCyrillic(message) ? 'Готово.' : 'Done.';
        } else {
          content =
              _looksCyrillic(message)
                  ? 'Не удалось сформировать ответ. Попробуйте уточнить запрос.'
                  : 'I could not generate a response. Please rephrase your request.';
        }
      }

      // Save full interaction to session history (including tool calls).
      // messages[0] is system, messages[1..N-1] are prior history,
      // new messages start after that. We need to save everything after
      // the prior history end.
      final priorCount = sessionHistory.length + 1; // +1 for system msg
      for (var i = priorCount; i < messages.length; i++) {
        sessionHistory.add(Map<String, Object?>.from(messages[i]));
      }
      // If the final assistant text response wasn't already added via messages
      // (happens when model responds without tool calls on first iteration),
      // add it explicitly.
      if (sessionHistory.isEmpty ||
          sessionHistory.last['role'] != 'assistant' ||
          sessionHistory.last['content'] != content) {
        // Remove any trailing assistant entry that had empty content from streaming
        if (sessionHistory.isNotEmpty &&
            sessionHistory.last['role'] == 'assistant' &&
            (sessionHistory.last['content'] == null ||
                (sessionHistory.last['content'] as String?)?.isEmpty == true)) {
          sessionHistory.removeLast();
        }
        sessionHistory.add({'role': 'assistant', 'content': content});
      }
      final sanitizedFinalHistory = _sanitizeStoredHistory(sessionHistory);
      if (!identical(sanitizedFinalHistory, sessionHistory)) {
        sessionHistory
          ..clear()
          ..addAll(sanitizedFinalHistory);
      }

      controller.add(
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'assistant.message',
          timestamp: DateTime.now(),
          data: {'messageId': messageId, 'content': content},
        ),
      );
      controller.add(
        ChatEvent(
          type: ChatEventType.result,
          rawType: 'result',
          timestamp: DateTime.now(),
          data: {
            'usage': {
              'outputTokens': streamedChunks,
              'premiumRequests': 0,
              'totalApiDurationMs': stopwatch.elapsedMilliseconds,
              'sessionDurationMs': stopwatch.elapsedMilliseconds,
              if (firstTokenMs >= 0) 'firstTokenMs': firstTokenMs,
              'generationDurationMs':
                  firstTokenMs >= 0
                      ? stopwatch.elapsedMilliseconds - firstTokenMs
                      : stopwatch.elapsedMilliseconds,
            },
          },
        ),
      );
    } catch (e) {
      controller.addError(e);
    } finally {
      _running[session] = false;
      _cancelRequested.remove(session);
      await controller.close();
    }
  }

  List<Map<String, Object?>> _buildMessages(
    List<Map<String, Object?>> history,
    String userMessage,
    ChatRuntimeContext? runtimeContext, {
    List<Map<String, Object?>>? audioContentOverride,
    String? cliMermaidShort,
  }) {
    final boardId = runtimeContext?.boardId?.trim();
    final boardName = runtimeContext?.boardName?.trim();
    final panelId = runtimeContext?.panelId?.trim();
    final panelTitle = runtimeContext?.panelTitle?.trim();
    final panelType = runtimeContext?.panelType?.trim();
    final boardsSummary = runtimeContext?.availableBoardsSummary?.trim();
    final panelsSummary = runtimeContext?.currentBoardPanelsSummary?.trim();

    final systemBuf = StringBuffer();
    systemBuf.writeln(
      'You are YoLo Assistant. '
      'Always use the available tools to fulfill requests. '
      'For greetings or pure casual chat with no action, reply with text only. '
      'Keep answers concise. Respond in the user\'s language.',
    );

    if (cliMermaidShort != null && cliMermaidShort.isNotEmpty) {
      systemBuf.writeln(
        '\nYoLoIT CLI command map (auto-generated, prefer typed tools over `do`):\n'
        '```mermaid\n$cliMermaidShort\n```',
      );
    }

    if (boardId != null && boardId.isNotEmpty) {
      systemBuf.writeln('\nCurrent context:');
      systemBuf.writeln('- Board: ${boardName ?? boardId} (id: $boardId)');
      if (panelId != null && panelId.isNotEmpty) {
        systemBuf.writeln('- Panel: ${panelTitle ?? panelId} (id: $panelId)');
      }
      if (panelType != null && panelType.isNotEmpty) {
        systemBuf.writeln('- Panel type: $panelType');
      }
      systemBuf.writeln(
        'Use this board/panel as default when a tool argument is omitted.',
      );
    }
    if (boardsSummary != null && boardsSummary.isNotEmpty) {
      systemBuf.writeln('\nAvailable boards:');
      systemBuf.writeln(boardsSummary);
    }
    if (panelsSummary != null && panelsSummary.isNotEmpty) {
      systemBuf.writeln('\nCurrent board panels:');
      systemBuf.writeln(panelsSummary);
    }
    final targetPanelSummary = runtimeContext?.targetPanelSummary?.trim();
    if (targetPanelSummary != null && targetPanelSummary.isNotEmpty) {
      systemBuf.writeln('\nFocus panel (the panel the assistant is attached to):');
      systemBuf.writeln(targetPanelSummary);
    }

    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': systemBuf.toString().trim()},
    ];

    for (final msg in history) {
      messages.add(Map<String, Object?>.from(msg));
    }

    if (audioContentOverride != null && audioContentOverride.isNotEmpty) {
      // Multimodal user message: send audio content directly to the LLM.
      messages.add({'role': 'user', 'content': audioContentOverride});
    } else {
      final snapshotB64 = runtimeContext?.boardSnapshotBase64;
      if (snapshotB64 != null && snapshotB64.isNotEmpty) {
        // Multimodal: text + board snapshot image
        messages.add({
          'role': 'user',
          'content': <Map<String, Object?>>[
            {'type': 'text', 'text': userMessage},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/png;base64,$snapshotB64',
                'detail': 'low',
              },
            },
          ],
        });
      } else {
        messages.add({'role': 'user', 'content': userMessage});
      }
    }
    return messages;
  }

  List<Map<String, Object?>> _sanitizeStoredHistory(
    List<Map<String, Object?>> history,
  ) {
    var changed = false;
    var generatedIdSequence = 0;
    final cleaned = <Map<String, Object?>>[];

    for (var i = 0; i < history.length; i++) {
      final current = Map<String, Object?>.from(history[i]);
      final role = current['role'] as String? ?? '';
      if (role == 'tool') {
        changed = true;
        continue;
      }

      if (role == 'assistant') {
        final toolCallsJson = current['_tool_calls_json'];
        if (toolCallsJson is String && toolCallsJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(toolCallsJson) as List;
            final lookaheadTools = <Map<String, Object?>>[];
            var j = i + 1;
            while (j < history.length) {
              final next = history[j];
              if ((next['role'] as String?) != 'tool') break;
              lookaheadTools.add(Map<String, Object?>.from(next));
              j++;
            }

            final normalizedToolCalls = <Map<String, Object?>>[];
            final expectedIds = <String>{};
            for (var idx = 0; idx < decoded.length; idx++) {
              final toolCall = Map<String, Object?>.from(decoded[idx] as Map);
              final currentId = (toolCall['id'] as String?)?.trim();
              final lookaheadId =
                  idx < lookaheadTools.length
                      ? (lookaheadTools[idx]['tool_call_id'] as String?)?.trim()
                      : null;
              final resolvedId =
                  (currentId != null && currentId.isNotEmpty)
                      ? currentId
                      : (lookaheadId != null && lookaheadId.isNotEmpty)
                      ? lookaheadId
                      : 'history-tc-${generatedIdSequence++}';
              if (resolvedId != currentId) changed = true;
              toolCall['id'] = resolvedId;
              normalizedToolCalls.add(toolCall);
              expectedIds.add(resolvedId);
            }
            current['_tool_calls_json'] = jsonEncode(normalizedToolCalls);
            cleaned.add(current);
            for (final tool in lookaheadTools) {
              final toolId = (tool['tool_call_id'] as String?)?.trim();
              if (toolId == null || !expectedIds.contains(toolId)) {
                changed = true;
                continue;
              }
              cleaned.add(tool);
            }
            if (lookaheadTools.isNotEmpty) {
              i = j - 1;
            }
            continue;
          } catch (_) {
            changed = true;
            current.remove('_tool_calls_json');
          }
        }
      }

      cleaned.add(current);
    }

    if (!changed && cleaned.length == history.length) return history;
    return cleaned;
  }

  Future<_ApiResponse> _callApi({
    required CloudLlmConfig config,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    required void Function(String delta) onDelta,
  }) async {
    var base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    // Ollama's OpenAI-compatible endpoint lives under /v1.  If the user
    // configured a local Ollama URL without the /v1 suffix, auto-correct it
    // so the request doesn't 404 on /chat/completions.
    final lowerBase = base.toLowerCase();
    final looksLikeOllama =
        lowerBase.contains('ollama') || lowerBase.contains(':11434');
    if (looksLikeOllama && !lowerBase.endsWith('/v1')) {
      base = '$base/v1';
    }
    final url = '$base/chat/completions';

    // Convert internal message format to OpenAI API format.
    final apiMessages =
        messages.map((m) {
          final msg = Map<String, Object?>.from(m);
          // Restore tool_calls from internal storage format.
          final tcJson = msg.remove('_tool_calls_json');
          if (tcJson is String) {
            try {
              msg['tool_calls'] = jsonDecode(tcJson);
            } catch (_) {}
          }
          return msg;
        }).toList();

    final body = jsonEncode({
      'model': config.model,
      'messages': apiMessages,
      if (tools.isNotEmpty) 'tools': tools,
      'stream': true,
      'max_tokens': 1024,
      'temperature': 0.1,
    });

    final client = YoloitHttpClientImpl();
    try {
      final response = await client.postJsonStream(
        url,
        body: jsonDecode(body),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          ...config.extraHeaders,
        },
      );

      // Parse SSE stream.
      var content = '';
      final toolCalls = <_ToolCallAccumulator>{};

      var sseBuffer = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        sseBuffer += chunk;
        final lines = sseBuffer.split('\n');
        sseBuffer = lines.removeLast();
        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;

            final choice = choices[0] as Map<String, dynamic>;
            final delta = choice['delta'] as Map<String, dynamic>?;
            final message = choice['message'] as Map<String, dynamic>?;
            if (delta == null && message == null) continue;

            final textDelta =
                (delta?['content'] as String?) ??
                (message?['content'] as String?);
            if (textDelta != null && textDelta.isNotEmpty) {
              content += textDelta;
              onDelta(textDelta);
            }

            final tcList =
                (delta?['tool_calls'] as List?) ??
                (message?['tool_calls'] as List?);
          if (tcList != null) {
            for (var i = 0; i < tcList.length; i++) {
              final tc = tcList[i];
              final tcMap = tc as Map<String, dynamic>;
              final index = tcMap['index'] as int? ?? i;
              final toolId = tcMap['id'] as String?;
              _ToolCallAccumulator? acc;
              if (toolId != null && toolId.isNotEmpty) {
                for (final existing in toolCalls) {
                  if (existing.id == toolId) {
                    acc = existing;
                    break;
                  }
                }
              }
              acc ??= toolCalls.firstWhere(
                (a) => a.index == index,
                orElse: () {
                  final a = _ToolCallAccumulator(index: index);
                  toolCalls.add(a);
                  return a;
                },
              );
              if (toolId != null && toolId.isNotEmpty) acc.id = toolId;
              final fn = tcMap['function'] as Map<String, dynamic>?;
              if (fn != null) {
                if (fn['name'] != null) {
                  final incomingName = fn['name'] as String;
                  // Some providers emit consecutive tool calls without a stable
                  // index/id in streaming chunks. If two complete yoloit names
                  // are non-prefix-compatible, start a new accumulator instead
                  // of concatenating into a broken name.
                  if (_isCompleteYoloitName(acc.name) &&
                      _isCompleteYoloitName(incomingName) &&
                      !incomingName.startsWith(acc.name) &&
                      !acc.name.startsWith(incomingName)) {
                    final next = _ToolCallAccumulator(index: toolCalls.length);
                    if (toolId != null && toolId.isNotEmpty) next.id = toolId;
                    toolCalls.add(next);
                    acc = next;
                  }
                  acc.name = _appendStreamFragment(acc.name, incomingName);
                }
                if (fn['arguments'] != null) {
                  acc.arguments = _appendStreamFragment(
                    acc.arguments,
                    fn['arguments'] as String,
                  );
                }
              }
            }
          }

          final legacyFunctionCall =
              (delta?['function_call'] as Map<String, dynamic>?) ??
              (message?['function_call'] as Map<String, dynamic>?);
          if (legacyFunctionCall != null) {
            final acc = toolCalls.firstWhere(
              (a) => a.index == 0,
              orElse: () {
                final a = _ToolCallAccumulator(index: 0);
                toolCalls.add(a);
                return a;
              },
            );
            acc.id = acc.id.isNotEmpty ? acc.id : 'legacy-function-call';
            if (legacyFunctionCall['name'] != null) {
              acc.name = _appendStreamFragment(
                acc.name,
                legacyFunctionCall['name'] as String,
              );
            }
            if (legacyFunctionCall['arguments'] != null) {
              acc.arguments = _appendStreamFragment(
                acc.arguments,
                legacyFunctionCall['arguments'] as String,
              );
            }
          }
        } catch (_) {}
      }
    }

    final parsedToolCalls =
        toolCalls.map((acc) {
          Map<String, Object?> args = {};
          try {
            args = Map<String, Object?>.from(jsonDecode(acc.arguments) as Map);
          } catch (_) {}
          return _ParsedToolCall(
            id: acc.id.isNotEmpty ? acc.id : null,
            functionName: acc.name,
            arguments: args,
          );
        }).toList();

    return _ApiResponse(
      content: content.isNotEmpty ? content : null,
      toolCalls: parsedToolCalls,
    );
    } finally {
      client.close();
    }
  }

  static final _thinkTagRe = RegExp(
    r'<think>[\s\S]*?</think>\s*',
    caseSensitive: false,
  );

  /// Strip `<think>...</think>` blocks some models emit (Qwen3, Mistral, etc.)
  String _stripThinkTags(String text) =>
      text.replaceAll(_thinkTagRe, '').trim();

  bool _looksCyrillic(String text) => RegExp(r'[\u0400-\u04FF]').hasMatch(text);

  bool _toolResultSucceeded(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map) return decoded['ok'] == true;
    } catch (_) {}
    return !result.contains('"ok":false');
  }

  String _appendStreamFragment(String current, String incoming) {
    if (incoming.isEmpty) return current;
    if (current.isEmpty) return incoming;
    if (incoming.startsWith(current)) return incoming;
    if (current.endsWith(incoming)) return current;
    return '$current$incoming';
  }

  bool _isCompleteYoloitName(String value) {
    final v = value.trim();
    if (!v.startsWith('yoloit_')) return false;
    return RegExp(r'^yoloit_[a-z0-9_]+$').hasMatch(v);
  }

  @override
  Future<void> stop(String sessionName) async {
    _cancelRequested[sessionName] = true;
  }

  @override
  void dispose() {
    _running.clear();
    _cancelRequested.clear();
  }
}

class _ApiResponse {
  const _ApiResponse({
    this.content,
    this.toolCalls = const [],
    this.directReply,
  });
  final String? content;
  final List<_ParsedToolCall> toolCalls;
  final String? directReply;
}

class _ParsedToolCall {
  const _ParsedToolCall({
    this.id,
    required this.functionName,
    required this.arguments,
  });
  final String? id;
  final String functionName;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': functionName, 'arguments': jsonEncode(arguments)},
  };
}

class _ToolCallAccumulator {
  _ToolCallAccumulator({required this.index});
  final int index;
  String id = '';
  String name = '';
  String arguments = '';
}
