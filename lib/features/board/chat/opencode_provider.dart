import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// [ChatProvider] implementation that wraps OpenCode via its HTTP API.
///
/// Starts `opencode serve` in the background and communicates via
/// REST (POST /session, POST /api/session/{id}/prompt) and
/// SSE (GET /global/event) for real-time streaming.
class OpencodeProvider extends ChatProvider {
  OpencodeProvider();

  static const _defaultPort = 4343;

  Process? _serveProcess;
  HttpClient? _httpClient;
  StreamSubscription<String>? _sseSubscription;
  final _sseController = StreamController<GlobalEvent>();

  /// sessionName → sessionID (openCode's `ses_xxx` ID)
  final Map<String, String> _sessionIds = {};
  final Map<String, bool> _runningSessions = {};

  /// The SSE stream. Lazily connects to opencode serve.
  /// SSE connection state.
  bool _sseConnected = false;

  int get _port {
    final envPort = Platform.environment['OPENCODE_PORT'];
    if (envPort != null) {
      return int.tryParse(envPort) ?? _defaultPort;
    }
    return _defaultPort;
  }

  String get _baseUrl => 'http://127.0.0.1:$_port';

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
  bool isRunning(String sessionName) => _runningSessions[sessionName] == true;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
  }) {
    final controller = StreamController<ChatEvent>();

    _runSession(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      attachments: attachments,
      runtimeContext: runtimeContext,
      controller: controller,
    );

    return controller.stream;
  }

  Future<void> _runSession({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required StreamController<ChatEvent> controller,
  }) async {
    await stop(config.sessionName);
    _runningSessions[config.sessionName] = true;

    try {
      await _ensureServeRunning();
      await _ensureSseConnected(config.workingDir);

      // Create or reuse session
      String sessionID;
      if (isFirstMessage) {
        sessionID = await _createSession(
          workingDir: config.workingDir,
          modelId: config.model,
        );
        _sessionIds[config.sessionName] = sessionID;
        debugPrint('[OpenCode] Created session: $sessionID');
      } else {
        sessionID = _sessionIds[config.sessionName]!;
      }

      final effectiveMessage =
          isFirstMessage
              ? await CliGuidanceService.instance.prependGuidance(
                message,
                runtimeContext: runtimeContext,
              )
              : message;

      // Build prompt with attachments
      final promptFiles = <Map<String, dynamic>>[];
      for (final path in attachments) {
        if (_looksLikeImage(path)) {
          final mime = _mimeForPath(path);
          promptFiles.add({
            'uri': 'file://$path',
            'mime': mime,
            'name': path.split('/').last,
          });
        }
      }

      // Emit user message event
      controller.add(
        const ChatEvent(
          type: ChatEventType.userMessage,
          rawType: 'opencode.user.message',
          data: {},
        ),
      );

      // Subscribe to SSE events for this session before sending prompt
      final sseSub = _sseController.stream.listen(
        (event) {
          if (event.sessionID != sessionID) return;
          final chatEvents = _mapGlobalEvent(event);
          for (final ce in chatEvents) {
            controller.add(ce);
          }
        },
        onError: (Object error) {
          debugPrint('[OpenCode] SSE error: $error');
        },
      );

      // Send prompt
      await _sendPrompt(
        sessionID: sessionID,
        text: effectiveMessage,
        workingDir: config.workingDir,
        files: promptFiles,
      );

      // Poll/wait for completion with timeout
      await _waitForSessionIdle(sessionID, config.workingDir);

      // Emit result
      controller.add(
        const ChatEvent(
          type: ChatEventType.result,
          rawType: 'opencode.result',
          data: {},
        ),
      );

      await sseSub.cancel();
    } catch (e, st) {
      debugPrint('[OpenCode] Error: $e\n$st');
      controller.addError(e);
    } finally {
      _runningSessions.remove(config.sessionName);
      await controller.close();
    }
  }

  // ── serve process ──────────────────────────────────────────────────────

  Future<void> _ensureServeRunning() async {
    if (_serveProcess != null) return;

    final extraEnv =
        await GlobalEnvGroupsService.instance.resolveSelectedGroups(const []);
    final baseEnv = {...Platform.environment, ...extraEnv};
    final enrichedPath = PlatformShell.instance.enrichedPath(
      baseEnv['PATH'] ?? '',
    );

    debugPrint('[OpenCode] Starting `opencode serve --port $_port`');
    _serveProcess = await Process.start(
      'opencode',
      ['serve', '--port', '$_port'],
      environment: {...baseEnv, 'PATH': enrichedPath},
    );

    _serveProcess!.stdout
        .transform(utf8.decoder)
        .listen((chunk) => debugPrint('[OpenCode serve] stdout: $chunk'));
    _serveProcess!.stderr
        .transform(utf8.decoder)
        .listen((chunk) => debugPrint('[OpenCode serve] stderr: $chunk'));

    _serveProcess!.exitCode.then((code) {
      debugPrint('[OpenCode serve] exited: $code');
      _serveProcess = null;
    });

    // Wait for server to be ready
    await _waitForServer(_port);
  }

  Future<void> _waitForServer(int port) async {
    final client = _ensureHttpClient();
    for (var i = 0; i < 30; i++) {
      try {
        final request = await client.getUrl(Uri.parse('$_baseUrl/'));
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        await response.drain<void>();
        debugPrint('[OpenCode] Server ready on port $port');
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw Exception('OpenCode server did not start on port $port');
  }

  // ── SSE event stream ───────────────────────────────────────────────────

  Future<void> _ensureSseConnected(String workingDir) async {
    if (_sseConnected) return;

    final client = _ensureHttpClient();
    final uri = Uri.parse('$_baseUrl/global/event').replace(
      queryParameters: {
        if (workingDir.isNotEmpty) 'directory': workingDir,
      },
    );

    final request = await client.getUrl(uri);
    request.headers.set('Accept', 'text/event-stream');
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('SSE connection failed: ${response.statusCode}');
    }

    _sseConnected = true;
    _sseSubscription?.cancel();
    _sseSubscription = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6);
              try {
                final json = jsonDecode(jsonStr) as Map<String, dynamic>;
                final event = GlobalEvent.fromJson(json);
                _sseController.add(event);
              } catch (e) {
                // Skip unparseable events
              }
            }
          },
          onError: (Object error) {
            debugPrint('[OpenCode] SSE stream error: $error');
            _sseConnected = false;
          },
          onDone: () {
            debugPrint('[OpenCode] SSE stream closed');
            _sseConnected = false;
          },
          cancelOnError: false,
        );
  }

  // ── HTTP helpers ───────────────────────────────────────────────────────

  HttpClient _ensureHttpClient() {
    _httpClient?.close(force: true);
    _httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    return _httpClient!;
  }

  Future<String> _createSession({
    required String workingDir,
    required String modelId,
  }) async {
    final client = _ensureHttpClient();
    final (providerID, modelID) = _parseModel(modelId);

    final body = jsonEncode({
      if (providerID != null) ...{
        'model': {'providerID': providerID, 'id': modelID},
      },
    });

    final uri = Uri.parse('$_baseUrl/session').replace(
      queryParameters: {
        if (workingDir.isNotEmpty) 'directory': workingDir,
      },
    );

    final request = await client.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Content-Length', '${body.length}');
    request.write(body);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to create session: $responseBody');
    }

    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final sessionID = data['id'] as String?;
    if (sessionID == null) {
      throw Exception('No session ID in response: $responseBody');
    }
    return sessionID;
  }

  Future<void> _sendPrompt({
    required String sessionID,
    required String text,
    required String workingDir,
    List<Map<String, dynamic>> files = const [],
  }) async {
    final client = _ensureHttpClient();

    final prompt = <String, dynamic>{
      'text': text,
    };

    if (files.isNotEmpty) {
      prompt['files'] = files.map((f) {
        return <String, dynamic>{
          'uri': f['uri'],
          'mime': f['mime'],
          'name': f['name'],
        };
      }).toList();
    }

    final body = jsonEncode({
      'prompt': prompt,
      'delivery': 'immediate',
    });

    final uri = Uri.parse('$_baseUrl/api/session/$sessionID/prompt').replace(
      queryParameters: {
        if (workingDir.isNotEmpty) 'directory': workingDir,
      },
    );

    final request = await client.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Content-Length', '${body.length}');
    request.write(body);

    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errBody = await response.transform(utf8.decoder).join();
      throw Exception('Failed to send prompt: $errBody');
    }
    await response.drain<void>();
  }

  Future<void> _abortSession(String sessionID, String workingDir) async {
    if (sessionID.isEmpty) return;
    final client = _ensureHttpClient();
    final uri = Uri.parse('$_baseUrl/session/$sessionID/abort').replace(
      queryParameters: {
        if (workingDir.isNotEmpty) 'directory': workingDir,
      },
    );
    try {
      final request = await client.postUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>();
    } catch (_) {}
  }

  Future<void> _waitForSessionIdle(
    String sessionID,
    String workingDir,
  ) async {
    final client = _ensureHttpClient();
    final uri =
        Uri.parse('$_baseUrl/api/session/$sessionID/wait').replace(
      queryParameters: {
        if (workingDir.isNotEmpty) 'directory': workingDir,
      },
    );
    try {
      final request = await client.postUrl(uri);
      final response = await request.close().timeout(
        const Duration(minutes: 20),
      );
      await response.drain<void>();
    } catch (_) {}
  }

  // ── event mapping ──────────────────────────────────────────────────────

  List<ChatEvent> _mapGlobalEvent(GlobalEvent event) {
    switch (event.type) {
      case 'session.next.text.started':
        return [
          ChatEvent(
            type: ChatEventType.assistantMessageStart,
            rawType: event.type,
            data: {'messageId': event.textID ?? event.id},
            id: event.textID ?? event.id,
          ),
        ];

      case 'session.next.text.delta':
        return [
          ChatEvent(
            type: ChatEventType.assistantDelta,
            rawType: event.type,
            data: {'deltaContent': event.delta},
          ),
        ];

      case 'session.next.text.ended':
        return [
          ChatEvent(
            type: ChatEventType.assistantMessage,
            rawType: event.type,
            data: {
              'content': event.text ?? '',
              'messageId': event.id,
            },
            id: event.id,
          ),
        ];

      case 'session.next.tool.called':
        return [
          ChatEvent(
            type: ChatEventType.toolStart,
            rawType: event.type,
            data: {
              'toolCallId': event.callID,
              'toolName': event.tool,
              'arguments': event.input ?? const {},
            },
          ),
        ];

      case 'session.next.tool.success':
        final contentText = _extractToolContent(event.content);
        return [
          ChatEvent(
            type: ChatEventType.toolComplete,
            rawType: event.type,
            data: {
              'toolCallId': event.callID,
              'success': true,
              'result': {'content': contentText},
            },
          ),
        ];

      case 'session.next.tool.failed':
        return [
          ChatEvent(
            type: ChatEventType.toolComplete,
            rawType: event.type,
            data: {
              'toolCallId': event.callID,
              'success': false,
              'result': {
                'content': event.errorMessage ?? 'Tool execution failed',
              },
            },
          ),
        ];

      case 'session.next.step.started':
        return [
          ChatEvent(
            type: ChatEventType.assistantTurnStart,
            rawType: event.type,
            data: {'agent': event.agent},
          ),
        ];

      case 'session.next.step.ended':
        return [
          ChatEvent(
            type: ChatEventType.assistantTurnEnd,
            rawType: event.type,
            data: {
              'cost': event.cost,
              'tokens': event.tokens,
              'finish': event.finish,
            },
          ),
        ];

      case 'session.next.step.failed':
        return [
          ChatEvent(
            type: ChatEventType.assistantTurnEnd,
            rawType: event.type,
            data: {'error': event.errorMessage ?? 'Step failed'},
          ),
        ];

      case 'session.next.shell.started':
        return [
          ChatEvent(
            type: ChatEventType.toolStart,
            rawType: event.type,
            data: {
              'toolCallId': event.callID,
              'toolName': 'bash',
              'arguments': {'command': event.command},
            },
          ),
        ];

      case 'session.next.shell.ended':
        return [
          ChatEvent(
            type: ChatEventType.toolComplete,
            rawType: event.type,
            data: {
              'toolCallId': event.callID,
              'success': true,
              'result': {'content': event.output ?? ''},
            },
          ),
        ];

      case 'session.status':
        return [
          ChatEvent(
            type: ChatEventType.sessionStatus,
            rawType: event.type,
            data: {'status': event.status},
          ),
        ];

      case 'session.next.tool.progress':
      case 'session.next.reasoning.started':
      case 'session.next.reasoning.delta':
      case 'session.next.reasoning.ended':
      case 'session.next.prompted':
      case 'session.next.synthetic':
      case 'session.next.tool.input.started':
      case 'session.next.tool.input.delta':
      case 'session.next.tool.input.ended':
      case 'session.next.compaction.started':
      case 'session.next.compaction.delta':
      case 'session.next.compaction.ended':
      case 'session.next.agent.switched':
      case 'session.next.model.switched':
      case 'session.next.retried':
        // Events we silently skip
        return const [];

      default:
        return const [];
    }
  }

  String _extractToolContent(List<Map<String, dynamic>>? content) {
    if (content == null) return '';
    return content
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String? ?? '')
        .join('\n');
  }

  // ── helpers ────────────────────────────────────────────────────────────

  /// Split "providerID/modelID" into a tuple.
  (String? providerID, String modelID) _parseModel(String modelId) {
    final slashIdx = modelId.indexOf('/');
    if (slashIdx > 0) {
      return (
        modelId.substring(0, slashIdx),
        modelId.substring(slashIdx + 1),
      );
    }
    return (null, modelId);
  }

  bool _looksLikeImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'application/octet-stream';
  }

  @override
  Future<void> stop(String sessionName) async {
    _runningSessions.remove(sessionName);
    final sessionID = _sessionIds[sessionName];
    if (sessionID != null) {
      await _abortSession(sessionID, '');
    }
  }

  @override
  void dispose() {
    _runningSessions.clear();
    _sseSubscription?.cancel();
    _sseController.close();
    _httpClient?.close(force: true);
    _serveProcess?.kill(ProcessSignal.sigterm);
    _serveProcess = null;
    _sseConnected = false;
  }
}

