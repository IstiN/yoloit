import 'dart:async';

import 'package:yoloit/features/board/model/chat_models.dart';

/// How images should be passed to the provider.
enum ChatImageMode {
  /// Send file path reference (e.g. Copilot CLI).
  filePath,

  /// Send base64-encoded image data (e.g. local LLMs).
  base64,
}

/// Runtime context for the current chat send operation.
class ChatRuntimeContext {
  const ChatRuntimeContext({
    this.boardId,
    this.boardName,
    this.panelId,
    this.panelTitle,
  });

  final String? boardId;
  final String? boardName;
  final String? panelId;
  final String? panelTitle;
}

/// Abstract interface for chat backends.
///
/// Implementations wrap specific CLI tools or APIs. The board chat panel
/// only depends on this interface, making it easy to swap providers.
abstract class ChatProvider {
  /// Unique provider identifier (e.g. 'copilot', 'cursor', 'local').
  String get providerId;

  /// Human-readable display name.
  String get displayName;

  /// Available models for this provider.
  List<ChatModelInfo> get availableModels;

  /// Whether this provider supports image attachments.
  bool get supportsImages;

  /// How images are transmitted.
  ChatImageMode get imageMode;

  /// Send a message and receive a stream of [ChatEvent]s.
  ///
  /// [config] contains session name, working dir, model, etc.
  /// [isFirstMessage] indicates whether this is a new session (vs resume).
  /// [attachments] optional file paths to attach (images, documents).
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
  });

  /// Stop any running process for [sessionName].
  Future<void> stop(String sessionName);

  /// Whether a session is currently running.
  bool isRunning(String sessionName);

  /// Dispose all resources.
  void dispose();
}
