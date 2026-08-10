import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/chat/cli_yoloit_resolver.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/models_dev_catalog_service.dart';
import 'package:yoloit/features/settings/data/opencode_auth_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

/// [ChatProvider] implementation that wraps the OpenCode CLI.
///
/// Runs `opencode run --format json --dangerously-skip-permissions`
/// and parses the NDJSON output into [ChatEvent] objects, same pattern
/// as CopilotCliProvider and CursorAgentProvider.
class OpencodeProvider extends CliProviderBase {
  OpencodeProvider({super.agentId = 'opencode', super.processStarter});

  @override
  String get debugPrefix => '[OpenCode]';

  @override
  String get displayName => 'OpenCode';

  @override
  String get defaultLaunchCommand => 'opencode';

  @override
  List<ChatModelInfo> get availableModels {
    final catalogModels = ProviderModelCatalogService.instance
        .modelsForProvider(agentId);
    if (catalogModels != null && catalogModels.isNotEmpty) {
      return catalogModels;
    }
    // 1. models.dev dynamically loaded (most up-to-date)
    if (_cachedModelsDevModels != null && _cachedModelsDevModels!.isNotEmpty) {
      return _cachedModelsDevModels!;
    }
    // 2. GitHub-hosted catalog (provider_models.json)
    final opencodeCatalogModels = ProviderModelCatalogService.instance
        .modelsForProvider('opencode');
    if (opencodeCatalogModels != null && opencodeCatalogModels.isNotEmpty) {
      return opencodeCatalogModels;
    }
    // 3. Hardcoded fallback
    return kOpencodeModels;
  }

  /// Triggers a background refresh of models from models.dev + opencode auth.
  ///
  /// Loads:
  /// - FREE opencode provider models (always available without a key)
  /// - ALL models from providers configured in opencode's auth.json
  Future<void> refreshModelsFromModelsDev({bool force = false}) async {
    try {
      final configuredProviders =
          await OpenCodeAuthService.instance.configuredProviderIds();
      final models = await ModelsDevCatalogService.instance
          .opencodeModelsWithAuth(
            configuredProviderIds: configuredProviders,
            force: force,
          );
      if (models.isNotEmpty) {
        _cachedModelsDevModels = models;
      }
    } catch (e) {
      debugPrint('[OpenCode] models.dev refresh failed: $e');
    }
  }

  // Cached models loaded from models.dev
  List<ChatModelInfo>? _cachedModelsDevModels;

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool get passSessionArgs => false;

