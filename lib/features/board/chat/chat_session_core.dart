import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/cli/cli_text_argument_resolver.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';

/// State of a single chat session, independent of any UI widget.
///
/// Holds the [ChatProvider], messages, streaming state, and config.
/// The UI widget subscribes to [onChanged] for rendering updates;
/// the CLI handler can call [sendMessage] directly.
class ChatSession extends ChangeNotifier {
  ChatSession({
    required this.panelId,
    required ChatSessionConfig config,
    this._providerFactory,
  }) : _config = config {
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
  int? _assistantInsertIndex;
  int _totalOutputTokens = 0;
  ChatTokenUsage? _lastUsage;
  StreamSubscription<ChatEvent>? _eventSub;
  String? _opencodeSessionId;
  String? _copilotSessionId;
  String? _cursorSessionId;

  /// Streaming deltas are accumulated here and flushed into
  /// [_streamingContent] at most once per [_deltaFlushInterval]. Streaming
  /// providers emit several deltas per second (one per token); appending each
  /// directly to the growing string is O(n²) copying, and notifying listeners
  /// per token re-renders the whole markdown bubble hundreds of times per
  /// second — that was the dominant main-thread + GC cost while an agent
  /// streams. Flushing at ~10/s keeps the typewriter feel at a fraction of
  /// the cost. The buffer is flushed synchronously before any non-delta
  /// event, stream end/error, stop, and finalize, so no content is ever lost
  /// or reordered.
  static const _deltaFlushInterval = Duration(milliseconds: 100);
  final _deltaBuffer = StringBuffer();
  Timer? _deltaFlushTimer;
  ChatEvent? _lastDeltaEvent;

  String _getAdapterFor(String providerId) {
    final agentConfig = AgentConfigService.instance.configForAgent(providerId);
    return agentConfig?.streamAdapter ?? providerId;
  }

  /// Re-applies persisted provider session IDs to the provider for [adapter].
  void _applyStoredSessionIds(String adapter, String sessionName) {
    if (adapter == 'opencode' && _opencodeSessionId != null) {
      _provider.setSessionId(sessionName, _opencodeSessionId!);
    }
    if (adapter == 'copilot' && _copilotSessionId != null) {
      _provider.setSessionId(sessionName, _copilotSessionId!);
    }
    if (adapter == 'cursor' && _cursorSessionId != null) {
      _provider.setSessionId(sessionName, _cursorSessionId!);
    }
  }

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
  String? get copilotSessionId => _copilotSessionId;
  String? get cursorSessionId => _cursorSessionId;

  /// Last known scroll offset of the chat message list UI.
  /// Persisted across board switches so the user returns to the same position.
  double? savedScrollOffset;

  // ── Configuration ───────────────────────────────────────────────────────

  void updateConfig(ChatSessionConfig newConfig) {
    if (newConfig == _config) return;
    final previousSessionName = _config.sessionName;
    if (newConfig.provider != _config.provider) {
      _provider.dispose();
      _provider = _createProviderFor(newConfig.provider);
      _applyStoredSessionIds(
        _getAdapterFor(newConfig.provider),
        newConfig.sessionName,
      );
    } else if (newConfig.sessionName != previousSessionName) {
      _applyStoredSessionIds(
        _getAdapterFor(_config.provider),
        newConfig.sessionName,
      );
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
      if (_getAdapterFor(_config.provider) == 'opencode') {
        _provider.setSessionId(_config.sessionName, sessionId);
      }
    }
  }

  void restoreCopilotSessionId(String? sessionId) {
    if (sessionId != null && sessionId.isNotEmpty) {
      _copilotSessionId = sessionId;
      if (_getAdapterFor(_config.provider) == 'copilot') {
        _provider.setSessionId(_config.sessionName, sessionId);
      }
    }
  }

  void restoreCursorSessionId(String? sessionId) {
    if (sessionId != null && sessionId.isNotEmpty) {
      _cursorSessionId = sessionId;
      if (_getAdapterFor(_config.provider) == 'cursor') {
        _provider.setSessionId(_config.sessionName, sessionId);
      }
    }
  }

  /// Sync the widget's current messages/state into this session.
  ///
  /// Called by the widget before detaching so the session holds the latest
  /// state.  When the widget re-mounts it reads from [messages] / getters.
  void syncFromWidget({
    required List<ChatMessage> messages,
    bool isFirstMessage = true,
    bool isProcessing = false,
    String streamingContent = '',
    String? streamingMessageId,
    int totalOutputTokens = 0,
    ChatTokenUsage? lastUsage,
    String? opencodeSessionId,
    String? copilotSessionId,
    String? cursorSessionId,
  }) {
    _messages
      ..clear()
      ..addAll(messages);
    _isFirstMessage = isFirstMessage;
    _isProcessing = isProcessing;
    _streamingContent = streamingContent;
    _streamingMessageId = streamingMessageId;
    _totalOutputTokens = totalOutputTokens;
    _lastUsage = lastUsage;
    if (opencodeSessionId != null) {
      _opencodeSessionId = opencodeSessionId;
    }
    if (copilotSessionId != null) {
      _copilotSessionId = copilotSessionId;
    }
    if (cursorSessionId != null) {
      _cursorSessionId = cursorSessionId;
    }
  }

  /// Whether at least one assistant reply exists in this session.
  bool _hasAssistantReply() =>
      _messages.any((m) => m.role == ChatRole.assistant);

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

  static final _filePathRe = RegExp(r'^/.+');
  static final _imageExtRe = RegExp(
    r'\.(png|jpg|jpeg|gif|webp|bmp)$',
    caseSensitive: false,
  );

  Future<bool> sendMessage({
    required String text,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    void Function(ChatEvent event)? onEvent,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    if (text.trim().isEmpty) return false;
    if (_isProcessing) return false;

    _isProcessing = true;

    _prepareForSend(
      onEvent: onEvent,
      onError: onError,
      onDone: onDone,
    );

    // Parse attachments from text
    final tokens = text.split(RegExp(r'\s+'));
    final allAttachments = <String>[
      ...attachments,
      ...tokens.where((t) => _filePathRe.hasMatch(t)),
    ];
    var promptText =
        tokens.where((t) => !_filePathRe.hasMatch(t)).join(' ').trim();

    // Inline plain-text file contents so the model can see them.
    // (Images are forwarded via the provider's attachment path; other
    // non-image files are shown as chips in the UI.)
    // NOTE: keep this loop inline in sendMessage — it contains the first
    // real await of this method, and moving it into a helper would insert
    // an extra microtask suspension point before the user message is
    // appended, changing observable timing for synchronous senders.
    final keptAttachments = <String>[];
    final textFileExtras = <String>[];
    for (final path in allAttachments) {
      if (path.endsWith('.txt')) {
        final isClip = CliTextArgumentResolver.isClipTextFilePath(path);
        final inlined = await _readTextAttachmentForPrompt(path);
        if (inlined != null) {
          textFileExtras.add(inlined);
        }
        if (!isClip || inlined != null) {
          keptAttachments.add(path);
        }
        continue;
      }
      keptAttachments.add(path);
    }
    promptText = _appendTextFileExtras(promptText, textFileExtras);

    // Add user message
    _appendUserMessage(text, promptText, keptAttachments);

    // Start streaming
    _startStreaming(promptText, text, keptAttachments, runtimeContext);

    return true;
  }

  /// Stores UI callbacks (when provided) and finalizes any in-flight
  /// streaming message before a new send.
  void _prepareForSend({
    void Function(ChatEvent event)? onEvent,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    // Store UI callbacks if provided
    if (onEvent != null) _uiEventCallback = onEvent;
    if (onError != null) _uiErrorCallback = onError;
    if (onDone != null) _uiDoneCallback = onDone;

    // If currently streaming, finalize
    _flushDeltaBuffer();
    if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
      _finalizeStreamingMessage();
    }
  }

  /// Appends inlined text-file contents to the prompt.
  String _appendTextFileExtras(
    String promptText,
    List<String> textFileExtras,
  ) {
    if (textFileExtras.isEmpty) return promptText;
    return promptText.isEmpty
        ? textFileExtras.join('\n\n')
        : '$promptText\n\n${textFileExtras.join('\n\n')}';
  }

  /// Appends the user message and resets streaming bookkeeping.
  void _appendUserMessage(
    String originalText,
    String promptText,
    List<String> keptAttachments,
  ) {
    _messages.add(
      ChatMessage(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        role: ChatRole.user,
        content: promptText.isNotEmpty ? promptText : originalText,
        attachments: keptAttachments,
        timestamp: DateTime.now(),
      ),
    );
    _streamingContent = '';
    _streamingMessageId = null;
    _assistantInsertIndex = _messages.length;
    notifyListeners();
  }

  /// Starts the provider stream and wires up event/error/done handlers.
  void _startStreaming(
    String promptText,
    String originalText,
    List<String> keptAttachments,
    ChatRuntimeContext? runtimeContext,
  ) {
    final imageAttachments = _collectImageAttachments(
      keptAttachments,
      runtimeContext,
    );

    _applyStoredSessionIds(
      _getAdapterFor(_config.provider),
      _config.sessionName,
    );

    final stream = _provider.sendMessage(
      message: promptText.isNotEmpty ? promptText : originalText,
      config: _config,
      isFirstMessage: _isFirstMessage,
      attachments: imageAttachments,
      runtimeContext: runtimeContext,
    );

    final wasFirstMessage = _isFirstMessage;
    _isFirstMessage = false;

    _eventSub?.cancel();
    _eventSub = stream.listen(
      (event) {
        // Delta events are coalesced (see [_deltaFlushInterval]); everything
        // else flushes pending deltas first to preserve event ordering.
        if (event.type == ChatEventType.assistantDelta &&
            event.deltaContent != null) {
          _onAssistantDelta(event);
          return;
        }
        _flushDeltaBuffer();
        _handleCoreEvent(event);
        // Forward to UI if attached
        _uiEventCallback?.call(event);
      },
      onError: (Object error) {
        _flushDeltaBuffer();
        _handleStreamError(error, wasFirstMessage);
      },
      onDone: () {
        _flushDeltaBuffer();
        _handleStreamDone();
      },
    );
  }

  /// Filters [keptAttachments] down to images and injects the board snapshot
  /// as attachment for CLI agents (file path mode).
  List<String> _collectImageAttachments(
    List<String> keptAttachments,
    ChatRuntimeContext? runtimeContext,
  ) {
    final imageAttachments =
        keptAttachments.where((t) => _imageExtRe.hasMatch(t)).toList();

    // Inject board snapshot as attachment for CLI agents (file path mode)
    final snapshotPath = runtimeContext?.boardSnapshotPath;
    if (snapshotPath != null && snapshotPath.isNotEmpty) {
      final isCliAgent = _provider.imageMode == ChatImageMode.filePath;
      if (isCliAgent) {
        imageAttachments.add(snapshotPath);
      }
    }
    return imageAttachments;
  }

  void _handleStreamError(Object error, bool wasFirstMessage) {
    _isProcessing = false;
    // If the first message failed, allow guidance to be re-injected on retry.
    if (wasFirstMessage && !_hasAssistantReply()) {
      _isFirstMessage = true;
    }
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
  }

  void _handleStreamDone() {
    // Persist provider session IDs
    final doneAdapter = _getAdapterFor(_config.provider);
    if (doneAdapter == 'opencode') {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null && sid != _opencodeSessionId) {
        _opencodeSessionId = sid;
      }
    }
    if (doneAdapter == 'copilot') {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null && sid != _copilotSessionId) {
        _copilotSessionId = sid;
      }
    }
    if (doneAdapter == 'cursor') {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null && sid != _cursorSessionId) {
        _cursorSessionId = sid;
      }
    }
    _isProcessing = false;
    if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
      _finalizeStreamingMessage();
    }
    _assistantInsertIndex = null;
    notifyListeners();
    _persistToHistory();
    _uiDoneCallback?.call();
  }

  /// Send a message and wait for all events to complete. Returns the final
  /// messages list. Used internally when synchronous completion is required
  /// (e.g. agent:run initial task dispatch).
  Future<List<ChatMessage>> sendAndWait({
    required String text,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
  }) async {
    final completer = Completer<List<ChatMessage>>();

    final ok = await sendMessage(
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
    _flushDeltaBuffer();
    if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
      _finalizeStreamingMessage();
    }
    _streamingContent = '';
    _streamingMessageId = null;
    _assistantInsertIndex = null;
    _isProcessing = false;
    notifyListeners();
    await _provider.stop(_config.sessionName);
  }

  // ── Core event handling (non-UI) ────────────────────────────────────────

  void _handleCoreEvent(ChatEvent event) {
    // Capture provider session IDs early
    _captureNewSessionIds(_getAdapterFor(_config.provider));

    final handler = _coreEventHandlers[event.type];
    // Events without a handler (subagentStart, subagentComplete, etc.) are
    // forwarded to the UI via onEvent.
    handler?.call(event);
  }

  late final Map<ChatEventType, void Function(ChatEvent event)>
  _coreEventHandlers = {
    ChatEventType.assistantMessageStart: _onAssistantMessageStart,
    ChatEventType.assistantDelta: _onAssistantDelta,
    ChatEventType.assistantMessage: _onAssistantMessage,
    ChatEventType.toolStart: _onToolStart,
    ChatEventType.toolComplete: _onToolComplete,
    ChatEventType.result: _onResultEvent,
  };

  /// Captures provider session IDs that are not yet known for [adapter].
  void _captureNewSessionIds(String adapter) {
    if (adapter == 'opencode' && _opencodeSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _opencodeSessionId = sid;
      }
    }
    if (adapter == 'copilot' && _copilotSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _copilotSessionId = sid;
      }
    }
    if (adapter == 'cursor' && _cursorSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _cursorSessionId = sid;
      }
    }
  }

  void _onAssistantMessageStart(ChatEvent event) {
    _streamingMessageId = event.messageId;
    _streamingContent = '';
    _assistantInsertIndex ??= _messages.length;
    notifyListeners();
  }

  void _onAssistantDelta(ChatEvent event) {
    final delta = event.deltaContent;
    if (delta == null) return;
    _deltaBuffer.write(delta);
    _lastDeltaEvent = event;
    if (_deltaFlushTimer?.isActive ?? false) return;
    _deltaFlushTimer = Timer(_deltaFlushInterval, _flushDeltaBuffer);
  }

  /// Moves buffered deltas into [_streamingContent] and notifies/forwards a
  /// single merged delta event. Called by the flush timer and synchronously
  /// before any non-delta event, stream end/error, stop, or finalize.
  void _flushDeltaBuffer() {
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
    if (_deltaBuffer.isEmpty) return;
    final chunk = _deltaBuffer.toString();
    _deltaBuffer.clear();
    _streamingContent += chunk;
    notifyListeners();
    final last = _lastDeltaEvent;
    if (last == null) return;
    _uiEventCallback?.call(
      ChatEvent(
        type: last.type,
        rawType: last.rawType,
        data: <String, dynamic>{...last.data, 'deltaContent': chunk},
        id: last.id,
        timestamp: last.timestamp,
        parentId: last.parentId,
        ephemeral: last.ephemeral,
      ),
    );
  }

  void _onAssistantMessage(ChatEvent event) {
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

    final insertAt = _assistantInsertIndex?.clamp(0, _messages.length);
    final assistantMessage = ChatMessage(
      id:
          event.messageId ??
          'assistant-${DateTime.now().millisecondsSinceEpoch}',
      role: ChatRole.assistant,
      content: content,
      timestamp: event.timestamp ?? DateTime.now(),
      toolCalls: toolCalls,
      isStreaming: false,
      tokenUsage: usage,
    );
    if (insertAt != null && insertAt < _messages.length) {
      _messages.insert(insertAt, assistantMessage);
    } else {
      _messages.add(assistantMessage);
    }
    _streamingMessageId = null;
    _streamingContent = '';
    _assistantInsertIndex = null;
    notifyListeners();
  }

  void _onToolStart(ChatEvent event) {
    _assistantInsertIndex ??= _messages.length;
  }

  void _onToolComplete(ChatEvent event) {
    _assistantInsertIndex ??= _messages.length;
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
  }

  void _onResultEvent(ChatEvent event) {
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
    _assistantInsertIndex = null;
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
    final configJson = _config.toJson();
    if (_opencodeSessionId != null) {
      configJson['opencodeSessionId'] = _opencodeSessionId;
    }
    if (_copilotSessionId != null) {
      configJson['copilotSessionId'] = _copilotSessionId;
    }
    if (_cursorSessionId != null) {
      configJson['cursorSessionId'] = _cursorSessionId;
    }
    return {
      'config': configJson,
      'messages': serializeMessages(),
      if (_lastUsage != null) 'lastUsage': _lastUsage!.toJson(),
      if (_opencodeSessionId != null) 'opencodeSessionId': _opencodeSessionId,
      if (_copilotSessionId != null) 'copilotSessionId': _copilotSessionId,
      if (_cursorSessionId != null) 'cursorSessionId': _cursorSessionId,
    };
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<String?> _readTextAttachmentForPrompt(String path) async {
    if (CliTextArgumentResolver.isClipTextFilePath(path)) {
      final content = CliTextArgumentResolver.resolve(path);
      if (content == null || content.isEmpty) return null;
      return '--- Clipboard ---\n$content';
    }
    try {
      if (await FileStorageAdapter.instance.exists(path)) {
        final content = await FileStorageAdapter.instance.readString(path);
        if (content != null && content.isNotEmpty) {
          return '--- File: $path ---\n$content';
        }
      }
    } catch (_) {
      // ignore read failures
    }
    return null;
  }

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
    _deltaFlushTimer?.cancel();
    _deltaFlushTimer = null;
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
    throw UnsupportedError('No provider factory available for $providerId');
  }
}

