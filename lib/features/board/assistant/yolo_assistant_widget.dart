import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:record/record.dart';
import 'package:yoloit/core/platform/microphone_permission_service.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/copyable_error_dialog.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/core/utils/json_utils.dart';
import 'package:yoloit/core/utils/string_utils.dart';

import 'package:yoloit/features/board/assistant/assistant_message_utils.dart';
import 'package:yoloit/features/board/assistant/assistant_voice_visualizer.dart';
import 'package:yoloit/features/board/assistant/widgets/assistant_history_dialog.dart';
import 'package:yoloit/features/board/assistant/widgets/assistant_thinking_indicator.dart';
import 'package:yoloit/features/board/assistant/widgets/assistant_tool_executor.dart';
import 'package:yoloit/features/board/assistant/widgets/debug_logs_dialog.dart';
import 'package:yoloit/features/board/assistant/widgets/session_bar_button.dart';
import 'package:yoloit/features/board/assistant/widgets/tools_dialog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/cloud_asr_service.dart';
import 'package:yoloit/features/board/chat/cloud_llm_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/board/chat/panel_context_builder.dart';
import 'package:yoloit/features/board/chat/yolo_chat_prompt.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_catalog_local.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';
import 'package:yoloit/features/settings/ui/settings_page.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

part 'yolo_assistant_widget_send.dart';
part 'yolo_assistant_widget_voice.dart';

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

  /// Test-only hook for building the chat provider used by the assistant.
  ///
  /// When non-null, the send pipeline builds the provider through this
  /// factory instead of constructing real cloud/local providers (which
  /// require model runtimes or network access).
  @visibleForTesting
  static ChatProvider Function(
    String providerType,
    AssistantToolExecutor toolExecutor,
  )? debugChatProviderFactory;

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
  AssistantToolExecutor? _wrappedExecutor;
  ChatProvider? _chatProvider;
  String? _chatProviderType; // tracks current provider type for re-creation
  Map<String, dynamic>? _pendingAsrDebug;
  bool _isRecordingMic = false;
  bool _isStartingMic = false;
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
    final status = computeAssistantOverlayStatus(
      forcedStatus: forcedStatus,
      isRecordingMic: _isRecordingMic,
      isTranscribingMic: _isTranscribingMic,
      isGeneratingReply: _isGeneratingReply,
      receivedAssistantToken: _receivedAssistantToken,
      draft: draft,
    );
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

  String? get _targetPanelId =>
      widget.panel.state['targetPanelId'] as String?;

  BoardPanelInstance? get _targetPanel {
    final id = _targetPanelId;
    if (id == null || id == widget.panel.id) return null;
    final board = _currentBoard();
    if (board == null) return null;
    try {
      return board.panels.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

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
    final ctx = _beginSendMessage(mirrorToOverlay: mirrorToOverlay);
    if (ctx == null) return;

    try {
      _messageDraft = ctx.messages;
      final runtimeContext = await _runtimeContext();
      _prepareToolExecutor(ctx);
      final providerType = await _resolveAssistantProviderType();
      final provider = await _ensureChatProvider(providerType);
      await _streamAssistantReply(
        ctx,
        provider: provider,
        providerType: providerType,
        runtimeContext: runtimeContext,
      );
      _finalizeAssistantReply(ctx);
    } catch (e) {
      _handleSendMessageError(ctx, e);
    } finally {
      _cleanupAfterSendMessage(dbg: ctx.dbg, mirrorToOverlay: mirrorToOverlay);
    }
  }

  void _replaceAssistantMessageContent({
    required String assistantMessageId,
    required String content,
    bool mirrorToOverlay = false,
    List<String> overlayToolLogs = const [],
  }) {
    final current = _messageDraft ?? _messages;
    if (!replaceMessageContentInPlace(current, assistantMessageId, content)) {
      return;
    }
    if (_isGeneratingReply && content.trim().isNotEmpty) {
      _receivedAssistantToken = true;
    }
    _messageDraft = current;
    final newStatus = assistantOverlayStatus(
      isGenerating: _isGeneratingReply,
      content: content,
      overlayToolLogs: overlayToolLogs,
    );
    // ignore: avoid_print
    if (mirrorToOverlay && !_voiceOverlayHidden) {
      print(
        '[YoloAssistant] _replaceContent → status=$newStatus content="${content.length}ch" tools=${overlayToolLogs.length}',
      );
    }
    _updateState({
      'messages': current,
      if (mirrorToOverlay && !_voiceOverlayHidden) ...{
        'voiceResponse': composeAssistantOverlayResponse(
          content,
          overlayToolLogs,
        ),
        'assistantStatus': newStatus,
      },
    });
    _scrollToBottom();
  }

  String _composeOverlayResponse(
    String assistantContent,
    List<String> toolLogs,
  ) => composeAssistantOverlayResponse(assistantContent, toolLogs);

  BoardDocument? _currentBoard() =>
      context.read<BoardCubit>().state.activeBoard;

  String _availableBoardsSummary() {
    final cubit = context.read<BoardCubit>();
    final current = cubit.state.activeBoard;
    return availableBoardsSummary(cubit.state.boards, current?.id);
  }

  String _currentBoardPanelsSummary(BoardDocument? board) =>
      boardPanelsSummary(board);

  Future<ChatRuntimeContext> _runtimeContext() async {
    final board = _currentBoard();
    final target = _targetPanel;
    return ChatRuntimeContext(
      boardId: board?.id,
      boardName: board?.name,
      panelId: widget.panel.id,
      panelTitle: widget.panel.title,
      panelType: widget.panel.type,
      availableBoardsSummary: _availableBoardsSummary(),
      currentBoardPanelsSummary: _currentBoardPanelsSummary(board),
      viewportScale: board?.viewport.scale,
      targetPanelSummary: target != null
          ? await buildFocusPanelSummary(
              target,
              typeName: BoardPluginRegistry.instance.pluginFor(target.type)?.displayName,
            )
          : null,
      boardCubit: context.read<BoardCubit>(),
    );
  }

  Map<String, dynamic> _toolTargetPatchIfNeeded({
    required String? toolCommand,
    required Map<String, Object?> arguments,
    required String result,
  }) => toolTargetPatchIfNeeded(
    toolCommand: toolCommand,
    arguments: arguments,
    result: result,
    selfPanelId: widget.panel.id,
  );

  String _cleanAssistantToolEchoes(String content, List<String> calledTools) =>
      cleanAssistantToolEchoes(content, calledTools);

  String _compactToolResult(String toolName, String result, bool success) =>
      compactAssistantToolResult(toolName, result, success);

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
    final target = _targetPanel;
    final targetSummary = target != null
        ? await buildFocusPanelSummary(
            target,
            typeName: BoardPluginRegistry.instance.pluginFor(target.type)?.displayName,
          )
        : null;
    final buffer = StringBuffer()
      ..writeln(await loadYoloChatSystemPrompt())
      ..writeln()
      ..writeln(_buildContextSnapshotMarkdown());
    if (targetSummary != null) {
      buffer
        ..writeln()
        ..writeln(targetSummary);
    }
    buffer
      ..writeln()
      ..writeln('Active skills: ${_activeSkills.join(', ')}.')
      ..writeln('Last target note panel id: ${_lastTargetNotePanelId ?? 'unknown'}.')
      ..writeln('Focus panel id: ${target?.id ?? 'none'}.');
    final systemContent = buffer.toString().trim();

    return <Map<String, String>>[
      {'role': 'system', 'content': systemContent},
      ...conversationMessagesForRequest(chatMessages),
    ];
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
    final tools = YoloitCliToolCatalogLocal.localToolsFor(
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

  int _estimateTokens(String text) => estimateTokenCount(text);

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
                await copyToClipboard(prompt);
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
                          color: context.appColors.textMuted,
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
    await showDialog<void>(
      context: context,
      builder:
          (_) => DebugLogsDialog(
            sessions: _debugSessions,
            activeSession: _activeDebugSession,
            onSimulate: _addFakeDebugSession,
            onClear: _debugSessions.clear,
          ),
    );
  }

  void _addFakeDebugSession() {
    final now = DateTime.now();
    _debugSessions.add(<String, dynamic>{
      'id': 'sim_${now.millisecondsSinceEpoch}',
      'userMessage': '[Simulation] Show weather + open browser',
      'modelId': 'google/gemini-3.1-flash-lite-preview',
      'modelProvider': 'openrouter',
      'requestAt': now.subtract(const Duration(seconds: 8)).toIso8601String(),
      'promptSentAt':
          now.subtract(const Duration(seconds: 8)).toIso8601String(),
      'firstTokenAt':
          now.subtract(const Duration(milliseconds: 4800)).toIso8601String(),
      'completedAt':
          now.subtract(const Duration(milliseconds: 400)).toIso8601String(),
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
              now.subtract(const Duration(milliseconds: 7200)).toIso8601String(),
          'endAt':
              now.subtract(const Duration(milliseconds: 6800)).toIso8601String(),
          'success': true,
        },
        {
          'name': 'web:open',
          'arguments': {
            'board': 'board-1778878703064560',
            'panel': '__yolo_badge__',
            'url': 'https://www.google.com/search?q=weather+in+Grodno',
          },
          'startAt':
              now.subtract(const Duration(milliseconds: 6600)).toIso8601String(),
          'endAt':
              now.subtract(const Duration(milliseconds: 5900)).toIso8601String(),
          'success': true,
        },
        {
          'name': 'panels',
          'arguments': {'board': 'board-1778878703064560'},
          'startAt':
              now.subtract(const Duration(milliseconds: 5700)).toIso8601String(),
          'endAt':
              now.subtract(const Duration(milliseconds: 5200)).toIso8601String(),
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
              now.subtract(const Duration(milliseconds: 5000)).toIso8601String(),
          'endAt':
              now.subtract(const Duration(milliseconds: 3800)).toIso8601String(),
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
              now.subtract(const Duration(milliseconds: 3600)).toIso8601String(),
          'endAt':
              now.subtract(const Duration(milliseconds: 1200)).toIso8601String(),
          'success': true,
        },
      ],
    });
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
    showDialog<void>(
      context: context,
      builder:
          (_) => ToolsDialog(
            initialDisabled: _disabledLocalTools(),
            onPersist: (next) {
              final sorted = next.toList()..sort();
              _updateState({'disabledLocalToolNames': sorted});
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
          Caption('$msgCount msgs'),
          const Spacer(),
          // History
          SessionBarButton(
            icon: Icons.history,
            tooltip: 'Session history',
            onTap: () => _showHistoryDialog(context),
          ),
          const SizedBox(width: 4),
          // New session
          SessionBarButton(
            icon: Icons.add_circle_outline,
            tooltip: 'New session',
            onTap: _newSession,
          ),
          const SizedBox(width: 4),
          // Clear
          SessionBarButton(
            icon: Icons.delete_outline,
            tooltip: 'Clear chat',
            onTap: _clearSession,
          ),
          const SizedBox(width: 4),
          // More actions (keeps the input bar clean)
          PopupMenuButton<String>(
            tooltip: 'Assistant actions',
            icon: const Icon(Icons.more_vert, size: 18),
            padding: EdgeInsets.zero,
            onSelected: (value) {
              switch (value) {
                case 'preview':
                  unawaited(_showChatSessionDialog());
                case 'debug':
                  unawaited(_showDebugLogsDialog());
                case 'copy':
                  unawaited(_copyFullLogsToClipboard());
              }
            },
            itemBuilder:
                (context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'preview',
                    child: Row(
                      children: [
                        Icon(Icons.manage_search_outlined, size: 18),
                        SizedBox(width: 8),
                        Flexible(child: Text('Preview next LLM request')),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'debug',
                    child: Row(
                      children: [
                        Icon(Icons.bug_report_outlined, size: 18),
                        SizedBox(width: 8),
                        Flexible(child: Text('LLM debug logs')),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'copy',
                    child: Row(
                      children: [
                        Icon(Icons.content_copy_outlined, size: 18),
                        SizedBox(width: 8),
                        Flexible(child: Text('Copy chat log')),
                      ],
                    ),
                  ),
                ],
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
    final sessionName = deriveAssistantSessionName(msgs);

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
          (_) => AssistantHistoryDialog(currentSessionId: _assistantSessionId),
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
                    context.appColors.textMuted.withAlpha(153),
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
    final displayContent = assistantDisplayContent(
      isUser: isUser,
      content: content,
    );
    final showThinking = !isUser && content.isEmpty && _isGeneratingReply;
    final containsMermaid = content.contains('```mermaid');
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    if (isTool) {
      return _buildToolMessageBubble(
        msg,
        colors,
        textColor: textColor,
        content: content,
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
            decoration: _messageBubbleDecoration(
              isUser: isUser,
              colors: colors,
            ),
            child: _buildMessageBubbleContent(
              colors: colors,
              isUser: isUser,
              showThinking: showThinking,
              containsMermaid: containsMermaid,
              displayContent: displayContent,
              content: content,
              textColor: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolMessageBubble(
    Map<String, dynamic> msg,
    AppColorScheme colors, {
    required Color textColor,
    required String content,
  }) {
    final success = msg['success'] as bool? ?? true;
    final toolName = msg['toolName'] as String? ?? 'tool';
    final args = compactPromptJson(msg['arguments'], 420);
    final rawResult = msg['rawResult'] as String?;
    final result = compactToolResultForPrompt(rawResult);
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

  BoxDecoration _messageBubbleDecoration({
    required bool isUser,
    required AppColorScheme colors,
  }) {
    return BoxDecoration(
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
    );
  }

  Widget _buildMessageBubbleContent({
    required AppColorScheme colors,
    required bool isUser,
    required bool showThinking,
    required bool containsMermaid,
    required String displayContent,
    required String content,
    required Color textColor,
  }) {
    final codeBg = colors.surface;
    if (showThinking) {
      return AssistantThinkingIndicator(
        color:
            Theme.of(context).textTheme.bodyMedium?.color ??
            Theme.of(context).colorScheme.onSurface,
      );
    }
    if (isUser) {
      return SelectableText(
        displayContent,
        style: TextStyle(
          fontSize: 13,
          color: colors.textPrimary,
          height: 1.4,
        ),
      );
    }
    if (containsMermaid) {
      return RepaintBoundary(
        child: MarkdownDocumentPreview(content: content),
      );
    }
    return RepaintBoundary(
      child: MarkdownBody(
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
    );
  }

  Widget _buildInputBar(AppColorScheme colors) {
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final hintColor =
        context.appColors.textMuted.withAlpha(153);
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      decoration: BoxDecoration(
        color: colors.surface,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Voice mode toggle
          _buildVoiceModeToggle(colors),
          const SizedBox(width: 8),
          _buildToolsButton(colors),

          _buildInputField(colors, textColor, hintColor),
          const SizedBox(width: 6),
          // Microphone button — tap to start recording, tap again to stop & send
          _buildMicButton(colors),
          const SizedBox(width: 6),
          // Stop button (during generation) / Send button
          _buildSendButton(colors),
        ],
      ),
    );
  }

  Widget _buildVoiceModeToggle(AppColorScheme colors) {
    return GestureDetector(
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
    );
  }

  Widget _buildToolsButton(AppColorScheme colors) {
    return GestureDetector(
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
    );
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (isEnter && !HardwareKeyboard.instance.isShiftPressed) {
      unawaited(_sendMessage());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInputField(
    AppColorScheme colors,
    Color textColor,
    Color hintColor,
  ) {
    return Expanded(
      child: Focus(
        onKeyEvent: _handleInputKeyEvent,
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
    );
  }

  void _onMicButtonTap() {
    unawaited(_isRecordingMic ? _stopAndSendMic() : _startPushToTalkMic());
  }

  Widget _buildMicButton(AppColorScheme colors) {
    return GestureDetector(
      onTap: _isTranscribingMic ? null : _onMicButtonTap,
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
    );
  }

  Widget _buildSendButton(AppColorScheme colors) {
    return GestureDetector(
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
    );
  }

  // ── Voice mode ────────────────────────────────────────────────────────────

  Widget _buildVoiceMode() {
    final colors = context.appColors;
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
                    state: VoiceVisualizerState.idle,
                    colors: colors,
                    size: 160,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Tap to speak',
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
    _isStartingMic = true;
    try {
      await _startRecordingFromMic();
    } finally {
      _isStartingMic = false;
    }
  }

  /// Stops recording and sends immediately (tap-to-toggle mic behaviour).
  Future<void> _stopAndSendMic() async {
    if (_isTranscribingMic || !_isRecordingMic) return;
    await _stopRecordingAndTranscribe(sendAfterTranscription: true);
  }

  Future<void> _startRecordingFromMic() async {
    if (!await _ensureAsrModelReady()) return;
    if (!await _ensureMicPermissions()) return;
    if (!await _startMicStream()) return;
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

  /// Ensures an ASR model is available when cloud ASR is disabled.
  /// Returns false when recording must not start (user was sent to Settings).
  Future<bool> _ensureAsrModelReady() async {
    final voiceSettings =
        await CloudLlmSettingsService.instance.loadVoiceSettings();
    if (voiceSettings.useCloudAsr) return true;
    await LocalAiModelsService.instance.initialize();
    if (LocalAiModelsService.instance.hasSelectedAsrInstalled) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Install ASR model first. Opening Settings → AI Models…',
        ),
        duration: Duration(seconds: 2),
      ),
    );
    await SettingsPage.show(context, initialCategory: 'AI Models');
    return false;
  }

  /// Checks native and recorder mic permissions, showing the hint dialog
  /// when either is missing. Returns false when recording must not start.
  Future<bool> _ensureMicPermissions() async {
    final nativeGranted =
        await MicrophonePermissionService.instance.ensureGranted();
    if (!nativeGranted) {
      if (!mounted) return false;
      await _showMicrophonePermissionHint();
      return false;
    }

    final granted = await _micRecorder.hasPermission();
    if (granted) return true;
    if (!mounted) return false;
    await _showMicrophonePermissionHint();
    return false;
  }

  /// Starts the PCM mic stream. Returns false when recording must not start
  /// (permission lost or start failure — the user was already informed).
  Future<bool> _startMicStream() async {
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
      return true;
    } on Exception catch (e) {
      if (!mounted) return false;
      final stillNoPermission = !await _micRecorder.hasPermission();
      if (!mounted) return false;
      if (stillNoPermission) {
        await _showMicrophonePermissionHint();
        return false;
      }
      await _showCopyableErrorDialog(
        title: 'Microphone error',
        message: 'Failed to start microphone:\n$e',
      );
      return false;
    }
  }

  Future<void> _stopRecordingAndTranscribe({
    bool sendAfterTranscription = false,
    bool mirrorToOverlay = false,
  }) async {
    final wavBytes = await _stopMicCaptureAndBuildWav();

    if (!mounted) return;
    setState(() {
      _isRecordingMic = false;
      _isTranscribingMic = true;
    });
    _syncOverlayState(hiddenOverride: _voiceOverlayHidden);

    final voiceSettings =
        await CloudLlmSettingsService.instance.loadVoiceSettings();
    final run = await _beginAsrRun(voiceSettings);

    // For local ASR we still need a temp file path (local ASR reads from disk).
    // Cloud ASR uses bytes directly.
    if (wavBytes != null && !voiceSettings.useCloudAsr) {
      run.tempPath =
          '${Directory.systemTemp.path}/yoloit_asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    try {
      await _runAsrTranscription(
        wavBytes,
        voiceSettings,
        sendAfterTranscription,
        run,
      );
    } finally {
      await _finalizeAsrRun(run, wavBytes);
    }
    await _maybeSendAfterTranscription(run, mirrorToOverlay: mirrorToOverlay);
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

  Future<void> _copyMessageToClipboard(String text) async {
    if (text.isEmpty) return;
    await copyToClipboard(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _copyFullLogsToClipboard() async {
    final text = buildFullChatLogsText(
      messages: _messages,
      debugSessions: _debugSessions,
    );
    await copyToClipboard(text);
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
    await showCopyableErrorDialog(
      context: context,
      title: title,
      message: message,
    );
  }

  Future<void> _showMicrophonePermissionHint() async {
    if (!mounted) return;
    final appName = await MicrophonePermissionService.instance.displayName();
    final bundleId =
        await MicrophonePermissionService.instance.bundleIdentifier();
    final resetCommand = microphonePermissionResetCommand(bundleId);
    final status = await MicrophonePermissionService.instance.status();
    if (!mounted) return;
    final hintText = buildMicrophonePermissionHintText(
      appName: appName,
      bundleId: bundleId,
      status: status,
    );
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Microphone access required'),
            content: SizedBox(width: 560, child: SelectableText(hintText)),
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
                  await copyToClipboard(resetCommand);
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

  String _formatAssistantError(Object error) => formatAssistantError(error);
}



// ── Debug session list/detail view ────────────────────────────────────────



