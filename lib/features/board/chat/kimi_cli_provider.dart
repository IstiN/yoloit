import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

/// Per-session mutable state so that rapid successive messages do not
/// overwrite each other's data.
class _KimiSessionState {
  final Map<String, String> toolCallNames = {};
  bool wireJsonlAvailable = false;
  String? currentTurnId;
  String lastWirePartType = '';
}

/// [ChatProvider] implementation that wraps the Kimi CLI.
///
/// Uses `stream-json` for structured fallback events (tool calls, session IDs)
/// and watches the internal `wire.jsonl` log file for real-time thinking
/// and streaming text content.
class KimiCliProvider extends CliProviderBase {
  KimiCliProvider({
    super.agentId = 'kimi',
    super.processStarter,
    this.wireJsonlPath,
  });

  /// When non-null, overrides the auto-discovered wire.jsonl path.
  /// An empty string disables the watcher entirely (stream-json fallback).
  final String? wireJsonlPath;

  final Map<String, _KimiSessionState> _sessionStates = {};
  final Map<String, Process> _currentProcesses = {};
  final Map<String, Future<void>> _wireWatcherFutures = {};

  @override
  String get debugPrefix => '[KimiCli]';

  @override
  String get displayName => 'Kimi';

  @override
  String get defaultLaunchCommand => 'kimi';

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  void dispose() {
    _sessionStates.clear();
    _currentProcesses.clear();
    _wireWatcherFutures.clear();
    super.dispose();
  }

  _KimiSessionState _state(String sessionName) {
    return _sessionStates.putIfAbsent(sessionName, _KimiSessionState.new);
  }

  @override
  List<ChatModelInfo> get availableModels {
    final catalogModels = ProviderModelCatalogService.instance
        .modelsForProvider(agentId);
    if (catalogModels != null && catalogModels.isNotEmpty) {
      return catalogModels;
    }
    return kKimiModels;
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
    final configObj = AgentConfigService.instance.configForAgent(agentId);
    final passDefault = configObj?.passDefaultArgs ?? true;

    final args = <String>[...extraCmdArgs, ...baseArgs];

    if (passDefault) {
      if (config.mode == 'plan') {
        args.add('--plan');
      }
    }

    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;

    final prompt =
        attachments.isEmpty
            ? effectiveMessage
            : '$effectiveMessage\n\nAttachments:\n${attachments.join('\n')}';
    args.addAll(['-p', prompt]);

    return args;
  }

  @override
  void onProcessStarted(
    Process process,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    final state = _state(sessionName);
    state.currentTurnId = null;
    state.wireJsonlAvailable = false;
    state.lastWirePartType = '';
    state.toolCallNames.clear();

    _currentProcesses[sessionName] = process;

    // Start watching wire.jsonl for real-time thinking and streaming.
    _wireWatcherFutures[sessionName] = _startWireJsonlWatcher(
      process,
      sessionName,
      controller,
    );
  }

  // ---------------------------------------------------------------------------
  // wire.jsonl watcher
  // ---------------------------------------------------------------------------

  Future<void> _startWireJsonlWatcher(
    Process process,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) async {
    // Wait for wire.jsonl to be created.
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    final startTime = DateTime.now().subtract(const Duration(seconds: 2));

    final wirePath = await _resolveWireJsonlPath(startTime, sessionName);
    if (wirePath == null) return;

    debugPrint('$debugPrefix [$sessionName] Found wire.jsonl: $wirePath');
    _state(sessionName).wireJsonlAvailable = true;

    await _pollWireJsonl(process, sessionName, controller, wirePath, startTime);
  }

  /// Resolves the wire.jsonl path: explicit override, auto-discovery, or
  /// null when explicitly disabled / not found.
  Future<String?> _resolveWireJsonlPath(
    DateTime startTime,
    String sessionName,
  ) async {
    final overridePath = wireJsonlPath;
    if (overridePath != null) {
      if (overridePath.isEmpty) {
        // Explicitly disabled (e.g. in unit tests).
        return null;
      }
      return overridePath;
    }
    final discovered = await _findWireJsonl(startTime);
    if (discovered == null) {
      debugPrint(
        '$debugPrefix [$sessionName] wire.jsonl not found, '
        'using stream-json fallback',
      );
    }
    return discovered;
  }

