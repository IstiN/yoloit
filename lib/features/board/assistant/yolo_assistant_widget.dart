import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_models_flutter/runtime/embedded_gemma_tool_calls.dart';
import 'package:record/record.dart';
import 'package:yoloit/core/platform/microphone_permission_service.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/assistant/assistant_voice_visualizer.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/cloud_asr_service.dart';
import 'package:yoloit/features/board/chat/cloud_llm_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/board/chat/yolo_chat_prompt.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';
import 'package:yoloit/features/settings/ui/settings_page.dart';

class YoloAssistantController {
  Future<void> Function()? _startMic;
  Future<void> Function({bool sendAfterTranscription})? _stopMic;
  Future<void> Function()? _cancelMic;
  Future<void> Function()? _sendDraft;
  VoidCallback? _resetOverlay;

  /// Broadcast stream of normalized mic amplitude (0.0 = silence, 1.0 = max).
  /// Active only while the microphone is recording.
  final StreamController<double> _micAmplitudeCtrl =
      StreamController<double>.broadcast();
  Stream<double> get micAmplitudeStream => _micAmplitudeCtrl.stream;

  void _attach({
    required Future<void> Function() startMic,
    required Future<void> Function({bool sendAfterTranscription}) stopMic,
    required Future<void> Function() cancelMic,
    required Future<void> Function() sendDraft,
    required VoidCallback resetOverlay,
  }) {
    _startMic = startMic;
    _stopMic = stopMic;
    _cancelMic = cancelMic;
    _sendDraft = sendDraft;
    _resetOverlay = resetOverlay;
  }

  void _detach() {
    _startMic = null;
    _stopMic = null;
    _cancelMic = null;
    _sendDraft = null;
    _resetOverlay = null;
  }

  Future<void> startMic() => _startMic?.call() ?? Future<void>.value();

  Future<void> stopMic({bool sendAfterTranscription = false}) =>
      _stopMic?.call(sendAfterTranscription: sendAfterTranscription) ??
      Future<void>.value();

  Future<void> cancelMic() => _cancelMic?.call() ?? Future<void>.value();

  Future<void> sendDraft() => _sendDraft?.call() ?? Future<void>.value();

  void resetOverlay() => _resetOverlay?.call();

  void dispose() => _micAmplitudeCtrl.close();
}

/// Main widget for the YoLo Assistant panel.
///
/// Supports two modes: **text** (chat) and **voice** (voice-to-voice).
class YoloAssistantWidget extends StatefulWidget {
  const YoloAssistantWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
    this.controller,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;
  final YoloAssistantController? controller;

  @override
  State<YoloAssistantWidget> createState() => _YoloAssistantWidgetState();
}

