import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/copilot_cli_provider.dart';
import 'package:yoloit/features/board/chat/cursor_agent_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/board/chat/opencode_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// State of a single chat session, independent of any UI widget.
///
/// Holds the [ChatProvider], messages, streaming state, and config.
/// The UI widget subscribes to [onChanged] for rendering updates;
/// the CLI handler can call [sendMessage] directly.
class ChatSession extends ChangeNotifier {
  ChatSession({
    required this.panelId,
    required ChatSessionConfig config,
    ChatProvider Function(String providerId)? providerFactory,
  }) : _config = config,
       _providerFactory = providerFactory {
    _provider = _createProviderFor(config.provider);
  }

  final String panelId;
  final ChatProvider Function(String providerId)? _providerFactory;
  late ChatProvider _provider;
  ChatSessionConfig _config;
  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;
  bool _isFirstMessage = true;
  String _streamingContent = '';
  String? _streamingMessageId;
  int _totalOutputTokens = 0;
  ChatTokenUsage? _lastUsage;
  StreamSubscription<ChatEvent>? _eventSub;
  String? _opencodeSessionId;

  // Mutable UI callbacks — nullified on detach, set on sendMessage.
  // This allows the session to keep processing events from the provider
  // even when the UI widget is detached (disposed).
  void Function(ChatEvent event)? _uiEventCallback;
  void Function(Object error)? _uiErrorCallback;
  void Function()? _uiDoneCallback;

  // ── Public getters ──────────────────────────────────────────────────────

  ChatProvider get provider => _provider;
  ChatSessionConfig get config => _config;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isProcessing => _isProcessing;
  bool get isFirstMessage => _isFirstMessage;
  String get streamingContent => _streamingContent;
  String? get streamingMessageId => _streamingMessageId;
  int get totalOutputTokens => _totalOutputTokens;
  ChatTokenUsage? get lastUsage => _lastUsage;
  String? get opencodeSessionId => _opencodeSessionId;

  // ── Configuration ───────────────────────────────────────────────────────

  void updateConfig(ChatSessionConfig newConfig) {
    if (newConfig == _config) return;
    if (newConfig.provider != _config.provider) {
      _provider.dispose();
      _provider = _createProviderFor(newConfig.provider);
      if (newConfig.provider == 'opencode' && _opencodeSessionId != null) {
        _provider.setSessionId(newConfig.sessionName, _opencodeSessionId!);
      }
    }
    _config = newConfig;
    notifyListeners();
  }

  // ── Message management ──────────────────────────────────────────────────

  /// Restore messages from persisted state (called on session creation from
  /// board panel state).
  void restoreMessages(List<Map<String, dynamic>> savedMessages) {
    for (final m in savedMessages) {
      try {
        final msg = ChatMessage.fromJson(Map<String, dynamic>.from(m));
        _messages.add(msg);
        if (msg.tokenUsage != null) {
          _totalOutputTokens += msg.tokenUsage!.outputTokens;
        }
      } catch (_) {}
    }
    if (_messages.isNotEmpty) {
      _isFirstMessage = false;
    }
  }

  void restoreLastUsage(Map<String, dynamic>? savedUsage) {
    if (savedUsage != null) {
      _lastUsage = ChatTokenUsage.fromJson(savedUsage);
    }
  }

  void restoreOpencodeSessionId(String? sessionId) {
    if (sessionId != null && sessionId.isNotEmpty) {
      _opencodeSessionId = sessionId;
      if (_config.provider == 'opencode') {
        _provider.setSessionId(_config.sessionName, sessionId);
      }
    }
  }

  void clearMessages() {
    _messages.clear();
    _totalOutputTokens = 0;
    _lastUsage = null;
    _isFirstMessage = true;
    notifyListeners();
  }

  // ── Send message ────────────────────────────────────────────────────────