  /// Polls [wirePath] for appended bytes until the controller closes or the
  /// process is replaced, then flushes any remaining bytes.
  Future<void> _pollWireJsonl(
    Process process,
    String sessionName,
    StreamController<ChatEvent> controller,
    String wirePath,
    DateTime startTime,
  ) async {
    final file = File(wirePath);
    var lastSize = 0;

    while (!controller.isClosed &&
        _currentProcesses[sessionName] == process) {
      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (!await file.exists()) continue;

      final stat = await file.stat();
      if (stat.size <= lastSize) continue;

      lastSize = await _readWireJsonlChunk(
        file,
        lastSize,
        stat.size,
        startTime,
        sessionName,
        controller,
      );
    }

    // Flush any remaining bytes after the loop exits.
    await _flushRemainingWireJsonl(
      wirePath,
      lastSize,
      startTime,
      sessionName,
      controller,
    );
  }

  /// Reads bytes in `[lastSize, size)` from [file], parses each line and
  /// emits events. Returns the new offset (unchanged on read failure).
  Future<int> _readWireJsonlChunk(
    File file,
    int lastSize,
    int size,
    DateTime startTime,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) async {
    var newSize = lastSize;
    try {
      final raf = await file.open(mode: FileMode.read);
      await raf.setPosition(lastSize);
      final bytes = await raf.read(size - lastSize);
      await raf.close();
      newSize = size;

      final text = utf8.decode(bytes);
      for (final line in const LineSplitter().convert(text)) {
        if (line.trim().isEmpty) continue;
        try {
          final events = _parseWireJsonlLine(
            line,
            startTime,
            sessionName,
          );
          for (final event in events) {
            if (!controller.isClosed) {
              controller.add(event);
            }
          }
        } catch (e) {
          debugPrint(
            '$debugPrefix [$sessionName] wire.jsonl parse error: $e',
          );
        }
      }
    } catch (e) {
      debugPrint(
        '$debugPrefix [$sessionName] wire.jsonl read error: $e',
      );
    }
    return newSize;
  }

  Future<void> _flushRemainingWireJsonl(
    String wirePath,
    int lastSize,
    DateTime startTime,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) async {
    final file = File(wirePath);
    if (!await file.exists()) return;

    // Give the file a moment to finish writing.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final stat = await file.stat();
    if (stat.size <= lastSize) return;

    try {
      final raf = await file.open(mode: FileMode.read);
      await raf.setPosition(lastSize);
      final bytes = await raf.read(stat.size - lastSize);
      await raf.close();

      final text = utf8.decode(bytes);
      for (final line in const LineSplitter().convert(text)) {
        if (line.trim().isEmpty) continue;
        try {
          final events = _parseWireJsonlLine(
            line,
            startTime,
            sessionName,
          );
          for (final event in events) {
            if (!controller.isClosed) {
              controller.add(event);
            }
          }
        } catch (e) {
          debugPrint(
            '$debugPrefix [$sessionName] wire.jsonl flush parse error: $e',
          );
        }
      }
    } catch (e) {
      debugPrint(
        '$debugPrefix [$sessionName] wire.jsonl flush error: $e',
      );
    }
  }

  Future<String?> _findWireJsonl(DateTime after) async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;

    // Retry up to 15 times (3s total) – wire.jsonl may not exist immediately.
    for (var attempt = 0; attempt < 15; attempt++) {
      final result = await Process.run(
        'find',
        ['$home/.kimi-code/sessions', '-name', 'wire.jsonl'],
      );

      final paths =
          (result.stdout as String)
              .trim()
              .split('\n')
              .where((p) => p.isNotEmpty)
              .toList();

      File? newestFile;
      DateTime? newestTime;
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final stat = await file.stat();
        if (stat.modified.isBefore(after)) continue;
        if (newestTime == null || stat.modified.isAfter(newestTime)) {
          newestTime = stat.modified;
          newestFile = file;
        }
      }

      if (newestFile != null) {
        debugPrint(
          '$debugPrefix wire.jsonl found after ${attempt + 1} '
          'attempt(s): ${newestFile.path}',
        );
        return newestFile.path;
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    debugPrint('$debugPrefix wire.jsonl not found after 15 attempts');
    return null;
  }

  List<ChatEvent> _parseWireJsonlLine(
    String line,
    DateTime startTime,
    String sessionName,
  ) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    final type = json['type'] as String?;

