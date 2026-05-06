import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/copilot_cli_provider.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/terminal/data/clipboard_file_service.dart';

/// The chat UI rendered inside a board panel.
///
/// Manages its own [ChatProvider] instance, message list, and streaming state.
class ChatPanelWidget extends StatefulWidget {
  const ChatPanelWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;

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
    _provider = CopilotCliProvider();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  void _initConfig() {
    final raw = widget.panel.state['config'];
    if (raw is Map) {
      _config = ChatSessionConfig.fromJson(Map<String, dynamic>.from(raw));
    } else {
      _config = ChatSessionConfig(
        sessionName: 'chat-${widget.panel.id}',
        workingDir: '',
      );
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
      _lastUsage = ChatTokenUsage.fromJson(Map<String, dynamic>.from(savedUsage));
    }
  }

  static const _maxSavedMessages = 100;

  void _persistMessages() {
    final trimmed = _messages.length > _maxSavedMessages
        ? _messages.sublist(_messages.length - _maxSavedMessages)
        : _messages;
    widget.onUpdateState({
      ...widget.panel.state,
      'config': _config.toJson(),
      'messages': trimmed.map((m) => m.toJson()).toList(),
      'lastUsage': _lastUsage?.toJson(),
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _provider.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _glowCtrl.dispose();
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

  void _setProcessing(bool value) {
    _isProcessing = value;
    processingNotifier.value = value;
    if (value) {
      _glowCtrl.repeat(reverse: true);
    } else {
      _glowCtrl.stop();
      _glowCtrl.value = 0;
    }
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();

    // Add user message
    setState(() {
      _messages.add(ChatMessage(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        role: ChatRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _setProcessing(true);
      _streamingContent = '';
      _streamingMessageId = null;
      _activeToolCalls.clear();
    });

    _scrollToBottom();

    // Start streaming
    final stream = _provider.sendMessage(
      message: text,
      config: _config,
      isFirstMessage: _isFirstMessage,
    );

    _isFirstMessage = false;

    _eventSub?.cancel();
    _eventSub = stream.listen(
      _handleEvent,
      onError: (Object error) {
        setState(() {
          _setProcessing(false);
          _messages.add(ChatMessage(
            id: 'error-${DateTime.now().millisecondsSinceEpoch}',
            role: ChatRole.system,
            content: '❌ Error: $error',
            timestamp: DateTime.now(),
          ));
        });
        _persistMessages();
        _scrollToBottom();
      },
      onDone: () {
        setState(() {
          _setProcessing(false);
          // Finalize any streaming message
          if (_streamingMessageId != null && _streamingContent.isNotEmpty) {
            _finalizeStreamingMessage();
          }
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
          _messages.removeWhere((m) =>
            m.id == _streamingMessageId && m.isStreaming);

          final toolCalls = toolReqs.map((tr) {
            final args = tr['arguments'];
            return ChatToolCall(
              toolCallId: tr['toolCallId'] as String? ?? '',
              toolName: tr['name'] as String? ?? '',
              arguments: args is Map
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

          _messages.add(ChatMessage(
            id: event.messageId ?? 'assistant-${DateTime.now().millisecondsSinceEpoch}',
            role: ChatRole.assistant,
            content: content,
            timestamp: event.timestamp ?? DateTime.now(),
            toolCalls: toolCalls,
            isStreaming: false,
            tokenUsage: usage,
          ));
          _streamingMessageId = null;
          _streamingContent = '';
        });
        _scrollToBottom();
        break;

      case ChatEventType.toolStart:
        final toolCallId = event.toolCallId ?? '';
        final toolName = event.toolName ?? 'unknown';
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
        final toolCallId = event.data['toolCallId'] as String? ?? '';
        final success = event.data['success'] as bool? ?? true;
        final resultContent = event.toolResultContent ?? '';
        setState(() {
          _activeToolCalls[toolCallId] = (_activeToolCalls[toolCallId] ??
            ChatToolCall(
              toolCallId: toolCallId,
              toolName: 'unknown',
              arguments: {},
            )).copyWith(
            isRunning: false,
            success: success,
            result: resultContent.length > 500
                ? '${resultContent.substring(0, 500)}…'
                : resultContent,
          );

          // Add tool result as a message for the chat log
          _messages.add(ChatMessage(
            id: 'tool-$toolCallId',
            role: ChatRole.tool,
            content: resultContent.length > 500
                ? '${resultContent.substring(0, 500)}…'
                : resultContent,
            toolName: _activeToolCalls[toolCallId]?.toolName ?? 'unknown',
            toolCallId: toolCallId,
            timestamp: event.timestamp ?? DateTime.now(),
          ));
        });
        _scrollToBottom();
        break;

      case ChatEventType.result:
        final usage = event.usageData;
        if (usage != null) {
          final codeChanges = usage['codeChanges'] as Map<String, dynamic>?;
          setState(() {
            _lastUsage = ChatTokenUsage(
              premiumRequests: (usage['premiumRequests'] as num?)?.toInt() ?? 0,
              totalApiDurationMs: (usage['totalApiDurationMs'] as num?)?.toInt() ?? 0,
              sessionDurationMs: (usage['sessionDurationMs'] as num?)?.toInt() ?? 0,
              linesAdded: (codeChanges?['linesAdded'] as num?)?.toInt() ?? 0,
              linesRemoved: (codeChanges?['linesRemoved'] as num?)?.toInt() ?? 0,
            );
          });
        }
        break;

      case ChatEventType.askUser:
        final question = event.data['question'] as String? ?? '';
        final choicesRaw = event.data['choices'];
        final choices = choicesRaw is List
            ? choicesRaw.cast<String>()
            : <String>[];
        final allowFreeform = event.data['allowFreeform'] as bool? ?? true;
        if (question.isNotEmpty) {
          setState(() {
            _messages.add(ChatMessage(
              id: 'ask-${DateTime.now().millisecondsSinceEpoch}',
              role: ChatRole.system,
              content: question,
              timestamp: DateTime.now(),
              metadata: {
                'type': 'ask_user',
                'choices': choices,
                'allowFreeform': allowFreeform,
              },
            ));
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

  void _finalizeStreamingMessage() {
    if (_streamingContent.isEmpty) return;
    _messages.add(ChatMessage(
      id: _streamingMessageId ?? 'assistant-${DateTime.now().millisecondsSinceEpoch}',
      role: ChatRole.assistant,
      content: _streamingContent,
      timestamp: DateTime.now(),
    ));
    _streamingMessageId = null;
    _streamingContent = '';
  }

  @override
  Widget build(BuildContext context) {
    if (_config.workingDir.isEmpty) {
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
          _config = config;
          _isFirstMessage = true;
        });
        // Persist config to panel state
        widget.onUpdateState({
          ...widget.panel.state,
          'config': config.toJson(),
        });
      },
    );
  }

  // ── Chat view ─────────────────────────────────────────────────────────────

  Widget _buildChatView() {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, child) {
        return Container(
          decoration: _isProcessing
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF34D399).withAlpha(
                      (40 + _glowCtrl.value * 80).round(),
                    ),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF34D399).withAlpha(
                        (_glowCtrl.value * 40).round(),
                      ),
                      blurRadius: 12,
                    ),
                  ],
                )
              : null,
          child: child,
        );
      },
      child: Column(
        children: [
          // Model + session info bar
          _buildInfoBar(),
          const Divider(height: 1),
          // Messages
          Expanded(
            child: _messages.isEmpty && !_isProcessing
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0x0AFFFFFF),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF34D399)),
          const SizedBox(width: 4),
          Text(
            _config.model,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.folder_outlined, size: 14, color: Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _shortPath(_config.workingDir),
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_lastUsage != null) ...[
            Text(
              '${_lastUsage!.totalApiDurationMs}ms',
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
            ),
            const SizedBox(width: 4),
            if (_lastUsage!.premiumRequests > 0)
              Text(
                '${_lastUsage!.premiumRequests} premium',
                style: const TextStyle(fontSize: 10, color: Color(0xFFFBBF24)),
              ),
          ],
          if (_totalOutputTokens > 0) ...[
            const SizedBox(width: 4),
            Text(
              '∑ ${_totalOutputTokens}tok',
              style: const TextStyle(fontSize: 10, color: Color(0xFF818CF8)),
            ),
          ],
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF34D399),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: Colors.white.withAlpha(30),
          ),
          const SizedBox(height: 12),
          const Text(
            'Send a message to start',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        itemCount: _messages.length
            + (_streamingContent.isNotEmpty ? 1 : 0)
            + (_activeToolCalls.values.any((t) => t.isRunning) ? 1 : 0),
        itemBuilder: (context, index) {
          // Active tool calls indicator
          final runningTools = _activeToolCalls.values.where((t) => t.isRunning).toList();
          final hasRunningTools = runningTools.isNotEmpty;

          if (index < _messages.length) {
            return _buildMessageBubble(_messages[index]);
          }

          // Running tools indicator
          if (hasRunningTools && index == _messages.length) {
            return _buildRunningToolsCard(runningTools);
          }

          // Streaming content
          if (_streamingContent.isNotEmpty) {
            return _buildStreamingBubble();
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    switch (message.role) {
      case ChatRole.user:
        return _UserBubble(content: message.content);
      case ChatRole.assistant:
        return _AssistantBubble(
          content: message.content,
          toolCalls: message.toolCalls,
          tokenUsage: message.tokenUsage,
        );
      case ChatRole.tool:
        return _ToolResultCard(
          toolName: message.toolName ?? 'tool',
          toolCallId: message.toolCallId ?? '',
          content: message.content,
          success: _activeToolCalls[message.toolCallId]?.success,
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
        children: tools.map((tool) => Container(
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
                width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.build_outlined, size: 14, color: Color(0xFFFBBF24)),
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
        )).toList(),
      ),
    );
  }

  Widget _buildStreamingBubble() {
    final processedContent = _streamingContent
        .replaceAll(RegExp(r'<br\s*/?>'), '\n');
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, right: 40),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: processedContent,
              onTapLink: (text, href, title) {
                if (href != null && href.isNotEmpty) {
                  PlatformLauncher.instance.openUrl(href);
                }
              },
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
                a: const TextStyle(fontSize: 13, color: Color(0xFF60A5FA), decoration: TextDecoration.underline),
                code: const TextStyle(fontSize: 12, color: Color(0xFF34D399), backgroundColor: Color(0xFF0F172A)),
              ),
            ),
            const SizedBox(height: 4),
            const _TypingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        children: [
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is! KeyDownEvent) return;
                // Enter (without Shift) → send
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  _sendMessage();
                  return;
                }
                // Cmd+V (macOS) or Ctrl+V → smart paste
                final isCmd = HardwareKeyboard.instance.isMetaPressed;
                final isCtrl = HardwareKeyboard.instance.isControlPressed;
                if (event.logicalKey == LogicalKeyboardKey.keyV && (isCmd || isCtrl)) {
                  _handleSmartPaste();
                }
              },
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
                decoration: InputDecoration(
                  hintText: _isProcessing ? 'Agent working… (you can still send)' : 'Type a message… (Shift+Enter for newline)',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF34D399)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                maxLines: 5,
                minLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send, color: Color(0xFF34D399), size: 20),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  /// Smart paste: short text pastes inline, long text or images → file ref.
  Future<void> _handleSmartPaste() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final reader = await clipboard.read();