  /// Sends a message through the provider and processes events.
  ///
  /// [onEvent] is called for each event (UI uses this for rendering).
  /// [onError] is called on stream error.
  /// [onDone] is called when stream completes.
  ///
  /// Returns false if already processing or text is empty.
  /// Attach UI callbacks for event forwarding.
  ///
  /// Called by the UI widget when it mounts or re-attaches to this session.
  /// While attached, events are forwarded to the widget for UI-specific
  /// rendering (sub-agent panels, tool call expansion, sounds, etc.).
  void attachUI({
    void Function(ChatEvent event)? onEvent,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    _uiEventCallback = onEvent;
    _uiErrorCallback = onError;
    _uiDoneCallback = onDone;
  }

  bool sendMessage({
    required String text,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    void Function(ChatEvent event)? onEvent,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    if (text.trim().isEmpty) return false;
    if (_isProcessing) return false;

    _isProcessing = true;

    // Store UI callbacks if provided
    if (onEvent != null) _uiEventCallback = onEvent;
    if (onError != null) _uiErrorCallback = onError;
    if (onDone != null) _uiDoneCallback = onDone;

    // If currently streaming, finalize
    if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
      _finalizeStreamingMessage();
    }

    // Parse attachments from text
    final filePathRe = RegExp(r'^/.+');
    final imageExtRe = RegExp(
      r'\.(png|jpg|jpeg|gif|webp|bmp)$',
      caseSensitive: false,
    );
    final tokens = text.split(RegExp(r'\s+'));
    final allAttachments = <String>[
      ...attachments,
      ...tokens.where((t) => filePathRe.hasMatch(t)),
    ];
    final promptText =
        tokens.where((t) => !filePathRe.hasMatch(t)).join(' ').trim();

    // Add user message
    _messages.add(
      ChatMessage(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        role: ChatRole.user,
        content: promptText.isNotEmpty ? promptText : text,
        attachments: allAttachments,
        timestamp: DateTime.now(),
      ),
    );
    _streamingContent = '';
    _streamingMessageId = null;
    notifyListeners();

    // Start streaming
    final imageAttachments =
        allAttachments.where((t) => imageExtRe.hasMatch(t)).toList();

    final stream = _provider.sendMessage(
      message: promptText.isNotEmpty ? promptText : text,
      config: _config,
      isFirstMessage: _isFirstMessage,
      attachments: imageAttachments,
      runtimeContext: runtimeContext,
    );

    _isFirstMessage = false;

    _eventSub?.cancel();
    _eventSub = stream.listen(
      (event) {
        _handleCoreEvent(event);
        // Forward to UI if attached
        _uiEventCallback?.call(event);
      },
      onError: (Object error) {
        _isProcessing = false;
        _messages.add(
          ChatMessage(
            id: 'error-${DateTime.now().millisecondsSinceEpoch}',
            role: ChatRole.system,
            content: '❌ Error: $error',
            timestamp: DateTime.now(),
          ),
        );
        notifyListeners();
        _persistToHistory();
        _uiErrorCallback?.call(error);
      },
      onDone: () {
        // Persist opencode session ID
        if (_config.provider == 'opencode') {
          final sid = _provider.getSessionId(_config.sessionName);
          if (sid != null && sid != _opencodeSessionId) {
            _opencodeSessionId = sid;
          }
        }
        _isProcessing = false;
        if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
          _finalizeStreamingMessage();
        }
        notifyListeners();
        _persistToHistory();
        _uiDoneCallback?.call();
      },
    );

    return true;
  }