// ── SSE GlobalEvent model parsed from opencode SSE ─────────────────────

class GlobalEvent {
  final String type;
  final String id;
  final String sessionID;

  // text events
  final String? textID; // reasoningID or text start ID
  final String? delta;
  final String? text;

  // tool events
  final String? callID;
  final String? tool;
  final Map<String, dynamic>? input;

  // shell events
  final String? command;
  final String? output;

  // tool result
  final List<Map<String, dynamic>>? content;

  // step events
  final String? agent;
  final double? cost;
  final Map<String, dynamic>? tokens;
  final String? finish;
  final String? errorMessage;

  // session status
  final String? status;

  GlobalEvent({
    required this.type,
    required this.id,
    required this.sessionID,
    this.textID,
    this.delta,
    this.text,
    this.callID,
    this.tool,
    this.input,
    this.command,
    this.output,
    this.content,
    this.agent,
    this.cost,
    this.tokens,
    this.finish,
    this.errorMessage,
    this.status,
  });

  factory GlobalEvent.fromJson(Map<String, dynamic> json) {
    // The SSE envelope: { directory, payload: { type, id, properties: {...} } }
    // or the raw event: { type, id, properties: {...} }
    Map<String, dynamic> payload;
    if (json.containsKey('payload')) {
      payload = Map<String, dynamic>.from(json['payload'] as Map);
    } else {
      payload = json;
    }

    final type = payload['type'] as String? ?? '';
    final id = payload['id'] as String? ?? '';
    final props =
        payload['properties'] is Map
            ? Map<String, dynamic>.from(payload['properties'] as Map)
            : <String, dynamic>{};

    // For tool.success/tool.failed - extract error
    String? errorMsg;
    final error = props['error'];
    if (error is Map) {
      errorMsg = error['message'] as String?;
    }

    // Extract content array
    List<Map<String, dynamic>>? contentList;
    final rawContent = props['content'];
    if (rawContent is List) {
      contentList = rawContent
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    return GlobalEvent(
      type: type,
      id: id,
      sessionID: props['sessionID'] as String? ?? '',
      textID: props['reasoningID'] as String? ?? props['id'] as String?,
      delta: props['delta'] as String?,
      text: props['text'] as String?,
      callID: props['callID'] as String?,
      tool: props['tool'] as String?,
      input:
          props['input'] is Map
              ? Map<String, dynamic>.from(props['input'] as Map)
              : null,
      command: props['command'] as String?,
      output: props['output'] as String?,
      content: contentList,
      agent: props['agent'] as String?,
      cost: (props['cost'] as num?)?.toDouble(),
      tokens:
          props['tokens'] is Map
              ? Map<String, dynamic>.from(props['tokens'] as Map)
              : null,
      finish: props['finish'] as String?,
      errorMessage: errorMsg,
      status: props['status'] as String?,
    );
  }
}
