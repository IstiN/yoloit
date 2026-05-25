import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_models_flutter/runtime/embedded_gemma_tool_calls.dart';
import 'package:record/record.dart';
import 'package:yoloit/core/platform/microphone_permission_service.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/assistant/assistant_voice_visualizer.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
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

  // In-memory ring buffer of raw LLM debug sessions (last 20, not persisted).
  final List<Map<String, dynamic>> _debugSessions = [];
  Map<String, dynamic>? _activeDebugSession;

  // Pending state overrides — prevents stale widget.panel.state reads from
  // overwriting state changes made between board rebuilds. Each _updateState
  // call accumulates here; acknowledged keys are cleared in didUpdateWidget.
  final Map<String, dynamic> _pendingStateOverrides = {};

  static const _kAccent = Color(0xFF8B5CF6);

  bool get _voiceOverlayHidden =>
      (_pendingStateOverrides['voiceOverlayHidden'] ??
          widget.panel.state['voiceOverlayHidden']) as bool? ??
      true;

  // Effective state: pending overrides layered on top of last-known panel state.
  Map<String, dynamic> get _effectiveState =>
      Map<String, dynamic>.from(widget.panel.state)..addAll(_pendingStateOverrides);

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
    print('[YoloAssistant] _syncOverlayState: forced=$forcedStatus → status=$status (isGenerating=$_isGeneratingReply, hasToken=$_receivedAssistantToken)');
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

    // ── Debug session ──────────────────────────────────────────────────────
    final dbg = <String, dynamic>{
      'id': 'dbg-${DateTime.now().millisecondsSinceEpoch}',
      'userMessage': text,
      'requestAt': DateTime.now().toIso8601String(),
      'toolCalls': <Map<String, dynamic>>[],
      if (asrDebug != null) 'asr': asrDebug,
    };
    _activeDebugSession = dbg;

    try {
      _messageDraft = msgs;
      final runtimeContext = _runtimeContext();
      final calledTools = <String>[];
      final overlayToolLogs = <String>[];

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
          'startAt': DateTime.now().toIso8601String(),
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
            final args = event.data['arguments'] as Map<String, Object?>? ?? {};
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
        _syncOverlayState(
          draftOverride: '',
          forcedStatus: 'output',
          responseOverride: _composeOverlayResponse(
            cleanedFinal,
            overlayToolLogs,
          ),
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
        _isGeneratingReply &&
                content.trim().isEmpty &&
                overlayToolLogs.isEmpty
            ? 'processing'
            : _isGeneratingReply
            ? 'responding'
            : 'output';
    // ignore: avoid_print
    if (mirrorToOverlay && !_voiceOverlayHidden) {
      print('[YoloAssistant] _replaceContent → status=$newStatus content="${content.length}ch" tools=${overlayToolLogs.length}');
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
    if (toolLogs.isEmpty) return text;
    final lines = toolLogs.map((t) => '- $t').join('\n');
    final toolsSection = '### Tools\n$lines';
    if (text.isEmpty) return toolsSection;
    return '$text\n\n$toolsSection';
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
            style: TextStyle(fontSize: 11, color: colors.border),
          ),
          const Spacer(),
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
    _chatProvider?.dispose();
    _chatProvider = null;
    _chatProviderType = null;
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
    _updateState({'messages': <dynamic>[], 'lastUsage': null});
    setState(() {});
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
                  backgroundColor: _kAccent.withAlpha(25),
                  selectedColor: _kAccent.withAlpha(50),
                  side: BorderSide(color: _kAccent.withAlpha(60)),
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
                    ? const Color(0x1434D399)
                    : Theme.of(context).colorScheme.error.withAlpha(24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  success
                      ? const Color(0x5534D399)
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
                        ? const Color(0xFF34D399)
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
                      ? const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
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
              child: Icon(Icons.graphic_eq, size: 14, color: _kAccent),
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
                          : Border.all(color: _kAccent.withAlpha(100)),
                ),
                child: Icon(
                  Icons.settings_input_component_outlined,
                  size: 14,
                  color: _kAccent,
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
                  color: _kAccent,
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
                          : _kAccent,
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
                  color: _kAccent,
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
                    borderSide: BorderSide(color: _kAccent, width: 0.8),
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
                        : _kAccent,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Stop button (during generation) / Send button
          GestureDetector(
            onTap:
                _isGeneratingReply
                    ? () => setState(() => _isCancelled = true)
                    : () => unawaited(_sendMessage()),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color:
                    _isGeneratingReply
                        ? Theme.of(context).colorScheme.error
                        : _kAccent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _isGeneratingReply ? Icons.stop_rounded : Icons.arrow_upward,
                color: Colors.white,
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
                    size: 160,
                    color: _kAccent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _kAccent.withAlpha(200),
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
            style: TextButton.styleFrom(foregroundColor: _kAccent),
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

    final outputPath =
        '${Directory.systemTemp.path}/yoloit_asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _micRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: outputPath,
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
    _syncOverlayState(hiddenOverride: false);
  }

  Future<void> _stopRecordingAndTranscribe({
    bool sendAfterTranscription = false,
    bool mirrorToOverlay = false,
  }) async {
    final path = await _micRecorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecordingMic = false;
      _isTranscribingMic = true;
    });
    _syncOverlayState(hiddenOverride: _voiceOverlayHidden);

    final voiceSettings =
        await CloudLlmSettingsService.instance.loadVoiceSettings();
    final asrMode = voiceSettings.useCloudAsr ? 'cloud' : 'local';
    final asrStartedAt = DateTime.now().toIso8601String();
    final asrStopwatch = Stopwatch()..start();
    var asrStatus = 'ok';
    var asrTranscriptChars = 0;
    String? asrError;

    var shouldSend = false;
    try {
      if (path == null || path.isEmpty) {
        asrStatus = 'no_audio';
        return;
      }

      if (voiceSettings.useCloudAsr) {
        // ── Cloud ASR: transcribe with configured cloud provider/model ───────
        final transcript = await _cloudAsrService.transcribeFromFile(
          audioPath: path,
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
        // ── Local ASR: transcribe locally then send text ─────────────────
        final transcript = await LocalAiModelsService.instance
            .transcribeWithSelectedAsr(path);

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
      _pendingAsrDebug = {
        'mode': asrMode,
        'status': asrStatus,
        'startedAt': asrStartedAt,
        'completedAt': DateTime.now().toIso8601String(),
        'durationMs': asrStopwatch.elapsedMilliseconds,
        'transcriptChars': asrTranscriptChars,
        if (asrError != null) 'error': asrError,
      };
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (f.existsSync()) {
          try {
            await f.delete();
          } on FileSystemException {
            // ignore
          }
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
    if (!_isRecordingMic) {
      _resetVoiceOverlay();
      return;
    }
    final path = await _micRecorder.stop();
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          await file.delete();
        } on FileSystemException {
          // ignore temp cleanup failure
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _isRecordingMic = false;
      _isTranscribingMic = false;
    });
    _inputController.clear();
    _resetVoiceOverlay();
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
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: context.appColors.border),
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
    buf.writeln('=== LLM Session Timings ===');
    buf.writeln();
    buf.writeln('User message: ${s['userMessage'] ?? ''}');
    buf.writeln();

    final requestAt = _parseTs(s['requestAt']);
    final promptSentAt = _parseTs(s['promptSentAt']);
    final firstTokenAt = _parseTs(s['firstTokenAt']);
    final completedAt = _parseTs(s['completedAt']);

    buf.writeln('requestAt:    ${s['requestAt'] ?? '-'}');
    buf.writeln('promptSentAt: ${s['promptSentAt'] ?? '-'}');
    if (requestAt != null && promptSentAt != null) {
      final initMs = promptSentAt.difference(requestAt).inMilliseconds;
      buf.writeln('  → init+build: ${initMs}ms');
    }
    buf.writeln('firstTokenAt: ${s['firstTokenAt'] ?? '-'}');
    if (promptSentAt != null && firstTokenAt != null) {
      final ttftMs = firstTokenAt.difference(promptSentAt).inMilliseconds;
      buf.writeln('  → TTFT (time to first token): ${ttftMs}ms');
    }
    buf.writeln('completedAt:  ${s['completedAt'] ?? '-'}');
    if (firstTokenAt != null && completedAt != null) {
      final genMs = completedAt.difference(firstTokenAt).inMilliseconds;
      buf.writeln('  → generation: ${genMs}ms');
    }
    if (promptSentAt != null && completedAt != null) {
      final llmResponseMs = completedAt.difference(promptSentAt).inMilliseconds;
      buf.writeln('  → LLM response total: ${llmResponseMs}ms');
    }
    if (requestAt != null && completedAt != null) {
      final totalMs = completedAt.difference(requestAt).inMilliseconds;
      buf.writeln('  → total: ${totalMs}ms');
    }
    buf.writeln();

    final asr = s['asr'] as Map?;
    if (asr != null) {
      buf.writeln('ASR timings:');
      buf.writeln('  mode:         ${asr['mode'] ?? '-'}');
      buf.writeln('  status:       ${asr['status'] ?? '-'}');
      buf.writeln('  startedAt:    ${asr['startedAt'] ?? '-'}');
      buf.writeln('  completedAt:  ${asr['completedAt'] ?? '-'}');
      final asrMs = asr['durationMs'];
      buf.writeln('  total:        ${asrMs != null ? '${asrMs}ms' : '-'}');
      if (asrMs is num && promptSentAt != null && completedAt != null) {
        final llmResponseMs =
            completedAt.difference(promptSentAt).inMilliseconds;
        buf.writeln('  ASR→LLM total:${asrMs.toInt() + llmResponseMs}ms');
      }
      final chars = asr['transcriptChars'];
      if (chars != null) {
        buf.writeln('  transcript:   ${chars} chars');
      }
      if (asr['error'] != null) {
        buf.writeln('  error:        ${asr['error']}');
      }
      buf.writeln();
    }

    if (s['error'] != null) {
      buf.writeln('ERROR: ${s['error']}');
      buf.writeln();
    }

    buf.writeln('Model settings:');
    buf.writeln('  maxTokens:   ${s['maxTokens'] ?? '-'}');
    buf.writeln('  temperature: ${s['temperature'] ?? '-'}');
    buf.writeln();

    // Swift-level timing from the native MLX backend
    final swift = s['swiftTimings'] as Map?;
    if (swift != null) {
      buf.writeln('Swift (MLX native) timings:');
      final cacheHit = swift['swiftCacheHit'];
      buf.writeln(
        '  model cache:    ${cacheHit == true
            ? 'HIT ✓'
            : cacheHit == false
            ? 'MISS (loaded from disk)'
            : '-'}',
      );
      final loadMs = swift['swiftLoadMs'];
      if (loadMs != null) buf.writeln('  load time:      ${loadMs}ms');
      final ttft = swift['swiftFirstTokenMs'];
      if (ttft != null) {
        buf.writeln('  first token:    ${ttft}ms  (TTFT inside Swift)');
      }
      final genMs = swift['swiftGenerateMs'];
      if (genMs != null) buf.writeln('  generation:     ${genMs}ms');
      final totalMs = swift['swiftTotalMs'];
      if (totalMs != null) buf.writeln('  swift total:    ${totalMs}ms');
      buf.writeln();
    }

    final toolCalls = s['toolCalls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      buf.writeln('Tool calls: ${toolCalls.length}');
      for (final tc in toolCalls) {
        if (tc is Map) {
          final start = _parseTs(tc['startAt']);
          final end = _parseTs(tc['endAt']);
          final durMs =
              (start != null && end != null)
                  ? end.difference(start).inMilliseconds
                  : null;
          buf.writeln(
            '  ${tc['name']} → ${durMs != null ? '${durMs}ms' : '?'}',
          );
        }
      }
    }

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
