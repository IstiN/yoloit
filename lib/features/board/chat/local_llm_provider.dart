import 'dart:async';
import 'dart:convert';

import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:local_models_flutter/runtime/embedded_gemma_tool_calls.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yolo_chat_prompt.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

const _compactLocalRoutingPrompt = '''
You are YoLo Assistant router.

Map the user's request to the single best `yoloit_` tool call.
Prefer calling a tool over describing steps. Keep normal assistant text short.

Rules:
- Use the current board/panel context when arguments are omitted.
- Infer obvious panel types and simple arguments from the user's wording.
- For destructive actions, require explicit user confirmation first.
- If no tool fits, answer briefly instead of inventing a tool.
''';

class LocalLlmProvider extends ChatProvider {
  LocalLlmProvider({
    flm.LmEngine? engine,
    Future<flm.InstalledModel> Function()? installedModelLoader,
    Future<void> Function()? runtimeReady,
    YoloitToolExecutor? toolExecutor,
  }) : _engine = engine ?? flm.NativeLmEngine(),
       _installedModelLoader = installedModelLoader,
       _runtimeReady = runtimeReady,
       _toolExecutor = toolExecutor ?? YoloitCliToolExecutor();

  final flm.LmEngine _engine;
  final Future<flm.InstalledModel> Function()? _installedModelLoader;
  final Future<void> Function()? _runtimeReady;
  final YoloitToolExecutor _toolExecutor;
  final Map<String, bool> _running = {};
  final Map<String, bool> _cancelRequested = {};
  final Map<String, List<({String user, String assistant})>> _history = {};
  final Map<
    String,
    List<
      ({
        String toolName,
        Map<String, Object?> arguments,
        String result,
        bool success,
      })
    >
  >
  _toolHistory = {};
  int _toolCallSequence = 0;

  @override
  String get providerId => 'local';

  @override
  String get displayName => 'Local LLM';

