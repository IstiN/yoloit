import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/provider_icon.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/cursor_agent_provider.dart';
import 'package:yoloit/features/board/chat/copilot_cli_provider.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';
import 'package:yoloit/features/settings/data/tool_call_settings_service.dart';
import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';
import 'package:yoloit/ui/widgets/ui_components.dart';

/// The chat UI rendered inside a board panel.
///
/// Manages its own [ChatProvider] instance, message list, and streaming state.
class ChatPanelWidget extends StatefulWidget {
  const ChatPanelWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
    this.onCreateLinkedPanel,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;
  final Future<String?> Function(
    String typeId,
    Map<String, dynamic> state,
    String title,
  )?
  onCreateLinkedPanel;

  /// Global registry of processing notifiers keyed by panel ID.
  /// Used by [_BoardPanelCard] to animate the border glow.
  static final Map<String, ValueNotifier<bool>> processingNotifiers = {};

  /// Fires whenever any panel's processing state changes. Used by minimap.
  static final ValueNotifier<int> processingChangeNotifier = ValueNotifier(0);

  @override
  State<ChatPanelWidget> createState() => _ChatPanelWidgetState();
}

class _ChatPanelWidgetState extends State<ChatPanelWidget>
    with SingleTickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  late AnimationController _glowCtrl;

  late ChatProvider _provider;
  late ChatSessionConfig _config;

  final List<ChatMessage> _messages = [];
  final Map<String, ChatToolCall> _activeToolCalls = {};
  final Set<String> _ignoredToolCallIds = <String>{};
  Set<String> _ignoredToolCalls = const {'report_intent'};
  bool _isProcessing = false;
  bool _isFirstMessage = true;
  ChatTokenUsage? _lastUsage;
  int _totalOutputTokens = 0;
  StreamSubscription<ChatEvent>? _eventSub;

  /// Notifier for panel border animation.
  final ValueNotifier<bool> processingNotifier = ValueNotifier(false);

  // Streaming assistant message accumulator
  String _streamingContent = '';
  String? _streamingMessageId;

  @override
  void initState() {
    super.initState();
    _initConfig();
    ToolCallSettingsService.instance.load().then((_) {
      if (!mounted) return;
      _handleIgnoredToolsChanged();
    });
    ToolCallSettingsService.instance.ignoredToolsListenable.addListener(
      _handleIgnoredToolsChanged,
    );
    _provider = _providerForId(_config.provider);
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Register processing notifier for board-level glow
    ChatPanelWidget.processingNotifiers[widget.panel.id] = processingNotifier;
    _consumeCliPendingMessage();
  }

  static ChatProvider _providerForId(String id) {
    return switch (id) {
      'cursor' => CursorAgentProvider(),
      _ => CopilotCliProvider(),
    };
  }

  @override
  void didUpdateWidget(covariant ChatPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRaw = oldWidget.panel.state['config'];
    final newRaw = widget.panel.state['config'];
    if (oldRaw is Map && newRaw is Map) {
      final nextConfig = ChatSessionConfig.fromJson(
        Map<String, dynamic>.from(newRaw),
      );
      final previousConfig = ChatSessionConfig.fromJson(
        Map<String, dynamic>.from(oldRaw),
      );
      if (nextConfig != previousConfig && nextConfig != _config) {
        setState(() {
          if (nextConfig.provider != _config.provider) {
            _provider.dispose();
            _provider = _providerForId(nextConfig.provider);
          }
          _config = nextConfig;
        });
      }
    }

    _consumeCliPendingMessage(
      previousPendingMessage:
          oldWidget.panel.state['_cliPendingMessage'] as String?,
    );
  }

  void _consumeCliPendingMessage({String? previousPendingMessage}) {
    final pendingMessage = widget.panel.state['_cliPendingMessage'] as String?;
    if (pendingMessage == null || pendingMessage.isEmpty) return;
    if (previousPendingMessage != null &&
        pendingMessage == previousPendingMessage) {
      return;
    }
    final attachments =
        (widget.panel.state['_cliPendingAttachments'] as List?)
            ?.cast<String>() ??
        const <String>[];
    final clearedState =
        {...widget.panel.state}
          ..remove('_cliPendingMessage')
          ..remove('_cliPendingAttachments');
    widget.onUpdateState(clearedState);
    unawaited(
      _sendMessage(
        overrideText: pendingMessage,
        overrideAttachments: attachments,
      ),
    );
  }

  void _initConfig() {
    final raw = widget.panel.state['config'];
    if (raw is Map) {
      _config = ChatSessionConfig.fromJson(Map<String, dynamic>.from(raw));
    } else {
      _config = ChatSessionConfig(sessionName: '', workingDir: '');
    }
    // Restore saved messages
    final savedMessages = widget.panel.state['messages'];
    if (savedMessages is List) {
      for (final m in savedMessages) {
        if (m is Map) {
          try {
            final msg = ChatMessage.fromJson(Map<String, dynamic>.from(m));
            _messages.add(msg);
            // Restore token count
            if (msg.tokenUsage != null) {
              _totalOutputTokens += msg.tokenUsage!.outputTokens;
            }
          } catch (_) {}
        }
      }
      if (_messages.isNotEmpty) {
        _isFirstMessage = false;
        _scrollToBottom();
      }
    }
    // Restore last usage
    final savedUsage = widget.panel.state['lastUsage'];
    if (savedUsage is Map) {
      _lastUsage = ChatTokenUsage.fromJson(
        Map<String, dynamic>.from(savedUsage),
      );
    }
  }

  static const _maxSavedMessages = 100;

  void _persistMessages() {
    final trimmed =
        _messages.length > _maxSavedMessages
            ? _messages.sublist(_messages.length - _maxSavedMessages)
            : _messages;
    final messagesJson = trimmed.map((m) => m.toJson()).toList();
    widget.onUpdateState({
      ...widget.panel.state,
      'config': _config.toJson(),
      'messages': messagesJson,
      'lastUsage': _lastUsage?.toJson(),
    });
    // Update session history registry (metadata + messages on disk)
    ChatSessionHistory.instance.upsert(
      ChatSessionEntry(
        id: widget.panel.id,
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
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    ToolCallSettingsService.instance.ignoredToolsListenable.removeListener(
      _handleIgnoredToolsChanged,
    );
    _provider.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _glowCtrl.dispose();
    ChatPanelWidget.processingNotifiers.remove(widget.panel.id);
    processingNotifier.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleIgnoredToolsChanged() {
    final next = ToolCallSettingsService.instance.ignoredTools;
    if (!mounted || setEquals(next, _ignoredToolCalls)) return;
    setState(() => _ignoredToolCalls = next);
  }

  bool _isIgnoredToolCall(String name) =>
      _ignoredToolCalls.contains(name.trim().toLowerCase());

  String _resolveToolName(String? toolName, {String? content}) {
    final raw = toolName?.trim() ?? '';
    final normalized = raw.toLowerCase();
    if (normalized.isNotEmpty && normalized != 'unknown') return raw;
    final text = content?.trim().toLowerCase() ?? '';
    if (text == 'intent logged') return 'report_intent';
    return raw.isEmpty ? 'unknown' : raw;
  }

  static final RegExp _changedFilePathRe = RegExp(r'(/\S+)');
  static const Set<String> _fileMutationToolNames = {
    'create',
    'edit',
    'apply_patch',
    'write_file',
    'delete_file',
    'move_file',
    'rename',
  };

  List<String> _extractChangedFiles({
    required String toolName,
    required String resultContent,
    Map<String, dynamic> arguments = const {},
  }) {
    final loweredName = toolName.trim().toLowerCase();
    final loweredContent = resultContent.toLowerCase();
    final likelyMutation =
        _fileMutationToolNames.contains(loweredName) ||
        loweredContent.contains('created file ') ||
        loweredContent.contains('updated with changes') ||
        loweredContent.contains('updated file') ||
        loweredContent.contains('deleted file');
    if (!likelyMutation) return const [];

    final found = <String>{};
    for (final match in _changedFilePathRe.allMatches(resultContent)) {
      final cleaned = _normalizePathToken(match.group(1) ?? '');
      if (cleaned.isNotEmpty) found.add(cleaned);
    }

    void collectFromDynamic(dynamic value, {String? key}) {
      if (value is String) {
        final candidate = _normalizePathToken(value);
        if (!candidate.startsWith('/')) return;
        if (key != null) {
          const pathKeys = {
            'path',
            'file',
            'filepath',
            'target',
            'destination',
            'newpath',
            'oldpath',
            'from',
            'to',
          };
          if (!pathKeys.contains(key.toLowerCase())) return;
        }
        found.add(candidate);
        return;
      }
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key is! String) continue;
          collectFromDynamic(entry.value, key: entry.key as String);
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          collectFromDynamic(item);
        }
      }
    }

    collectFromDynamic(arguments);
    return found.toList()..sort();
  }

  String _normalizePathToken(String raw) {
    var value = raw.trim();
    if (value.isEmpty || !value.startsWith('/')) return '';
    value = value.replaceAll(RegExp("^[`\"']+|[`\"']+\$"), '');
    value = value.replaceAll(RegExp(r'[),.;:!?]+$'), '');
    return value;
  }

  List<String> _collectChangedFilesForStrip() {
    final dedup = <String>{};
    final ordered = <String>[];
    for (final message in _messages.reversed) {
      if (message.role != ChatRole.tool) continue;
      final files =
          (message.metadata?['changedFiles'] as List?)?.cast<String>() ??
          _extractChangedFiles(
            toolName: _resolveToolName(
              message.toolName,
              content: message.content,
            ),
            resultContent: message.content,
          );
      if (files.isEmpty) continue;
      for (final path in files) {
        if (dedup.add(path)) ordered.add(path);
      }
      if (ordered.length >= 16) break;
    }
    return ordered;
  }

  void _handleLinkTap(String? href) {
    if (href == null || href.isEmpty) return;
    final createPanel = widget.onCreateLinkedPanel;
    if (createPanel != null &&
        (href.startsWith('http://') || href.startsWith('https://'))) {
      // Open as a new webpage panel linked to this chat
      final uri = Uri.tryParse(href);
      final title = uri?.host ?? href;
      createPanel('board.webpage', {'url': href}, title);
    } else {
      PlatformLauncher.instance.openUrl(href);
    }
  }

  /// Open a local file path: board preview for supported types, system open otherwise.
  void _handleOpenFile(String path) {
    if (path.isEmpty) return;
    final ext = path.split('.').last.toLowerCase();
    const boardPreviewable = {
      // images
      'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg',
      // video
      'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv',
      // audio
      'mp3', 'aac', 'wav', 'ogg', 'flac', 'm4a', 'opus', 'wma',
    };
    final createPanel = widget.onCreateLinkedPanel;
    if (createPanel != null && boardPreviewable.contains(ext)) {
      final title = path.split('/').last;
      createPanel('board.file.preview', {'path': path, 'title': title}, title);
    } else {
      Process.run('open', [path]);
    }
  }

  void _openInPreviewPanel(String path) {
    if (path.isEmpty) return;
    final createPanel = widget.onCreateLinkedPanel;
    if (createPanel != null) {
      final title = path.split('/').last;
      createPanel('board.file.preview', {'path': path, 'title': title}, title);
      return;
    }
    _handleOpenFile(path);
  }

  void _setProcessing(bool value) {
    _isProcessing = value;
    processingNotifier.value = value;
    // Notify minimap and other global listeners
    ChatPanelWidget.processingChangeNotifier.value++;
    if (value) {
      _glowCtrl.repeat(reverse: true);
    } else {
      _glowCtrl.stop();
      _glowCtrl.value = 0;
    }
  }

  bool _isSending = false;

  BoardDocument? _currentBoardForPanel() {
    final state = context.read<BoardCubit>().state;
    for (final board in state.boards) {
      final hasPanel = board.panels.any((p) => p.id == widget.panel.id);
      if (hasPanel) return board;
    }
    return state.activeBoard;
  }

  Future<void> _sendMessage({
    String? overrideText,
    List<String> overrideAttachments = const [],
  }) async {
    final text = overrideText?.trim() ?? _inputController.text.trim();
    if (text.isEmpty) return;
    if (_isSending) return; // prevent re-entrance

    // Handle /model command
    if (text == '/model') {
      _inputController.clear();
      _showModelPicker(context);
      return;
    }

    _isSending = true;
    if (overrideText == null) {
      _inputController.clear();
    }

    // If currently processing, finalize any partial response first
    if (_isProcessing) {
      _eventSub?.cancel();
      _eventSub = null;
      await _provider.stop(_config.sessionName);
      setState(() {
        _finalizeStreamingMessage();
        _streamingContent = '';
        _streamingMessageId = null;
        _activeToolCalls.clear();
        _ignoredToolCallIds.clear();
      });
    }

    // Start streaming
    // Extract file paths from message text and pass as attachments.
    // Any absolute path token (starts with /) is treated as an attachment.
    final filePathRe = RegExp(r'^/.+');
    final imageExtRe = RegExp(
      r'\.(png|jpg|jpeg|gif|webp|bmp)$',
      caseSensitive: false,
    );
    final tokens = text.split(RegExp(r'\s+'));
    final attachments = <String>[
      ...overrideAttachments,
      ...tokens.where((t) => filePathRe.hasMatch(t)),
    ];
    final promptText =
        tokens.where((t) => !filePathRe.hasMatch(t)).join(' ').trim();

    // Add user message — store attachments separately, content without paths
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'user-${DateTime.now().millisecondsSinceEpoch}',
          role: ChatRole.user,
          content: promptText,
          attachments: attachments,
          timestamp: DateTime.now(),
        ),
      );
      _setProcessing(true);
      _streamingContent = '';
      _streamingMessageId = null;
      _activeToolCalls.clear();
      _ignoredToolCallIds.clear();
    });

    _scrollToBottom();

    // For providers that support native attachment (copilot uses --attachment)
    // pass only image files as attachments; others get path embedded in prompt.
    final imageAttachments =
        attachments.where((t) => imageExtRe.hasMatch(t)).toList();
    final board = _currentBoardForPanel();

    final stream = _provider.sendMessage(
      message: promptText.isNotEmpty ? promptText : text,
      config: _config,
      isFirstMessage: _isFirstMessage,
      attachments: imageAttachments,
      runtimeContext: ChatRuntimeContext(
        boardId: board?.id,
        boardName: board?.name,
        panelId: widget.panel.id,
        panelTitle: widget.panel.title,
      ),
    );

    _isFirstMessage = false;

    _eventSub?.cancel();
    _eventSub = stream.listen(
      _handleEvent,
      onError: (Object error) {
        _isSending = false;
        setState(() {
          _setProcessing(false);
          _messages.add(
            ChatMessage(
              id: 'error-${DateTime.now().millisecondsSinceEpoch}',
              role: ChatRole.system,
              content: '❌ Error: $error',
              timestamp: DateTime.now(),
            ),
          );
        });
        _persistMessages();
        _scrollToBottom();
      },
      onDone: () {
        _isSending = false;
        setState(() {
          _setProcessing(false);
          // Finalize any streaming message
          if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
            _finalizeStreamingMessage();
          }
          _markAllActiveToolCallsCompleted();
        });
        _persistMessages();
        _scrollToBottom();
        // Play macOS system sound on completion
        _playCompletionSound();
      },
    );
  }

  void _playCompletionSound() {
    try {
      Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
    } catch (_) {}
  }

  void _handleEvent(ChatEvent event) {
    switch (event.type) {
      case ChatEventType.assistantMessageStart:
        setState(() {
          _streamingMessageId = event.messageId;
          _streamingContent = '';
        });
        break;

      case ChatEventType.assistantDelta:
        final delta = event.deltaContent;
        if (delta != null) {
          setState(() {
            _streamingContent += delta;
          });
          _scrollToBottom();
        }
        break;

      case ChatEventType.assistantMessage:
        final content = event.messageContent ?? _streamingContent;
        final toolReqs = event.toolRequests;
        setState(() {
          // Remove any existing streaming placeholder
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

          // Extract token usage from this message if available
          final outputTokens = (event.data['outputTokens'] as num?)?.toInt();
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
        });
        _scrollToBottom();
        break;

      case ChatEventType.toolStart:
        final toolCallId = event.toolCallId ?? '';
        final toolName = _resolveToolName(event.toolName);
        if (_isIgnoredToolCall(toolName)) {
          if (toolCallId.isNotEmpty) {
            _ignoredToolCallIds.add(toolCallId);
          }
          break;
        }
        setState(() {
          _activeToolCalls[toolCallId] = ChatToolCall(
            toolCallId: toolCallId,
            toolName: toolName,
            arguments: event.toolArguments ?? {},
            isRunning: true,
          );
        });
        _scrollToBottom();
        break;

      case ChatEventType.toolComplete:
        var toolCallId = event.data['toolCallId'] as String? ?? '';
        if (toolCallId.isEmpty && _activeToolCalls.length == 1) {
          toolCallId = _activeToolCalls.keys.first;
        }
        if (toolCallId.isNotEmpty && _ignoredToolCallIds.remove(toolCallId)) {
          break;
        }
        final success = event.data['success'] as bool? ?? true;
        final resultContent = event.toolResultContent ?? '';
        final toolArguments =
            _activeToolCalls[toolCallId]?.arguments ??
            event.toolArguments ??
            {};
        final toolName = _resolveToolName(
          _activeToolCalls[toolCallId]?.toolName ?? event.toolName,
          content: resultContent,
        );
        final changedFiles = _extractChangedFiles(
          toolName: toolName,
          resultContent: resultContent,
          arguments: toolArguments,
        );
        if (_isIgnoredToolCall(toolName)) {
          setState(() {
            _activeToolCalls.remove(toolCallId);
          });
          break;
        }
        setState(() {
          _activeToolCalls[toolCallId] = (_activeToolCalls[toolCallId] ??
                  ChatToolCall(
                    toolCallId: toolCallId,
                    toolName: 'unknown',
                    arguments: {},
                  ))
              .copyWith(
                isRunning: false,
                success: success,
                result: resultContent,
              );

          // Add tool result as a message for the chat log
          _messages.add(
            ChatMessage(
              id: 'tool-$toolCallId',
              role: ChatRole.tool,
              content: resultContent,
              toolName: toolName,
              toolCallId: toolCallId,
              timestamp: event.timestamp ?? DateTime.now(),
              metadata: {
                'success': success,
                if (changedFiles.isNotEmpty) 'changedFiles': changedFiles,
              },
            ),
          );
        });
        _scrollToBottom();
        break;

      case ChatEventType.result:
        final usage = event.usageData;
        if (usage != null) {
          final codeChanges = usage['codeChanges'] as Map<String, dynamic>?;
          final outputTokens = (usage['outputTokens'] as num?)?.toInt() ?? 0;
          setState(() {
            // Accumulate output tokens (providers like cursor report them only at result)
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
              linesRemoved:
                  (codeChanges?['linesRemoved'] as num?)?.toInt() ?? 0,
            );
          });
        }
        break;

      case ChatEventType.askUser:
        final question = event.data['question'] as String? ?? '';
        final choicesRaw = event.data['choices'];
        final choices =
            choicesRaw is List ? choicesRaw.cast<String>() : <String>[];
        final allowFreeform = event.data['allowFreeform'] as bool? ?? true;
        if (question.isNotEmpty) {
          setState(() {
            _messages.add(
              ChatMessage(
                id: 'ask-${DateTime.now().millisecondsSinceEpoch}',
                role: ChatRole.system,
                content: question,
                timestamp: DateTime.now(),
                metadata: {
                  'type': 'ask_user',
                  'choices': choices,
                  'allowFreeform': allowFreeform,
                },
              ),
            );
          });
          _scrollToBottom();
        }
        break;
      case ChatEventType.sessionStatus:
      case ChatEventType.userMessage:
      case ChatEventType.assistantTurnStart:
      case ChatEventType.assistantTurnEnd:
      case ChatEventType.unknown:
        break;
    }
  }

  void _markAllActiveToolCallsCompleted() {
    if (_activeToolCalls.isEmpty) return;
    final updated = <String, ChatToolCall>{};
    _activeToolCalls.forEach((id, call) {
      updated[id] = call.isRunning ? call.copyWith(isRunning: false) : call;
    });
    _activeToolCalls
      ..clear()
      ..addAll(updated);
    _ignoredToolCallIds.clear();
  }

  void _finalizeStreamingMessage() {
    if (_streamingContent.isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
    final configured = widget.panel.state['configured'] == true;
    if (!configured && _messages.isEmpty) {
      return _buildSetupView();
    }
    return _buildChatView();
  }

  // ── Setup view (pick folder + session name + model) ─────────────────────

  Widget _buildSetupView() {
    return _ChatSetupView(
      config: _config,
      models: _provider.availableModels,
      onStart: (config) {
        setState(() {
          // Switch provider if it changed
          if (config.provider != _config.provider) {
            _provider.dispose();
            _provider = _providerForId(config.provider);
          }
          _config = config;
          _isFirstMessage = true;
        });
        // Update panel title to session name
        if (config.sessionName.isNotEmpty) {
          context.read<BoardCubit>().updatePanelTitle(
            widget.panel.id,
            config.sessionName,
          );
        }
        // Persist config to panel state
        widget.onUpdateState({
          ...widget.panel.state,
          'config': config.toJson(),
          'configured': true,
        });
      },
    );
  }

  // ── Chat view ─────────────────────────────────────────────────────────────

  Widget _buildChatView() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: Column(
        children: [
          // Session info bar
          _buildInfoBar(),
          // Messages
          Expanded(
            child:
                _messages.isEmpty && !_isProcessing
                    ? _buildEmptyState()
                    : _buildMessageList(),
          ),
          // Input
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInfoBar() {
    final colors = context.appColors;
    final muted =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 11, color: muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _shortPath(_config.workingDir),
              style: TextStyle(fontSize: 10, color: muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ChatProviderIcon(provider: _config.provider, size: 14, color: muted),
          const SizedBox(width: 8),
          // Autopilot toggle
          GestureDetector(
            onTap: () {
              setState(() {
                _config = _config.copyWith(autopilot: !_config.autopilot);
              });
              _persistMessages();
            },
            child: Tooltip(
              message: _config.autopilot ? 'Autopilot ON' : 'Autopilot OFF',
              child: Icon(
                Icons.rocket_launch,
                size: 12,
                color: _config.autopilot ? const Color(0xFF34D399) : muted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Reasoning effort
          GestureDetector(
            onTap: _cycleReasoningEffort,
            child: Tooltip(
              message: 'Effort: ${_config.reasoningEffort ?? 'default'}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      _config.reasoningEffort != null
                          ? const Color(0x20F59E0B)
                          : const Color(0x151E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        _config.reasoningEffort != null
                            ? const Color(0x80F59E0B)
                            : colors.border,
                    width: 0.6,
                  ),
                ),
                child: Text(
                  _reasoningLabel(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color:
                        _config.reasoningEffort != null
                            ? const Color(0xFFF59E0B)
                            : muted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(_config.model, style: TextStyle(fontSize: 9, color: muted)),
          if (_totalOutputTokens > 0) ...[
            const SizedBox(width: 6),
            Text(
              '∑${_totalOutputTokens}',
              style: TextStyle(fontSize: 9, color: colors.primary),
            ),
          ],
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.2,
                  color: Color(0xFF34D399),
                ),
              ),
            ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _copySessionToClipboard,
            child: Tooltip(
              message: 'Copy session',
              child: Icon(Icons.copy_all_outlined, size: 13, color: muted),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showSessionHistoryDialog(context),
            child: Icon(Icons.history, size: 13, color: muted),
          ),
        ],
      ),
    );
  }

  String _reasoningLabel() {
    return switch (_config.reasoningEffort) {
      'low' => 'Effort: low',
      'medium' => 'Effort: med',
      'high' => 'Effort: high',
      'xhigh' => 'Effort: xhigh',
      _ => 'Effort',
    };
  }

  void _cycleReasoningEffort() {
    const levels = [null, 'low', 'medium', 'high', 'xhigh'];
    final currentIdx = levels.indexOf(_config.reasoningEffort);
    final nextIdx = (currentIdx + 1) % levels.length;
    setState(() {
      _config = _config.copyWith(reasoningEffort: () => levels[nextIdx]);
    });
    _persistMessages();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(30),
          ),
          const SizedBox(height: 12),
          Text(
            'Send a message to start',
            style: TextStyle(
              fontSize: 13,
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final hasRunningTools = _activeToolCalls.values.any(
      (t) => t.isRunning && !_isIgnoredToolCall(t.toolName),
    );
    final showStreaming = _streamingContent.isNotEmpty;
    // Show thinking indicator when processing but no streaming content and no running tools
    final showThinking = _isProcessing && !showStreaming && !hasRunningTools;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount:
          _messages.length +
          (showStreaming ? 1 : 0) +
          (hasRunningTools ? 1 : 0) +
          (showThinking ? 1 : 0),
      itemBuilder: (context, index) {
        final runningTools =
            _activeToolCalls.values
                .where((t) => t.isRunning && !_isIgnoredToolCall(t.toolName))
                .toList();

        if (index < _messages.length) {
          return _buildMessageBubble(_messages[index]);
        }

        final extra = index - _messages.length;

        // Running tools indicator
        if (hasRunningTools && extra == 0) {
          return _buildRunningToolsCard(runningTools);
        }

        // Streaming content
        if (showStreaming) {
          return _buildStreamingBubble();
        }

        // Thinking indicator (pulsing dots)
        if (showThinking) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appColors.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: const _TypingIndicator(),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    switch (message.role) {
      case ChatRole.user:
        return _UserBubble(
          content: message.content,
          attachments: message.attachments,
          onOpenFile: _handleOpenFile,
        );
      case ChatRole.assistant:
        final visibleToolCalls =
            message.toolCalls
                .map(
                  (tc) => tc.copyWith(
                    toolName: _resolveToolName(tc.toolName, content: tc.result),
                  ),
                )
                .where((tc) => !_isIgnoredToolCall(tc.toolName))
                .toList();
        return _AssistantBubble(
          content: message.content,
          toolCalls: visibleToolCalls,
          tokenUsage: message.tokenUsage,
          onLinkTap: _handleLinkTap,
          onOpenFile: _handleOpenFile,
        );
      case ChatRole.tool:
        final resolvedToolName = _resolveToolName(
          message.toolName,
          content: message.content,
        );
        if (_isIgnoredToolCall(resolvedToolName)) {
          return const SizedBox.shrink();
        }
        final persistedSuccess = message.metadata?['success'] as bool?;
        return _ToolResultCard(
          toolName: resolvedToolName,
          toolCallId: message.toolCallId ?? '',
          content: message.content,
          success:
              _activeToolCalls[message.toolCallId]?.success ?? persistedSuccess,
        );
      case ChatRole.system:
        final meta = message.metadata;
        if (meta != null && meta['type'] == 'ask_user') {
          return _AskUserCard(
            question: message.content,
            choices: (meta['choices'] as List?)?.cast<String>() ?? [],
            onChoice: (choice) {
              _inputController.text = choice;
              _sendMessage();
            },
          );
        }
        return _SystemBubble(content: message.content);
    }
  }

  Widget _buildRunningToolsCard(List<ChatToolCall> tools) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            tools
                .map(
                  (tool) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0x15FBBF24),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x30FBBF24)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFFFBBF24),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.build_outlined,
                          size: 14,
                          color: Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tool.toolName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFBBF24),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }

  Widget _buildStreamingBubble() {
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final codeBg = colors.surface;
    final processedContent = _streamingContent.replaceAll(
      RegExp(r'<br\s*/?>'),
      '\n',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child:
            processedContent.isEmpty
                ? const _TypingIndicator()
                : MarkdownBody(
                  data: processedContent,
                  onTapLink: (text, href, title) {
                    _handleLinkTap(href);
                  },
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: 13, color: textColor, height: 1.5),
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
    );
  }

  Widget _buildInputBar() {
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final hintColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    final changedFiles = _collectChangedFilesForStrip();
    return Container(
      margin: const EdgeInsets.fromLTRB(1.5, 0, 1.5, 1.5),
      padding: const EdgeInsets.fromLTRB(10, 8, 22, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (changedFiles.isNotEmpty) ...[
            _ChangedFilesStrip(
              files: changedFiles,
              onOpenFile: _openInPreviewPanel,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Model selector (bottom-left)
              Builder(
                builder:
                    (btnContext) => GestureDetector(
                      onTap: () => _showModelPicker(btnContext),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: colors.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: colors.terminalPrompt,
                        ),
                      ),
                    ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    // Enter (without Shift) → send
                    if (event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _sendMessage();
                      return KeyEventResult.handled;
                    }
                    // Cmd+V (macOS) or Ctrl+V → smart paste — intercept fully
                    final isCmd = HardwareKeyboard.instance.isMetaPressed;
                    final isCtrl = HardwareKeyboard.instance.isControlPressed;
                    if (event.logicalKey == LogicalKeyboardKey.keyV &&
                        (isCmd || isCtrl)) {
                      _handleSmartPaste();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocusNode,
                    style: TextStyle(
                      fontSize: 13,
                      color: textColor,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: _isProcessing ? 'Agent working…' : 'Message…',
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
                        borderSide: BorderSide(
                          color: colors.terminalPrompt,
                          width: 0.8,
                        ),
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
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Voice input coming soon'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.mic_none,
                    size: 15,
                    color: colors.terminalPrompt,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: colors.terminalPrompt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.arrow_upward,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Smart paste: short text pastes inline, long text or images → file ref.
  Future<void> _handleSmartPaste() async {
    try {
      final pasted =
          await SmartClipboardPasteService.instance
              .readInlineTextOrSavedFilePath();
      if (pasted != null && mounted) {
        _insertTextAtCursor(pasted);
      }
    } catch (e) {
      debugPrint('[ChatPanel] Smart paste error: $e');
    }
  }

  void _insertTextAtCursor(String text) {
    final sel = _inputController.selection;
    final current = _inputController.text;
    final before = sel.isValid ? current.substring(0, sel.start) : current;
    final after = sel.isValid ? current.substring(sel.end) : '';
    _inputController.text = '$before$text$after';
    _inputController.selection = TextSelection.collapsed(
      offset: before.length + text.length,
    );
  }

  String _shortPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 3) return path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  Future<void> _copySessionToClipboard() async {
    final transcript = _buildSessionTranscript();
    await Clipboard.setData(ClipboardData(text: transcript));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _buildSessionTranscript() {
    final b =
        StringBuffer()
          ..writeln(
            'Session: ${_config.sessionName.isEmpty ? 'unnamed' : _config.sessionName}',
          )
          ..writeln('Provider: ${_config.provider}')
          ..writeln('Model: ${_config.model}')
          ..writeln('Working dir: ${_config.workingDir}')
          ..writeln('Messages: ${_messages.length}')
          ..writeln('');

    for (final message in _messages) {
      final ts = message.timestamp?.toIso8601String() ?? '-';
      final role = message.role.name.toUpperCase();
      final toolName = message.toolName;
      final title =
          toolName != null && toolName.isNotEmpty
              ? '[$ts] $role ($toolName)'
              : '[$ts] $role';
      b.writeln(title);
      if (message.attachments.isNotEmpty) {
        b.writeln('Attachments: ${message.attachments.join(', ')}');
      }
      b.writeln(message.content.trimRight());
      b.writeln('');
    }

    if (_streamingContent.isNotEmpty) {
      b.writeln('[streaming] ASSISTANT');
      b.writeln(_streamingContent.trimRight());
      b.writeln('');
    }

    return b.toString().trimRight();
  }

  void _showModelPicker(BuildContext context) {
    final models = _provider.availableModels;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final buttonPos = renderBox.localToGlobal(Offset.zero);
    final menuHeight = (models.length * 32.0).clamp(0.0, 520.0);
    // Position directly above the button
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPos.dx,
        buttonPos.dy - menuHeight,
        buttonPos.dx + 260,
        buttonPos.dy,
      ),
      color: context.appColors.surface,
      items:
          models
              .map(
                (m) => PopupMenuItem<String>(
                  value: m.id,
                  height: 32,
                  child: Row(
                    children: [
                      if (m.id == _config.model)
                        const Icon(
                          Icons.check,
                          size: 14,
                          color: Color(0xFF34D399),
                        )
                      else
                        const SizedBox(width: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          m.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                m.id == _config.model
                                    ? const Color(0xFF34D399)
                                    : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        '${m.costMultiplier}x',
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              m.costMultiplier == 0
                                  ? const Color(0xFF34D399)
                                  : m.costMultiplier > 3
                                  ? const Color(0xFFF87171)
                                  : Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color ??
                                      Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    ).then((selected) {
      if (selected != null && selected != _config.model) {
        setState(() {
          _config = _config.copyWith(model: selected);
        });
        _persistMessages();
      }
    });
  }

  void _showSessionHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => _SessionHistoryDialog(
            currentPanelId: widget.panel.id,
            onRestore: (entry, messages) {
              setState(() {
                _config = _config.copyWith(
                  sessionName: entry.sessionName,
                  workingDir: entry.workingDir,
                  model: entry.model,
                  envGroupIds: entry.envGroupIds,
                );
                _messages.clear();
                for (final m in messages) {
                  try {
                    _messages.add(ChatMessage.fromJson(m));
                  } catch (_) {}
                }
                _isFirstMessage = false;
              });
              // Update panel title
              context.read<BoardCubit>().updatePanelTitle(
                widget.panel.id,
                entry.sessionName,
              );
              _persistMessages();
              _scrollToBottom();
            },
          ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session history dialog (accessible from info bar)
// ─────────────────────────────────────────────────────────────────────────────

class _SessionHistoryDialog extends StatefulWidget {
  const _SessionHistoryDialog({required this.currentPanelId, this.onRestore});
  final String currentPanelId;
  final void Function(
    ChatSessionEntry entry,
    List<Map<String, dynamic>> messages,
  )?
  onRestore;

  @override
  State<_SessionHistoryDialog> createState() => _SessionHistoryDialogState();
}

class _SessionHistoryDialogState extends State<_SessionHistoryDialog> {
  late Future<List<ChatSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = ChatSessionHistory.instance.loadAll();
  }

  void _refresh() {
    setState(() {
      _entriesFuture = ChatSessionHistory.instance.loadAll();
    });
  }

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
            color:
                Theme.of(context).textTheme.bodyMedium?.color ??
                Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            'Session history',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 420,
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
                  style: TextStyle(
                    color:
                        Theme.of(context).textTheme.bodySmall?.color ??
                        Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final e = entries[index];
                final isCurrent = e.id == widget.currentPanelId;
                return Container(
                  decoration: BoxDecoration(
                    color: isCurrent ? colors.surfaceElevated : colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isCurrent
                            ? Border.all(
                              color: const Color(0xFF34D399),
                              width: 0.5,
                            )
                            : null,
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
                                ? const Color(0xFF34D399)
                                : Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color ??
                                    Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.sessionName.isNotEmpty
                                  ? e.sessionName
                                  : 'Unnamed session',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color:
                                    isCurrent
                                        ? const Color(0xFF34D399)
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.provider} • ${e.model} • ${e.messageCount} msgs',
                              style: TextStyle(
                                fontSize: 10,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color ??
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDate(e.lastMessageAt ?? e.createdAt),
                        style: TextStyle(
                          fontSize: 9,
                          color:
                              Theme.of(context).textTheme.bodySmall?.color ??
                              Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Restore button (not for current session)
                      if (!isCurrent && widget.onRestore != null)
                        _actionButton(
                          icon: Icons.restore,
                          color: const Color(0xFF60A5FA),
                          tooltip: 'Restore',
                          onTap: () async {
                            final msgs = await ChatSessionHistory.instance
                                .loadMessages(e.id);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            widget.onRestore?.call(e, msgs);
                          },
                        ),
                      // Delete button
                      _actionButton(
                        icon: Icons.delete_outline,
                        color: const Color(0xFFF87171),
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

  Widget _actionButton({
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
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ChatSetupView extends StatefulWidget {
  const _ChatSetupView({
    required this.config,
    required this.models,
    required this.onStart,
  });

  final ChatSessionConfig config;
  final List<ChatModelInfo> models;
  final ValueChanged<ChatSessionConfig> onStart;

  @override
  State<_ChatSetupView> createState() => _ChatSetupViewState();
}

class _ChatSetupViewState extends State<_ChatSetupView> {
  late TextEditingController _sessionCtrl;
  late TextEditingController _dirCtrl;
  late String _selectedProvider;
  late String _selectedModel;
  late List<String> _selectedEnvGroupIds;

  static const _providers = [
    ('copilot', 'GitHub Copilot'),
    ('cursor', 'Cursor Agent'),
  ];

  List<ChatModelInfo> get _modelsForProvider =>
      _selectedProvider == 'cursor' ? kCursorModels : kCopilotModels;

  @override
  void initState() {
    super.initState();
    _sessionCtrl = TextEditingController(text: widget.config.sessionName);
    _dirCtrl = TextEditingController(text: widget.config.workingDir);
    _selectedProvider = widget.config.provider;
    _selectedModel = widget.config.model;
    _selectedEnvGroupIds = List<String>.from(widget.config.envGroupIds);
  }

  @override
  void dispose() {
    _sessionCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final dir = _dirCtrl.text.trim();
    if (dir.isEmpty) return;
    var sessionName = _sessionCtrl.text.trim();
    if (sessionName.isEmpty) {
      sessionName = 'chat-${DateTime.now().millisecondsSinceEpoch}';
    }
    // Ensure selected model is valid for the chosen provider
    final validModels = _modelsForProvider;
    final model =
        validModels.any((m) => m.id == _selectedModel)
            ? _selectedModel
            : (validModels
                .firstWhere((m) => m.isDefault, orElse: () => validModels.first)
                .id);
    widget.onStart(
      ChatSessionConfig(
        sessionName: sessionName,
        workingDir: dir,
        provider: _selectedProvider,
        model: model,
        envGroupIds: _selectedEnvGroupIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 11,
      color:
          Theme.of(context).textTheme.bodySmall?.color ??
          Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
    );
    final inputTextStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurface,
    );
    final hintStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurface.withAlpha(100),
    );
    final inputFill = colors.surfaceElevated;
    final dropdownFill = colors.surface;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Provider type selector
          Text('Provider', style: labelStyle),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: inputFill,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProvider,
                isExpanded: true,
                dropdownColor: dropdownFill,
                style: inputTextStyle,
                items:
                    _providers
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.$1,
                            child: Row(
                              children: [
                                ChatProviderIcon(provider: p.$1, size: 16),
                                const SizedBox(width: 8),
                                Text(p.$2),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedProvider = v;
                    // Reset model to default for the new provider
                    final models = _modelsForProvider;
                    _selectedModel =
                        models
                            .firstWhere(
                              (m) => m.isDefault,
                              orElse: () => models.first,
                            )
                            .id;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          EnvGroupSelectionField(
            selectedGroupIds: _selectedEnvGroupIds,
            onChanged: (value) {
              setState(() => _selectedEnvGroupIds = value);
            },
          ),
          const SizedBox(height: 14),

          // Working directory
          Text('Working Directory', style: labelStyle),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final dir = await FilePicker.getDirectoryPath(
                      dialogTitle: 'Select working directory',
                    );
                    if (dir != null) {
                      setState(() => _dirCtrl.text = dir);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: inputFill,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_outlined,
                          size: 16,
                          color: Color(0xFF34D399),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dirCtrl.text.isEmpty
                                ? 'Select folder…'
                                : _dirCtrl.text.split('/').last,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  _dirCtrl.text.isEmpty
                                      ? colorScheme.onSurface.withAlpha(120)
                                      : colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Session name
          Text('Session Name', style: labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _sessionCtrl,
            style: inputTextStyle,
            decoration: InputDecoration(
              hintText: 'auto-generated if empty',
              hintStyle: hintStyle,
              filled: true,
              fillColor: inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),

          // Model selector
          Text('Model', style: labelStyle),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: inputFill,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedModel,
                isExpanded: true,
                dropdownColor: dropdownFill,
                style: inputTextStyle,
                items:
                    _modelsForProvider
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.id,
                            child: Row(
                              children: [
                                Expanded(child: Text(m.displayName)),
                                Text(
                                  '${m.costMultiplier}x',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        m.costMultiplier == 0
                                            ? const Color(0xFF34D399)
                                            : m.costMultiplier > 3
                                            ? const Color(0xFFF87171)
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedModel = v);
                },
              ),
            ),
          ),

          const Spacer(),

          FilledButton(
            onPressed: _dirCtrl.text.trim().isEmpty ? null : _start,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF34D399),
              foregroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Start Chat',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubbles
// ─────────────────────────────────────────────────────────────────────────────

class _ChangedFilesStrip extends StatelessWidget {
  const _ChangedFilesStrip({required this.files, required this.onOpenFile});

  final List<String> files;
  final void Function(String path) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final labelColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.file_present_rounded, size: 13, color: colors.primary),
            const SizedBox(width: 5),
            Text(
              'Files changed',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                files.map((path) {
                  final fileName = path.split('/').last;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: path,
                      waitDuration: const Duration(milliseconds: 350),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onOpenFile(path),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.border.withOpacity(0.6),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 12,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                fileName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }
}

class _UserBubble extends StatefulWidget {
  const _UserBubble({
    required this.content,
    this.attachments = const [],
    this.onOpenFile,
  });
  final String content;
  final List<String> attachments;
  final void Function(String path)? onOpenFile;

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  bool _isHovered = false;

  static final _pathTokenRe = RegExp(r'^/\S+');

  static ({List<String> paths, String text}) _resolve(
    String content,
    List<String> attachments,
  ) {
    final tokens = content.split(RegExp(r'\s+'));
    final inlinePaths = tokens.where((t) => _pathTokenRe.hasMatch(t)).toList();
    final textOnly =
        tokens.where((t) => !_pathTokenRe.hasMatch(t)).join(' ').trim();

    final allPaths = <String>{...attachments, ...inlinePaths}.toList();
    return (paths: allPaths, text: textOnly);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve(widget.content, widget.attachments);
    final hasText = resolved.text.isNotEmpty;
    final hasAttachments = resolved.paths.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, left: 48),
      child: Align(
        alignment: Alignment.centerRight,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.65,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasAttachments)
                    Padding(
                      padding: EdgeInsets.only(bottom: hasText ? 8 : 0),
                      child: _AttachmentPreviewSection(
                        paths: resolved.paths,
                        onLight: false,
                        onOpenFile: widget.onOpenFile,
                      ),
                    ),
                  if (hasText)
                    SelectionArea(
                      child: Text(
                        resolved.text,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 100),
                    child: _BubbleMenu(textToCopy: resolved.text, light: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small menu button for chat bubbles — copy on click.
class _BubbleMenu extends StatelessWidget {
  const _BubbleMenu({required this.textToCopy, this.light = false});
  final String textToCopy;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color =
        light
            ? Colors.white.withOpacity(0.6)
            : (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: 28,
        height: 20,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: textToCopy));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Icon(Icons.more_horiz, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

/// Shows image thumbnails + file chips for a list of file paths.
/// Used in both user bubbles (attachments) and assistant bubbles (detected paths).
class _AttachmentPreviewSection extends StatelessWidget {
  const _AttachmentPreviewSection({
    required this.paths,
    this.onLight = true,
    this.onOpenFile,
  });

  final List<String> paths;

  /// True when rendered on a light background (assistant bubble), false on dark (user bubble).
  final bool onLight;

  /// Called when the user taps a file — uses board preview or system open.
  final void Function(String path)? onOpenFile;

  static final _imageRe = RegExp(
    r'\.(png|jpg|jpeg|gif|webp|bmp|svg)$',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final images = paths.where((p) => _imageRe.hasMatch(p)).toList();
    final files = paths.where((p) => !_imageRe.hasMatch(p)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty) _buildImageGrid(context, images),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 6),
        if (files.isNotEmpty) _buildFileChips(context, files),
      ],
    );
  }

  Widget _buildImageGrid(BuildContext context, List<String> imagePaths) {
    if (imagePaths.length == 1) {
      return _ImageThumbnail(
        path: imagePaths.first,
        maxWidth: 280,
        maxHeight: 200,
        onOpenFile: onOpenFile,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children:
          imagePaths
              .map(
                (p) => _ImageThumbnail(
                  path: p,
                  maxWidth: 140,
                  maxHeight: 120,
                  onOpenFile: onOpenFile,
                ),
              )
              .toList(),
    );
  }

  Widget _buildFileChips(BuildContext context, List<String> filePaths) {
    final chipBg =
        onLight
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.white.withOpacity(0.15);
    final textColor =
        onLight ? Theme.of(context).colorScheme.onSurface : Colors.white;
    final iconColor =
        onLight
            ? Theme.of(context).colorScheme.primary
            : const Color(0xFFBFDBFE);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children:
          filePaths.map((p) {
            final name = p.split('/').last;
            return GestureDetector(
              onTap: () {
                if (onOpenFile != null) {
                  onOpenFile!(p);
                } else {
                  // Fallback: reveal in Finder
                  Process.run('open', ['-R', p]);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        onLight
                            ? Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.3)
                            : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: 13,
                      color: iconColor,
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }
}

/// Tappable image thumbnail that opens via [onOpenFile] on tap.
class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({
    required this.path,
    this.maxWidth = 280,
    this.maxHeight = 200,
    this.onOpenFile,
  });

  final String path;
  final double maxWidth;
  final double maxHeight;
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final name = path.split('/').last;

    return GestureDetector(
      onTap: () {
        if (onOpenFile != null) {
          onOpenFile!(path);
        } else {
          Process.run('open', [path]);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, __, ___) => Container(
                      width: 80,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: Colors.white38,
                      ),
                    ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            name,
            style: const TextStyle(fontSize: 9, color: Color(0xFFBFDBFE)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatefulWidget {
  const _AssistantBubble({
    required this.content,
    this.toolCalls = const [],
    this.tokenUsage,
    this.onLinkTap,
    this.onOpenFile,
  });
  final String content;
  final List<ChatToolCall> toolCalls;
  final ChatTokenUsage? tokenUsage;
  final void Function(String? href)? onLinkTap;
  final void Function(String path)? onOpenFile;

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _isHovered = false;

  static final _absPathRe = RegExp(
    r'(?<![`\w])(\/[\w./\-_ ]+\.[\w]{1,10})(?![`\w])',
  );

  static List<String> _extractFilePaths(String text) {
    final matches = _absPathRe.allMatches(text);
    final seen = <String>{};
    final result = <String>[];
    for (final m in matches) {
      final path = m.group(1)!.trim();
      if (seen.add(path)) result.add(path);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    final codeBg = colors.surface;
    final processedContent = widget.content.replaceAll(
      RegExp(r'<br\s*/?>'),
      '\n',
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.toolCalls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children:
                      widget.toolCalls
                          .map(
                            (tc) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x15FBBF24),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0x30FBBF24),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.terminal_rounded,
                                    size: 10,
                                    color: Color(0xFFFBBF24),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tc.toolName,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFFFBBF24),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),

            if (processedContent.trim().isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectionArea(
                        child: MarkdownBody(
                          data: processedContent,
                          selectable: false,
                          onTapLink: (text, href, title) {
                            if (widget.onLinkTap != null) {
                              widget.onLinkTap!(href);
                            } else if (href != null && href.isNotEmpty) {
                              PlatformLauncher.instance.openUrl(href);
                            }
                          },
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
                              fontFamily: 'JetBrains Mono',
                              color: colors.terminalPrompt,
                              backgroundColor: codeBg,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: codeBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                            ),
                            codeblockPadding: const EdgeInsets.all(10),
                            listBullet: TextStyle(
                              fontSize: 13,
                              color: mutedColor,
                            ),
                            h1: TextStyle(
                              fontSize: 16,
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                            h2: TextStyle(
                              fontSize: 14,
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                            h3: TextStyle(
                              fontSize: 13,
                              color: textColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 100),
                        child: _BubbleMenu(
                          textToCopy: processedContent,
                          light: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (widget.tokenUsage != null)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 6),
                child: Text(
                  '${widget.tokenUsage!.outputTokens} tok',
                  style: TextStyle(
                    fontSize: 9,
                    color:
                        Theme.of(context).textTheme.bodySmall?.color ??
                        Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),

            Builder(
              builder: (_) {
                final detectedPaths = _extractFilePaths(widget.content);
                if (detectedPaths.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _AttachmentPreviewSection(
                    paths: detectedPaths,
                    onLight: true,
                    onOpenFile: widget.onOpenFile,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolResultCard extends StatefulWidget {
  const _ToolResultCard({
    required this.toolName,
    required this.toolCallId,
    required this.content,
    this.success,
  });
  final String toolName;
  final String toolCallId;
  final String content;
  final bool? success;

  @override
  State<_ToolResultCard> createState() => _ToolResultCardState();
}

class _ToolResultCardState extends State<_ToolResultCard> {
  bool _expanded = false;

  void _copyResult() {
    Clipboard.setData(ClipboardData(text: widget.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tool result copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _openFullView() {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 900,
              height: 640,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.toolName} • Full view',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          tooltip: 'Copy',
                          onPressed: _copyResult,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        widget.content,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final status = _ToolExecutionStatus.from(
      success: widget.success,
      content: widget.content,
    );
    final previewText = _toolResultPreview(widget.content);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color.lerp(colors.surfaceHighlight, status.tint, 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  Color.lerp(colors.border, status.tint, 0.35) ?? colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: status.tint.withAlpha(28),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(status.icon, size: 14, color: status.tint),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: colors.surface.withAlpha(180),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border.withAlpha(120)),
                    ),
                    child: Icon(
                      Icons.build_outlined,
                      size: 12,
                      color:
                          Theme.of(context).textTheme.bodyMedium?.color ??
                          Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.toolName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ToolStatusBadge(status: status),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Copy',
                    child: InkWell(
                      onTap: _copyResult,
                      child: Icon(
                        Icons.copy_all_outlined,
                        size: 14,
                        color:
                            Theme.of(context).textTheme.bodySmall?.color ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Full view',
                    child: InkWell(
                      onTap: _openFullView,
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 14,
                        color:
                            Theme.of(context).textTheme.bodySmall?.color ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color:
                        Theme.of(context).textTheme.bodySmall?.color ??
                        Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
              if (previewText != null && !_expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 28, right: 4),
                  child: Text(
                    previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color:
                          Theme.of(context).textTheme.bodySmall?.color ??
                          Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              if (_expanded && widget.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color.lerp(colors.surface, status.tint, 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border.withAlpha(110)),
                    ),
                    child: SelectableText(
                      widget.content,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color:
                            Theme.of(context).textTheme.bodyMedium?.color ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolStatusBadge extends StatelessWidget {
  const _ToolStatusBadge({required this.status});

  final _ToolExecutionStatus status;

  @override
  Widget build(BuildContext context) {
    return NeonBadge(
      label: status.label,
      color: status.tint,
      showPulse: status.isRunning,
    );
  }
}

class _ToolExecutionStatus {
  const _ToolExecutionStatus({
    required this.icon,
    required this.label,
    required this.tint,
    this.isRunning = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final bool isRunning;

  static _ToolExecutionStatus from({
    required bool? success,
    required String content,
  }) {
    final exitCode = _extractExitCode(content);
    if (success == null) {
      if (exitCode != null) {
        return _ToolExecutionStatus(
          icon:
              exitCode == 0 ? Icons.check_circle_rounded : Icons.error_rounded,
          label: exitCode == 0 ? 'Done $exitCode' : 'Failed $exitCode',
          tint:
              exitCode == 0 ? const Color(0xFF34D399) : const Color(0xFFF87171),
        );
      }
      if (content.trim().isNotEmpty) {
        return const _ToolExecutionStatus(
          icon: Icons.check_circle_rounded,
          label: 'Done',
          tint: Color(0xFF34D399),
        );
      }
      return const _ToolExecutionStatus(
        icon: Icons.pending_outlined,
        label: 'Running',
        tint: Color(0xFFFBBF24),
        isRunning: true,
      );
    }
    if (success) {
      return _ToolExecutionStatus(
        icon: Icons.check_circle_rounded,
        label: exitCode == null ? 'Done' : 'Done $exitCode',
        tint: const Color(0xFF34D399),
      );
    }
    return _ToolExecutionStatus(
      icon: Icons.error_rounded,
      label: exitCode == null ? 'Failed' : 'Failed $exitCode',
      tint: const Color(0xFFF87171),
    );
  }
}

int? _extractExitCode(String content) {
  final match = RegExp(
    r'(?:exited with exit code|exit code)\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(content);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String? _toolResultPreview(String content) {
  final cleaned =
      content
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .where(
            (line) => !line.toLowerCase().contains('exited with exit code'),
          )
          .toList();
  if (cleaned.isEmpty) {
    final exitCode = _extractExitCode(content);
    return exitCode == null ? null : 'Exited with code $exitCode';
  }
  return cleaned.first;
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x15F87171),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            content,
            style: const TextStyle(fontSize: 12, color: Color(0xFFF87171)),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _AskUserCard extends StatelessWidget {
  const _AskUserCard({
    required this.question,
    required this.choices,
    required this.onChoice,
  });
  final String question;
  final List<String> choices;
  final ValueChanged<String> onChoice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x15818CF8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x40818CF8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.help_outline,
                  size: 16,
                  color: Color(0xFF818CF8),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Agent asks:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF818CF8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              question,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    choices
                        .map(
                          (choice) => OutlinedButton(
                            onPressed: () => onChoice(choice),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF818CF8),
                              side: const BorderSide(color: Color(0xFF818CF8)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: Text(choice),
                          ),
                        )
                        .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

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
                    color:
                        Theme.of(context).textTheme.bodyMedium?.color ??
                        Theme.of(context).colorScheme.onSurface,
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
