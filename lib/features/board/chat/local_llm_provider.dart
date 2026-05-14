import 'dart:async';

import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

class LocalLlmProvider extends ChatProvider {
  LocalLlmProvider({flm.NativeLmEngine? engine})
    : _engine = engine ?? flm.NativeLmEngine();

  final flm.NativeLmEngine _engine;
  final Map<String, bool> _running = {};
  final Map<String, bool> _cancelRequested = {};
  final Map<String, List<({String user, String assistant})>> _history = {};

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
    );
    return controller.stream;
  }

  Future<void> _run({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required StreamController<ChatEvent> controller,
  }) async {
    final session = config.sessionName;
    _running[session] = true;
    _cancelRequested[session] = false;

    try {
      await LocalAiModelsService.instance.initialize();
      final modelId = LocalAiModelsService.instance.selectedChatModelId;
      final installed = LocalAiModelsService.instance.installedModelById(
        modelId,
      );
      if (installed == null) {
        throw StateError(
          'Model "$modelId" is not installed. Download it in Settings → AI Models.',
        );
      }

      if (isFirstMessage) {
        _history[session] = [];
      }
      final sessionHistory = _history.putIfAbsent(
        session,
        () => <({String user, String assistant})>[],
      );

      final prompt = _buildPrompt(sessionHistory, message);
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
      final full = await _engine.completeStreaming(
        flm.LmCompletionRequest(
          modelPath: installed.directory.path,
          manifest: installed.manifest,
          prompt: prompt,
          maxTokens: 1024,
          temperature: 0.2,
        ),
        (chunk) {
          if (_cancelRequested[session] == true) return;
          final delta = _extractDelta(previous: emitted, incoming: chunk);
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

      if (_cancelRequested[session] == true) {
        return;
      }

      final content = full.trim().isNotEmpty ? full.trim() : emitted.trim();
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
          data: const {
            'usage': {
              'outputTokens': 0,
              'premiumRequests': 0,
              'totalApiDurationMs': 0,
              'sessionDurationMs': 0,
              'codeChanges': {'linesAdded': 0, 'linesRemoved': 0},
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

  String _buildPrompt(
    List<({String user, String assistant})> turns,
    String userMessage,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
      'You are a concise, practical assistant. Answer directly and avoid unnecessary verbosity.',
    );
    for (final turn in turns) {
      buffer.writeln('\nUser: ${turn.user}');
      buffer.writeln('Assistant: ${turn.assistant}');
    }
    buffer.writeln('\nUser: $userMessage');
    buffer.write('Assistant:');
    return buffer.toString();
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