        // Check for plain text first
        if (reader.canProvide(Formats.plainText)) {
          final text = await reader.readValue(Formats.plainText);
          if (text != null && text.isNotEmpty) {
            final wordCount = text.trim().split(RegExp(r'\s+')).length;
            if (wordCount <= 1000) {
              // Short text — let default paste handle it
              return;
            }
          }
        }
      }

      // Long text or image — save to file and insert path
      final path = await ClipboardFileService.instance.saveClipboardToFile();
      if (path != null && mounted) {
        // Clear any text that the default paste might have inserted
        // (we schedule this after the current frame)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentText = _inputController.text;
          // Replace the pasted long text with the file path
          _inputController.text = currentText.isEmpty ? path : '$currentText $path';
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
        });
      }
    } catch (e) {
      debugPrint('[ChatPanel] Smart paste error: $e');
    }
  }

  String _shortPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 3) return path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Setup view (folder + session + model picker)
// ─────────────────────────────────────────────────────────────────────────────

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
  late String _selectedModel;

  @override
  void initState() {
    super.initState();
    _sessionCtrl = TextEditingController(text: widget.config.sessionName);
    _dirCtrl = TextEditingController(text: widget.config.workingDir);
    _selectedModel = widget.config.model;
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
    widget.onStart(ChatSessionConfig(
      sessionName: sessionName,
      workingDir: dir,
      model: _selectedModel,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Setup AI Chat',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE2E8F0),
            ),
          ),
          const SizedBox(height: 12),

          // Working directory
          const Text(
            'Working Directory',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dirCtrl,
                  readOnly: true,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
                  decoration: InputDecoration(
                    hintText: 'Select a project folder…',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.folder_open, size: 20, color: Color(0xFF34D399)),
                splashRadius: 18,
                tooltip: 'Browse…',
                onPressed: () async {
                  final dir = await FilePicker.getDirectoryPath(
                    dialogTitle: 'Select working directory',
                  );
                  if (dir != null) {
                    setState(() => _dirCtrl.text = dir);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Session name (optional)
          const Text(
            'Session Name (optional)',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _sessionCtrl,
            style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
            decoration: InputDecoration(
              hintText: 'auto-generated if empty',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),

          // Model selector
          const Text(
            'Model',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedModel,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
                items: widget.models.map((m) => DropdownMenuItem(
                  value: m.id,
                  child: Row(
                    children: [
                      Expanded(child: Text(m.displayName)),
                      Text(
                        '${m.costMultiplier}x',
                        style: TextStyle(
                          fontSize: 10,
                          color: m.costMultiplier == 0
                              ? const Color(0xFF34D399)
                              : m.costMultiplier > 3
                                  ? const Color(0xFFF87171)
                                  : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedModel = v);
                },
              ),
            ),
          ),

          const Spacer(),

          FilledButton.icon(
            onPressed: _dirCtrl.text.trim().isEmpty ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Chat'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF34D399),
              foregroundColor: const Color(0xFF0F172A),
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

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    // Check if content is a file reference (from clipboard paste)
    final isImageFile = content.startsWith('/') &&
        RegExp(r'\.(png|jpg|jpeg|gif|webp|bmp)$', caseSensitive: false).hasMatch(content);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, left: 40),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: isImageFile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                        child: Image.file(File(content), fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      content.split('/').last,
                      style: const TextStyle(fontSize: 10, color: Color(0xFFBFDBFE)),
                    ),
                  ],
                )
              : Text(
                  content,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.content,
    this.toolCalls = const [],
    this.tokenUsage,
  });
  final String content;
  final List<ChatToolCall> toolCalls;
  final ChatTokenUsage? tokenUsage;

  @override
  Widget build(BuildContext context) {
    // Preprocess: replace <br> tags with newlines for markdown rendering
    final processedContent = content
        .replaceAll(RegExp(r'<br\s*/?>'), '\n');

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, right: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tool call badges (if the assistant invoked tools in this message)
          if (toolCalls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 4,
                children: toolCalls.map((tc) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x20FBBF24),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0x40FBBF24)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.build_outlined, size: 10, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 4),
                      Text(
                        tc.toolName,
                        style: const TextStyle(fontSize: 10, color: Color(0xFFFBBF24)),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: MarkdownBody(
              data: processedContent.isEmpty ? '_thinking…_' : processedContent,
              onTapLink: (text, href, title) {
                if (href != null && href.isNotEmpty) {
                  PlatformLauncher.instance.openUrl(href);
                }
              },
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
                a: const TextStyle(fontSize: 13, color: Color(0xFF60A5FA), decoration: TextDecoration.underline),
                code: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF34D399),
                  backgroundColor: Color(0xFF0F172A),
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // Token usage
          if (tokenUsage != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                '${tokenUsage!.outputTokens} tokens',
                style: const TextStyle(fontSize: 10, color: Color(0xFF475569)),
              ),
            ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final statusIcon = widget.success == null
        ? Icons.hourglass_top
        : widget.success!
            ? Icons.check_circle_outline
            : Icons.error_outline;
    final statusColor = widget.success == null
        ? const Color(0xFF94A3B8)
        : widget.success!
            ? const Color(0xFF34D399)
            : const Color(0xFFF87171);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Icon(Icons.build_outlined, size: 12, color: const Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.toolName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
              if (_expanded && widget.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      widget.content,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF94A3B8),
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
                const Icon(Icons.help_outline, size: 16, color: Color(0xFF818CF8)),
                const SizedBox(width: 6),
                const Text(
                  'Agent asks:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF818CF8)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              question,
              style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
            ),
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: choices.map((choice) => OutlinedButton(
                  onPressed: () => onChoice(choice),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF818CF8),
                    side: const BorderSide(color: Color(0xFF818CF8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(choice),
                )).toList(),
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
            final opacity = (0.3 + 0.7 * (1.0 - (t * 2 - 1).abs())).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF94A3B8),
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
