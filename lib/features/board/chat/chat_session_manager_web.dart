import 'dart:async';

import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_core.dart';
import 'package:yoloit/features/board/chat/chat_session_manager_mixin.dart';
import 'package:yoloit/features/board/chat/cloud_llm_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Web-safe [ChatSessionManager] singleton.
///
/// Only cloud providers are supported in the browser. All other provider IDs
/// resolve to a stub that emits an error event.
class ChatSessionManager with ChatSessionManagerMixin {
  ChatSessionManager._({
    ChatProvider Function(String providerId)? providerFactory,
  }) : _providerFactory = providerFactory;

  static final ChatSessionManager instance = ChatSessionManager._(
    providerFactory: _createProvider,
  );

  /// For testing: create an isolated instance.
  factory ChatSessionManager.testInstance({
    ChatProvider Function(String providerId)? providerFactory,
  }) => ChatSessionManager._(providerFactory: providerFactory);

  final ChatProvider Function(String providerId)? _providerFactory;

  @override
  ChatProvider Function(String providerId)? get providerFactory =>
      _providerFactory ?? _createProvider;

  @override
  final Map<String, ChatSession> sessions = {};

  @override
  ChatSession getOrCreate(String panelId, ChatSessionConfig config) =>
      super.getOrCreate(panelId, config);

  static ChatProvider _createProvider(String providerId) {
    if (providerId.startsWith('cloud:')) {
      final configId = providerId.substring(6);
      return CloudLlmProvider.deferred(
        configId: configId,
        toolExecutor: YoloitWebToolExecutor(),
      );
    }
    return _UnsupportedProvider(providerId: providerId);
  }
}

class _UnsupportedProvider extends ChatProvider {
  _UnsupportedProvider({required this.providerId});

  @override
  final String providerId;

  @override
  String get displayName => 'Unsupported';

  @override
  List<ChatModelInfo> get availableModels => const [];

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.base64;

  @override
  bool isRunning(String sessionName) => false;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) {
    final controller = StreamController<ChatEvent>();
    scheduleMicrotask(() {
      controller.addError(
        StateError(
          'Provider \$providerId is not supported in the browser. '
          'Use a cloud provider instead.',
        ),
      );
    });
    return controller.stream;
  }

  @override
  Future<void> stop(String sessionName) async {}

  @override
  void dispose() {}
}