class _YoloAssistantWidgetState extends State<YoloAssistantWidget> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final AudioRecorder _micRecorder = AudioRecorder();
  StreamSubscription<dynamic>? _amplitudeSub;

  /// Accumulates raw PCM bytes from the mic stream (avoids disk roundtrip).
  BytesBuilder? _micStreamBytes;
  StreamSubscription<Uint8List>? _micStreamSub;
  final YoloitToolExecutor _toolExecutor = YoloitCliToolExecutor();
  final CloudAsrService _cloudAsrService = CloudAsrService();
  _AssistantToolExecutor? _wrappedExecutor;
  ChatProvider? _chatProvider;
  String? _chatProviderType; // tracks current provider type for re-creation
  Map<String, dynamic>? _pendingAsrDebug;
  bool _isRecordingMic = false;
  bool _isStartingMic = false;
  bool _stopMicAfterStart = false;
  bool _isTranscribingMic = false;
  bool _isGeneratingReply = false;
  bool _isCancelled = false;
  bool _receivedAssistantToken = false;
  List<Map<String, dynamic>>? _messageDraft;

  // When non-null, the next _sendMessage call will pass audio content directly
  // to the cloud LLM instead of sending the text in _inputController.
  List<Map<String, Object?>>? _pendingAudioContent;
  int? _pendingAsrConversionMs; // MP3 conversion duration for timeline

  // In-memory ring buffer of raw LLM debug sessions (last 20, not persisted).
  final List<Map<String, dynamic>> _debugSessions = [];
  Map<String, dynamic>? _activeDebugSession;

  // Current session tracking for history persistence.
  String? _assistantSessionId;
  DateTime? _assistantSessionCreatedAt;

  // Pending state overrides — prevents stale widget.panel.state reads from
  // overwriting state changes made between board rebuilds. Each _updateState
  // call accumulates here; acknowledged keys are cleared in didUpdateWidget.
  final Map<String, dynamic> _pendingStateOverrides = {};

  bool get _voiceOverlayHidden =>
      (_pendingStateOverrides['voiceOverlayHidden'] ??
              widget.panel.state['voiceOverlayHidden'])
          as bool? ??
      true;

  // Effective state: pending overrides layered on top of last-known panel state.
  Map<String, dynamic> get _effectiveState =>
      Map<String, dynamic>.from(widget.panel.state)
        ..addAll(_pendingStateOverrides);

  void _syncOverlayState({
    String? draftOverride,
    String? forcedStatus,
    String? responseOverride,
    String? promptOverride,
    bool? hiddenOverride,
  }) {
    final draft = draftOverride ?? _inputController.text.trim();
    final status =
        forcedStatus ??
        (_isRecordingMic
            ? 'listening'
            : _isTranscribingMic
            ? 'processing'
            : _isGeneratingReply
            ? (_receivedAssistantToken ? 'responding' : 'thinking')
            : draft.isNotEmpty
            ? 'ready'
            : 'idle');
    // ignore: avoid_print
    print(
      '[YoloAssistant] _syncOverlayState: forced=$forcedStatus → status=$status (isGenerating=$_isGeneratingReply, hasToken=$_receivedAssistantToken)',
    );
    final effective = _effectiveState;
    _updateState({
      'voiceDraft': draft,
      'assistantStatus': status,
      'voiceResponse':
          responseOverride ?? (effective['voiceResponse'] as String? ?? ''),
      'voicePrompt':
          promptOverride ?? (effective['voicePrompt'] as String? ?? ''),
      'voiceOverlayHidden': hiddenOverride ?? _voiceOverlayHidden,
    });
  }

  void _resetVoiceOverlay() {
    _updateState({
      'voiceDraft': '',
      'voicePrompt': '',
      'voiceResponse': '',
      'assistantStatus': 'idle',
      'voiceOverlayHidden': true,
    });
  }

  // ── Derived state from panel ──────────────────────────────────────────────

  List<Map<String, dynamic>> get _messages => List<Map<String, dynamic>>.from(
    (widget.panel.state['messages'] as List<dynamic>?) ?? [],
  );

  List<String> get _activeSkills => List<String>.from(
    (widget.panel.state['activeSkills'] as List<dynamic>?) ?? _defaultSkills,
  );

  List<String> get _disabledLocalToolNames => List<String>.from(
    (widget.panel.state['disabledLocalToolNames'] as List<dynamic>?) ??
        const [],
  );

  String? get _lastTargetNotePanelId =>
      widget.panel.state['lastTargetNotePanelId'] as String?;

  int get _maxOutputTokens {
    final value = widget.panel.state['localModelMaxOutputTokens'];
    if (value is num) return value.toInt().clamp(128, 4096);
    return 1024;
  }

  double get _temperature {
    final value = widget.panel.state['localModelTemperature'];
    if (value is num) return value.toDouble().clamp(0.0, 2.0);
    return 0.2;
  }

  bool get _enableThinking {
    final value = widget.panel.state['localModelEnableThinking'];
    return value is bool ? value : false;
  }

  String get _mode => widget.panel.state['mode'] as String? ?? 'text';
  bool get _isListening => widget.panel.state['isListening'] as bool? ?? false;
  bool get _isSpeaking => widget.panel.state['isSpeaking'] as bool? ?? false;

  static const _defaultSkills = ['Terminal', 'Board Control', 'Web Search'];
  static const _allSkills = [
    'Terminal',
    'Board Control',
    'Web Search',
    'Code Analysis',
    'File Manager',
    'Git Tools',
    'Notes',
    'Calendar',
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(
      startMic: _startRecordingFromMic,
      stopMic:
          ({bool sendAfterTranscription = false}) =>
              _stopRecordingAndTranscribe(
                sendAfterTranscription: sendAfterTranscription,
                mirrorToOverlay: true,
              ),
      cancelMic: _cancelRecordingFromMic,
      sendDraft: () => _sendMessage(mirrorToOverlay: true),
      resetOverlay: _resetVoiceOverlay,
    );
  }

  @override
  void didUpdateWidget(covariant YoloAssistantWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Remove overrides the board has now acknowledged (its state matches our value).
    if (!identical(oldWidget.panel.state, widget.panel.state)) {
      _pendingStateOverrides.removeWhere(
        (key, value) => widget.panel.state[key] == value,
      );
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(
        startMic: _startRecordingFromMic,
        stopMic:
            ({bool sendAfterTranscription = false}) =>
                _stopRecordingAndTranscribe(
                  sendAfterTranscription: sendAfterTranscription,
                  mirrorToOverlay: true,
                ),
        cancelMic: _cancelRecordingFromMic,
        sendDraft: () => _sendMessage(mirrorToOverlay: true),
        resetOverlay: _resetVoiceOverlay,
      );
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _chatProvider?.dispose();
    _amplitudeSub?.cancel();
    _micStreamSub?.cancel();
    _micStreamBytes = null;
    unawaited(_micRecorder.dispose());
    super.dispose();
  }

  // ── State helpers ─────────────────────────────────────────────────────────

  void _updateState(Map<String, dynamic> patch) {
    // Accumulate patch into overrides so that rapid back-to-back _updateState
    // calls don't lose earlier changes via stale widget.panel.state reads.
    _pendingStateOverrides.addAll(patch);
    final merged = Map<String, dynamic>.from(widget.panel.state)
      ..addAll(_pendingStateOverrides);
    widget.onUpdateState(merged);
  }

  void _stopGeneration() {
    // Immediately flip UI so the button responds at once.
    setState(() {
      _isCancelled = true;
      _isGeneratingReply = false;
    });
    // Cancel the underlying provider HTTP request / stream.
    unawaited(
      _chatProvider?.stop('__yolo_badge_assistant__').catchError((_) {}),
    );
  }

  Future<void> _sendMessage({bool mirrorToOverlay = false}) async {
    if (_isGeneratingReply) return;
    final rawText = _inputController.text.trim();
    // Allow empty rawText only when audio content is pending.
    final audioContent = _pendingAudioContent;
    _pendingAudioContent = null;
    if (rawText.isEmpty && audioContent == null) return;
    _inputController.clear();

    // When sending audio directly to LLM: no voice-prefix, show mic icon in chat.
    // For transcribed voice: prepend ASR context for the LLM.
    final String text;
    final String displayContent;
    if (audioContent != null) {
      // Audio sent directly — display mic icon, no prefix for LLM history
      // (audio IS the content).
      displayContent = '🎤 Voice message';
      text = displayContent; // stored in history for display only
    } else if (mirrorToOverlay) {
      text =
          '[Voice message — transcribed via speech recognition, '
          'may contain recognition errors]\n$rawText';
      displayContent = text;
    } else {
      text = rawText;
      displayContent = text;
    }

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

    try {
      _messageDraft = msgs;
      final runtimeContext = _runtimeContext();
      final calledTools = <String>[];
      final overlayToolLogs = <String>[];
      // Maps toolCallId → startAt ISO string for accurate per-tool timing.
      final pendingToolStarts = <String, String>{};

      // Create or reuse the wrapped executor (persistent across messages).
      _wrappedExecutor ??= _AssistantToolExecutor(
        delegate: _toolExecutor,
        assistantPanelId: widget.panel.id,
        assistantPanelTitle: widget.panel.title,
        onFocusPanel: (focusArgs) async {
          await _toolExecutor.invoke(
            'yoloit_panel_focus',
            focusArgs,
            runtimeContext: _runtimeContext(),
          );
        },
      );
      // Update per-message mutable state on the executor.
      _wrappedExecutor!.userMessage = text;
      _wrappedExecutor!.lastTargetNotePanelId = _lastTargetNotePanelId;
      _wrappedExecutor!.onToolCompleted = (
        String toolCommand,
        Map<String, Object?> arguments,
        String result,
        bool success,
      ) {
        calledTools.add(toolCommand);
        final short = _compactToolResult(toolCommand, result, success);
        // Replace the matching ⏳ running entry instead of appending, so the
        // overlay shows ✅/❌ in-place rather than showing both states at once.
        final runningIdx = overlayToolLogs.lastIndexWhere(
          (e) => e.startsWith('⏳ running:'),
        );
        final doneEntry = success ? '✅ $short' : '❌ $short';
        if (runningIdx >= 0) {
          overlayToolLogs[runningIdx] = doneEntry;
        } else {
          overlayToolLogs.add(doneEntry);
        }
        final statePatch = _toolTargetPatchIfNeeded(
          toolCommand: toolCommand,
          arguments: arguments,
          result: result,
        );
        if (statePatch.isNotEmpty) {
          _updateState(statePatch);
        }
        if (mirrorToOverlay && mounted) {
          _syncOverlayState(
            draftOverride: '',
            forcedStatus: 'responding',
            responseOverride: _composeOverlayResponse('', overlayToolLogs),
            promptOverride: overlayPrompt,
            hiddenOverride: false,
          );
        }
        (dbg['toolCalls'] as List<Map<String, dynamic>>).add({
          'name': toolCommand,
          'arguments': arguments,
          'result': result,
          'success': success,
          'startAt':
              pendingToolStarts.remove(toolCommand) ??
              DateTime.now().toIso8601String(),
          'endAt': DateTime.now().toIso8601String(),
        });
      };

      // Pick provider: cloud or local based on user settings.
      // Provider is reused across messages to preserve history.
      final providerPref =
          await CloudLlmSettingsService.instance.loadAssistantProviderType();
      String providerType;
      if (providerPref == 'cloud') {
        final cloudConfig =
            await CloudLlmSettingsService.instance.loadActiveConfig();
        if (cloudConfig != null && cloudConfig.isValid) {
          providerType = 'cloud:${cloudConfig.id}';
        } else {
          providerType = 'local';
        }
      } else {
        providerType = 'local';
      }

      // Re-create provider only if type changed or first use.
      if (_chatProvider == null || _chatProviderType != providerType) {
        _chatProvider?.dispose();
        if (providerType.startsWith('cloud:')) {
          final cloudConfig =
              await CloudLlmSettingsService.instance.loadActiveConfig();
          _chatProvider = CloudLlmProvider(
            config: cloudConfig!,
            toolExecutor: _wrappedExecutor!,
          );
        } else {
          _chatProvider = LocalLlmProvider(toolExecutor: _wrappedExecutor!);
        }
        _chatProviderType = providerType;
      }
      final provider = _chatProvider!;

      final config = ChatSessionConfig(
        sessionName: '__yolo_badge_assistant__',
        workingDir: Directory.current.path,
        provider: providerType,
        disabledLocalToolNames: _disabledLocalToolNames,
      );

      dbg['promptSentAt'] = DateTime.now().toIso8601String();
      // Record model info for display in debug timings.
      if (providerType.startsWith('cloud:')) {
        final cfg = (_chatProvider as CloudLlmProvider).config;
        if (cfg != null) {
          dbg['modelId'] = cfg.model;
          dbg['modelProvider'] = cfg.name;
          dbg['modelBaseUrl'] = cfg.baseUrl;
        }
      } else {
        dbg['modelId'] = 'local (MLX)';
        dbg['modelProvider'] = 'local';
      }
      var emitted = '';
      var firstTokenReceived = false;

      await for (final event in provider.sendMessage(
        message: text,
        config: config,
        isFirstMessage: msgs.where((m) => m['role'] == 'user').length <= 1,
        runtimeContext: runtimeContext,
        audioContentOverride: audioContent,
      )) {
        if (_isCancelled) break;

        switch (event.type) {
          case ChatEventType.assistantDelta:
            final delta = event.data['deltaContent'] as String? ?? '';
            if (delta.isEmpty) continue;
            if (!firstTokenReceived && delta.trim().isNotEmpty) {
              firstTokenReceived = true;
              dbg['firstTokenAt'] = DateTime.now().toIso8601String();
            }
            emitted += delta;
            if (mounted) {
              _replaceAssistantMessageContent(
                assistantMessageId: assistantMessageId,
                content: emitted.trim(),
                mirrorToOverlay: mirrorToOverlay,
                overlayToolLogs: overlayToolLogs,
              );
            }
          case ChatEventType.toolStart:
            final toolName = event.data['toolName'] as String? ?? '';
            final toolCallId = event.data['toolCallId'] as String? ?? toolName;
            final args = event.data['arguments'] as Map<String, Object?>? ?? {};
            // Capture TTFT from prompt to first LLM response (text OR tool call).
            if (!firstTokenReceived) {
              firstTokenReceived = true;
              dbg['firstTokenAt'] = DateTime.now().toIso8601String();
            }
            // Record start time so onToolCompleted can compute accurate duration.
            // Store under function name, toolCallId, AND CLI command so the
            // lookup in onToolCompleted (keyed by CLI command) succeeds.
            final now = DateTime.now().toIso8601String();
            pendingToolStarts[toolName] = now;
            pendingToolStarts[toolCallId] = now;
            final cliCmd =
                YoloitCliToolCatalog.byFunctionName(toolName)?.command;
            if (cliCmd != null) pendingToolStarts[cliCmd] = now;
            overlayToolLogs.add('⏳ running: $toolName');
            if (mirrorToOverlay && mounted) {
              _syncOverlayState(
                draftOverride: '',
                forcedStatus: 'responding',
                responseOverride: _composeOverlayResponse('', overlayToolLogs),
                promptOverride: overlayPrompt,
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
          case ChatEventType.toolComplete:
            final tcId = event.data['toolCallId'] as String? ?? '';
            final tcResult =
                event.data['result'] as Map<String, dynamic>? ?? {};
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
          case ChatEventType.assistantMessage:
            final content = event.data['content'] as String? ?? '';
            if (content.isNotEmpty) {
              final cleaned = _cleanAssistantToolEchoes(content, calledTools);
              if (mounted) {
                _replaceAssistantMessageContent(
                  assistantMessageId: assistantMessageId,
                  content: cleaned,
                  mirrorToOverlay: mirrorToOverlay,
                  overlayToolLogs: overlayToolLogs,
                );
              }
            }
          case ChatEventType.result:
            dbg['completedAt'] = DateTime.now().toIso8601String();
            final usage = event.data['usage'] as Map<String, dynamic>? ?? {};
            dbg['usage'] = usage;
          default:
            break;
        }
      }

      dbg['completedAt'] ??= DateTime.now().toIso8601String();

      // Final cleanup of the displayed content.
      final cleanedFinal = _cleanAssistantToolEchoes(
        emitted.trim(),
        calledTools,
      );
      if (mounted && cleanedFinal.isNotEmpty) {
        _replaceAssistantMessageContent(
          assistantMessageId: assistantMessageId,
          content: cleanedFinal,
          mirrorToOverlay: mirrorToOverlay,
          overlayToolLogs: overlayToolLogs,
        );
      }
      if (mirrorToOverlay) {
        // Use clean text only (no tool logs) so the card crossfades from
        // the tools-call view to the final answer without duplicating the logs.
        _syncOverlayState(
          draftOverride: '',
          forcedStatus: 'output',
          responseOverride: cleanedFinal,
          promptOverride: overlayPrompt,
          hiddenOverride: false,
        );
      }
      dbg['cleanedResponse'] = cleanedFinal;
    } catch (e) {
      dbg['error'] = '$e';
      dbg['completedAt'] = DateTime.now().toIso8601String();
      _replaceAssistantMessageContent(
        assistantMessageId: assistantMessageId,
        content: _formatAssistantError(e),
        mirrorToOverlay: mirrorToOverlay,
        overlayToolLogs: const [],
      );
      if (mirrorToOverlay) {
        _syncOverlayState(
          draftOverride: '',
          forcedStatus: 'output',
          responseOverride: _formatAssistantError(e),
          promptOverride: overlayPrompt,
          hiddenOverride: false,
        );
      }
    } finally {
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

  void _replaceAssistantMessageContent({
    required String assistantMessageId,
    required String content,
    bool mirrorToOverlay = false,
    List<String> overlayToolLogs = const [],
  }) {
    final current = _messageDraft ?? _messages;
    final idx = current.indexWhere((m) => m['id'] == assistantMessageId);
    if (idx == -1) return;
    if (_isGeneratingReply && content.trim().isNotEmpty) {
      _receivedAssistantToken = true;
    }
    current[idx] = {...current[idx], 'content': content};
    _messageDraft = current;
    final newStatus =
        _isGeneratingReply && content.trim().isEmpty && overlayToolLogs.isEmpty
            ? 'processing'
            : _isGeneratingReply
            ? 'responding'
            : 'output';
    // ignore: avoid_print
    if (mirrorToOverlay && !_voiceOverlayHidden) {
      print(
        '[YoloAssistant] _replaceContent → status=$newStatus content="${content.length}ch" tools=${overlayToolLogs.length}',
      );
    }
    _updateState({
      'messages': current,
      if (mirrorToOverlay && !_voiceOverlayHidden) ...{
        'voiceResponse': _composeOverlayResponse(content, overlayToolLogs),
        'assistantStatus': newStatus,
      },
    });
    _scrollToBottom();
  }

  String _composeOverlayResponse(
    String assistantContent,
    List<String> toolLogs,
  ) {
    final text = assistantContent.trim();

    // Show up to 5 recent tool calls as compact lines (⚙️ tool:name).
    if (toolLogs.isEmpty) return text;
    final recent =
        toolLogs.length > 5 ? toolLogs.sublist(toolLogs.length - 5) : toolLogs;
    final toolText = recent
        .map((entry) {
          // Normalize: strip leading emoji/status prefixes, keep just tool name
          final clean =
              entry
                  .replaceAll(RegExp(r'^[⏳✅❌]\s*running:\s*'), '')
                  .replaceAll(RegExp(r'^[⏳✅❌]\s*'), '')
                  .trim();
          final isDone = entry.startsWith('✅') || entry.startsWith('❌');
          final icon =
              entry.startsWith('❌')
                  ? '❌'
                  : isDone
                  ? '✅'
                  : '⚙️';
          return '$icon $clean';
        })
        .join('\n');

    if (text.isEmpty) return toolText;
    return '$toolText\n\n$text';
  }

  BoardDocument? _currentBoard() =>
      context.read<BoardCubit>().state.activeBoard;

  String _availableBoardsSummary() {
    final cubit = context.read<BoardCubit>();
    final current = cubit.state.activeBoard;
    return cubit.state.boards
        .map((board) {
          final marker = board.id == current?.id ? ' (current)' : '';
          return '- ${board.name} [${board.id}]$marker';
        })
        .join('\n');
  }

  String _currentBoardPanelsSummary(BoardDocument? board) {
    if (board == null) return '';
    final panels = [...board.panels]
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    return panels
        .map((panel) => '- ${panel.title} [${panel.type}] (${panel.id})')
        .join('\n');
  }

  ChatRuntimeContext _runtimeContext() {
    final board = _currentBoard();
    return ChatRuntimeContext(
      boardId: board?.id,
      boardName: board?.name,
      panelId: widget.panel.id,
      panelTitle: widget.panel.title,
      panelType: widget.panel.type,
      availableBoardsSummary: _availableBoardsSummary(),
      currentBoardPanelsSummary: _currentBoardPanelsSummary(board),
      viewportScale: board?.viewport.scale,
    );
  }

  Map<String, dynamic> _toolTargetPatchIfNeeded({
    required String? toolCommand,
    required Map<String, Object?> arguments,
    required String result,
  }) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map && decoded['ok'] == false) return const {};
    } catch (_) {}
    if (toolCommand == 'panel:create') {
      final type = '${arguments['type'] ?? ''}'.trim();
      if (type != 'board.note.markdown') return const {};
      try {
        final decoded = jsonDecode(result);
        if (decoded is! Map) return const {};
        final stdout = decoded['stdout'];
        final payload = stdout is String ? jsonDecode(stdout) : decoded;
        if (payload is! Map) return const {};
        final panel = payload['panel'];
        if (panel is! Map) return const {};
        final id = '${panel['id'] ?? ''}'.trim();
        final title = '${panel['title'] ?? id}'.trim();
        if (id.isEmpty) return const {};
        return {
          'lastTargetNotePanelId': id,
          'lastTargetNotePanelTitle': title.isEmpty ? id : title,
        };
      } catch (_) {
        return const {};
      }
    }
    if (toolCommand == 'note' || toolCommand?.startsWith('note:') == true) {
      final panel = '${arguments['panel'] ?? ''}'.trim();
      if (panel.isEmpty || panel == widget.panel.id) return const {};
      return {
        'lastTargetNotePanelId': panel,
        'lastTargetNotePanelTitle': panel,
      };
    }
    return const {};
  }

  String _cleanAssistantToolEchoes(String content, List<String> calledTools) {
    var cleaned = stripEmbeddedGemmaToolCallBlocks(content).trim();
    if (cleaned.startsWith(RegExp(r'\[yoloit_[^\]]+\]')) &&
        (cleaned.contains('"ok"') || cleaned.contains('"command"'))) {
      cleaned = '';
    }
    cleaned = cleaned.replaceAll(
      RegExp(r'^\s*\[yoloit_[^\]]+\]\s*\{[\s\S]*?\}\s*$', multiLine: true),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'^\s*\[yoloit_[^\]]+\].*$', multiLine: true),
      '',
    );
    cleaned = cleaned.trim();
    if (cleaned.isNotEmpty) return cleaned;
    if (calledTools.isEmpty) return '';
    final unique = <String>[];
    for (final tool in calledTools) {
      if (!unique.contains(tool)) unique.add(tool);
    }
    return 'Готово — выполнил через ${unique.join(', ')}.';
  }

  String _compactToolResult(String toolName, String result, bool success) {
    String? command;
    String? error;
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map) {
        command = decoded['command'] as String?;
        error = decoded['error'] as String?;
      }
    } catch (_) {}
    if (!success) {
      return error == null || error.isEmpty
          ? 'Tool failed: $toolName'
          : 'Tool failed: $error';
    }
    return command == null || command.isEmpty ? 'Done: $toolName' : command;
  }

  void _appendToolMessage({
    required String callId,
    required String toolName,
    required Map<String, Object?> arguments,
    required String result,
    required bool success,
    Map<String, dynamic> statePatch = const {},
  }) {
    final current = _messageDraft ?? _messages;
    final toolMessage = {
      'id': callId,
      'role': 'tool',
      'toolName': toolName,
      'content': _compactToolResult(toolName, result, success),
      'rawResult': result,
      'arguments': arguments,
      'success': success,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (current.isNotEmpty && current.last['role'] == 'assistant') {
      current.insert(current.length - 1, toolMessage);
    } else {
      current.add(toolMessage);
    }
    _messageDraft = current;
    _updateState({'messages': current, ...statePatch});
    _scrollToBottom();
  }

  void _updateToolMessage({
    required String callId,
    required String toolName,
    required String result,
    required bool success,
  }) {
    final current = _messageDraft ?? _messages;
    for (final msg in current) {
      if (msg['id'] == callId && msg['role'] == 'tool') {
        msg['content'] = _compactToolResult(toolName, result, success);
        msg['rawResult'] = result;
        msg['success'] = success;
        break;
      }
    }
    _messageDraft = current;
    _updateState({'messages': current});
  }

  /// Build structured messages list for `LmCompletionRequest.messages`.
  /// Returns `[{role, content}, ...]` with:
  ///   - role='system' for the system prompt (first entry)
  ///   - role='user'/'assistant'/'tool' for conversation history
  Future<List<Map<String, String>>> _buildMessagesForRequest(
    List<Map<String, dynamic>> chatMessages,
  ) async {
    final systemContent =
        '${await loadYoloChatSystemPrompt()}\n\n'
        '${_buildContextSnapshotMarkdown()}\n'
        'Active skills: ${_activeSkills.join(', ')}.\n'
        'Last target note panel id: ${_lastTargetNotePanelId ?? 'unknown'}.';

    final result = <Map<String, String>>[
      {'role': 'system', 'content': systemContent},
    ];

    for (final m in chatMessages) {
      final role = (m['role'] as String? ?? '').toLowerCase();
      final content = (m['content'] as String? ?? '').trim();
      if (role == 'user') {
        if (content.isEmpty) continue;
        result.add({'role': 'user', 'content': content});
      } else if (role == 'assistant') {
        if (content.isEmpty) continue;
        result.add({'role': 'assistant', 'content': content});
      } else if (role == 'tool') {
        result.add({'role': 'tool', 'content': _formatToolMessageForPrompt(m)});
      }
    }
    return result;
  }

  String _buildContextSnapshotMarkdown() {
    final cubit = context.read<BoardCubit>();
    final board = cubit.state.activeBoard;
    final enabledTools = _enabledLocalToolCount();
    final boardsList = _availableBoardsSummary();
    final panelsList = _currentBoardPanelsSummary(board);
    return '''
## Current YoLoIT context snapshot

- Board id: ${board?.id ?? 'unknown'}
- Board name: ${board?.name ?? 'unknown'}
- Assistant panel id: ${widget.panel.id}
- Assistant panel title: ${widget.panel.title}
- Enabled tools: $enabledTools/${YoloitCliToolCatalog.tools.length}
- Max output tokens: $_maxOutputTokens
- Temperature: $_temperature
- Thinking: ${_enableThinking ? 'enabled' : 'disabled'}

### Available boards (id-aware)
$boardsList

Use this list when user asks to switch/open a board. Do not claim missing access without trying board:focus.

### Current board panels
$panelsList

Use this list when user asks to show/focus/play an existing panel on the current board.
'''.trim();
  }

  Future<String> _buildNextRequestPreviewMarkdown() async {
    final text = _inputController.text.trim();
    final previewMessages = _messages;
    if (text.isNotEmpty) {
      previewMessages.add({
        'id': 'preview-user',
        'role': 'user',
        'content': text,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
    final messages = await _buildMessagesForRequest(previewMessages);
    final disabled = _disabledLocalTools();
    final tools = YoloitCliToolCatalog.localToolsFor(
      disabledFunctionNames: disabled,
    );
    final toolSchemas = const JsonEncoder.withIndent(
      '  ',
    ).convert(tools.map((tool) => tool.toJson()).toList());
    final outputTokensInHistory = previewMessages
        .where((m) => m['role'] == 'assistant')
        .map((m) => _estimateTokens(m['content'] as String? ?? ''))
        .fold<int>(0, (sum, value) => sum + value);
    final approxPromptTokens = messages.fold<int>(
      0,
      (sum, m) => sum + _estimateTokens(m['content'] ?? ''),
    );
    final messagesJson = const JsonEncoder.withIndent('  ').convert(messages);
    return '''
# Next YoLo Chat request preview

## Model settings

- Max output tokens: $_maxOutputTokens
- Temperature: $_temperature
- Thinking: ${_enableThinking ? 'enabled' : 'disabled'}
- Approx prompt tokens: $approxPromptTokens
- Approx assistant output tokens in history: $outputTokensInHistory
- Messages stored in UI state: ${previewMessages.length}
- Tool calls stored in UI state: ${previewMessages.where((m) => m['role'] == 'tool').length}

## Enabled function tools

${tools.map((tool) => '- `${tool.name}`').join('\n')}

## Function tool schemas sent to model

```json
$toolSchemas
```

## Messages sent to model

```json
$messagesJson
```
''';
  }

  String _formatToolMessageForPrompt(Map<String, dynamic> message) {
    final toolName = (message['toolName'] as String? ?? 'tool').trim();
    final success = message['success'] as bool? ?? true;
    final arguments = _compactJsonForPrompt(
      message['arguments'],
      maxChars: 600,
    );
    final result = _compactToolResultForPrompt(message['rawResult']);
    return '\nTool $toolName ${success ? 'succeeded' : 'failed'}'
        '\nTool arguments: $arguments'
        '\nTool result: $result';
  }

  String _compactToolResultForPrompt(Object? rawResult) {
    if (rawResult is! String || rawResult.trim().isEmpty) return 'none';
    try {
      final decoded = jsonDecode(rawResult);
      if (decoded is Map) {
        final compact = <String, Object?>{
          if (decoded.containsKey('ok')) 'ok': decoded['ok'],
          if (decoded['command'] != null) 'command': decoded['command'],
          if (decoded['error'] != null) 'error': decoded['error'],
        };
        final stdout = decoded['stdout'];
        final panelSummary = _panelSummaryFromStdout(stdout);
        if (panelSummary != null) compact['panel'] = panelSummary;
        if (compact.isNotEmpty) {
          return _compactJsonForPrompt(compact, maxChars: 800);
        }
      }
    } catch (_) {}
    return _truncatePromptText(rawResult, 800);
  }

  Map<String, Object?>? _panelSummaryFromStdout(Object? stdout) {
    if (stdout is! String || stdout.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) return null;
      final panel = decoded['panel'];
      if (panel is! Map) return null;
      return <String, Object?>{
        if (panel['id'] != null) 'id': panel['id'],
        if (panel['title'] != null) 'title': panel['title'],
        if (panel['type'] != null) 'type': panel['type'],
      };
    } catch (_) {
      return null;
    }
  }

  String _compactJsonForPrompt(Object? value, {required int maxChars}) {
    try {
      return _truncatePromptText(jsonEncode(value), maxChars);
    } catch (_) {
      return _truncatePromptText('$value', maxChars);
    }
  }

  String _truncatePromptText(Object? value, int maxChars) {
    final text = '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}…';
  }

  int _estimateTokens(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return 0;
    return (normalized.length / 4).ceil();
  }

  Future<void> _showChatSessionDialog() async {
    final colors = context.appColors;
    final prompt = await _buildNextRequestPreviewMarkdown();
    if (!mounted) return;
    var maxTokens = _maxOutputTokens;
    var temperature = _temperature;
    var enableThinking = _enableThinking;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> copyPreview() async {
                await Clipboard.setData(ClipboardData(text: prompt));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied next LLM request preview'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }

              void persistSettings() {
                _updateState({
                  'localModelMaxOutputTokens': maxTokens,
                  'localModelTemperature': temperature,
                  'localModelEnableThinking': enableThinking,
                });
              }

              return AlertDialog(
                title: Row(
                  children: [
                    const Expanded(child: Text('Chat session request')),
                    IconButton(
                      tooltip: 'Copy preview',
                      onPressed: () => unawaited(copyPreview()),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 760,
                  height: 640,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This is the prompt/context/tool list that will be sent with the next message.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 180,
                            child: TextFormField(
                              initialValue: '$maxTokens',
                              decoration: const InputDecoration(
                                labelText: 'Max output tokens',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final parsed = int.tryParse(value);
                                if (parsed == null) return;
                                setDialogState(() {
                                  maxTokens = parsed.clamp(128, 4096);
                                });
                                persistSettings();
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 180,
                            child: TextFormField(
                              initialValue: '$temperature',
                              decoration: const InputDecoration(
                                labelText: 'Temperature',
                                isDense: true,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (value) {
                                final parsed = double.tryParse(value);
                                if (parsed == null) return;
                                setDialogState(() {
                                  temperature = parsed.clamp(0.0, 2.0);
                                });
                                persistSettings();
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: enableThinking,
                                onChanged: (v) {
                                  setDialogState(() {
                                    enableThinking = v ?? false;
                                  });
                                  persistSettings();
                                },
                              ),
                              const Text('Thinking'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.border),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              prompt,
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _toggleMode() {
    _updateState({
      'mode': _mode == 'text' ? 'voice' : 'text',
      'isListening': false,
      'isSpeaking': false,
    });
  }

  // ── Debug logs dialog ─────────────────────────────────────────────────────

  Future<void> _showDebugLogsDialog() async {
    final colors = context.appColors;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              final sessions =
                  List<Map<String, dynamic>>.from(
                    _debugSessions,
                  ).reversed.toList();
              final active = _activeDebugSession;
              if (active != null &&
                  !sessions.any((s) => s['id'] == active['id'])) {
                sessions.insert(0, active);
              }
              return AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.bug_report_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('LLM Debug Logs')),
                    Text(
                      '${sessions.length} sessions',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 800,
                  height: 660,
                  child:
                      sessions.isEmpty
                          ? const Center(
                            child: Text(
                              'No LLM sessions yet.\nSend a message to see raw logs here.',
                              textAlign: TextAlign.center,
                            ),
                          )
                          : _DebugSessionListView(
                            sessions: sessions,
                            colors: colors,
                          ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      // Insert a fake simulation session with 5 tool calls
                      final now = DateTime.now();
                      final fake = <String, dynamic>{
                        'id': 'sim_${now.millisecondsSinceEpoch}',
                        'userMessage':
                            '[Simulation] Show weather + open browser',
                        'modelId': 'google/gemini-3.1-flash-lite-preview',
                        'modelProvider': 'openrouter',
                        'requestAt':
                            now
                                .subtract(const Duration(seconds: 8))
                                .toIso8601String(),
                        'promptSentAt':
                            now
                                .subtract(const Duration(seconds: 8))
                                .toIso8601String(),
                        'firstTokenAt':
                            now
                                .subtract(const Duration(milliseconds: 4800))
                                .toIso8601String(),
                        'completedAt':
                            now
                                .subtract(const Duration(milliseconds: 400))
                                .toIso8601String(),
                        'asr': {
                          'durationMs': 1240,
                          'status': 'ok',
                          'mode': 'cloud',
                          'transcriptChars': 34,
                          'model': 'google/chirp-3',
                          'provider': 'openrouter',
                        },
                        'maxTokens': null,
                        'temperature': null,
                        'toolCalls': [
                          {
                            'name': 'panel:focus',
                            'arguments': {
                              'board': 'board-1778878703064560',
                              'panel': 'Список покупок',
                            },
                            'startAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 7200),
                                    )
                                    .toIso8601String(),
                            'endAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 6800),
                                    )
                                    .toIso8601String(),
                            'success': true,
                          },
                          {
                            'name': 'web:open',
                            'arguments': {
                              'board': 'board-1778878703064560',
                              'panel': '__yolo_badge__',
                              'url':
                                  'https://www.google.com/search?q=weather+in+Grodno',
                            },
                            'startAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 6600),
                                    )
                                    .toIso8601String(),
                            'endAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 5900),
                                    )
                                    .toIso8601String(),
                            'success': true,
                          },
                          {
                            'name': 'panels',
                            'arguments': {'board': 'board-1778878703064560'},
                            'startAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 5700),
                                    )
                                    .toIso8601String(),
                            'endAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 5200),
                                    )
                                    .toIso8601String(),
                            'success': true,
                          },
                          {
                            'name': 'panel:create',
                            'arguments': {
                              'board': 'board-1778878703064560',
                              'type': 'board.webpage',
                              'title': 'Weather in Grodno',
                            },
                            'startAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 5000),
                                    )
                                    .toIso8601String(),
                            'endAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 3800),
                                    )
                                    .toIso8601String(),
                            'success': true,
                          },
                          {
                            'name': 'agent:run',
                            'arguments': {
                              'agent': 'copilot',
                              'path': '.',
                              'task': 'Write a Hello World program',
                            },
                            'startAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 3600),
                                    )
                                    .toIso8601String(),
                            'endAt':
                                now
                                    .subtract(
                                      const Duration(milliseconds: 1200),
                                    )
                                    .toIso8601String(),
                            'success': true,
                          },
                        ],
                      };
                      _debugSessions.add(fake);
                      setDialogState(() {});
                    },
                    child: const Text('Simulate'),
                  ),
                  TextButton(
                    onPressed: () {
                      _debugSessions.clear();
                      setDialogState(() {});
                    },
                    child: const Text('Clear'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Skills ────────────────────────────────────────────────────────────────

  void _addSkill(String skill) {
    final skills = List<String>.from(_activeSkills);
    if (!skills.contains(skill)) {
      skills.add(skill);
      _updateState({'activeSkills': skills});
    }
  }

  void _removeSkill(String skill) {
    final skills = List<String>.from(_activeSkills);
    skills.remove(skill);
    _updateState({'activeSkills': skills});
  }

  void _showAddSkillSheet() {
    final available =
        _allSkills.where((s) => !_activeSkills.contains(s)).toList();
    showModalBottomSheet<void>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add Skill',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('All skills are active'),
                  )
                else
                  ...available.map(
                    (s) => ListTile(
                      title: Text(s),
                      leading: const Icon(Icons.add_circle_outline, size: 20),
                      onTap: () {
                        _addSkill(s);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Set<String> _disabledLocalTools() =>
      _disabledLocalToolNames.map((name) => name.trim()).toSet();

  int _enabledLocalToolCount() =>
      YoloitCliToolCatalog.tools.length - _disabledLocalTools().length;

  void _showToolsDialog() {
    final colors = context.appColors;
    final muted =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withAlpha(153);
    var disabled = _disabledLocalTools();
    final tools = [...YoloitCliToolCatalog.tools]..sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      return byGroup == 0 ? a.command.compareTo(b.command) : byGroup;
    });

    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              void persist(Set<String> next) {
                disabled = {...next};
                final sorted = disabled.toList()..sort();
                _updateState({'disabledLocalToolNames': sorted});
              }

              Widget tile(YoloitCliTool tool) {
                final enabled = !disabled.contains(tool.functionName);
                return CheckboxListTile(
                  dense: true,
                  value: enabled,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    final next = {...disabled};
                    if (value == true) {
                      next.remove(tool.functionName);
                    } else {
                      next.add(tool.functionName);
                    }
                    setDialogState(() => persist(next));
                  },
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'yoloit ${tool.command}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (tool.destructive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withAlpha(28),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'destructive',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${tool.functionName}\n${tool.description}',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                );
              }

              final grouped = <String, List<YoloitCliTool>>{};
              for (final tool in tools) {
                grouped.putIfAbsent(tool.group, () => []).add(tool);
              }

              return AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.settings_input_component_outlined),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('YoLo tools')),
                    Text(
                      '${tools.length - disabled.length}/${tools.length}',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 720,
                  height: 560,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Checked tools are available to YoLo Chat. Unchecked tools are hidden from the local LLM and blocked at runtime.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final entry in grouped.entries) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  bottom: 4,
                                ),
                                child: Text(
                                  entry.key.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: colors.primary,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              ...entry.value.map(tile),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => setDialogState(() => persist(<String>{})),
                    child: const Text('Enable all'),
                  ),
                  TextButton(
                    onPressed: () {
                      final next = {
                        for (final tool in tools) tool.functionName,
                      };
                      setDialogState(() => persist(next));
                    },
                    child: const Text('Disable all'),
                  ),
                  TextButton(
                    onPressed: () {
                      final next = {
                        for (final tool in tools)
                          if (tool.destructive) tool.functionName,
                      };
                      setDialogState(() => persist(next));
                    },
                    child: const Text('Disable destructive'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _mode == 'voice' ? _buildVoiceMode() : _buildTextMode();
  }

  // ── Text (chat) mode ──────────────────────────────────────────────────────

  Widget _buildTextMode() {
    final colors = context.appColors;
    return Column(
      children: [
        _buildSessionBar(colors),
        Expanded(child: _buildMessageList(colors)),
        _buildInputBar(colors),
      ],
    );
  }

  Widget _buildSessionBar(AppColorScheme colors) {
    final msgCount = _messages.length;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border.withAlpha(40))),
      ),
      child: Row(
        children: [
          // Session info
          Text(
            '$msgCount msgs',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          const Spacer(),
          // History
          _SessionBarButton(
            icon: Icons.history,
            tooltip: 'Session history',
            onTap: () => _showHistoryDialog(context),
          ),
          const SizedBox(width: 4),
          // New session
          _SessionBarButton(
            icon: Icons.add_circle_outline,
            tooltip: 'New session',
            onTap: _newSession,
          ),
          const SizedBox(width: 4),
          // Clear
          _SessionBarButton(
            icon: Icons.delete_outline,
            tooltip: 'Clear chat',
            onTap: _clearSession,
          ),
        ],
      ),
    );
  }

  void _newSession() {
    // Persist current session before starting a new one.
    _persistToHistory();
    _chatProvider?.dispose();
    _chatProvider = null;
    _chatProviderType = null;
    // Reset session tracking so a fresh ID is generated for the new session.
    _assistantSessionId = null;
    _assistantSessionCreatedAt = null;
    _updateState({
      'messages': <dynamic>[],
      'lastUsage': null,
      'opencodeSessionId': null,
    });
    setState(() {});
  }

  void _clearSession() {
    _chatProvider?.dispose();
    _chatProvider = null;
    _chatProviderType = null;
    _assistantSessionId = null;
    _assistantSessionCreatedAt = null;
    _updateState({'messages': <dynamic>[], 'lastUsage': null});
    setState(() {});
  }

  /// Generates a stable session ID for this conversation. The ID is kept in
  /// memory; a new one is created each time _newSession / _clearSession resets.
  String _getOrCreateSessionId() {
    _assistantSessionId ??= 'yolo-${DateTime.now().millisecondsSinceEpoch}';
    _assistantSessionCreatedAt ??= DateTime.now();
    return _assistantSessionId!;
  }

  /// Persists the current messages to [ChatSessionHistory] so the user can
  /// browse and restore past yolo chat sessions.
  void _persistToHistory() {
    final msgs = _messageDraft ?? _messages;
    if (msgs.isEmpty) return;
    final sessionId = _getOrCreateSessionId();
    final createdAt = _assistantSessionCreatedAt ?? DateTime.now();

    // Derive a short name from the first user message.
    final firstUserMsg = msgs.firstWhere(
      (m) => m['role'] == 'user',
      orElse: () => <String, dynamic>{},
    );
    final firstText = (firstUserMsg['content'] as String? ?? '').trim();
    final rawName =
        firstText.length > 60 ? firstText.substring(0, 60) : firstText;
    final sessionName =
        rawName.isEmpty ? 'Yolo session' : rawName.replaceAll('\n', ' ');

    final providerType = _chatProviderType ?? 'local';
    final modelLabel =
        providerType.startsWith('cloud:')
            ? (_chatProvider is CloudLlmProvider
                ? (_chatProvider as CloudLlmProvider).config?.model ??
                    providerType
                : providerType)
            : 'local';

    final entry = ChatSessionEntry(
      id: sessionId,
      sessionName: sessionName,
      provider: providerType,
      model: modelLabel,
      workingDir: '',
      createdAt: createdAt,
      lastMessageAt: DateTime.now(),
      messageCount: msgs.where((m) => m['role'] != 'tool').length,
    );
    ChatSessionHistory.instance.upsert(entry, messages: msgs.cast());
  }

  Future<void> _showHistoryDialog(BuildContext context) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder:
          (_) => _AssistantHistoryDialog(currentSessionId: _assistantSessionId),
    );
    if (result != null && mounted) {
      // Restore messages and start a new session ID.
      _assistantSessionId = null;
      _assistantSessionCreatedAt = null;
      _chatProvider?.dispose();
      _chatProvider = null;
      _chatProviderType = null;
      _updateState({'messages': result, 'lastUsage': null});
      setState(() {});
    }
  }

  Widget _buildSkillsBar(AppColorScheme colors) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          children: [
            ..._activeSkills.map(
              (skill) => Padding(
                padding: const EdgeInsets.only(right: 6, top: 10, bottom: 10),
                child: InputChip(
                  label: Text(skill, style: const TextStyle(fontSize: 11)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeSkill(skill),
                  backgroundColor: colors.primary.withAlpha(25),
                  selectedColor: colors.primary.withAlpha(50),
                  side: BorderSide(color: colors.primary.withAlpha(60)),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: ActionChip(
                avatar: const Icon(Icons.add, size: 14),
                label: const Text('Add', style: TextStyle(fontSize: 11)),
                onPressed: _showAddSkillSheet,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(AppColorScheme colors) {
    final msgs = _messages;
    if (msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 30,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(76),
            ),
            const SizedBox(height: 10),
            Text(
              'Send a message to start',
              style: TextStyle(
                fontSize: 13,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: msgs.length,
      itemBuilder: (_, i) => _buildMessageBubble(msgs[i], colors),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, AppColorScheme colors) {
    final isUser = msg['role'] == 'user';
    final isTool = msg['role'] == 'tool';
    final content = (msg['content'] as String? ?? '').trim();
    // Strip voice prefix from display (prefix is kept in LLM context but hidden in UI)
    final displayContent =
        isUser && content.startsWith('[Voice message')
            ? content.substring(content.indexOf('\n') + 1).trim()
            : content;
    final showThinking = !isUser && content.isEmpty && _isGeneratingReply;
    final containsMermaid = content.contains('```mermaid');
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final codeBg = colors.surface;
    if (isTool) {
      final success = msg['success'] as bool? ?? true;
      final toolName = msg['toolName'] as String? ?? 'tool';
      final args = _compactJsonForPrompt(msg['arguments'], maxChars: 420);
      final rawResult = msg['rawResult'] as String?;
      final result = _compactToolResultForPrompt(rawResult);
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color:
                success
                    ? colors.accentGreen.withAlpha(20)
                    : Theme.of(context).colorScheme.error.withAlpha(24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  success
                      ? colors.accentGreen.withAlpha(85)
                      : Theme.of(context).colorScheme.error.withAlpha(80),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                success
                    ? Icons.build_circle_outlined
                    : Icons.error_outline_rounded,
                size: 16,
                color:
                    success
                        ? colors.accentGreen
                        : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  '$toolName\nargs: $args\n$content\nresult: $result',
                  style: TextStyle(fontSize: 11, color: textColor, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 6,
        bottom: 2,
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress:
              content.isEmpty
                  ? null
                  : () => unawaited(_copyMessageToClipboard(content)),
          child: Container(
            constraints: BoxConstraints(maxWidth: containsMermaid ? 740 : 460),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient:
                  isUser
                      ? LinearGradient(
                        colors: [colors.accentBlue, colors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                      : null,
              color: isUser ? null : colors.surfaceElevated,
              borderRadius:
                  isUser
                      ? const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      )
                      : const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
            ),
            child:
                showThinking
                    ? _AssistantThinkingIndicator(
                      color:
                          Theme.of(context).textTheme.bodyMedium?.color ??
                          Theme.of(context).colorScheme.onSurface,
                    )
                    : isUser
                    ? SelectableText(
                      displayContent,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                        height: 1.4,
                      ),
                    )
                    : containsMermaid
                    ? MarkdownDocumentPreview(content: content)
                    : MarkdownBody(
                      data: content,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 13,
                          color: textColor,
                          height: 1.5,
                        ),
                        a: TextStyle(
                          fontSize: 13,
                          color: colors.primary,
                          decoration: TextDecoration.underline,
                        ),
                        code: TextStyle(
                          fontSize: 11.5,
                          color: colors.terminalPrompt,
                          backgroundColor: codeBg,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: codeBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.border),
                        ),
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(AppColorScheme colors) {
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final hintColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withAlpha(153);
    return Container(
      margin: const EdgeInsets.fromLTRB(1.5, 0, 1.5, 1.5),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Voice mode toggle
          GestureDetector(
            onTap: _toggleMode,
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.graphic_eq, size: 14, color: colors.primary),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showToolsDialog,
            child: Tooltip(
              message:
                  'YoLo tools (${_enabledLocalToolCount()}/${YoloitCliToolCatalog.tools.length} enabled)',
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      _disabledLocalToolNames.isEmpty
                          ? null
                          : Border.all(color: colors.primary.withAlpha(100)),
                ),
                child: Icon(
                  Icons.settings_input_component_outlined,
                  size: 14,
                  color: colors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => unawaited(_showChatSessionDialog()),
            child: Tooltip(
              message: 'Preview next LLM request',
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.manage_search_outlined,
                  size: 15,
                  color: colors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Debug logs button
          GestureDetector(
            onTap: () => unawaited(_showDebugLogsDialog()),
            child: Tooltip(
              message: 'LLM debug logs (${_debugSessions.length} sessions)',
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      _isGeneratingReply
                          ? Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withAlpha(120),
                          )
                          : null,
                ),
                child: Icon(
                  Icons.bug_report_outlined,
                  size: 15,
                  color:
                      _isGeneratingReply
                          ? Theme.of(context).colorScheme.error
                          : colors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Copy full chat log to clipboard
          GestureDetector(
            onTap: () => unawaited(_copyFullLogsToClipboard()),
            child: Tooltip(
              message: 'Copy chat log to clipboard',
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.content_copy_outlined,
                  size: 15,
                  color: colors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final isEnter =
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (isEnter && !HardwareKeyboard.instance.isShiftPressed) {
                  unawaited(_sendMessage());
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                style: TextStyle(fontSize: 13, color: textColor, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Ask YoLo…',
                  hintStyle: TextStyle(fontSize: 13, color: hintColor),
                  filled: true,
                  fillColor: colors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.primary, width: 0.8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                maxLines: 4,
                minLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Microphone button — tap to start recording, tap again to stop & send
          GestureDetector(
            onTap:
                _isTranscribingMic
                    ? null
                    : () => unawaited(
                      _isRecordingMic
                          ? _stopAndSendMic()
                          : _startPushToTalkMic(),
                    ),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _isRecordingMic
                    ? Icons.mic_rounded
                    : (_isTranscribingMic
                        ? Icons.hourglass_top_rounded
                        : Icons.mic_none),
                size: 15,
                color:
                    _isRecordingMic
                        ? Theme.of(context).colorScheme.error
                        : colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Stop button (during generation) / Send button
          GestureDetector(
            onTap:
                _isGeneratingReply
                    ? _stopGeneration
                    : () => unawaited(_sendMessage()),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color:
                    _isGeneratingReply
                        ? Theme.of(context).colorScheme.error
                        : colors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _isGeneratingReply ? Icons.stop_rounded : Icons.arrow_upward,
                color: colors.textPrimary,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Voice mode ────────────────────────────────────────────────────────────

  Widget _buildVoiceMode() {
    final colors = context.appColors;

    VoiceVisualizerState vizState;
    String label;
    if (_isListening) {
      vizState = VoiceVisualizerState.listening;
      label = 'Listening…';
    } else if (_isSpeaking) {
      vizState = VoiceVisualizerState.speaking;
      label = 'Speaking…';
    } else {
      vizState = VoiceVisualizerState.idle;
      label = 'Tap to speak';
    }

    return Column(
      children: [
        _buildSkillsBar(colors),
        Expanded(
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Voice-to-Voice coming soon'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AssistantVoiceVisualizer(
                    state: vizState,
                    colors: colors,
                    size: 160,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colors.primary.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: TextButton.icon(
            onPressed: _toggleMode,
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('Back to text'),
            style: TextButton.styleFrom(foregroundColor: colors.primary),
          ),
        ),
      ],
    );
  }

  Future<void> _startPushToTalkMic() async {
    if (_isRecordingMic || _isTranscribingMic || _isStartingMic) return;
    _stopMicAfterStart = false;
    _isStartingMic = true;
    try {
      await _startRecordingFromMic();
    } finally {
      _isStartingMic = false;
    }
    if (_stopMicAfterStart && mounted && _isRecordingMic) {
      _stopMicAfterStart = false;
      await _stopRecordingAndTranscribe(sendAfterTranscription: true);
    }
  }

  Future<void> _finishPushToTalkMic() async {
    if (_isTranscribingMic) return;
    if (_isStartingMic) {
      _stopMicAfterStart = true;
      return;
    }
    if (_isRecordingMic) {
      await _stopRecordingAndTranscribe(sendAfterTranscription: true);
    }
  }

  /// Stops recording and sends immediately (tap-to-toggle mic behaviour).
  Future<void> _stopAndSendMic() async {
    if (_isTranscribingMic || !_isRecordingMic) return;
    await _stopRecordingAndTranscribe(sendAfterTranscription: true);
  }

  Future<void> _startRecordingFromMic() async {
    final voiceSettings =
        await CloudLlmSettingsService.instance.loadVoiceSettings();
    if (!voiceSettings.useCloudAsr) {
      await LocalAiModelsService.instance.initialize();
      if (!LocalAiModelsService.instance.hasSelectedAsrInstalled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Install ASR model first. Opening Settings → AI Models…',
            ),
            duration: Duration(seconds: 2),
          ),
        );
        await SettingsPage.show(context, initialCategory: 'AI Models');
        return;
      }
    }

    final nativeGranted =
        await MicrophonePermissionService.instance.ensureGranted();
    if (!nativeGranted) {
      if (!mounted) return;
      await _showMicrophonePermissionHint();
      return;
    }

    final granted = await _micRecorder.hasPermission();
    if (!granted) {
      if (!mounted) return;
      await _showMicrophonePermissionHint();
      return;
    }

    try {
      _micStreamBytes = BytesBuilder(copy: false);
      final stream = await _micRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _micStreamSub = stream.listen(
        (chunk) => _micStreamBytes?.add(chunk),
        onError: (_) {},
        cancelOnError: false,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      final stillNoPermission = !await _micRecorder.hasPermission();
      if (!mounted) return;
      if (stillNoPermission) {
        await _showMicrophonePermissionHint();
        return;
      }
      await _showCopyableErrorDialog(
        title: 'Microphone error',
        message: 'Failed to start microphone:\n$e',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isRecordingMic = true);
    // Stream real mic amplitude to the overlay waveform.
    _amplitudeSub?.cancel();
    _amplitudeSub = _micRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 60))
        .listen((amp) {
          // dBFS: 0 = max, ~-50 = silence for speech. Normalize to 0..1.
          final normalized = ((amp.current + 50.0) / 50.0).clamp(0.0, 1.0);
          widget.controller?._micAmplitudeCtrl.add(normalized);
        });
    _syncOverlayState(hiddenOverride: false);
  }

  Future<void> _stopRecordingAndTranscribe({
    bool sendAfterTranscription = false,
    bool mirrorToOverlay = false,
  }) async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    // Stop stream recording and collect buffered PCM bytes.
    await _micRecorder.stop();
    await _micStreamSub?.cancel();
    _micStreamSub = null;
    final pcmBytes = _micStreamBytes?.takeBytes();
    _micStreamBytes = null;

    // Build WAV from raw PCM (16-bit mono 16 kHz).
    final wavBytes =
        pcmBytes != null && pcmBytes.isNotEmpty
            ? _buildWavFromPcm(pcmBytes)
            : null;

    if (!mounted) return;
    setState(() {
      _isRecordingMic = false;
      _isTranscribingMic = true;
    });
    _syncOverlayState(hiddenOverride: _voiceOverlayHidden);

    final voiceSettings =
        await CloudLlmSettingsService.instance.loadVoiceSettings();
    final asrMode =
        !voiceSettings.useCloudAsr
            ? 'local'
            : voiceSettings.useChatModelForCloudAsr
            ? 'direct_audio'
            : 'cloud';
    // Resolve the effective ASR model for debug display (mirrors CloudAsrService logic).
    String? asrResolvedModel;
    String? asrProviderName;
    if (voiceSettings.useCloudAsr) {
      if (!voiceSettings.useChatModelForCloudAsr &&
          voiceSettings.cloudAsrModel?.trim().isNotEmpty == true) {
        asrResolvedModel = voiceSettings.cloudAsrModel!.trim();
      }
      // Load config to get provider name + fallback model.
      final explicitId =
          voiceSettings.useChatModelForCloudAsr
              ? null
              : voiceSettings.cloudAsrConfigId?.trim();
      final asrCfg =
          (explicitId != null && explicitId.isNotEmpty
              ? await CloudLlmSettingsService.instance.loadConfigById(
                explicitId,
              )
              : null) ??
          await CloudLlmSettingsService.instance.loadActiveConfig();
      asrResolvedModel ??= asrCfg?.model.trim();
      asrProviderName = asrCfg?.name;
    }
    final asrStartedAt = DateTime.now().toIso8601String();
    final asrStopwatch = Stopwatch()..start();
    var asrStatus = 'ok';
    var asrTranscriptChars = 0;
    String? asrError;

    // For local ASR we still need a temp file path (local ASR reads from disk).
    // Cloud ASR uses bytes directly.
    String? tempPath;
    if (wavBytes != null && !voiceSettings.useCloudAsr) {
      tempPath =
          '${Directory.systemTemp.path}/yoloit_asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    var shouldSend = false;
    try {
      if (wavBytes == null || wavBytes.isEmpty) {
        asrStatus = 'no_audio';
        return;
      }

      if (voiceSettings.useCloudAsr && voiceSettings.useChatModelForCloudAsr) {
        // ── Direct audio → chat model: attach audio as message content ──────
        // Optionally convert WAV → MP3 to reduce payload size.
        var audioBytes = wavBytes;
        var audioFormat = 'wav';
        int? conversionMs;
        if (voiceSettings.convertWavToMp3) {
          try {
            final convSw = Stopwatch()..start();
            final tmpWav =
                '${Directory.systemTemp.path}/yoloit_direct_${DateTime.now().millisecondsSinceEpoch}.wav';
            final tmpMp3 = tmpWav.replaceAll('.wav', '.mp3');
            await File(tmpWav).writeAsBytes(wavBytes, flush: true);
            final result = await Process.run('ffmpeg', [
              '-i',
              tmpWav,
              '-codec:a',
              'libmp3lame',
              '-qscale:a',
              '4',
              '-y',
              tmpMp3,
            ]);
            convSw.stop();
            conversionMs = convSw.elapsedMilliseconds;
            if (result.exitCode == 0 && File(tmpMp3).existsSync()) {
              audioBytes = await File(tmpMp3).readAsBytes();
              audioFormat = 'mp3';
            }
            // Clean up temp files
            try {
              File(tmpWav).deleteSync();
            } catch (_) {}
            try {
              File(tmpMp3).deleteSync();
            } catch (_) {}
          } on ProcessException {
            // ffmpeg not available — fall back to WAV
          }
        }
        _pendingAudioContent = [
          {
            'type': 'input_audio',
            'input_audio': {
              'data': base64Encode(audioBytes),
              'format': audioFormat,
            },
          },
        ];
        if (conversionMs != null) {
          _pendingAsrConversionMs = conversionMs;
        }
        if (!mounted) return;
        _syncOverlayState(hiddenOverride: _voiceOverlayHidden);
        shouldSend = sendAfterTranscription;
        asrStatus = 'ok';
        asrTranscriptChars = -1; // sentinel: audio sent directly
      } else if (voiceSettings.useCloudAsr) {
        // ── Cloud ASR: transcribe with ASR model, then put text in field ────
        final transcript = await _cloudAsrService.transcribeFromBytes(
          audioBytes: wavBytes,
          voiceSettings: voiceSettings,
        );
        if (!mounted) return;
        final text = transcript.trim();
        asrTranscriptChars = text.length;
        if (text.isNotEmpty) {
          final current = _inputController.text.trim();
          _inputController.text =
              current.isEmpty ? text : '$current ${text.trim()}';
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
          _syncOverlayState(hiddenOverride: _voiceOverlayHidden);
          shouldSend = sendAfterTranscription;
        }
      } else {
        // ── Local ASR: needs a file on disk — write WAV once ─────────────────
        if (tempPath != null) {
          await File(tempPath).writeAsBytes(wavBytes, flush: true);
        }
        final transcript = await LocalAiModelsService.instance
            .transcribeWithSelectedAsr(tempPath ?? '');

        if (!mounted) return;
        final text = transcript.trim();
        asrTranscriptChars = text.length;
        if (text.isNotEmpty) {
          final current = _inputController.text.trim();
          _inputController.text =
              current.isEmpty ? text : '$current ${text.trim()}';
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
          _syncOverlayState(hiddenOverride: _voiceOverlayHidden);
          shouldSend = sendAfterTranscription;
        }
      }
    } catch (e) {
      asrStatus = 'error';
      asrError = '$e';
      if (!mounted) return;
      await _showCopyableErrorDialog(
        title: 'ASR error',
        message: 'ASR failed:\n$e',
      );
    } finally {
      asrStopwatch.stop();
      final completedAt = DateTime.now().toIso8601String();
      _pendingAsrDebug = {
        'mode': asrMode,
        'status': asrStatus,
        'startedAt': asrStartedAt,
        'completedAt': completedAt,
        'durationMs': asrStopwatch.elapsedMilliseconds,
        'transcriptChars': asrTranscriptChars,
        if (asrResolvedModel != null) 'model': asrResolvedModel,
        if (asrProviderName != null) 'provider': asrProviderName,
        if (asrError != null) 'error': asrError,
      };
      // Save a persistent copy for ASR benchmarking.
      if (wavBytes != null && wavBytes.isNotEmpty) {
        try {
          final samplesDir = Directory(
            '${PlatformDirs.instance.dataDir}/asr_samples',
          );
          if (!samplesDir.existsSync()) {
            samplesDir.createSync(recursive: true);
          }
          final ts = DateTime.now().millisecondsSinceEpoch;
          final sampleWav = '${samplesDir.path}/$ts.wav';
          // Reuse already-written temp file if available, otherwise write from bytes.
          if (tempPath != null && File(tempPath).existsSync()) {
            await File(tempPath).copy(sampleWav);
          } else {
            await File(sampleWav).writeAsBytes(wavBytes, flush: true);
          }
          // Companion metadata JSON — useful for replay benchmarks.
          final transcript =
              asrTranscriptChars > 0 ? (_inputController.text.trim()) : '';
          final meta = {
            'recordedAt': asrStartedAt,
            'completedAt': completedAt,
            'durationMs': asrStopwatch.elapsedMilliseconds,
            'asrMode': asrMode,
            'asrStatus': asrStatus,
            if (asrResolvedModel != null) 'asrModel': asrResolvedModel,
            if (asrProviderName != null) 'asrProvider': asrProviderName,
            'transcript': transcript,
            'transcriptChars': asrTranscriptChars,
            if (asrError != null) 'error': asrError,
          };
          await File(
            '${samplesDir.path}/$ts.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(meta));
        } on Exception {
          // Best-effort — never block the main flow.
        }
      }
      // Delete the temp file used for local ASR (if written).
      if (tempPath != null) {
        try {
          final f = File(tempPath);
          if (f.existsSync()) await f.delete();
        } on FileSystemException {
          // ignore
        }
      }
      if (mounted) {
        setState(() => _isTranscribingMic = false);
        // If we are about to send the message, keep the overlay in 'processing'
        // to avoid a visual bounce: processing → idle → processing.
        _syncOverlayState(
          forcedStatus: shouldSend ? 'processing' : null,
          hiddenOverride: _voiceOverlayHidden,
        );
      }
    }
    if (shouldSend && mounted) {
      if (_pendingAudioContent != null ||
          _inputController.text.trim().isNotEmpty) {
        if (mirrorToOverlay) {
          await Future<void>.delayed(const Duration(milliseconds: 850));
          if (!mounted) return;
        }
        await _sendMessage(mirrorToOverlay: mirrorToOverlay);
      }
    }
  }

  Future<void> _cancelRecordingFromMic() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (!_isRecordingMic) {
      _resetVoiceOverlay();
      return;
    }
    await _micRecorder.stop();
    await _micStreamSub?.cancel();
    _micStreamSub = null;
    _micStreamBytes = null;
    if (!mounted) return;
    setState(() {
      _isRecordingMic = false;
      _isTranscribingMic = false;
    });
    _inputController.clear();
    _resetVoiceOverlay();
  }

  /// Builds a standard WAV file from raw PCM-16bit mono 16kHz bytes.
  static Uint8List _buildWavFromPcm(Uint8List pcm) {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final fileSize = 36 + dataSize; // RIFF chunk size

    final header = ByteData(44);
    // RIFF chunk
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // chunk size = 16 for PCM
    header.setUint16(20, 1, Endian.little); // PCM = 1
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcm);
    return wav;
  }

  Future<void> _copyMessageToClipboard(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _copyFullLogsToClipboard() async {
    final buf = StringBuffer();
    buf.writeln('=== YoLoIT Chat Logs ===');
    buf.writeln('Messages: ${_messages.length}');
    buf.writeln('');
    for (final msg in _messages) {
      final role = msg['role'] ?? 'unknown';
      final content = msg['content'] as String? ?? '';
      buf.writeln('--- [$role] ---');
      buf.writeln(content);
      final toolCalls = msg['toolCalls'] as List<dynamic>?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        for (final tc in toolCalls) {
          if (tc is Map) {
            buf.writeln('  [tool] ${tc['toolName']}(${tc['arguments']})');
            if (tc['result'] != null) buf.writeln('  [result] ${tc['result']}');
          }
        }
      }
      buf.writeln('');
    }
    // Also append debug session data if available.
    if (_debugSessions.isNotEmpty) {
      buf.writeln('=== LLM Debug Sessions ===');
      for (final dbg in _debugSessions) {
        buf.writeln('User: ${dbg['userMessage'] ?? ''}');
        if (dbg['error'] != null) buf.writeln('ERROR: ${dbg['error']}');
        final resp = dbg['response'] as String? ?? '';
        if (resp.isNotEmpty) {
          buf.writeln(
            'Response: ${resp.substring(0, resp.length.clamp(0, 500))}',
          );
        }
        buf.writeln('');
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full chat log copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showCopyableErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(child: SelectableText(message)),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied error text'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Future<void> _showMicrophonePermissionHint() async {
    if (!mounted) return;
    final appName = await MicrophonePermissionService.instance.displayName();
    final bundleId =
        await MicrophonePermissionService.instance.bundleIdentifier();
    final resetCommand = 'tccutil reset Microphone $bundleId';
    final status = await MicrophonePermissionService.instance.status();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Microphone access required'),
            content: SizedBox(
              width: 560,
              child: SelectableText(
                'YoLoIT needs microphone access to record audio for local ASR.\n\n'
                'App shown to macOS: $appName\n'
                'Bundle id: $bundleId\n'
                'macOS status: $status\n\n'
                'If the system prompt does not appear, macOS has already saved a decision for this exact debug bundle. '
                'Open Privacy & Security → Microphone and enable $appName. If it is missing from the list, reset the saved decision and press Request again:\n\n'
                '$resetCommand',
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final granted =
                      await MicrophonePermissionService.instance
                          .ensureGranted();
                  if (!mounted) return;
                  if (granted) {
                    Navigator.of(dialogContext).pop();
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Microphone is still not allowed by macOS'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.mic_outlined, size: 18),
                label: const Text('Request again'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: resetCommand));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied reset command'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copy reset command'),
              ),
              TextButton.icon(
                onPressed:
                    () => unawaited(() async {
                      final opened =
                          await MicrophonePermissionService.instance
                              .openSettings();
                      if (!opened) {
                        await PlatformLauncher.instance.openUrl(
                          'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
                        );
                      }
                    }()),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  String _formatAssistantError(Object error) {
    final raw = error.toString();
    if (raw.contains('flm_dispatch_json')) {
      return 'Local model runtime mismatch: missing symbol "flm_dispatch_json". '
          'Please update/reinstall the selected local model runtime in Settings → AI Models, then restart YoLoIT.';
    }
    return 'Error: $raw';
  }
}

class _SessionBarButton extends StatelessWidget {
  const _SessionBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _AssistantThinkingIndicator extends StatefulWidget {
  const _AssistantThinkingIndicator({required this.color});

  final Color color;

  @override
  State<_AssistantThinkingIndicator> createState() =>
      _AssistantThinkingIndicatorState();
}

class _AssistantThinkingIndicatorState
    extends State<_AssistantThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final opacity = (0.3 + 0.7 * (1.0 - (t * 2 - 1).abs())).clamp(
              0.3,
              1.0,
            );
            return Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Debug session list/detail view ────────────────────────────────────────

class _DebugSessionListView extends StatefulWidget {
  const _DebugSessionListView({required this.sessions, required this.colors});

  final List<Map<String, dynamic>> sessions;
  final AppColorScheme colors;

  @override
  State<_DebugSessionListView> createState() => _DebugSessionListViewState();
}

class _DebugSessionListViewState extends State<_DebugSessionListView> {
  int _selectedIndex = 0;
  String _selectedTab = 'timings';

  static const _tabs = ['timings', 'messages', 'tools', 'raw output'];

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final colors = widget.colors;
    final session = sessions.isEmpty ? null : sessions[_selectedIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Session list (left side)
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Sessions (newest first)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final isActive = s['completedAt'] == null;
                    final isSelected = i == _selectedIndex;
                    final userMsg = '${s['userMessage'] ?? ''}'.trim();
                    final short =
                        userMsg.length > 32
                            ? '${userMsg.substring(0, 32)}…'
                            : userMsg;
                    final ts = s['requestAt'] as String? ?? '';
                    final time = ts.length >= 19 ? ts.substring(11, 19) : ts;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? colors.primary.withAlpha(30)
                                  : colors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                isSelected
                                    ? colors.primary.withAlpha(80)
                                    : colors.border.withAlpha(40),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isActive)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.color,
                                    ),
                                  ),
                                ),
                                if (s['error'] != null)
                                  Icon(
                                    Icons.error_outline,
                                    size: 12,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              short,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Detail panel (right side)
        Expanded(
          child:
              session == null
                  ? const SizedBox.shrink()
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tab row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children:
                              _tabs.map((tab) {
                                final sel = tab == _selectedTab;
                                return GestureDetector(
                                  onTap:
                                      () => setState(() => _selectedTab = tab),
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      right: 6,
                                      bottom: 6,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          sel
                                              ? colors.primary.withAlpha(40)
                                              : colors.surfaceElevated,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            sel
                                                ? colors.primary
                                                : colors.border.withAlpha(60),
                                      ),
                                    ),
                                    child: Text(
                                      tab,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight:
                                            sel
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                        color:
                                            sel
                                                ? colors.primary
                                                : Theme.of(
                                                  context,
                                                ).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.border),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              _buildDetailText(session, _selectedTab),
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 11,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                final text = _buildDetailText(
                                  session,
                                  _selectedTab,
                                );
                                Clipboard.setData(ClipboardData(text: text));
                              },
                              icon: const Icon(Icons.copy_outlined, size: 14),
                              label: const Text('Copy'),
                              style: TextButton.styleFrom(
                                textStyle: const TextStyle(fontSize: 11),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
        ),
      ],
    );
  }

  String _buildDetailText(Map<String, dynamic> s, String tab) {
    switch (tab) {
      case 'timings':
        return _buildTimingsText(s);
      case 'messages':
        final msgs = s['messages'];
        if (msgs is List) {
          return const JsonEncoder.withIndent('  ').convert(msgs);
        }
        return '${s['prompt'] ?? '(not captured yet)'}';
      case 'tools':
        return _buildToolsText(s);
      case 'raw output':
        return _buildRawOutputText(s);
      default:
        return '';
    }
  }

  String _buildTimingsText(Map<String, dynamic> s) {
    final buf = StringBuffer();

    final asr = s['asr'] as Map?;
    final requestAt = _parseTs(s['requestAt']);
    final promptSentAt = _parseTs(s['promptSentAt']);
    final firstTokenAt = _parseTs(s['firstTokenAt']);
    final completedAt = _parseTs(s['completedAt']);
    final toolCalls =
        (s['toolCalls'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
        [];

    // ── helpers ──────────────────────────────────────────────────────────────
    String ms(int? v) => v != null ? '${v}ms' : '?';
    // Right-align a label/value row in a fixed 40-char line
    String row(String tag, String label, String? value) {
      final pad = (30 - label.length).clamp(1, 30);
      final dots = '.' * pad;
      return '$tag  $label$dots  ${value ?? '?'}';
    }

    // ── header ───────────────────────────────────────────────────────────────
    buf.writeln('User: ${s['userMessage'] ?? ''}');
    buf.writeln();
    // Model info line
    final modelId = s['modelId'] as String?;
    final modelProvider = s['modelProvider'] as String?;
    if (modelId != null) {
      final providerLabel = modelProvider != null ? '[$modelProvider]' : '';
      buf.writeln('Model: $modelId  $providerLabel'.trim());
      buf.writeln();
    }
    buf.writeln('══ Timeline ══════════════════════════════════');

    // ── [ASR] phase ──────────────────────────────────────────────────────────
    if (asr != null) {
      final asrMs = (asr['durationMs'] as num?)?.toInt();
      final asrStatus = asr['status'] as String? ?? '';
      final chars = asr['transcriptChars'] as num?;
      final mode = asr['mode'] as String? ?? '';
      final asrModel = asr['model'] as String?;
      final asrProvider = asr['provider'] as String?;
      final convMs = (asr['conversionMs'] as num?)?.toInt();
      final suffix = [
        if (asrStatus.isNotEmpty && asrStatus != 'ok') '($asrStatus)',
        if (mode.isNotEmpty) '[$mode]',
        if (chars != null) '$chars chars',
      ].join('  ');
      buf.writeln(row('[ASR]', 'audio → text', '${ms(asrMs)}  $suffix'.trim()));
      if (convMs != null) {
        buf.writeln(row('     ', '↳ wav→mp3 convert', ms(convMs)));
      }
      if (asrModel != null) {
        final provLabel = asrProvider != null ? '  [$asrProvider]' : '';
        buf.writeln(row('     ', '↳ model', '$asrModel$provLabel'));
      }
    }

    // ── [LLM] text → first token (TTFT) ──────────────────────────────────────
    final ttftMs =
        (promptSentAt != null && firstTokenAt != null)
            ? firstTokenAt.difference(promptSentAt).inMilliseconds
            : null;
    if (toolCalls.isNotEmpty) {
      buf.writeln(row('[LLM]', 'text → tools (TTFT)', ms(ttftMs)));
    } else {
      buf.writeln(row('[LLM]', 'text → first token (TTFT)', ms(ttftMs)));
    }

    // ── per-tool lines ────────────────────────────────────────────────────────
    DateTime? lastToolEnd;
    for (final tc in toolCalls) {
      final toolStart = _parseTs(tc['startAt'] as String?);
      final toolEnd = _parseTs(tc['endAt'] as String?);
      final durMs =
          (toolStart != null && toolEnd != null)
              ? toolEnd.difference(toolStart).inMilliseconds
              : null;
      final ok = tc['success'] as bool? ?? true;
      final name = tc['name'] as String? ?? '?';
      buf.writeln(row('[TOOL]', '↳ $name', '${ms(durMs)}  ${ok ? '✅' : '❌'}'));
      // Show up to 3 argument key=value pairs inline
      final args = tc['arguments'];
      if (args is Map && args.isNotEmpty) {
        var shown = 0;
        for (final entry in args.entries) {
          if (shown >= 3) break;
          final val = '${entry.value}';
          final truncVal = val.length > 40 ? '${val.substring(0, 37)}…' : val;
          buf.writeln(row('     ', '  ${entry.key}', truncVal));
          shown++;
        }
      }
      if (toolEnd != null) lastToolEnd = toolEnd;
    }

    // ── [LLM] tools → final response ─────────────────────────────────────────
    if (toolCalls.isNotEmpty && lastToolEnd != null && completedAt != null) {
      final finalMs = completedAt.difference(lastToolEnd).inMilliseconds;
      buf.writeln(row('[LLM]', 'tools → final message', ms(finalMs)));
    } else if (toolCalls.isEmpty &&
        firstTokenAt != null &&
        completedAt != null) {
      final genMs = completedAt.difference(firstTokenAt).inMilliseconds;
      buf.writeln(row('[LLM]', 'streaming response', ms(genMs)));
    }

    // ── totals ────────────────────────────────────────────────────────────────
    buf.writeln('──────────────────────────────────────────────');
    final asrMs = (asr?['durationMs'] as num?)?.toInt();
    if (asrMs != null && completedAt != null && promptSentAt != null) {
      final llmMs = completedAt.difference(promptSentAt).inMilliseconds;
      buf.writeln(row('     ', 'ASR + LLM total', ms(asrMs + llmMs)));
    }
    if (requestAt != null && completedAt != null) {
      final totalMs = completedAt.difference(requestAt).inMilliseconds;
      buf.writeln(row('     ', 'Wall time (total)', ms(totalMs)));
    }

    // ── error ─────────────────────────────────────────────────────────────────
    if (s['error'] != null) {
      buf.writeln();
      buf.writeln('❌ ERROR: ${s['error']}');
    }

    // ── Swift (MLX) section ───────────────────────────────────────────────────
    final swift = s['swiftTimings'] as Map?;
    if (swift != null) {
      buf.writeln();
      buf.writeln('══ MLX (Swift) ═══════════════════════════════');
      final cacheHit = swift['swiftCacheHit'];
      buf.writeln(
        row(
          '     ',
          'model cache',
          cacheHit == true
              ? 'HIT ✓'
              : cacheHit == false
              ? 'MISS (loaded)'
              : '-',
        ),
      );
      final loadMs = swift['swiftLoadMs'] as num?;
      if (loadMs != null)
        buf.writeln(row('     ', 'load time', ms(loadMs.toInt())));
      final ttft = swift['swiftFirstTokenMs'] as num?;
      if (ttft != null)
        buf.writeln(row('     ', 'first token (TTFT)', ms(ttft.toInt())));
      final genMs = swift['swiftGenerateMs'] as num?;
      if (genMs != null)
        buf.writeln(row('     ', 'generation', ms(genMs.toInt())));
      final totalMs = swift['swiftTotalMs'] as num?;
      if (totalMs != null)
        buf.writeln(row('     ', 'swift total', ms(totalMs.toInt())));
    }

    // ── model settings ────────────────────────────────────────────────────────
    buf.writeln();
    buf.writeln('══ Settings ══════════════════════════════════');
    buf.writeln(row('     ', 'maxTokens', '${s['maxTokens'] ?? '-'}'));
    buf.writeln(row('     ', 'temperature', '${s['temperature'] ?? '-'}'));

    return buf.toString();
  }

  String _buildToolsText(Map<String, dynamic> s) {
    final buf = StringBuffer();
    buf.writeln('=== Tool Schemas sent to LLM ===');
    buf.writeln();
    buf.writeln(s['toolSchemas'] ?? '(not captured yet)');
    buf.writeln();

    final toolCalls = s['toolCalls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      buf.writeln('=== Tool Calls (raw) ===');
      buf.writeln();
      for (final tc in toolCalls) {
        if (tc is Map) {
          buf.writeln('Tool: ${tc['name']}');
          buf.writeln('Start: ${tc['startAt']}  End: ${tc['endAt']}');
          buf.writeln('Arguments:');
          try {
            buf.writeln(
              const JsonEncoder.withIndent('  ').convert(tc['arguments']),
            );
          } catch (_) {
            buf.writeln('  ${tc['arguments']}');
          }
          buf.writeln('Result:');
          try {
            final res = tc['result'];
            final decoded = jsonDecode(res as String);
            buf.writeln(const JsonEncoder.withIndent('  ').convert(decoded));
          } catch (_) {
            buf.writeln('  ${tc['result']}');
          }
          buf.writeln();
        }
      }
    } else {
      buf.writeln('(no tool calls in this session)');
    }

    return buf.toString();
  }

  String _buildRawOutputText(Map<String, dynamic> s) {
    final buf = StringBuffer();
    buf.writeln('=== Raw Chunks Output (before stripping) ===');
    buf.writeln();
    buf.writeln(s['rawChunksOutput'] ?? '(not captured yet)');
    buf.writeln();
    buf.writeln('=== Raw Final Response ===');
    buf.writeln();
    buf.writeln(s['rawFinalResponse'] ?? '(not captured yet)');
    buf.writeln();
    if (s['cleanedResponse'] != null) {
      buf.writeln('=== Cleaned Response (after tool echo stripping) ===');
      buf.writeln();
      buf.writeln(s['cleanedResponse']);
    }
    return buf.toString();
  }

  DateTime? _parseTs(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
}

/// Wraps the base CLI tool executor with assistant-specific pre/post processing
/// (note retargeting, panel creation guard, focus after create).
class _AssistantToolExecutor implements YoloitToolExecutor {
  _AssistantToolExecutor({
    required this.delegate,
    required this.assistantPanelId,
    required this.assistantPanelTitle,
    required this.onFocusPanel,
  });

  final YoloitToolExecutor delegate;
  final String assistantPanelId;
  final String assistantPanelTitle;
  final Future<void> Function(Map<String, Object?> focusArgs) onFocusPanel;

  // Mutable per-message state — set before each sendMessage call.
  String? lastTargetNotePanelId;
  String userMessage = '';
  void Function(
    String toolCommand,
    Map<String, Object?> arguments,
    String result,
    bool success,
  )?
  onToolCompleted;

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
  }) async {
    final tool = YoloitCliToolCatalog.byFunctionName(functionName);
    final toolCommand = tool?.command ?? functionName;
    final mutableArgs = Map<String, Object?>.from(arguments);

    await _retargetPanelLookupToRealNoteIfNeeded(
      toolCommand,
      mutableArgs,
      runtimeContext,
    );

    // Retarget note tools to last known note panel.
    _retargetNoteToolIfNeeded(toolCommand, mutableArgs);

    // Guard: if note tool points to assistant panel, retarget to a real note panel.
    await _ensureNoteToolHasRealPanel(toolCommand, mutableArgs, runtimeContext);

    final result = await delegate.invoke(
      functionName,
      mutableArgs,
      runtimeContext: runtimeContext,
    );

    final success = _toolResultSucceeded(result);
    onToolCompleted?.call(toolCommand, mutableArgs, result, success);

    // Auto-focus newly created panels.
    if (toolCommand == 'panel:create' && success && runtimeContext != null) {
      final created = _createdPanelFromResult(result);
      if (created != null) {
        final board =
            '${mutableArgs['board'] ?? runtimeContext.boardId ?? runtimeContext.boardName ?? ''}'
                .trim();
        if (board.isNotEmpty) {
          await onFocusPanel({'board': board, 'panel': created.id});
        }
      }
    }

    return result;
  }

  void _retargetNoteToolIfNeeded(
    String toolCommand,
    Map<String, Object?> arguments,
  ) {
    if (toolCommand != 'note' && !toolCommand.startsWith('note:')) return;
    if (toolCommand == 'note:create') return;
    final lastPanelId = lastTargetNotePanelId?.trim();
    if (lastPanelId == null || lastPanelId.isEmpty) return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    final shouldRetarget =
        panel.isEmpty ||
        panel == assistantPanelId ||
        panel == assistantPanelTitle ||
        _mentionsPreviousNote(userMessage);
    if (shouldRetarget) {
      arguments['panel'] = lastPanelId;
    }
  }

  Future<void> _ensureNoteToolHasRealPanel(
    String toolCommand,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) async {
    if (toolCommand != 'note' && !toolCommand.startsWith('note:')) return;
    if (toolCommand == 'note:create') return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isEmpty ||
        panel == assistantPanelId ||
        panel == assistantPanelTitle) {
      final lastPanelId = lastTargetNotePanelId?.trim();
      if (lastPanelId != null && lastPanelId.isNotEmpty) {
        arguments['panel'] = lastPanelId;
        return;
      }
      final resolved = await _resolveNoteTarget(runtimeContext);
      if (resolved != null) {
        arguments['panel'] = resolved.panelId;
        arguments['board'] = resolved.boardId;
      }
    }
  }

  Future<void> _retargetPanelLookupToRealNoteIfNeeded(
    String toolCommand,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) async {
    final isPanelLookup =
        toolCommand == 'panel' || toolCommand == 'panel:focus';
    if (!isPanelLookup || !_looksLikeNoteLookupIntent(userMessage)) return;
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isNotEmpty &&
        panel != assistantPanelId &&
        panel != assistantPanelTitle) {
      return;
    }
    final resolved = await _resolveNoteTarget(runtimeContext);
    if (resolved == null) return;
    arguments['board'] = resolved.boardId;
    arguments['panel'] = resolved.panelId;
  }

  bool _looksLikeNoteLookupIntent(String msg) {
    final text = msg.toLowerCase();
    return text.contains('замет') ||
        text.contains('note') ||
        text.contains('mermaid') ||
        text.contains('diagram') ||
        text.contains('диаграм') ||
        text.contains('покажи') ||
        text.contains('show');
  }

  Future<({String boardId, String panelId})?> _resolveNoteTarget(
    ChatRuntimeContext? runtimeContext,
  ) async {
    final tokens = _searchTokens(userMessage);
    final hintedBoardId = '${runtimeContext?.boardId ?? ''}'.trim();
    try {
      final boardsRaw = await delegate.invoke(
        'yoloit_boards',
        const <String, Object?>{},
        runtimeContext: runtimeContext,
      );
      final boardsDecoded = jsonDecode(boardsRaw);
      if (boardsDecoded is! Map) return null;
      final boards = boardsDecoded['boards'];
      if (boards is! List) return null;

      ({String boardId, String panelId, int score, num zIndex})? best;
      for (final b in boards) {
        if (b is! Map) continue;
        final boardMap = Map<String, Object?>.from(b.cast<String, Object?>());
        final boardId = '${boardMap['id'] ?? ''}'.trim();
        if (boardId.isEmpty) continue;
        final panelsRaw = await delegate.invoke('yoloit_panels', {
          'id_or_name': boardId,
        }, runtimeContext: runtimeContext);
        final panelsDecoded = jsonDecode(panelsRaw);
        if (panelsDecoded is! Map) continue;
        final panels = panelsDecoded['panels'];
        if (panels is! List) continue;
        for (final p in panels) {
          if (p is! Map) continue;
          final panel = Map<String, Object?>.from(p.cast<String, Object?>());
          if (panel['type'] != 'board.note.markdown' ||
              panel['hidden'] == true) {
            continue;
          }
          final panelId = '${panel['id'] ?? ''}'.trim();
          if (panelId.isEmpty) continue;
          final title = '${panel['title'] ?? ''}'.toLowerCase();
          final zIndex = (panel['zIndex'] as num?) ?? 0;
          var score = 0;
          if (boardId == hintedBoardId) score += 2;
          if (title.contains('mermaid') ||
              title.contains('diagram') ||
              title.contains('диаграм')) {
            score += 3;
          }
          for (final token in tokens) {
            if (token.length < 3) continue;
            if (title.contains(token)) score += 2;
          }

          if (score < 4 && tokens.isNotEmpty) {
            try {
              final detailsRaw = await delegate.invoke('yoloit_panel', {
                'board': boardId,
                'panel': panelId,
              }, runtimeContext: runtimeContext);
              final details = jsonDecode(detailsRaw);
              if (details is Map) {
                final markdown =
                    '${(details['state'] as Map?)?['markdown'] ?? (details['content'] as Map?)?['markdown'] ?? ''}'
                        .toLowerCase();
                for (final token in tokens) {
                  if (token.length < 3) continue;
                  if (markdown.contains(token)) score += 2;
                }
              }
            } catch (_) {}
          }

          if (best == null ||
              score > best.score ||
              (score == best.score && zIndex > best.zIndex)) {
            best = (
              boardId: boardId,
              panelId: panelId,
              score: score,
              zIndex: zIndex,
            );
          }
        }
      }
      if (best == null) return null;
      return (boardId: best.boardId, panelId: best.panelId);
    } catch (_) {
      return null;
    }
  }

  Set<String> _searchTokens(String text) {
    final lower = text.toLowerCase();
    final parts = lower.split(RegExp(r'[^a-zа-я0-9_]+'));
    const skip = {
      'сделай',
      'покажи',
      'найди',
      'фокус',
      'focus',
      'show',
      'note',
      'заметку',
      'заметка',
      'на',
      'борде',
      'with',
      'for',
      'the',
      'and',
    };
    return parts.where((p) => p.isNotEmpty && !skip.contains(p)).toSet();
  }

  bool _mentionsPreviousNote(String msg) {
    final text = msg.toLowerCase();
    return text.contains('в нее') ||
        text.contains('в неё') ||
        text.contains('туда') ||
        text.contains('заметк') ||
        text.contains('note');
  }

  bool _toolResultSucceeded(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map && decoded['ok'] is bool) {
        return decoded['ok'] as bool;
      }
    } catch (_) {}
    return true;
  }

  ({String id, String title})? _createdPanelFromResult(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map) return null;
      final stdout = decoded['stdout'];
      final payload = stdout is String ? jsonDecode(stdout) : decoded;
      if (payload is! Map) return null;
      final panel = payload['panel'];
      if (panel is! Map) return null;
      final id = '${panel['id'] ?? ''}'.trim();
      final title = '${panel['title'] ?? id}'.trim();
      if (id.isEmpty) return null;
      return (id: id, title: title.isEmpty ? id : title);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yolo Assistant — Session history dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AssistantHistoryDialog extends StatefulWidget {
  const _AssistantHistoryDialog({this.currentSessionId});
  final String? currentSessionId;

  @override
  State<_AssistantHistoryDialog> createState() =>
      _AssistantHistoryDialogState();
}

class _AssistantHistoryDialogState extends State<_AssistantHistoryDialog> {
  late Future<List<ChatSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadYoloSessions();
  }

  Future<List<ChatSessionEntry>> _loadYoloSessions() async {
    final all = await ChatSessionHistory.instance.loadAll();
    // Show only sessions created by the yolo assistant (id starts with 'yolo-').
    return all.where((e) => e.id.startsWith('yolo-')).toList();
  }

  void _refresh() => setState(() => _entriesFuture = _loadYoloSessions());

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Icon(
            Icons.history,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            'Yolo session history',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 440,
        child: FutureBuilder<List<ChatSessionEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return Center(
                child: Text(
                  'No sessions yet.\nStart chatting to see history here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final e = entries[index];
                final isCurrent = e.id == widget.currentSessionId;
                return Container(
                  decoration: BoxDecoration(
                    color: isCurrent ? colors.surfaceElevated : colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isCurrent
                            ? Border.all(color: colors.accentGreen, width: 0.5)
                            : Border.all(
                              color: colors.border.withAlpha(80),
                              width: 0.5,
                            ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color:
                            isCurrent
                                ? colors.accentGreen
                                : colors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.sessionName.isNotEmpty
                                  ? e.sessionName
                                  : 'Yolo session',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color:
                                    isCurrent
                                        ? colors.accentGreen
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.provider} • ${e.messageCount} msgs',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDate(e.lastMessageAt ?? e.createdAt),
                        style: TextStyle(
                          fontSize: 9,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Restore
                      if (!isCurrent)
                        _historyBtn(
                          icon: Icons.restore,
                          color: colors.accentBlue,
                          tooltip: 'Restore',
                          onTap: () async {
                            final msgs = await ChatSessionHistory.instance
                                .loadMessages(e.id);
                            if (!context.mounted) return;
                            Navigator.pop(context, msgs);
                          },
                        ),
                      // Delete
                      _historyBtn(
                        icon: Icons.delete_outline,
                        color: colors.accentRed,
                        tooltip: 'Delete',
                        onTap: () async {
                          await ChatSessionHistory.instance.delete(e.id);
                          _refresh();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _historyBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