    if (type != 'context.append_loop_event') return const [];

    final event = json['event'] as Map<String, dynamic>?;
    if (event == null) return const [];

    final time = json['time'] as int?;
    if (time != null) {
      final eventTime = DateTime.fromMillisecondsSinceEpoch(time);
      if (eventTime.isBefore(startTime)) return const [];
    }

    final eventType = event['type'] as String?;
    final turnId = event['turnId'] as String?;
    final state = _state(sessionName);

    // Track current turn from the first step.begin we see.
    if (eventType == 'step.begin' && turnId != null) {
      if (state.currentTurnId == null) {
        state.currentTurnId = turnId;
        debugPrint(
          '$debugPrefix [$sessionName] Wire turnId: $turnId',
        );
      }
    }

    // Only process events from current turn.
    if (turnId != null && turnId != state.currentTurnId) return const [];

    switch (eventType) {
      case 'step.begin':
        return _wireStepBegin(event);
      case 'content.part':
        return _wireContentPart(event, state, sessionName);
      case 'tool.call':
        return _wireToolCall(event, state);
      case 'tool.result':
        return _wireToolResult(event, state);
      case 'step.end':
        return _wireStepEnd(event, state);
      default:
        return const [];
    }
  }

  List<ChatEvent> _wireStepBegin(Map<String, dynamic> event) {
    return [
      ChatEvent(
        type: ChatEventType.assistantMessageStart,
        rawType: 'kimi.wire.step_begin',
        id: 'kimi-step-${event['uuid']}',
        data: {'messageId': 'kimi-step-${event['uuid']}'},
      ),
    ];
  }

  List<ChatEvent> _wireContentPart(
    Map<String, dynamic> event,
    _KimiSessionState state,
    String sessionName,
  ) {
    final part = event['part'] as Map<String, dynamic>?;
    if (part == null) return const [];
    final partType = part['type'] as String?;

    if (partType == 'think') {
      return _wireThinkPart(event, part, state, sessionName);
    }
    if (partType == 'text') {
      return _wireTextPart(event, part, state, sessionName);
    }
    return const [];
  }

  List<ChatEvent> _wireThinkPart(
    Map<String, dynamic> event,
    Map<String, dynamic> part,
    _KimiSessionState state,
    String sessionName,
  ) {
    final think = part['think'] as String? ?? '';
    if (think.isEmpty) return const [];

    final delta = state.lastWirePartType != 'think'
        ? '> $think\n'
        : '$think\n';
    state.lastWirePartType = 'think';
    debugPrint(
      '$debugPrefix [$sessionName] Wire think '
      '[${state.currentTurnId ?? "?"}]: '
      '${think.substring(0, think.length.clamp(0, 60))}...',
    );

    return [
      ChatEvent(
        type: ChatEventType.assistantDelta,
        rawType: 'kimi.wire.think',
        id: 'kimi-think-${event['uuid']}',
        data: {'deltaContent': delta},
      ),
    ];
  }

  List<ChatEvent> _wireTextPart(
    Map<String, dynamic> event,
    Map<String, dynamic> part,
    _KimiSessionState state,
    String sessionName,
  ) {
    final text = part['text'] as String? ?? '';
    if (text.isEmpty) return const [];

    final delta = state.lastWirePartType == 'think'
        ? '\n$text'
        : text;
    state.lastWirePartType = 'text';
    debugPrint(
      '$debugPrefix [$sessionName] Wire text '
      '[${state.currentTurnId ?? "?"}]: '
      '${text.substring(0, text.length.clamp(0, 60))}...',
    );

    return [
      ChatEvent(
        type: ChatEventType.assistantDelta,
        rawType: 'kimi.wire.text',
        id: 'kimi-text-${event['uuid']}',
        data: {'deltaContent': delta},
      ),
    ];
  }

  List<ChatEvent> _wireToolCall(
    Map<String, dynamic> event,
    _KimiSessionState state,
  ) {
    final toolCallId = event['toolCallId'] as String? ?? '';
    final name = event['name'] as String? ?? '';
    final args = event['args'] as Map<String, dynamic>? ?? {};
    if (toolCallId.isNotEmpty && name.isNotEmpty) {
      state.toolCallNames[toolCallId] = name;
    }
    return [
      ChatEvent(
        type: ChatEventType.toolStart,
        rawType: 'kimi.wire.tool_call',
        id: toolCallId,
        data: {
          'toolCallId': toolCallId,
          'toolName': name,
          'arguments': args,
        },
      ),
    ];
  }

  List<ChatEvent> _wireToolResult(
    Map<String, dynamic> event,
    _KimiSessionState state,
  ) {
    final toolCallId = event['toolCallId'] as String? ?? '';
    final result = event['result'] as Map<String, dynamic>?;
    final output = result?['output'] as String? ?? '';
    final resolvedToolName = state.toolCallNames[toolCallId] ?? '';
    return [
      ChatEvent(
        type: ChatEventType.toolComplete,
        rawType: 'kimi.wire.tool_result',
        id: toolCallId,
        data: {
          'toolCallId': toolCallId,
          'toolName': resolvedToolName,
          'success': true,
          'result': {'content': output},
        },
      ),
    ];
  }

  List<ChatEvent> _wireStepEnd(
    Map<String, dynamic> event,
    _KimiSessionState state,
  ) {
    state.lastWirePartType = '';
    return [
      ChatEvent(
        type: ChatEventType.assistantMessage,
        rawType: 'kimi.wire.step_end',
        id: 'kimi-end-${event['uuid']}',
        data: {
          'messageId': 'kimi-end-${event['uuid']}',
          // Intentionally omit 'content' so that consumers fall back to
          // their accumulated _streamingContent via ??
        },
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // stream-json fallback
  // ---------------------------------------------------------------------------

  @override
  List<ChatEvent> parseLine(String line, String sessionName) {
    debugPrint('$debugPrefix [$sessionName] stream-json: $line');

    final json = jsonDecode(line) as Map<String, dynamic>;
    final role = json['role'] as String?;
    final state = _state(sessionName);

    // When wire.jsonl is available, skip assistant/tool events from
    // stream-json to avoid duplication. Only process meta/session events.
    if (state.wireJsonlAvailable) {
      if (role == 'assistant') {
        // Still extract tool_calls as a safety net.
        return _toolStartEvents(_extractToolCalls(json['tool_calls']), state);
      }

      if (role == 'tool') {
        return const [];
      }
    }

    // Fallback: full stream-json parsing when wire.jsonl is not available.
    if (role == 'assistant') {
      return _parseAssistantLine(json, state);
    }

    if (role == 'tool') {
      return _parseToolLine(json, state);
    }

    return _parseMetaLine(json, role, sessionName);
  }

  /// Builds toolStart events from extracted tool calls, recording the
  /// tool call names on [state] for later result resolution.
  List<ChatEvent> _toolStartEvents(
    List<Map<String, dynamic>> toolCalls,
    _KimiSessionState state,
  ) {
    final events = <ChatEvent>[];
    for (final tc in toolCalls) {
      final tcId = tc['toolCallId'] as String? ?? '';
      final tcName = tc['name'] as String? ?? '';
      if (tcId.isNotEmpty && tcName.isNotEmpty) {
        state.toolCallNames[tcId] = tcName;
      }
      events.add(
        ChatEvent(
          type: ChatEventType.toolStart,
          rawType: 'kimi.tool_call.start',
          id: tcId,
          data: {
            'toolCallId': tcId,
            'toolName': tcName,
            'arguments': tc['arguments'],
          },
        ),
      );
    }
    return events;
  }

  List<ChatEvent> _parseAssistantLine(
    Map<String, dynamic> json,
    _KimiSessionState state,
  ) {
    final content = _extractText(json['content']);
    final toolCalls = _extractToolCalls(json['tool_calls']);
    final id = 'kimi-${DateTime.now().microsecondsSinceEpoch}';
    final events = _toolStartEvents(toolCalls, state);

    events.add(
      ChatEvent(
        type: ChatEventType.assistantMessage,
        rawType: 'kimi.assistant',
        id: id,
        data: {
          'messageId': id,
          'content': content,
          if (toolCalls.isNotEmpty) 'toolRequests': toolCalls,
        },
      ),
    );
    return events;
  }

  List<ChatEvent> _parseToolLine(
    Map<String, dynamic> json,
    _KimiSessionState state,
  ) {
    final content = _extractText(json['content']);
    final toolCallId = json['tool_call_id'] as String? ?? '';
    final isError = content.contains('<system>ERROR:');
    final resolvedToolName = state.toolCallNames[toolCallId] ?? '';
    return [
      ChatEvent(
        type: ChatEventType.toolComplete,
        rawType: 'kimi.tool',
        id: toolCallId,
        data: {
          'toolCallId': toolCallId,
          'toolName': resolvedToolName,
          'success': !isError,
          'result': {'content': content},
        },
      ),
    ];
  }

  List<ChatEvent> _parseMetaLine(
    Map<String, dynamic> json,
    String? role,
    String sessionName,
  ) {
    // System notification (no role field).
    if (json['category'] is String || json['severity'] is String) {
      final title = json['title'] as String? ?? '';
      final body = json['body'] as String? ?? '';
      if (title.isNotEmpty || body.isNotEmpty) {
        return [
          ChatEvent(
            type: ChatEventType.sessionStatus,
            rawType: 'kimi.notification',
            data: {'title': title, 'body': body},
          ),
        ];
      }
      return const [];
    }

    // Plan display (no role field).
    if (json['file_path'] is String && json['content'] != null) {
      final planContent = json['content'] as String? ?? '';
      final planId = 'kimi-plan-${DateTime.now().microsecondsSinceEpoch}';
      return [
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'kimi.plan',
          id: planId,
          data: {'messageId': planId, 'content': planContent},
        ),
      ];
    }

    // Legacy meta event for session resumption (kept for backwards compat).
    if (role == 'meta' && json['type'] == 'session.resume_hint') {
      final sessionId = json['session_id'] as String?;
      if (sessionId != null && sessionId.isNotEmpty) {
        storeSessionId(sessionName, sessionId);
      }
      return const [];
    }

    return const [];
  }

  // ---------------------------------------------------------------------------
  // Hooks
  // ---------------------------------------------------------------------------

  @override
  void onProcessExited(
    int exitCode,
    String stderr,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    _currentProcesses.remove(sessionName);
  }

  @override
  Future<void> onBeforeControllerClose(String sessionName) async {
    final future = _wireWatcherFutures.remove(sessionName);
    if (future != null) {
      debugPrint(
        '$debugPrefix [$sessionName] Waiting for wire.jsonl watcher...',
      );
      await future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint(
            '$debugPrefix [$sessionName] wire.jsonl watcher timed out',
          );
        },
      );
      debugPrint(
        '$debugPrefix [$sessionName] wire.jsonl watcher done',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Extracts plain text from Kimi message content.
  /// Content may be a single string or a list of content parts.
  /// Thinking parts (type: "think") are included as a quoted block.
  String _extractText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final textParts = <String>[];
      final thinkParts = <String>[];
      for (final part in content) {
        if (part is String) {
          textParts.add(part);
          continue;
        }
        if (part is Map) {
          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            textParts.add(text);
            continue;
          }
          final think = part['think'];
          if (think is String && think.isNotEmpty) {
            thinkParts.add(think);
          }
        }
      }
      final result = <String>[];
      if (thinkParts.isNotEmpty) {
        final thinking = thinkParts.join();
        result.add('> **Thinking**\n');
        for (final line in thinking.split('\n')) {
          result.add('> $line\n');
        }
        result.add('\n');
      }
      result.addAll(textParts);
      return result.join();
    }
    return '';
  }

  /// Converts kosong-style tool_calls into the yoloit toolRequests format.
  List<Map<String, dynamic>> _extractToolCalls(Object? toolCallsJson) {
    if (toolCallsJson is! List) return const [];
    return toolCallsJson
        .whereType<Map<String, dynamic>>()
        .map((tc) {
          final id = tc['id'] as String? ?? '';
          final function = tc['function'] as Map<String, dynamic>?;
          final name = function?['name'] as String? ?? '';
          final argumentsStr = function?['arguments'] as String? ?? '{}';
          Map<String, dynamic> args;
          try {
            args = jsonDecode(argumentsStr) as Map<String, dynamic>;
          } catch (_) {
            args = <String, dynamic>{};
          }
          return <String, dynamic>{
            'toolCallId': id,
            'name': name,
            'arguments': args,
          };
        })
        .where(
          (tc) =>
              tc['toolCallId'] != null &&
              (tc['toolCallId'] as String).isNotEmpty,
        )
        .toList();
  }
}