  @override
  List<ChatModelInfo> get availableModels => kLocalModels;

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
  }) {
    // ignore: close_sinks
    final controller = StreamController<ChatEvent>();
    _run(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      controller: controller,
      runtimeContext: runtimeContext,
    );
    return controller.stream;
  }

  Future<void> _run({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required StreamController<ChatEvent> controller,
    required ChatRuntimeContext? runtimeContext,
  }) async {
    final session = config.sessionName;
    _running[session] = true;
    _cancelRequested[session] = false;

    try {
      final installed = await _loadInstalledModel();
      final requestProfile = _requestProfileFor(installed.manifest);

      if (isFirstMessage) {
        _history[session] = [];
        _toolHistory[session] = [];
      }
      final sessionHistory = _history.putIfAbsent(
        session,
        () => <({String user, String assistant})>[],
      );
      final sessionToolHistory = _toolHistory.putIfAbsent(
        session,
        () =>
            <
              ({
                String toolName,
                Map<String, Object?> arguments,
                String result,
                bool success,
              })
            >[],
      );

      final messages = await _buildMessages(
        installed.manifest,
        sessionHistory,
        sessionToolHistory,
        message,
        runtimeContext,
      );
      final messageId = 'assistant-${DateTime.now().millisecondsSinceEpoch}';
      controller.add(
        ChatEvent(
          type: ChatEventType.assistantMessageStart,
          rawType: 'assistant.message_start',
          timestamp: DateTime.now(),
          data: {'messageId': messageId},
        ),
      );

      var emitted = '';
      var rawEmitted = '';
      final completionStopwatch = Stopwatch()..start();
      var firstTokenMs = -1;
      var streamedChunkCount = 0;
      final toolHistoryCountBefore = sessionToolHistory.length;
      Future<String> toolHandler(String name, Map<String, Object?> arguments) {
        final disabledTools = YoloitCliToolCatalog.normalizeFunctionNames(
          config.disabledLocalToolNames,
        );
        final resolvedName =
            YoloitCliToolArgumentNormalizer.normalizeFunctionName(
              functionName: name,
              userMessage: message,
            );
        return _handleToolCall(
          name: resolvedName,
          arguments: arguments,
          userMessage: message,
          controller: controller,
          runtimeContext: runtimeContext,
          sessionName: session,
          disabledFunctionNames: disabledTools,
        );
      }

      final full = await _engine.completeStreaming(
        flm.LmCompletionRequest(
          modelPath: installed.directory.path,
          manifest: installed.manifest,
          messages: messages,
          maxTokens: requestProfile.maxTokens,
          temperature: requestProfile.temperature,
          enableThinking: requestProfile.enableThinking,
          tools: YoloitCliToolCatalog.localToolsFor(
            disabledFunctionNames:
                config.disabledLocalToolNames
                    .map((name) => name.trim())
                    .toSet(),
          ),
          onToolCall: toolHandler,
        ),
        (chunk) {
          if (_cancelRequested[session] == true) return;
          if (firstTokenMs < 0 && chunk.trim().isNotEmpty) {
            firstTokenMs = completionStopwatch.elapsedMilliseconds;
          }
          final rawDelta = _extractDelta(previous: rawEmitted, incoming: chunk);
          if (rawDelta.isEmpty) return;
          streamedChunkCount++;
          rawEmitted += rawDelta;
          final visible = stripEmbeddedGemmaToolCallBlocks(rawEmitted);
          final delta = _extractDelta(previous: emitted, incoming: visible);
          if (delta.isEmpty) return;
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
      completionStopwatch.stop();

      final rawFull = full.trim().isNotEmpty ? full : rawEmitted;
      var completedContent = await applyEmbeddedGemmaToolCallsIfAny(
        rawModelOutput: rawFull,
        cleanedOutput: stripEmbeddedGemmaToolCallBlocks(rawFull),
        onTool: toolHandler,
      );
      completedContent = await _applyRouterJsonToolCallIfAny(
        rawModelOutput: rawFull,
        currentContent: completedContent,
        toolHistory: sessionToolHistory,
        toolHistoryCountBefore: toolHistoryCountBefore,
        onTool: toolHandler,
      );
      if (completedContent.startsWith(emitted)) {
        final delta = completedContent.substring(emitted.length);
        if (delta.isNotEmpty) {
          emitted = completedContent;
          controller.add(
            ChatEvent(
              type: ChatEventType.assistantDelta,
              rawType: 'assistant.message_delta',
              timestamp: DateTime.now(),
              data: {'deltaContent': delta},
            ),
          );
        }
      }

      if (_cancelRequested[session] == true) {
        return;
      }

      final content =
          completedContent.trim().isNotEmpty
              ? completedContent.trim()
              : emitted.trim();
      Map<String, Object?>? nativeTimings;
      final engine = _engine;
      if (engine is flm.NativeLmEngine) {
        nativeTimings = engine.lastNativeTimings;
      }
      final totalApiDurationMs =
          (nativeTimings?['swiftTotalMs'] as num?)?.toInt() ??
          completionStopwatch.elapsedMilliseconds;
      final effectiveFirstTokenMs =
          (nativeTimings?['swiftFirstTokenMs'] as num?)?.toInt() ??
          firstTokenMs;
      final generationDurationMs =
          (nativeTimings?['swiftGenerateMs'] as num?)?.toInt() ??
          (effectiveFirstTokenMs >= 0
              ? totalApiDurationMs - effectiveFirstTokenMs
              : totalApiDurationMs);
      sessionHistory.add((user: message, assistant: content));
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
              'outputTokens': streamedChunkCount,
              'premiumRequests': 0,
              'totalApiDurationMs': totalApiDurationMs,
              'sessionDurationMs': totalApiDurationMs,
              'codeChanges': const {'linesAdded': 0, 'linesRemoved': 0},
              if (effectiveFirstTokenMs >= 0)
                'firstTokenMs': effectiveFirstTokenMs,
              'generationDurationMs':
                  generationDurationMs < 0 ? 0 : generationDurationMs,
              if (nativeTimings != null) 'nativeTimings': nativeTimings,
            },
          },
        ),
      );
    } catch (e) {
      final raw = e.toString();
      if (raw.contains('flm_dispatch_json')) {
        controller.addError(
          StateError(
            'Local model runtime mismatch: missing symbol "flm_dispatch_json". '
            'Update/reinstall local models in Settings → AI Models and restart YoLoIT.',
          ),
        );
      } else {
        controller.addError(e);
      }
    } finally {
      _running[session] = false;
      _cancelRequested.remove(session);
      await controller.close();
    }
  }

  Future<flm.InstalledModel> _loadInstalledModel() async {
    final loader = _installedModelLoader;
    if (loader != null) {
      return loader();
    }

    await LocalAiModelsService.instance.initialize();
    final runtimeReady = _runtimeReady;
    if (runtimeReady != null) {
      await runtimeReady();
    } else {
      await LocalAiModelsService.instance.ensureRuntimeReady();
    }
    final modelId = LocalAiModelsService.instance.selectedChatModelId;
    final installed = LocalAiModelsService.instance.installedModelById(modelId);
    if (installed == null) {
      throw StateError(
        'Model "$modelId" is not installed. Download it in Settings → AI Models.',
      );
    }
    return flm.InstalledModel(
      manifest: installed.manifest,
      directory: installed.directory,
      sourceLabel: installed.sourceLabel,
      installedAt: installed.installedAt,
      sizeBytes: installed.sizeBytes,
      metadataUpdatedAt: installed.metadataUpdatedAt,
    );
  }

  Future<String> _handleToolCall({
    required String name,
    required Map<String, Object?> arguments,
    required String userMessage,
    required StreamController<ChatEvent> controller,
    required ChatRuntimeContext? runtimeContext,
    required String sessionName,
    required Set<String> disabledFunctionNames,
  }) async {
    // Defensive copy — native FFI callbacks may pass unmodifiable maps.
    final mutableArgs = Map<String, Object?>.from(arguments);
    final tool = YoloitCliToolCatalog.byFunctionName(name);
    final toolName = tool?.command ?? name;
    final toolCallId =
        'local-tool-${DateTime.now().microsecondsSinceEpoch}-${_toolCallSequence++}';
    final normalizedArgs = YoloitCliToolArgumentNormalizer.normalize(
      functionName: name,
      arguments: mutableArgs,
      userMessage: userMessage,
      runtimeContext: runtimeContext,
    );
    if (_cancelRequested[sessionName] == true) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'Tool call cancelled.',
      });
    }
    if (name == 'get_tools' || name == 'list_tools') {
      return YoloitCliToolCatalog.compactToolsJson(
        disabledFunctionNames: disabledFunctionNames,
      );
    }
    controller.add(
      ChatEvent(
        type: ChatEventType.toolStart,
        rawType: 'tool.execution_start',
        timestamp: DateTime.now(),
        data: {
          'toolCallId': toolCallId,
          'toolName': toolName,
          'arguments': normalizedArgs,
        },
      ),
    );

    if (YoloitCliToolCatalog.isFunctionDisabled(
      functionName: name,
      disabledFunctionNames: disabledFunctionNames,
    )) {
      final result = jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'YoLoIT tool "$name" is disabled for this chat session.',
      });
      controller.add(
        ChatEvent(
          type: ChatEventType.toolComplete,
          rawType: 'tool.execution_complete',
          timestamp: DateTime.now(),
          data: {
            'toolCallId': toolCallId,
            'toolName': toolName,
            'arguments': normalizedArgs,
            'success': false,
            'result': {'content': result},
          },
        ),
      );
      _rememberToolCall(
        sessionName: sessionName,
        toolName: toolName,
        arguments: normalizedArgs,
        result: result,
        success: false,
      );
      return result;
    }

    try {
      final result = await _toolExecutor.invoke(
        name,
        normalizedArgs,
        runtimeContext: runtimeContext,
      );
      final success = _toolResultSucceeded(result);
      controller.add(
        ChatEvent(
          type: ChatEventType.toolComplete,
          rawType: 'tool.execution_complete',
          timestamp: DateTime.now(),
          data: {
            'toolCallId': toolCallId,
            'toolName': toolName,
            'arguments': normalizedArgs,
            'success': success,
            'result': {'content': result},
          },
        ),
      );
      _rememberToolCall(
        sessionName: sessionName,
        toolName: toolName,
        arguments: normalizedArgs,
        result: result,
        success: success,
      );
      return result;
    } catch (e) {
      final result = jsonEncode(<String, Object?>{'ok': false, 'error': '$e'});
      controller.add(
        ChatEvent(
          type: ChatEventType.toolComplete,
          rawType: 'tool.execution_complete',
          timestamp: DateTime.now(),
          data: {
            'toolCallId': toolCallId,
            'toolName': toolName,
            'arguments': normalizedArgs,
            'success': false,
            'result': {'content': result},
          },
        ),
      );
      _rememberToolCall(
        sessionName: sessionName,
        toolName: toolName,
        arguments: normalizedArgs,
        result: result,
        success: false,
      );
      return result;
    }
  }

  void _rememberToolCall({
    required String sessionName,
    required String toolName,
    required Map<String, Object?> arguments,
    required String result,
    required bool success,
  }) {
    final history = _toolHistory.putIfAbsent(
      sessionName,
      () =>
          <
            ({
              String toolName,
              Map<String, Object?> arguments,
              String result,
              bool success,
            })
          >[],
    );
    history.add((
      toolName: toolName,
      arguments: Map<String, Object?>.from(arguments),
      result: result,
      success: success,
    ));
    if (history.length > 20) {
      history.removeRange(0, history.length - 20);
    }
  }

  bool _toolResultSucceeded(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map && decoded['ok'] is bool) {
        return decoded['ok'] as bool;
      }
    } catch (_) {}
    return true;
  }

  Future<String> _applyRouterJsonToolCallIfAny({
    required String rawModelOutput,
    required String currentContent,
    required List<
      ({
        String toolName,
        Map<String, Object?> arguments,
        String result,
        bool success,
      })
    >
    toolHistory,
    required int toolHistoryCountBefore,
    required Future<String> Function(
      String name,
      Map<String, Object?> arguments,
    )
    onTool,
  }) async {
    if (toolHistory.length > toolHistoryCountBefore) {
      return currentContent;
    }
    final parsed =
        _parseRouterToolCall(currentContent) ??
        _parseRouterToolCall(rawModelOutput);
    if (parsed == null) {
      return currentContent;
    }
    final result = await onTool(parsed.name, parsed.arguments);
    final trimmed = currentContent.trim();
    if (trimmed.isEmpty || _parseRouterToolCall(trimmed) != null) {
      return _routerToolSummary(parsed.name, result);
    }
    return currentContent;
  }

  ({String name, Map<String, Object?> arguments})? _parseRouterToolCall(
    String text,
  ) {
    final candidate = _extractJsonObject(text);
    if (candidate == null) return null;
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! Map) return null;
      final root = Map<String, Object?>.from(decoded);
      final function = root['function'];
      String? name;
      Map<String, Object?> arguments = <String, Object?>{};
      if (function is Map) {
        final functionMap = Map<String, Object?>.from(function);
        name = functionMap['name'] as String?;
        final rawArgs =
            functionMap['arguments'] ??
            functionMap['args'] ??
            functionMap['params'];
        if (rawArgs is Map) {
          arguments = Map<String, Object?>.from(rawArgs);
        }
      } else {
        // Compact router format: {"c":"command","a":["arg1","arg2"]}
        final compactName = root['c'] as String?;
        if (compactName != null) {
          name = compactName;
          final rawA = root['a'];
          if (rawA is List) {
            arguments = _positionalArgsToNamed(compactName, rawA);
          }
        } else {
          name =
              root['name'] as String? ??
              root['tool'] as String? ??
              root['functionName'] as String?;
          final rawArgs = root['arguments'] ?? root['args'] ?? root['params'];
          if (rawArgs is Map) {
            arguments = Map<String, Object?>.from(rawArgs);
          }
        }
      }
      final trimmedName = name?.trim();
      if (trimmedName == null || trimmedName.isEmpty) {
        return null;
      }
      return (name: trimmedName, arguments: arguments);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _positionalArgsToNamed(String command, List<Object?> positional) {
    final tool = YoloitCliToolCatalog.byFunctionName(command);
    if (tool == null) return <String, Object?>{};
    final result = <String, Object?>{};
    final params = tool.params;
    for (var i = 0; i < positional.length && i < params.length; i++) {
      final value = positional[i];
      if (value != null && value.toString().isNotEmpty) {
        result[params[i].key] = value;
      }
    }
    return result;
  }

  String? _extractJsonObject(String text) {
    var trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('```')) {
      trimmed =
          trimmed
              .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
              .replaceFirst(RegExp(r'\s*```$'), '')
              .trim();
    }
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(trimmed);
    return match?.group(0);
  }

  String _routerToolSummary(String toolName, String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map) {
        final command = decoded['command'] as String?;
        if (command != null && command.trim().isNotEmpty) {
          return 'Prepared $command';
        }
        final error = decoded['error'] as String?;
        if (error != null && error.trim().isNotEmpty) {
          return 'Tool $toolName failed: $error';
        }
      }
    } catch (_) {
      // Keep empty if the tool result is not JSON.
    }
    return '';
  }

  ({
    bool compactPrompt,
    int maxTokens,
    double temperature,
    bool? enableThinking,
  })
  _requestProfileFor(flm.LocalModelManifest manifest) {
    final compactPrompt = _usesCompactRoutingPrompt(manifest);
    final defaults = manifest.runtimeConfig.defaultParameters;
    return (
      compactPrompt: compactPrompt,
      maxTokens:
          _intDefault(defaults, 'max_tokens') ??
          _intDefault(defaults, 'maxTokens') ??
          (compactPrompt ? (_isRouterModel(manifest) ? 96 : 128) : 1024),
      temperature:
          _doubleDefault(defaults, 'temperature') ??
          (compactPrompt ? 0.0 : 0.2),
      enableThinking:
          _boolDefault(defaults, 'enableThinking') ??
          (_shouldDisableThinking(manifest) ? false : null),
    );
  }

  bool _isRouterModel(flm.LocalModelManifest manifest) =>
      manifest.id.toLowerCase().contains('router');

  bool _usesCompactRoutingPrompt(flm.LocalModelManifest manifest) {
    final id = manifest.id.toLowerCase();
    return _isRouterModel(manifest) || id == 'qwen3-0.6b-4bit';
  }

  bool _shouldDisableThinking(flm.LocalModelManifest manifest) {
    final id = manifest.id.toLowerCase();
    return _usesCompactRoutingPrompt(manifest) || id.contains('qwen3');
  }

  int? _intDefault(Map<String, Object?> defaults, String key) {
    final value = defaults[key];
    return value is num ? value.toInt() : null;
  }

  double? _doubleDefault(Map<String, Object?> defaults, String key) {
    final value = defaults[key];
    return value is num ? value.toDouble() : null;
  }

  bool? _boolDefault(Map<String, Object?> defaults, String key) {
    final value = defaults[key];
    return value is bool ? value : null;
  }

  Future<List<Map<String, String>>> _buildMessages(
    flm.LocalModelManifest manifest,
    List<({String user, String assistant})> turns,
    List<
      ({
        String toolName,
        Map<String, Object?> arguments,
        String result,
        bool success,
      })
    >
    toolHistory,
    String userMessage,
    ChatRuntimeContext? runtimeContext,
  ) async {
    final boardId = runtimeContext?.boardId?.trim();
    final boardName = runtimeContext?.boardName?.trim();
    final panelId = runtimeContext?.panelId?.trim();
    final panelTitle = runtimeContext?.panelTitle?.trim();
    final hasContext =
        (boardId != null && boardId.isNotEmpty) ||
        (boardName != null && boardName.isNotEmpty) ||
        (panelId != null && panelId.isNotEmpty) ||
        (panelTitle != null && panelTitle.isNotEmpty);

    final systemBuf = StringBuffer();
    systemBuf.writeln(
      _usesCompactRoutingPrompt(manifest)
          ? _compactLocalRoutingPrompt.trim()
          : await loadYoloChatSystemPrompt(),
    );
    if (hasContext) {
      systemBuf.writeln('\nCurrent UI context:');
      systemBuf.writeln('- Board id: ${boardId ?? 'unknown'}');
      systemBuf.writeln('- Board name: ${boardName ?? 'unknown'}');
      systemBuf.writeln('- Chat panel id: ${panelId ?? 'unknown'}');
      systemBuf.writeln('- Chat panel title: ${panelTitle ?? 'unknown'}');
      systemBuf.write(
        'Default to this board/panel when a tool argument is omitted.',
      );
    }

    final result = <Map<String, String>>[
      {'role': 'system', 'content': systemBuf.toString().trim()},
    ];

    for (final turn in turns) {
      result.add({'role': 'user', 'content': turn.user});
      result.add({'role': 'assistant', 'content': turn.assistant});
    }

    if (toolHistory.isNotEmpty) {
      final toolBuf = StringBuffer('Tool call history:\n');
      for (final call in toolHistory) {
        toolBuf.writeln(
          '- ${call.toolName} ${call.success ? 'succeeded' : 'failed'} '
          'args=${_compactPromptJson(call.arguments, 600)} '
          'result=${_compactToolResultForPrompt(call.result)}',
        );
      }
      result.add({'role': 'tool', 'content': toolBuf.toString().trim()});
    }

    result.add({'role': 'user', 'content': userMessage});
    return result;
  }

  String _compactToolResultForPrompt(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map) {
        final compact = <String, Object?>{
          if (decoded.containsKey('ok')) 'ok': decoded['ok'],
          if (decoded['command'] != null) 'command': decoded['command'],
          if (decoded['error'] != null) 'error': decoded['error'],
        };
        final stdout = decoded['stdout'];
        final panel = _panelSummaryFromStdout(stdout);
        if (panel != null) compact['panel'] = panel;
        if (compact.isNotEmpty) return _compactPromptJson(compact, 800);
      }
    } catch (_) {}
    return _truncatePromptText(result, 800);
  }

  Map<String, Object?>? _panelSummaryFromStdout(Object? stdout) {
    if (stdout is! String || stdout.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) return null;
      final panel = decoded['panel'];
      if (panel is! Map) return null;
      return <String, Object?>{
        if (panel['id'] != null) 'id': panel['id'],
        if (panel['title'] != null) 'title': panel['title'],
        if (panel['type'] != null) 'type': panel['type'],
      };
    } catch (_) {
      return null;
    }
  }

  String _compactPromptJson(Object? value, int maxChars) {
    try {
      return _truncatePromptText(jsonEncode(value), maxChars);
    } catch (_) {
      return _truncatePromptText('$value', maxChars);
    }
  }

  String _truncatePromptText(String value, int maxChars) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}…';
  }

  String _extractDelta({required String previous, required String incoming}) {
    if (incoming.startsWith(previous)) {
      return incoming.substring(previous.length);
    }
    return incoming;
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