  @override
  Future<Map<String, String>> buildEnvironment({
    required Map<String, String> baseEnv,
    required ChatSessionConfig config,
  }) async {
    final yoloitBin = CliYoloitResolver.resolve();
    final sessionPath = CliYoloitResolver.buildSessionPath(
      baseEnv['PATH'] ?? '',
      yoloitBin: yoloitBin,
    );
    return {
      'PATH': sessionPath,
      if (yoloitBin != null) 'YOLOIT_BIN': yoloitBin,
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
    final args = <String>[...extraCmdArgs, ...baseArgs];

    // Model
    if (config.model.isNotEmpty) {
      args.addAll(['--model', config.model]);
    }

    // Reasoning effort / variant
    if (config.reasoningEffort != null && config.reasoningEffort!.isNotEmpty) {
      args.addAll(['--variant', config.reasoningEffort!]);
    }

    // Agent mode
    if (config.mode != null && config.mode!.isNotEmpty) {
      args.addAll(['--agent', config.mode!]);
    }

    // Session resume — reset session if model changed since last message.
    if (!isFirstMessage) {
      final lastModel = sessionModels[config.sessionName];
      if (lastModel != null && lastModel != config.model) {
        debugPrint(
          '[OpenCode] Model changed ($lastModel → ${config.model}), '
          'starting new session',
        );
        clearSessionId(config.sessionName);
      }
      final sessionID = getSessionId(config.sessionName);
      if (sessionID != null) {
        args.addAll(['--session', sessionID]);
        debugPrint('[OpenCode] Resuming session: $sessionID');
      } else {
        debugPrint(
          '[OpenCode] No sessionID for ${config.sessionName}, creating new',
        );
      }
    }
    sessionModels[config.sessionName] = config.model;

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

    return args;
  }

  @override
  void onProcessStarted(
    Process process,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    // Emit user message event immediately
    controller.add(
      const ChatEvent(
        type: ChatEventType.userMessage,
        rawType: 'opencode.user.message',
        data: {},
      ),
    );

    // Watch the opencode log file in real-time and surface retries immediately.
    // Log is at ~/.local/share/opencode/log/*.log — a new file per run.
    _logWatcher = OpenCodeLogWatcher(
      onRetry: (msg, {bool isFatal = false}) {
        _emitErrorMessage(controller, msg);
        if (isFatal) {
          // Kill immediately so the spinner stops — no need to wait for timeout.
          _startupTimer?.cancel();
          process.kill(ProcessSignal.sigkill);
        }
      },
    );
    unawaited(_logWatcher!.start());

    // Timeout: if no JSON event arrives within 120s, kill the process.
    _receivedFirstEvent = false;
    _startupTimer = Timer(const Duration(seconds: 120), () {
      if (!_receivedFirstEvent && !controller.isClosed) {
        debugPrint('[OpenCode] Startup timeout — no events in 120s');
        _emitErrorMessage(
          controller,
          'OpenCode не отвечает 120 секунд. Попробуйте позже.',
        );
        controller.add(
          const ChatEvent(
            type: ChatEventType.result,
            rawType: 'opencode.timeout',
            data: {},
          ),
        );
        process.kill(ProcessSignal.sigterm);
      }
    });
  }

  bool _receivedFirstEvent = false;
  Timer? _startupTimer;
  OpenCodeLogWatcher? _logWatcher;

  @override
  List<ChatEvent> parseLine(String line, String sessionName) {
    final json = jsonDecode(line) as Map<String, dynamic>;

    // Cancel startup timeout on first received event
    if (!_receivedFirstEvent) {
      _receivedFirstEvent = true;
      _startupTimer?.cancel();
    }

    // Capture sessionID from first event (for first message)
    final sid = json['sessionID'] as String?;
    if (sid != null && !getSessionId(sessionName).isSet) {
      storeSessionId(sessionName, sid);
      debugPrint('[OpenCode] Captured sessionID: $sid');
    }

    return _parseOpenCodeEvent(json);
  }

  @override
  void onProcessExited(
    int exitCode,
    String stderr,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    _startupTimer?.cancel();
    _logWatcher?.stop();
    _logWatcher = null;

    // Emit result event
    if (!controller.isClosed) {
      controller.add(
        const ChatEvent(
          type: ChatEventType.result,
          rawType: 'opencode.result',
          data: {},
        ),
      );
    }
  }

  // ── event mapping ──────────────────────────────────────────────────────

  (String, String) _extractTextAndId(Map<String, dynamic> json) {
    final part = json['part'] as Map<String, dynamic>?;
    final text = part?['text'] as String? ?? '';
    final partId = part?['id'] as String? ?? '';
    return (text, partId);
  }

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
        final (text, partId) = _extractTextAndId(json);
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
        final (text, partId) = _extractTextAndId(json);
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
        final message =
            errorData?['message'] as String? ??
            errorObj?['name'] as String? ??
            'Unknown error';
        // Emit as assistant message so it's visible in chat
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
    return part != null ? Map<String, dynamic>.from(part) : <String, dynamic>{};
  }

  // ── helpers ────────────────────────────────────────────────────────────

  /// Returns true if [line] looks like an error/status message from opencode
  /// that should be surfaced in chat (not silently swallowed).
  static bool looksLikeError(String line) {
    if (line.length < 4) return false;
    // Strip ANSI escape sequences before checking
    final clean =
        line.replaceAll(RegExp(r'\x1B\[[0-9;]*[mGKHF]'), '').toLowerCase();
    return clean.contains('exceeded') ||
        clean.contains('rate limit') ||
        clean.contains('retrying') ||
        clean.contains('subscribe') ||
        clean.contains('quota') ||
        clean.contains('unauthorized') ||
        clean.contains('forbidden') ||
        clean.contains('invalid api key') ||
        clean.contains('authentication') ||
        (clean.contains('error') && clean.length < 200);
  }

  /// Emits [message] as an assistant error message into [controller].
  static void _emitErrorMessage(
    StreamController<ChatEvent> controller,
    String message,
  ) {
    if (controller.isClosed) return;
    // Strip ANSI escapes and dots-only lines before showing
    final clean =
        message
            .replaceAll(RegExp(r'\x1B\[[0-9;]*[mGKHF]'), '')
            .replaceAll(RegExp(r'^[.\s]+'), '')
            .trim();
    if (clean.isEmpty) return;
    controller.add(
      ChatEvent(
        type: ChatEventType.assistantMessage,
        rawType: 'opencode.stderr.error',
        data: {'content': '⚠️ $clean', 'messageId': ''},
      ),
    );
  }