  /// Send a message and wait for all events to complete. Returns the final
  /// messages list. Useful for CLI where we need synchronous completion.
  Future<List<ChatMessage>> sendAndWait({
    required String text,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
  }) {
    final completer = Completer<List<ChatMessage>>();

    final ok = sendMessage(
      text: text,
      attachments: attachments,
      runtimeContext: runtimeContext,
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(List.unmodifiable(_messages));
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.complete(List.unmodifiable(_messages));
        }
      },
    );

    if (!ok) {
      return Future.value(List.unmodifiable(_messages));
    }

    return completer.future;
  }

  /// Stop any in-flight streaming.
  Future<void> stopStreaming() async {
    _eventSub?.cancel();
    _eventSub = null;
    if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
      _finalizeStreamingMessage();
    }
    _streamingContent = '';
    _streamingMessageId = null;
    _isProcessing = false;
    notifyListeners();
    await _provider.stop(_config.sessionName);
  }

  // ── Core event handling (non-UI) ────────────────────────────────────────

  void _handleCoreEvent(ChatEvent event) {
    // Capture opencode session ID early
    if (_config.provider == 'opencode' && _opencodeSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _opencodeSessionId = sid;
      }
    }

    switch (event.type) {
      case ChatEventType.assistantMessageStart:
        _streamingMessageId = event.messageId;
        _streamingContent = '';
        notifyListeners();

      case ChatEventType.assistantDelta:
        final delta = event.deltaContent;
        if (delta != null) {
          _streamingContent += delta;
          notifyListeners();
        }

      case ChatEventType.assistantMessage:
        final content = event.messageContent ?? _streamingContent;
        final toolReqs = event.toolRequests;

        // Remove streaming placeholder
        _messages.removeWhere(
          (m) => m.id == _streamingMessageId && m.isStreaming,
        );

        final toolCalls =
            toolReqs.map((tr) {
              final args = tr['arguments'];
              return ChatToolCall(
                toolCallId: tr['toolCallId'] as String? ?? '',
                toolName: tr['name'] as String? ?? '',
                arguments:
                    args is Map
                        ? Map<String, dynamic>.from(args)
                        : <String, dynamic>{},
              );
            }).toList();

        final outputTokens = event.outputTokens;
        ChatTokenUsage? usage;
        if (outputTokens != null) {
          usage = ChatTokenUsage(outputTokens: outputTokens);
          _totalOutputTokens += outputTokens;
        }

        _messages.add(
          ChatMessage(
            id:
                event.messageId ??
                'assistant-${DateTime.now().millisecondsSinceEpoch}',
            role: ChatRole.assistant,
            content: content,
            timestamp: event.timestamp ?? DateTime.now(),
            toolCalls: toolCalls,
            isStreaming: false,
            tokenUsage: usage,
          ),
        );
        _streamingMessageId = null;
        _streamingContent = '';
        notifyListeners();

      case ChatEventType.toolStart:
        {}

      case ChatEventType.toolComplete:
        _messages.add(
          ChatMessage(
            id:
                event.toolCallId ??
                'tool-${DateTime.now().millisecondsSinceEpoch}',
            role: ChatRole.tool,
            content: event.toolResultContent ?? '',
            toolName: event.toolName,
            toolCallId: event.toolCallId,
            timestamp: event.timestamp ?? DateTime.now(),
            metadata: {
              if (event.toolSuccess != null) 'success': event.toolSuccess,
            },
          ),
        );
        notifyListeners();

      case ChatEventType.result:
        final usage = event.usageData;
        if (usage != null) {
          final codeChanges = usage['codeChanges'] as Map<String, dynamic>?;
          final outputTokens = (usage['outputTokens'] as num?)?.toInt() ?? 0;
          if (outputTokens > 0) {
            _totalOutputTokens += outputTokens;
          }
          _lastUsage = ChatTokenUsage(
            outputTokens: outputTokens,
            premiumRequests: (usage['premiumRequests'] as num?)?.toInt() ?? 0,
            totalApiDurationMs:
                (usage['totalApiDurationMs'] as num?)?.toInt() ?? 0,
            sessionDurationMs:
                (usage['sessionDurationMs'] as num?)?.toInt() ?? 0,
            linesAdded: (codeChanges?['linesAdded'] as num?)?.toInt() ?? 0,
            linesRemoved: (codeChanges?['linesRemoved'] as num?)?.toInt() ?? 0,
          );
          notifyListeners();
        }

      default:
      // subagentStart, subagentComplete, etc. — forwarded to UI via onEvent.
    }
  }

  void _finalizeStreamingMessage() {
    if (_streamingContent.isEmpty) return;
    // Remove existing streaming placeholder
    _messages.removeWhere((m) => m.id == _streamingMessageId && m.isStreaming);
    _messages.add(
      ChatMessage(
        id:
            _streamingMessageId ??
            'assistant-${DateTime.now().millisecondsSinceEpoch}',
        role: ChatRole.assistant,
        content: _streamingContent,
        timestamp: DateTime.now(),
      ),
    );
    _streamingMessageId = null;
    _streamingContent = '';
  }

  static const _maxSavedMessages = 100;

  void _persistToHistory() {
    final trimmed =
        _messages.length > _maxSavedMessages
            ? _messages.sublist(_messages.length - _maxSavedMessages)
            : _messages;
    final messagesJson = trimmed.map((m) => m.toJson()).toList();
    unawaited(
      ChatSessionHistory.instance
          .upsert(
            ChatSessionEntry(
              id: panelId,
              sessionName: _config.sessionName,
              provider: _provider.providerId,
              model: _config.model,
              workingDir: _config.workingDir,
              envGroupIds: _config.envGroupIds,
              createdAt: DateTime.now(),
              lastMessageAt: _messages.isNotEmpty ? DateTime.now() : null,
              messageCount: _messages.length,
            ),
            messages: messagesJson,
          )
          .catchError((Object _) {}),
    );
  }

  /// Get serialized messages for board state persistence.
  List<Map<String, dynamic>> serializeMessages() {
    final trimmed =
        _messages.length > _maxSavedMessages
            ? _messages.sublist(_messages.length - _maxSavedMessages)
            : _messages;
    return trimmed.map((m) => m.toJson()).toList();
  }

  /// Get full state map for board panel persistence.
  Map<String, dynamic> serializeState() {
    return {
      'config': _config.toJson(),
      'messages': serializeMessages(),
      if (_lastUsage != null) 'lastUsage': _lastUsage!.toJson(),
      if (_opencodeSessionId != null) 'opencodeSessionId': _opencodeSessionId,
    };
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Detach from UI without killing processes or stopping event processing.
  ///
  /// The stream subscription continues — ChatSession keeps accumulating
  /// messages from in-flight processes. Only UI callbacks are removed.
  /// When the widget re-mounts, it reads accumulated messages from the session.
  void detach() {
    _uiEventCallback = null;
    _uiErrorCallback = null;
    _uiDoneCallback = null;
    // DO NOT cancel _eventSub — keep processing provider events.
    // DO NOT call _provider.detach() or dispose() — keep processes alive.
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _provider.dispose();
    super.dispose();
  }

  // ── Factory ─────────────────────────────────────────────────────────────

  ChatProvider _createProviderFor(String providerId) {
    final factory = _providerFactory;
    if (factory != null) {
      return factory(providerId);
    }
    return _createProvider(providerId);
  }

  static ChatProvider _createProvider(String providerId) {
    return switch (providerId) {
      'cursor' => CursorAgentProvider(),
      'local' => LocalLlmProvider(),
      'opencode' => OpencodeProvider(),
      _ => CopilotCliProvider(),
    };
  }
}

