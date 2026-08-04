part of 'yolo_assistant_widget.dart';

/// Mutable per-message state shared by the
/// [_YoloAssistantWidgetState._sendMessage] phase helpers.
class _SendMessageContext {
  _SendMessageContext({
    required this.rawText,
    required this.text,
    required this.audioContent,
    required this.overlayPrompt,
    required this.assistantMessageId,
    required this.mirrorToOverlay,
    required this.messages,
    required this.dbg,
  });

  final String rawText;
  final String text;
  final List<Map<String, Object?>>? audioContent;
  final String overlayPrompt;
  final String assistantMessageId;
  final bool mirrorToOverlay;
  final List<Map<String, dynamic>> messages;
  final Map<String, dynamic> dbg;
  final List<String> calledTools = [];
  final List<String> overlayToolLogs = [];

  /// Maps toolCallId → startAt ISO string for accurate per-tool timing.
  final Map<String, String> pendingToolStarts = {};
  String emitted = '';
  bool firstTokenReceived = false;
}

/// Phase helpers for [_YoloAssistantWidgetState._sendMessage].
///
/// Kept in a separate part file to satisfy the repository per-file line
/// limit. An extension in the same library has full access to the private
/// members of [_YoloAssistantWidgetState], and its methods are callable like
/// instance methods from within the class. Each phase was extracted verbatim
/// from the original method body.
extension _AssistantSendPhases on _YoloAssistantWidgetState {
  /// Prepares an outgoing message: validates input, appends the user and
  /// assistant placeholder messages, updates overlay state and opens the
  /// debug session. Returns `null` when there is nothing to send.
  _SendMessageContext? _beginSendMessage({required bool mirrorToOverlay}) {
    final rawText = _inputController.text.trim();
    // Allow empty rawText only when audio content is pending.
    final audioContent = _pendingAudioContent;
    _pendingAudioContent = null;
    if (rawText.isEmpty && audioContent == null) return null;
    _inputController.clear();

    // When sending audio directly to LLM: no voice-prefix, show mic icon in chat.
    // For transcribed voice: prepend ASR context for the LLM.
    final outgoing = resolveOutgoingMessageContent(
      rawText: rawText,
      hasAudioContent: audioContent != null,
      mirrorToOverlay: mirrorToOverlay,
    );
    final text = outgoing.text;
    final displayContent = outgoing.displayContent;

    final msgs = _messages;
    final userMessageId = 'msg-${DateTime.now().millisecondsSinceEpoch}';
    final assistantMessageId =
        'msg-${DateTime.now().millisecondsSinceEpoch + 1}';
    msgs.add({
      'id': userMessageId,
      'role': 'user',
      'content': displayContent,
      'timestamp': DateTime.now().toIso8601String(),
    });
    msgs.add({
      'id': assistantMessageId,
      'role': 'assistant',
      'content': '',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _receivedAssistantToken = false;
    // For overlay display: show mic icon when audio sent directly.
    final overlayPrompt = audioContent != null ? '🎤 Voice message' : rawText;
    _updateState({
      'messages': msgs,
      if (mirrorToOverlay) ...{
        'voiceDraft': '',
        'voicePrompt': overlayPrompt,
        'voiceResponse': '',
        'assistantStatus': 'processing',
        'voiceOverlayHidden': false,
      },
    });
    _scrollToBottom();

    setState(() {
      _isGeneratingReply = true;
      _isCancelled = false;
    });
    if (mirrorToOverlay) {
      _syncOverlayState(
        draftOverride: '',
        forcedStatus: 'processing',
        responseOverride: '',
        promptOverride: overlayPrompt,
        hiddenOverride: false,
      );
    }

    final asrDebug = mirrorToOverlay ? _pendingAsrDebug : null;
    _pendingAsrDebug = null;
    final asrConversionMs = _pendingAsrConversionMs;
    _pendingAsrConversionMs = null;

    // ── Debug session ──────────────────────────────────────────────────────
    final dbg = <String, dynamic>{
      'id': 'dbg-${DateTime.now().millisecondsSinceEpoch}',
      'userMessage': text,
      'requestAt': DateTime.now().toIso8601String(),
      'toolCalls': <Map<String, dynamic>>[],
      if (asrDebug != null)
        'asr': {
          ...asrDebug,
          if (asrConversionMs != null) 'conversionMs': asrConversionMs,
        },
    };
    _activeDebugSession = dbg;

    return _SendMessageContext(
      rawText: rawText,
      text: text,
      audioContent: audioContent,
      overlayPrompt: overlayPrompt,
      assistantMessageId: assistantMessageId,
      mirrorToOverlay: mirrorToOverlay,
      messages: msgs,
      dbg: dbg,
    );
  }

  void _prepareToolExecutor(_SendMessageContext ctx) {
    // Create or reuse the wrapped executor (persistent across messages).
    _wrappedExecutor ??= AssistantToolExecutor(
      delegate: _toolExecutor,
      assistantPanelId: widget.panel.id,
      assistantPanelTitle: widget.panel.title,
      targetPanelId: _targetPanelId,
      onFocusPanel: (focusArgs) async {
        await _toolExecutor.invoke(
          'yoloit_panel_focus',
          focusArgs,
          runtimeContext: await _runtimeContext(),
        );
      },
    );
    // Update per-message mutable state on the executor.
    _wrappedExecutor!.userMessage =
        ctx.audioContent != null && ctx.rawText.isNotEmpty
            ? ctx.rawText
            : ctx.text;
    _wrappedExecutor!.lastTargetNotePanelId = _lastTargetNotePanelId;
    _wrappedExecutor!.onToolCompleted = (
      String toolCommand,
      Map<String, Object?> arguments,
      String result,
      bool success,
    ) {
      _onToolCompleted(ctx, toolCommand, arguments, result, success);
    };
  }

  void _onToolCompleted(
    _SendMessageContext ctx,
    String toolCommand,
    Map<String, Object?> arguments,
    String result,
    bool success,
  ) {
    ctx.calledTools.add(toolCommand);
    final short = _compactToolResult(toolCommand, result, success);
    // Replace the matching ⏳ running entry instead of appending, so the
    // overlay shows ✅/❌ in-place rather than showing both states at once.
    final doneEntry = success ? '✅ $short' : '❌ $short';
    upsertOverlayToolLogEntry(ctx.overlayToolLogs, doneEntry);
    final statePatch = _toolTargetPatchIfNeeded(
      toolCommand: toolCommand,
      arguments: arguments,
      result: result,
    );
    if (statePatch.isNotEmpty) {
      _updateState(statePatch);
    }
    if (ctx.mirrorToOverlay && mounted) {
      _syncOverlayState(
        draftOverride: '',
        forcedStatus: 'responding',
        responseOverride: _composeOverlayResponse('', ctx.overlayToolLogs),
        promptOverride: ctx.overlayPrompt,
        hiddenOverride: false,
      );
    }
    (ctx.dbg['toolCalls'] as List<Map<String, dynamic>>).add({
      'name': toolCommand,
      'arguments': arguments,
      'result': result,
      'success': success,
      'startAt':
          ctx.pendingToolStarts.remove(toolCommand) ??
          DateTime.now().toIso8601String(),
      'endAt': DateTime.now().toIso8601String(),
    });
  }

  /// Pick provider: cloud or local based on user settings.
  /// Provider is reused across messages to preserve history.
  Future<String> _resolveAssistantProviderType() async {
    final providerPref =
        await CloudLlmSettingsService.instance.loadAssistantProviderType();
    if (providerPref == 'cloud') {
      final cloudConfig =
          await CloudLlmSettingsService.instance.loadActiveConfig();
      if (cloudConfig != null) {
        return 'cloud:${cloudConfig.id}';
      }
      final configs = await CloudLlmSettingsService.instance.loadConfigs();
      if (configs.isNotEmpty) {
        return 'cloud:${configs.first.id}';
      }
      return 'cloud:openrouter';
    }
    return 'local';
  }

  /// Re-create provider only if type changed or first use.
  Future<ChatProvider> _ensureChatProvider(String providerType) async {
    if (_chatProvider == null || _chatProviderType != providerType) {
      _chatProvider?.dispose();
      if (providerType.startsWith('cloud:')) {
        final configId = providerType.substring(6);
        final cloudConfig =
            await CloudLlmSettingsService.instance.loadConfigById(configId) ??
            await CloudLlmSettingsService.instance.loadActiveConfig();
        if (cloudConfig != null) {
          _chatProvider = CloudLlmProvider(
            config: cloudConfig,
            toolExecutor: _wrappedExecutor!,
          );
        } else {
          _chatProvider = CloudLlmProvider.deferred(configId: configId);
        }
      } else {
        _chatProvider = LocalLlmProvider(toolExecutor: _wrappedExecutor!);
      }
      _chatProviderType = providerType;
    }
    return _chatProvider!;
  }

  Future<void> _streamAssistantReply(
    _SendMessageContext ctx, {
    required ChatProvider provider,
    required String providerType,
    required ChatRuntimeContext runtimeContext,
  }) async {
    final config = ChatSessionConfig(
      sessionName: '__yolo_badge_assistant__',
      workingDir: Directory.current.path,
      provider: providerType,
      disabledLocalToolNames: _disabledLocalToolNames,
    );

    ctx.dbg['promptSentAt'] = DateTime.now().toIso8601String();
    _recordDebugModelInfo(ctx, providerType);

    await for (final event in provider.sendMessage(
      message: ctx.text,
      config: config,
      isFirstMessage:
          ctx.messages.where((m) => m['role'] == 'user').length <= 1,
      runtimeContext: runtimeContext,
      audioContentOverride: ctx.audioContent,
    )) {
      if (_isCancelled) break;
      _handleChatEvent(ctx, event);
    }
  }

  /// Record model info for display in debug timings.
  void _recordDebugModelInfo(_SendMessageContext ctx, String providerType) {
    if (providerType.startsWith('cloud:')) {
      final cfg = (_chatProvider as CloudLlmProvider).config;
      if (cfg != null) {
        ctx.dbg.addAll(
          cloudModelDebugInfo(
            model: cfg.model,
            providerName: cfg.name,
            baseUrl: cfg.baseUrl,
          ),
        );
      }
    } else {
      ctx.dbg['modelId'] = 'local (MLX)';
      ctx.dbg['modelProvider'] = 'local';
    }
  }

  void _handleChatEvent(_SendMessageContext ctx, ChatEvent event) {
    switch (event.type) {
      case ChatEventType.assistantDelta:
        _handleAssistantDeltaEvent(ctx, event);
      case ChatEventType.toolStart:
        _handleToolStartEvent(ctx, event);
      case ChatEventType.toolComplete:
        _handleToolCompleteEvent(ctx, event);
      case ChatEventType.assistantMessage:
        _handleAssistantMessageEvent(ctx, event);
      case ChatEventType.result:
        _handleResultEvent(ctx, event);
      default:
        break;
    }
  }

  void _handleAssistantDeltaEvent(_SendMessageContext ctx, ChatEvent event) {
    final delta = event.data['deltaContent'] as String? ?? '';
    if (delta.isEmpty) return;
    if (!ctx.firstTokenReceived && delta.trim().isNotEmpty) {
      ctx.firstTokenReceived = true;
      ctx.dbg['firstTokenAt'] = DateTime.now().toIso8601String();
    }
    ctx.emitted += delta;
    if (mounted) {
      _replaceAssistantMessageContent(
        assistantMessageId: ctx.assistantMessageId,
        content: ctx.emitted.trim(),
        mirrorToOverlay: ctx.mirrorToOverlay,
        overlayToolLogs: ctx.overlayToolLogs,
      );
    }
  }

  void _handleToolStartEvent(_SendMessageContext ctx, ChatEvent event) {
    final toolName = event.data['toolName'] as String? ?? '';
    final toolCallId = event.data['toolCallId'] as String? ?? toolName;
    final args = event.data['arguments'] as Map<String, Object?>? ?? {};
    // Capture TTFT from prompt to first LLM response (text OR tool call).
    if (!ctx.firstTokenReceived) {
      ctx.firstTokenReceived = true;
      ctx.dbg['firstTokenAt'] = DateTime.now().toIso8601String();
    }
    // Record start time so onToolCompleted can compute accurate duration.
    // Store under function name, toolCallId, AND CLI command so the
    // lookup in onToolCompleted (keyed by CLI command) succeeds.
    recordPendingToolStarts(
      ctx.pendingToolStarts,
      toolName: toolName,
      toolCallId: toolCallId,
      cliCommand: YoloitCliToolCatalog.byFunctionName(toolName)?.command,
    );
    ctx.overlayToolLogs.add('⏳ running: $toolName');
    if (ctx.mirrorToOverlay && mounted) {
      _syncOverlayState(
        draftOverride: '',
        forcedStatus: 'responding',
        responseOverride: _composeOverlayResponse('', ctx.overlayToolLogs),
        promptOverride: ctx.overlayPrompt,
        hiddenOverride: false,
      );
    }
    _appendToolMessage(
      callId:
          event.data['toolCallId'] as String? ??
          'tool-${DateTime.now().microsecondsSinceEpoch}',
      toolName: toolName,
      arguments: Map<String, Object?>.from(args),
      result: '⏳ running…',
      success: true,
    );
  }

  void _handleToolCompleteEvent(_SendMessageContext ctx, ChatEvent event) {
    final tcId = event.data['toolCallId'] as String? ?? '';
    final tcResult = event.data['result'] as Map<String, dynamic>? ?? {};
    final tcSuccess = event.data['success'] as bool? ?? true;
    final tcToolName = event.data['toolName'] as String? ?? '';
    final tcContent = tcResult['content'] as String? ?? '';
    // Update the existing tool message with actual result.
    _updateToolMessage(
      callId: tcId,
      toolName: tcToolName,
      result: tcContent,
      success: tcSuccess,
    );
  }

  void _handleAssistantMessageEvent(_SendMessageContext ctx, ChatEvent event) {
    final content = event.data['content'] as String? ?? '';
    if (content.isNotEmpty) {
      final cleaned = _cleanAssistantToolEchoes(content, ctx.calledTools);
      if (mounted) {
        _replaceAssistantMessageContent(
          assistantMessageId: ctx.assistantMessageId,
          content: cleaned,
          mirrorToOverlay: ctx.mirrorToOverlay,
          overlayToolLogs: ctx.overlayToolLogs,
        );
      }
    }
  }

  void _handleResultEvent(_SendMessageContext ctx, ChatEvent event) {
    ctx.dbg['completedAt'] = DateTime.now().toIso8601String();
    final usage = event.data['usage'] as Map<String, dynamic>? ?? {};
    ctx.dbg['usage'] = usage;
  }

  void _finalizeAssistantReply(_SendMessageContext ctx) {
    ctx.dbg['completedAt'] ??= DateTime.now().toIso8601String();

    // Final cleanup of the displayed content.
    final cleanedFinal = _cleanAssistantToolEchoes(
      ctx.emitted.trim(),
      ctx.calledTools,
    );
    if (mounted && cleanedFinal.isNotEmpty) {
      _replaceAssistantMessageContent(
        assistantMessageId: ctx.assistantMessageId,
        content: cleanedFinal,
        mirrorToOverlay: ctx.mirrorToOverlay,
        overlayToolLogs: ctx.overlayToolLogs,
      );
    }
    if (ctx.mirrorToOverlay) {
      // Use clean text only (no tool logs) so the card crossfades from
      // the tools-call view to the final answer without duplicating the logs.
      _syncOverlayState(
        draftOverride: '',
        forcedStatus: 'output',
        responseOverride: cleanedFinal,
        promptOverride: ctx.overlayPrompt,
        hiddenOverride: false,
      );
    }
    ctx.dbg['cleanedResponse'] = cleanedFinal;
  }

  void _handleSendMessageError(_SendMessageContext ctx, Object e) {
    ctx.dbg['error'] = '$e';
    ctx.dbg['completedAt'] = DateTime.now().toIso8601String();
    _replaceAssistantMessageContent(
      assistantMessageId: ctx.assistantMessageId,
      content: _formatAssistantError(e),
      mirrorToOverlay: ctx.mirrorToOverlay,
      overlayToolLogs: const [],
    );
    if (ctx.mirrorToOverlay) {
      _syncOverlayState(
        draftOverride: '',
        forcedStatus: 'output',
        responseOverride: _formatAssistantError(e),
        promptOverride: ctx.overlayPrompt,
        hiddenOverride: false,
      );
    }
  }

  void _cleanupAfterSendMessage({
    required Map<String, dynamic> dbg,
    required bool mirrorToOverlay,
  }) {
    _debugSessions.add(dbg);
    if (_debugSessions.length > 20) _debugSessions.removeAt(0);
    _activeDebugSession = null;
    _messageDraft = null;
    // Persist messages to history after each exchange.
    _persistToHistory();
    if (mounted) {
      setState(() {
        _isGeneratingReply = false;
        _isCancelled = false;
      });
      // When mirrorToOverlay, the try/catch already set the overlay to
      // 'output' + hidden=false.  Do NOT call _syncOverlayState here —
      // widget.panel still holds the STALE state (pre-_updateState rebuild),
      // so re-computing the status would overwrite 'output' with 'idle'.
      if (!mirrorToOverlay) {
        _syncOverlayState(hiddenOverride: _voiceOverlayHidden);
      }
    }
  }
}
