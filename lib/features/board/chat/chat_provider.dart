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
///
/// ## Sub-agent event support
///
/// Providers that support sub-agent visualization (showing nested agent
/// activity as inline terminal output) should merge `subagent*` [ChatEvent]s
/// into the stream returned by [sendMessage]. The [ChatPanelWidget] only
/// reacts to [ChatEventType] values and does not care about the source.
///
/// Copilot implementation: [SubAgentEventWatcher] tails
/// `~/.copilot/session-state/<session>/events.jsonl` by matching the
/// spawned process PID to its `inuse.<pid>.lock` file.
///
/// OpenCode / Cursor: implement a similar watcher that reads the
/// provider's own event log and emits the same `subagent*` event types.
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

  /// Set the external session ID for resume (used by providers that need
  /// to track session IDs across widget rebuilds). No-op by default.
  void setSessionId(String sessionName, String sessionId) {}

  /// Get the external session ID for resume. Returns null if not set.
  String? getSessionId(String sessionName) => null;

  /// Dispose all resources.
  void dispose();

  /// Detach from running processes without killing them.
  ///
  /// Called when the chat widget is temporarily removed from the tree (e.g.
  /// the user switches to a different board). Unlike [dispose], this must NOT
  /// send SIGTERM — in-flight CLI sessions should keep running so the user can
  /// resume them when they switch back. The Dart [Process] references are
  /// dropped so they can be GC-ed, but the OS processes continue until they
  /// exit naturally.
  ///
  /// Override in providers that manage OS processes. The default is a no-op.
  void detach() {}
}