  @override
  void onStderrChunk(
    String chunk,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    // Emit each line that looks like an error so the spinner stops
    for (final line in chunk.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (looksLikeError(trimmed)) {
        _emitErrorMessage(controller, trimmed);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OpenCode Log Watcher
//
// Tails ~/.local/share/opencode/log/ in real-time and surfaces 429 / retry
// errors immediately so the user sees them instead of an infinite spinner.
// ─────────────────────────────────────────────────────────────────────────────

@visibleForTesting
class OpenCodeLogWatcher {
  OpenCodeLogWatcher({
    required this.onRetry,
    @visibleForTesting Directory? logDir,
  }) : _logDirOverride = logDir;

  final void Function(String message, {bool isFatal}) onRetry;

  /// Overrides the auto-discovered opencode log directory (tests only).
  final Directory? _logDirOverride;

  bool _stopped = false;
  final _emittedMessages = <String>{};

  static Directory? get _logDir {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;
    final xdgDataHome =
        Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    final dir = Directory('$xdgDataHome/opencode/log');
    return dir.existsSync() ? dir : null;
  }

  Future<void> start() async {
    final dir = _logDirOverride ?? _logDir;
    if (dir == null) return;

    // Find the log file created most recently (within last 10 seconds)
    final logFile = await _findRecentLogFile(dir);
    if (logFile == null || _stopped) return;

    debugPrint('[OpenCodeLog] Watching: ${logFile.path}');
    // Start from beginning — the 429 error may already be in the file
    // by the time we find it, and we don't want to miss it.
    var offset = 0;

    while (!_stopped) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_stopped) break;
      offset = await _readNewLogContent(logFile, offset);
    }
  }

  /// Polls [dir] for a recently-created `.log` file (up to 10 attempts).
  Future<File?> _findRecentLogFile(Directory dir) async {
    final now = DateTime.now();
    for (int attempt = 0; attempt < 10 && !_stopped; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.log'))
              .toList()
            ..sort(
              (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
            );
      if (files.isNotEmpty) {
        final newest = files.first;
        if (now.difference(newest.statSync().modified).abs() <
            const Duration(seconds: 30)) {
          return newest;
        }
      }
    }
    return null;
  }

  /// Reads bytes appended to [logFile] since [offset] and scans them for
  /// error patterns. Returns the new offset (unchanged on read failure).
  Future<int> _readNewLogContent(File logFile, int offset) async {
    var newOffset = offset;
    try {
      final length = logFile.lengthSync();
      if (length <= offset) return offset;
      final raf = logFile.openSync();
      raf.setPositionSync(offset);
      final bytes = raf.readSync(length - offset);
      raf.closeSync();
      newOffset = length;

      final newContent = utf8.decode(bytes, allowMalformed: true);
      // 429 log lines can be 37KB+ (full request body included).
      // Don't split by '\n' — scan the raw chunk directly for error patterns.
      parseChunk(newContent);
    } catch (e) {
      debugPrint('[OpenCodeLog] read error: $e');
    }
    return newOffset;
  }

  @visibleForTesting
  void parseChunk(String content) {
    // Search raw content directly — log lines can be 37KB+ and may arrive
    // across multiple polls, so don't rely on complete line boundaries.
    final statusMatch = RegExp(r'"statusCode":(\d+)').firstMatch(content);
    final statusCode =
        statusMatch != null ? int.tryParse(statusMatch.group(1)!) : null;

    final msgMatch = RegExp(r'"message":"([^"]+)"').firstMatch(content);
    final msg = msgMatch?.group(1);

    if (statusCode == null && msg == null) return;

    String display;
    if (statusCode == 429) {
      display = '⏳ Rate limit (429): ${msg ?? 'Please try again later'}';
    } else if (content.contains('ERROR') && msg != null) {
      display = '⚠️ OpenCode: $msg';
    } else {
      return;
    }

    if (_emittedMessages.contains(display)) return;
    _emittedMessages.add(display);

    debugPrint('[OpenCodeLog] Emitting: $display');
    onRetry(display, isFatal: statusCode == 429);
  }

  void stop() {
    _stopped = true;
  }
}

extension on String? {
  bool get isSet => this != null && this!.isNotEmpty;
}