/// Singleton service that manages all active chat sessions.
///
/// Sessions survive widget lifecycle — the UI attaches/detaches as needed.
/// The CLI handler can create sessions and send messages directly.
class ChatSessionManager {
  ChatSessionManager._({
    ChatProvider Function(String providerId)? providerFactory,
  }) : _providerFactory = providerFactory;
  static final ChatSessionManager instance = ChatSessionManager._();

  /// For testing: create an isolated instance.
  factory ChatSessionManager.testInstance({
    ChatProvider Function(String providerId)? providerFactory,
  }) => ChatSessionManager._(providerFactory: providerFactory);

  final ChatProvider Function(String providerId)? _providerFactory;
  final Map<String, ChatSession> _sessions = {};

  /// Get an existing session or create a new one.
  ///
  /// If a session for [panelId] already exists, returns it (potentially
  /// updating config if [config] differs). If not, creates a new one.
  ChatSession getOrCreate(String panelId, ChatSessionConfig config) {
    final existing = _sessions[panelId];
    if (existing != null) {
      existing.updateConfig(config);
      return existing;
    }
    final session = ChatSession(
      panelId: panelId,
      config: config,
      providerFactory: _providerFactory,
    );
    _sessions[panelId] = session;
    return session;
  }

  /// Get a session by panel ID, or null if it doesn't exist.
  ChatSession? get(String panelId) => _sessions[panelId];

  /// Check if a session exists.
  bool has(String panelId) => _sessions.containsKey(panelId);

  /// Remove and dispose a session (kills processes).
  void remove(String panelId) {
    final session = _sessions.remove(panelId);
    session?.dispose();
  }

  /// Detach a session (UI going away, but keep session alive).
  void detach(String panelId) {
    _sessions[panelId]?.detach();
  }

  /// List all active session panel IDs.
  List<String> get activeSessionIds => _sessions.keys.toList();

  /// Dispose all sessions. Called on app shutdown.
  void disposeAll() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}
