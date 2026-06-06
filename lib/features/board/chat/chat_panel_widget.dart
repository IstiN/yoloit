import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:record/record.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';
import 'package:yoloit/core/platform/microphone_permission_service.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cloud_asr_service.dart';
import 'package:yoloit/features/board/chat/opencode_provider.dart';
import 'package:yoloit/features/board/chat/widgets/assistant_bubble.dart';
import 'package:yoloit/features/board/chat/widgets/chat_action_button.dart';
import 'package:yoloit/features/board/chat/widgets/chat_ask_user_card.dart';
import 'package:yoloit/features/board/chat/widgets/chat_context_toggles.dart';
import 'package:yoloit/features/board/chat/widgets/chat_info_bar.dart';
import 'package:yoloit/features/board/chat/widgets/chat_model_suggestions.dart';
import 'package:yoloit/features/board/chat/widgets/chat_running_tools_card.dart';
import 'package:yoloit/features/board/chat/widgets/chat_slash_chips.dart';
import 'package:yoloit/features/board/chat/widgets/chat_changed_files_strip.dart';
import 'package:yoloit/features/board/chat/widgets/chat_empty_state.dart';
import 'package:yoloit/features/board/chat/widgets/chat_setup_view.dart';
import 'package:yoloit/features/board/chat/widgets/chat_system_bubble.dart';
import 'package:yoloit/features/board/chat/widgets/chat_typing_indicator.dart';
import 'package:yoloit/features/board/chat/widgets/model_search_dialog.dart';
import 'package:yoloit/features/board/chat/widgets/session_history_dialog.dart';
import 'package:yoloit/features/board/chat/widgets/tool_result_card.dart';
import 'package:yoloit/features/board/chat/widgets/user_bubble.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';
import 'package:yoloit/features/settings/data/tool_call_settings_service.dart';
import 'package:yoloit/features/settings/ui/settings_page.dart';
import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';


/// The chat UI rendered inside a board panel.
///
/// Manages its own [ChatProvider] instance, message list, and streaming state.
class ChatPanelWidget extends StatefulWidget {
  const ChatPanelWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
    this.onCreateLinkedPanel,
    this.remoteInfo,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;
  final RemoteBoardInfo? remoteInfo;
  final Future<String?> Function(
    String typeId,
    Map<String, dynamic> state,
    String title,
  )?
  onCreateLinkedPanel;

  /// Global registry of processing notifiers keyed by panel ID.
  /// Used by [BoardPanelCard] to animate the border glow.
  static final Map<String, ValueNotifier<bool>> processingNotifiers = {};

  /// Fires whenever any panel's processing state changes. Used by minimap.
  static final ValueNotifier<int> processingChangeNotifier = ValueNotifier(0);

  @override
  State<ChatPanelWidget> createState() => _ChatPanelWidgetState();
}

class _ChatPanelWidgetState extends State<ChatPanelWidget>
    with SingleTickerProviderStateMixin {
  static final RegExp _brTagRe = RegExp(r'<br\s*/?>');

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  late AnimationController _glowCtrl;

  final _modelScrollCtrl = ScrollController();
  String _modelQuery = '';
  int _modelSelectedIndex = 0;

  late ChatProvider _provider;
  late ChatSessionConfig _config;
  ChatSession? _session;

  final List<ChatMessage> _messages = [];
  final Map<String, ChatToolCall> _activeToolCalls = {};
  final Set<String> _ignoredToolCallIds = <String>{};
  Set<String> _ignoredToolCalls = const {'report_intent'};
  bool _isProcessing = false;
  ChatTokenUsage? _lastUsage;
  int _totalOutputTokens = 0;

  // Sub-agent panel tracking: agentId → board panelId
  final Map<String, String> _subAgentPanels = {};
  // Sub-agent event log state: agentId → state
  final Map<String, SubAgentRunState> _subAgents = {};

  /// Persisted opencode session ID (survives widget rebuilds).
  String? _opencodeSessionId;
  String? _copilotSessionId;
  String? _cursorSessionId;

  /// Notifier for panel border animation.
  final ValueNotifier<bool> processingNotifier = ValueNotifier(false);

  // Streaming assistant message accumulator
  String _streamingContent = '';
  String? _streamingMessageId;
  // Insert position for the assistant message of the current turn.
  // Established as early as possible (send/tool/start) so tool results never
  // appear above the assistant text in providers that emit tools before final
  // assistant.message.
  int? _assistantInsertIndex;
  final AudioRecorder _micRecorder = AudioRecorder();
  bool _isRecordingMic = false;
  bool _isTranscribingMic = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _initConfig();
    ToolCallSettingsService.instance.load().then((_) {
      if (!mounted) return;
      _handleIgnoredToolsChanged();
    });
    ToolCallSettingsService.instance.ignoredToolsListenable.addListener(
      _handleIgnoredToolsChanged,
    );
    // Get or create session from manager — provider survives widget lifecycle.
    _session = ChatSessionManager.instance.getOrCreate(
      widget.panel.id,
      _config,
    );
    _provider = _session!.provider;

    // If opencode provider, refresh models and rebuild setup view once loaded.
    if (_provider is OpencodeProvider) {
      (_provider as OpencodeProvider).refreshModelsFromModelsDev().then((_) {
        if (mounted) setState(() {});
      });
    }

    // Restore messages from the session (source of truth).
    // The session accumulates messages via _handleCoreEvent even when
    // the widget is detached, so it always has the latest state.
    if (_session!.messages.isNotEmpty) {
      _messages.clear();
      _messages.addAll(_session!.messages);
      _isProcessing = _session!.isProcessing;
      _streamingContent = _session!.streamingContent;
      _streamingMessageId = _session!.streamingMessageId;
      _totalOutputTokens = _session!.totalOutputTokens;
      _lastUsage = _session!.lastUsage;
      if (_session!.opencodeSessionId != null) {
        _opencodeSessionId = _session!.opencodeSessionId;
      }
      if (_session!.copilotSessionId != null) {
        _copilotSessionId = _session!.copilotSessionId;
      }
      if (_session!.cursorSessionId != null) {
        _cursorSessionId = _session!.cursorSessionId;
      }
      // If the session finished processing while we were away, update UI
      if (_isProcessing) {
        _setProcessing(true);
      }
    } else if (_messages.isNotEmpty) {
      // First mount with persisted board state — feed into session.
      final savedMessages = widget.panel.state['messages'];
      if (savedMessages is List) {
        _session!.restoreMessages(
          savedMessages
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList(),
        );
      }
      final savedUsage = widget.panel.state['lastUsage'];
      if (savedUsage is Map) {
        _session!.restoreLastUsage(Map<String, dynamic>.from(savedUsage));
      }
    }

    // Restore sessionID for opencode
    if (_config.provider == 'opencode') {
      if (_session!.opencodeSessionId != null) {
        _opencodeSessionId = _session!.opencodeSessionId;
      }
      if (_opencodeSessionId != null) {
        _provider.setSessionId(_config.sessionName, _opencodeSessionId!);
        _session!.restoreOpencodeSessionId(_opencodeSessionId);
      }
    }
    if (_config.provider == 'copilot') {
      if (_session!.copilotSessionId != null) {
        _copilotSessionId = _session!.copilotSessionId;
      }
      if (_copilotSessionId != null) {
        _provider.setSessionId(_config.sessionName, _copilotSessionId!);
        _session!.restoreCopilotSessionId(_copilotSessionId);
      }
    }
    if (_config.provider == 'cursor') {
      if (_session!.cursorSessionId != null) {
        _cursorSessionId = _session!.cursorSessionId;
      }
      if (_cursorSessionId != null) {
        _provider.setSessionId(_config.sessionName, _cursorSessionId!);
        _session!.restoreCursorSessionId(_cursorSessionId);
      }
    }

    // Re-attach UI callbacks if the session is still processing
    // (e.g. widget disposed mid-stream, now re-mounting)
    if (_session!.isProcessing) {
      _isSending = true;
      _setProcessing(true);
      _session!.attachUI(
        onEvent: _handleEvent,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isSending = false;
            _setProcessing(false);
            _messages
              ..clear()
              ..addAll(_session!.messages);
          });
          _persistMessages();
          _scrollToBottom();
        },
        onDone: () {
          if (!mounted) return;
          if (_config.provider == 'opencode') {
            final sid = _provider.getSessionId(_config.sessionName);
            if (sid != null && sid != _opencodeSessionId) {
              _opencodeSessionId = sid;
              widget.onUpdateState({
                ...widget.panel.state,
                'opencodeSessionId': sid,
              });
            }
          }
          if (_config.provider == 'copilot') {
            final sid = _provider.getSessionId(_config.sessionName);
            if (sid != null && sid != _copilotSessionId) {
              _copilotSessionId = sid;
              widget.onUpdateState({
                ...widget.panel.state,
                'copilotSessionId': sid,
              });
            }
          }
          if (_config.provider == 'cursor') {
            final sid = _provider.getSessionId(_config.sessionName);
            if (sid != null && sid != _cursorSessionId) {
              _cursorSessionId = sid;
              widget.onUpdateState({
                ...widget.panel.state,
                'cursorSessionId': sid,
              });
            }
          }
          setState(() {
            _isSending = false;
            _setProcessing(false);
            _messages
              ..clear()
              ..addAll(_session!.messages);
            _streamingContent = '';
            _streamingMessageId = null;
          });
          _persistMessages();
          _scrollToBottom();
          _playCompletionSound();
        },
      );
    }
    // Register processing notifier for board-level glow
    ChatPanelWidget.processingNotifiers[widget.panel.id] = processingNotifier;
    // Subscribe to session ChangeNotifier so CLI-driven changes
    // (sendMessage called headlessly) update the UI automatically.
    _session?.addListener(_onSessionChanged);
    _consumeCliPendingMessage();
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
            // Update session config — it will recreate the provider internally
            _session?.updateConfig(nextConfig);
            _provider = _session!.provider;
            // Restore sessionID for new provider
            if (nextConfig.provider == 'opencode' &&
                _opencodeSessionId != null) {
              _provider.setSessionId(
                nextConfig.sessionName,
                _opencodeSessionId!,
              );
            }
            if (nextConfig.provider == 'cursor' && _cursorSessionId != null) {
              _provider.setSessionId(nextConfig.sessionName, _cursorSessionId!);
            }
          } else {
            _session?.updateConfig(nextConfig);
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
      _config = const ChatSessionConfig(sessionName: '', workingDir: '');
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
    // Restore opencode session ID
    if (_config.provider == 'opencode') {
      final savedSessionId =
          widget.panel.state['opencodeSessionId'] ??
          (raw is Map ? raw['opencodeSessionId'] : null);
      if (savedSessionId is String && savedSessionId.isNotEmpty) {
        _opencodeSessionId = savedSessionId;
      }
    }
    if (_config.provider == 'copilot') {
      final savedSessionId =
          widget.panel.state['copilotSessionId'] ??
          (raw is Map ? raw['copilotSessionId'] : null);
      if (savedSessionId is String && savedSessionId.isNotEmpty) {
        _copilotSessionId = savedSessionId;
      }
    }
    if (_config.provider == 'cursor') {
      final savedSessionId =
          widget.panel.state['cursorSessionId'] ??
          (raw is Map ? raw['cursorSessionId'] : null);
      if (savedSessionId is String && savedSessionId.isNotEmpty) {
        _cursorSessionId = savedSessionId;
      }
    }
  }

  static const _maxSavedMessages = 100;

  void _persistMessages() {
    final trimmed =
        _messages.length > _maxSavedMessages
            ? _messages.sublist(_messages.length - _maxSavedMessages)
            : _messages;
    final messagesJson = trimmed.map((m) => m.toJson()).toList();
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
    widget.onUpdateState({
      ...widget.panel.state,
      'config': configJson,
      'messages': messagesJson,
      'lastUsage': _lastUsage?.toJson(),
      if (_opencodeSessionId != null) 'opencodeSessionId': _opencodeSessionId,
      if (_copilotSessionId != null) 'copilotSessionId': _copilotSessionId,
      if (_cursorSessionId != null) 'cursorSessionId': _cursorSessionId,
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
    ToolCallSettingsService.instance.ignoredToolsListenable.removeListener(
      _handleIgnoredToolsChanged,
    );
    _session?.removeListener(_onSessionChanged);
    // Safety net: if the board is switched before the first opencode event
    // arrives (so _handleEvent never had a chance to run), persist the session
    // ID now so the next mount can resume the session correctly.
    if (_config.provider == 'opencode' && _opencodeSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _opencodeSessionId = sid;
        widget.onUpdateState({...widget.panel.state, 'opencodeSessionId': sid});
      }
    }
    if (_config.provider == 'copilot' && _copilotSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _copilotSessionId = sid;
        widget.onUpdateState({...widget.panel.state, 'copilotSessionId': sid});
      }
    }
    if (_config.provider == 'cursor' && _cursorSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _cursorSessionId = sid;
        widget.onUpdateState({...widget.panel.state, 'cursorSessionId': sid});
      }
    }
    // Persist current messages to board state
    _persistMessages();
    // Detach from session — session keeps its stream subscription alive.
    // The session already has accurate messages via _handleCoreEvent.
    // When the widget re-mounts, it reads from session.messages.
    ChatSessionManager.instance.detach(widget.panel.id);
    _session = null;
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _modelScrollCtrl.dispose();
    _glowCtrl.dispose();
    unawaited(_micRecorder.dispose());
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

  /// Called when the session changes via ChangeNotifier (e.g. CLI-driven
  /// sendMessage while the widget is mounted but not actively sending).
  void _onSessionChanged() {
    if (!mounted) return;
    final session = _session;
    if (session == null) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(session.messages);
      _isProcessing = session.isProcessing;
      _streamingContent = session.streamingContent;
      _streamingMessageId = session.streamingMessageId;
    });
    if (session.messages.isNotEmpty) {
      _scrollToBottom();
    }
    // Re-attach UI callbacks if session started processing externally
    if (session.isProcessing && !_isSending) {
      _isSending = true;
      _setProcessing(true);
      session.attachUI(
        onEvent: _handleEvent,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isSending = false;
            _setProcessing(false);
            _messages
              ..clear()
              ..addAll(session.messages);
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isSending = false;
            _setProcessing(false);
            _messages
              ..clear()
              ..addAll(session.messages);
            _streamingContent = '';
            _streamingMessageId = null;
          });
          _persistMessages();
          _scrollToBottom();
          _playCompletionSound();
        },
      );
    }
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

  static const _subAgentToolNames = <String>{
    'task',
    'run_agent',
    'agent',
    'subagent',
    'sub_agent',
  };

  bool _isSubAgentToolCall(String toolName) =>
      _subAgentToolNames.contains(toolName.toLowerCase().trim());

  /// Creates a markdown note panel on the current board with the sub-agent output.
  Future<void> _sendToolResultToPanel({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String content,
  }) async {
    final board = _currentBoardForPanel();
    if (board == null) return;

    final agentName =
        (arguments['name'] as String?)?.trim() ??
        (arguments['description'] as String?)?.trim() ??
        toolName;
    final agentType = (arguments['agent_type'] as String?)?.trim() ?? '';
    final title =
        '🤖 ${agentName.isNotEmpty ? agentName : toolName}${agentType.isNotEmpty ? ' ($agentType)' : ''}';

    // Format the note content with metadata header + result
    final agentPrompt = (arguments['prompt'] as String?)?.trim() ?? '';
    final buf = StringBuffer();
    buf.writeln('# $title');
    buf.writeln();
    if (agentPrompt.isNotEmpty) {
      buf.writeln('**Task:** $agentPrompt');
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln();
    buf.write(content);

    final noteContent = buf.toString();
    final cwd = _config.workingDir.isNotEmpty ? _config.workingDir : null;

    try {
      await Process.run(
        'yoloit',
        ['note:create', board.name, title, noteContent],
        workingDirectory: cwd,
        runInShell: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📋 Agent output → panel "$title"'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Silently ignore — panel creation is best-effort
    }
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

  Future<void> _stopStreaming() async {
    if (!_isSending) return;
    // Immediately flip UI so the button responds at once.
    if (mounted) {
      setState(() {
        _streamingContent = '';
        _streamingMessageId = null;
        _assistantInsertIndex = null;
        _activeToolCalls.clear();
        _ignoredToolCallIds.clear();
        _isSending = false;
        _setProcessing(false);
      });
    }
    // Kill the underlying provider process in the background.
    final session = _session;
    if (session == null) return;
    await session.stopStreaming();
    // Sync final messages once the process has actually stopped.
    if (mounted && _session != null) {
      setState(() {
        _messages
          ..clear()
          ..addAll(_session!.messages);
      });
    }
  }

  BoardDocument? _currentBoardForPanel() {
    final state = context.read<BoardCubit>().state;
    for (final board in state.boards) {
      final hasPanel = board.panels.any((p) => p.id == widget.panel.id);
      if (hasPanel) return board;
    }
    return state.activeBoard;
  }

  String _availableBoardsSummary() {
    final boards = context.read<BoardCubit>().state.boards;
    final current = _currentBoardForPanel();
    return boards
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

    // Handle /context command — just clear input, the picker is shown inline
    if (text == '/context') {
      _inputController.clear();
      return;
    }

    setState(() => _isSending = true);
    if (overrideText == null) {
      _inputController.clear();
    }

    // If currently processing, stop the current stream first
    if (_isProcessing) {
      await _session!.stopStreaming();
      if (!mounted) return;
      // Sync finalized messages from session
      _messages
        ..clear()
        ..addAll(_session!.messages);
      setState(() {
        _streamingContent = '';
        _streamingMessageId = null;
        _assistantInsertIndex = null;
        _activeToolCalls.clear();
        _ignoredToolCallIds.clear();
      });
    }

    _assistantInsertIndex = _messages.length;

    final board = _currentBoardForPanel();

    // Capture board snapshot if enabled
    String? snapshotPath;
    String? snapshotBase64;
    final snapshotEnabled = await SessionPrefs.isBoardSnapshotEnabled();
    if (snapshotEnabled) {
      final screenshotSvc = BoardScreenshotService.instance;
      final isCloudProvider =
          _session!.provider.imageMode == ChatImageMode.base64;
      if (isCloudProvider) {
        snapshotBase64 = await screenshotSvc.captureBase64(pixelRatio: 0.5);
      } else {
        snapshotPath = await screenshotSvc.captureJpegFile(pixelRatio: 0.5);
      }
      // Clean up old snapshots in the background
      screenshotSvc.cleanupOldSnapshots();
    }

    // Route through the session — it owns the stream subscription.
    // When this widget is disposed, the session keeps processing events.
    final ok = _session!.sendMessage(
      text: text,
      attachments: overrideAttachments,
      runtimeContext: ChatRuntimeContext(
        boardId: board?.id,
        boardName: board?.name,
        panelId: widget.panel.id,
        panelTitle: widget.panel.title,
        panelType: widget.panel.type,
        availableBoardsSummary: _availableBoardsSummary(),
        currentBoardPanelsSummary:
            _ctxBoardPanelsJson ? _currentBoardPanelsSummary(board) : null,
        viewportScale: board?.viewport.scale,
        boardSnapshotPath: snapshotPath,
        boardSnapshotBase64: snapshotBase64,
      ),
      onEvent: _handleEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _isSending = false;
          _setProcessing(false);
          _assistantInsertIndex = null;
          _messages
            ..clear()
            ..addAll(_session!.messages);
        });
        _persistMessages();
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        // Persist opencode session ID after first message completes
        if (_config.provider == 'opencode') {
          final sid = _provider.getSessionId(_config.sessionName);
          if (sid != null && sid != _opencodeSessionId) {
            _opencodeSessionId = sid;
            widget.onUpdateState({
              ...widget.panel.state,
              'opencodeSessionId': sid,
            });
          }
        }
        if (_config.provider == 'copilot') {
          final sid = _provider.getSessionId(_config.sessionName);
          if (sid != null && sid != _copilotSessionId) {
            _copilotSessionId = sid;
            widget.onUpdateState({
              ...widget.panel.state,
              'copilotSessionId': sid,
            });
          }
        }
        setState(() {
          _isSending = false;
          _setProcessing(false);
          // Sync final messages from session (includes finalized streaming)
          _messages
            ..clear()
            ..addAll(_session!.messages);
          _streamingContent = '';
          _streamingMessageId = null;
          _assistantInsertIndex = null;
          _markAllActiveToolCallsCompleted();
        });
        _persistMessages();
        _scrollToBottom();
        // Play macOS system sound on completion
        _playCompletionSound();
      },
    );

    if (!ok) {
      setState(() => _isSending = false);
      return;
    }

    // Sync user message and state from session for immediate render
    setState(() {
      _messages
        ..clear()
        ..addAll(_session!.messages);
      _setProcessing(true);
      _streamingContent = '';
      _streamingMessageId = null;
      _activeToolCalls.clear();
      _ignoredToolCallIds.clear();
    });

    _scrollToBottom();
  }

  void _playCompletionSound() {
    try {
      Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
    } catch (_) {}
  }

  void _handleEvent(ChatEvent event) {
    // Persist provider session IDs as soon as the provider captures them
    // (which happens on the first event). Doing it here — rather than only in
    // onDone — means the ID survives a board switch that happens mid-message.
    if (_config.provider == 'opencode' && _opencodeSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _opencodeSessionId = sid;
        widget.onUpdateState({...widget.panel.state, 'opencodeSessionId': sid});
      }
    }
    if (_config.provider == 'copilot' && _copilotSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _copilotSessionId = sid;
        widget.onUpdateState({...widget.panel.state, 'copilotSessionId': sid});
      }
    }
    if (_config.provider == 'cursor' && _cursorSessionId == null) {
      final sid = _provider.getSessionId(_config.sessionName);
      if (sid != null) {
        _cursorSessionId = sid;
        widget.onUpdateState({...widget.panel.state, 'cursorSessionId': sid});
      }
    }

    switch (event.type) {
      case ChatEventType.assistantMessageStart:
        setState(() {
          _streamingMessageId = event.messageId;
          _streamingContent = '';
          _assistantInsertIndex ??= _messages.length;
        });

      case ChatEventType.assistantDelta:
        final delta = event.deltaContent;
        if (delta != null) {
          setState(() {
            _streamingContent += delta;
          });
          _scrollToBottom();
        }

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

          // Insert at the position saved when streaming started so the
          // assistant text appears before any tool-result messages that were
          // added while the assistant was still streaming (cursor-agent sends
          // tool events before the final assistantMessage event).
          final insertAt = _assistantInsertIndex?.clamp(0, _messages.length);
          if (insertAt != null && insertAt < _messages.length) {
            _messages.insert(
              insertAt,
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
          } else {
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
          }
          _streamingMessageId = null;
          _streamingContent = '';
          _assistantInsertIndex = null;
        });
        _scrollToBottom();

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
          _assistantInsertIndex ??= _messages.length;
          _activeToolCalls[toolCallId] = ChatToolCall(
            toolCallId: toolCallId,
            toolName: toolName,
            arguments: event.toolArguments ?? {},
            isRunning: true,
          );
        });
        _scrollToBottom();

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
        // Notify any open file preview panels to refresh their content.
        for (final path in changedFiles) {
          BoardEventBus.instance.fileModified(path);
        }
        setState(() {
          _assistantInsertIndex ??= _messages.length;
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
      case ChatEventType.sessionStatus:
      case ChatEventType.userMessage:
      case ChatEventType.assistantTurnStart:
      case ChatEventType.assistantTurnEnd:
      case ChatEventType.unknown:
        break;

      // ── Sub-agent panel events ────────────────────────────────────────────
      case ChatEventType.subagentStarted:
        final agentId = event.agentId ?? event.toolCallId ?? '';
        if (agentId.isEmpty) break;
        // Deduplicate: ignore if we already have this agent (event can fire >1×)
        if (_subAgents.containsKey(agentId)) break;
        final agentName = event.agentName ?? 'Agent';
        final agentDesc = event.agentDescription ?? '';
        final state = SubAgentRunState(
          agentId: agentId,
          agentName: agentName,
          agentDescription: agentDesc,
        );
        setState(() => _subAgents[agentId] = state);
        // Create a linked board panel (to the right, with arrow) for the agent log
        unawaited(_createAgentLogPanel(agentId, agentName, agentDesc));

      case ChatEventType.subagentToolStart:
        final agentId = event.agentId ?? '';
        final state = _subAgents[agentId];
        if (state == null) break;
        setState(() {
          state.events.add(
            SubAgentEvent(
              type: 'tool_start',
              toolName: event.toolName ?? '',
              timestamp: event.timestamp ?? DateTime.now(),
            ),
          );
        });
        unawaited(_updateAgentPanel(agentId));

      case ChatEventType.subagentToolComplete:
        final agentId = event.agentId ?? '';
        final state = _subAgents[agentId];
        if (state == null) break;
        final toolName =
            event.toolName ?? event.data['toolName'] as String? ?? '';
        final success = event.data['success'] as bool? ?? true;
        final resultContent = event.toolResultContent ?? '';
        setState(() {
          state.events.add(
            SubAgentEvent(
              type: success ? 'tool_complete' : 'tool_error',
              toolName: toolName,
              content:
                  resultContent.length > 120
                      ? '${resultContent.substring(0, 120)}…'
                      : resultContent,
              timestamp: event.timestamp ?? DateTime.now(),
            ),
          );
        });
        unawaited(_updateAgentPanel(agentId));

      case ChatEventType.subagentMessage:
        final agentId = event.agentId ?? '';
        final state = _subAgents[agentId];
        if (state == null) break;
        final content = event.messageContent ?? '';
        if (content.isEmpty) break;
        setState(() {
          state.events.add(
            SubAgentEvent(
              type: 'message',
              content:
                  content.length > 300
                      ? '${content.substring(0, 300)}…'
                      : content,
              timestamp: event.timestamp ?? DateTime.now(),
            ),
          );
        });
        unawaited(_updateAgentPanel(agentId));

      case ChatEventType.subagentCompleted:
        final agentId = event.agentId ?? event.toolCallId ?? '';
        final state = _subAgents[agentId];
        if (state == null) break;
        setState(() {
          state.isRunning = false;
          // Also mark the outer task tool call as completed so it leaves
          // the running-tools card. The CLI stdout may not emit toolComplete
          // for the task tool itself — subagentCompleted is the signal.
          final existing = _activeToolCalls[agentId];
          if (existing != null && existing.isRunning) {
            _activeToolCalls[agentId] = existing.copyWith(isRunning: false);
          }
        });
        unawaited(_updateAgentPanel(agentId));
    }
  }

  // ── Sub-agent panel helpers ───────────────────────────────────────────────

  /// Creates a linked note panel on the board for the sub-agent log.
  Future<void> _createAgentLogPanel(
    String agentId,
    String agentName,
    String agentDescription,
  ) async {
    if (!mounted) return;
    final createPanel = widget.onCreateLinkedPanel;
    if (createPanel == null) return;
    final title = '🤖 $agentName';
    final markdown = _buildAgentMarkdown(agentId);
    final panelId = await createPanel('board.note.markdown', {
      'markdown': markdown,
      'autoScroll': true,
    }, title);
    if (panelId != null) {
      _subAgentPanels[agentId] = panelId;
      // Don't re-focus on every event update — just open once
    }
  }

  /// Rebuilds and updates the agent log panel content.
  Future<void> _updateAgentPanel(String agentId) async {
    final panelId = _subAgentPanels[agentId];
    if (panelId == null || !mounted) return;
    final state = _subAgents[agentId];
    if (state == null) return;
    final markdown = _buildAgentMarkdown(agentId);
    try {
      await context.read<BoardCubit>().updateMarkdownNote(
        panelId,
        title: '🤖 ${state.agentName}',
        markdown: markdown,
      );
    } catch (_) {}
  }

  String _buildAgentMarkdown(String agentId) {
    final state = _subAgents[agentId];
    if (state == null) return '';
    final buf = StringBuffer();
    buf.writeln('# 🤖 ${state.agentName}');
    if (state.agentDescription.isNotEmpty) {
      buf.writeln();
      buf.writeln('> ${state.agentDescription}');
    }
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('```');
    for (final ev in state.events) {
      final time =
          '${ev.timestamp.hour.toString().padLeft(2, '0')}:'
          '${ev.timestamp.minute.toString().padLeft(2, '0')}:'
          '${ev.timestamp.second.toString().padLeft(2, '0')}';
      switch (ev.type) {
        case 'tool_start':
          buf.writeln('$time  ▶ ${ev.toolName}');
        case 'tool_complete':
          final preview =
              ev.content?.isNotEmpty == true ? '  → ${ev.content}' : '';
          buf.writeln('$time  ✓ ${ev.toolName}$preview');
        case 'tool_error':
          buf.writeln('$time  ✗ ${ev.toolName}');
        default: // message
          buf.writeln('$time  » ${ev.content ?? ''}');
      }
    }
    if (state.isRunning) {
      buf.writeln('...');
    }
    buf.writeln('```');
    buf.writeln();
    buf.writeln(state.isRunning ? '*Running…*' : '*Completed.*');
    return buf.toString();
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

  @override
  Widget build(BuildContext context) {
    final configured = widget.panel.state['configured'] == true;
    if (!configured) {
      return _buildSetupView();
    }
    return _buildChatView();
  }

  // ── Setup view (pick folder + session name + model) ─────────────────────

  Widget _buildSetupView() {
    return ChatSetupView(
      panelId: widget.panel.id,
      config: _config,
      models: _provider.availableModels,
      remoteInfo: widget.remoteInfo,
      onStart: (config) {
        setState(() {
          // Update session config — it handles provider swap internally
          _session?.updateConfig(config);
          _provider = _session!.provider;
          _config = config;
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
          ChatInfoBar(
            workingDir: _config.workingDir,
            provider: _config.provider,
            model: _config.model,
            autopilot: _config.autopilot,
            reasoningEffort: _config.reasoningEffort,
            totalOutputTokens: _totalOutputTokens,
            isProcessing: _isProcessing,
            enabledLocalToolCount: _enabledLocalToolCount(),
            totalLocalToolCount: YoloitCliToolCatalog.tools.length,
            onAutopilotToggle: () {
              setState(() {
                _config = _config.copyWith(autopilot: !_config.autopilot);
              });
              _persistMessages();
            },
            onCycleReasoningEffort: _cycleReasoningEffort,
            onCopySession: _copySessionToClipboard,
            onShowHistory: () => _showSessionHistoryDialog(context),
            shortPath: _shortPath,
          ),
          // Messages
          Expanded(
            child:
                _messages.isEmpty && !_isProcessing
                    ? const ChatEmptyState()
                    : _buildMessageList(),
          ),
          // Input
          _buildInputBar(),
        ],
      ),
    );
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

  Set<String> _disabledLocalTools() =>
      _config.disabledLocalToolNames.map((name) => name.trim()).toSet();

  int _enabledLocalToolCount() =>
      YoloitCliToolCatalog.tools.length - _disabledLocalTools().length;

  Future<void> _showLocalToolsDialog() async {
    final colors = context.appColors;
    final muted =
        context.appColors.textMuted.withAlpha(153);
    var disabled = _disabledLocalTools();
    final tools = [...YoloitCliToolCatalog.tools]..sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      return byGroup == 0 ? a.command.compareTo(b.command) : byGroup;
    });

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              void persist(Set<String> next) {
                disabled = {...next};
                final sorted = disabled.toList()..sort();
                setState(() {
                  _config = _config.copyWith(disabledLocalToolNames: sorted);
                });
                _persistMessages();
              }

              Widget buildToolTile(YoloitCliTool tool) {
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
                            fontWeight: FontWeight.w600,
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
                            ).colorScheme.error.withAlpha(31),
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
                    const Expanded(child: Text('YoLo Chat tools')),
                    Text(
                      '${_enabledLocalToolCount()}/${tools.length}',
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
                        'Checked tools are exposed to the local LLM. Unchecked tools are removed from the tool schema and blocked if the model still tries to call them.',
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
                              ...entry.value.map(buildToolTile),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setDialogState(() => persist(<String>{}));
                    },
                    child: const Text('Enable all'),
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

  Widget _buildMessageList() {
    final runningTools =
        _activeToolCalls.values
            .where((t) => t.isRunning && !_isIgnoredToolCall(t.toolName))
            .toList();
    final hasRunningTools = runningTools.isNotEmpty;
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
        if (index < _messages.length) {
          return _buildMessageBubble(_messages[index]);
        }

        final extra = index - _messages.length;

        // Running tools indicator
        if (hasRunningTools && extra == 0) {
          return ChatRunningToolsCard(
            tools: runningTools,
            subAgents: _subAgents,
            subAgentPanels: _subAgentPanels,
            isSubAgentToolCall: _isSubAgentToolCall,
            onFocusPanel: (panelId) {
              context.read<BoardCubit>().focusPanel(panelId);
            },
          );
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
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: const ChatTypingIndicator(),
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
        return UserBubble(
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
        return AssistantBubble(
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
        final toolArgs = _activeToolCalls[message.toolCallId]?.arguments ?? {};
        return ToolResultCard(
          toolName: resolvedToolName,
          toolCallId: message.toolCallId ?? '',
          content: message.content,
          success:
              _activeToolCalls[message.toolCallId]?.success ?? persistedSuccess,
          onSendToPanel:
              message.content.isNotEmpty
                  ? () => unawaited(
                    _sendToolResultToPanel(
                      toolName: resolvedToolName,
                      arguments: toolArgs,
                      content: message.content,
                    ),
                  )
                  : null,
          onOpenAgentPanel:
              _isSubAgentToolCall(resolvedToolName) &&
                      _subAgentPanels.containsKey(message.toolCallId)
                  ? () => context.read<BoardCubit>().focusPanel(
                    _subAgentPanels[message.toolCallId]!,
                  )
                  : null,
        );
      case ChatRole.system:
        final meta = message.metadata;
        if (meta != null && meta['type'] == 'ask_user') {
          return ChatAskUserCard(
            question: message.content,
            choices: (meta['choices'] as List?)?.cast<String>() ?? [],
            onChoice: (choice) {
              _inputController.text = choice;
              _sendMessage();
            },
          );
        }
        return ChatSystemBubble(content: message.content);
    }
  }

  Widget _buildStreamingBubble() {
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final codeBg = colors.surface;
    final processedContent = _streamingContent.replaceAll(_brTagRe, '\n');
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child:
            processedContent.isEmpty
                ? const ChatTypingIndicator()
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
        context.appColors.textMuted.withAlpha(153);
    final changedFiles = _collectChangedFilesForStrip();
    return Container(
      margin: const EdgeInsets.fromLTRB(1.5, 0, 1.5, 1.5),
      padding: const EdgeInsets.fromLTRB(10, 8, 22, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (changedFiles.isNotEmpty) ...[
            ChatChangedFilesStrip(
              files: changedFiles,
              onOpenFile: _openInPreviewPanel,
            ),
            const SizedBox(height: 8),
          ],
          if (_isPlainSlash) ...[
            ChatSlashChips(
              commands: _filteredSlashCommands,
              onSelect: (cmd) {
                _inputController.text = '${cmd.triggers.first} ';
                _inputController.selection = TextSelection.collapsed(
                  offset: _inputController.text.length,
                );
                if (cmd.id == 'model') {
                  setState(() {
                    _isModelSlash = true;
                    _modelQuery = '';
                    _modelSelectedIndex = 0;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
          ],
          if (_isModelSlash) ...[
            ChatModelSuggestions(
              models: _filteredModels,
              selectedIndex: _modelSelectedIndex,
              currentModelId: _config.model,
              scrollController: _modelScrollCtrl,
              onSelect: _selectModelFromSlash,
            ),
            const SizedBox(height: 8),
          ],
          if (_isContextSlash) ...[
            ChatContextToggles(
              cliHelp: _ctxCliHelp,
              boardSnapshot: _ctxBoardSnapshot,
              boardPanelsJson: _ctxBoardPanelsJson,
              systemPrompt: _ctxSystemPrompt,
              onCliHelpChanged: (v) async {
                await SessionPrefs.saveInjectCliHelpEnabled(v);
                CliGuidanceService.instance.clearCache();
                if (!mounted) return;
                setState(() => _ctxCliHelp = v);
              },
              onBoardSnapshotChanged: (v) async {
                await SessionPrefs.saveBoardSnapshotEnabled(v);
                if (!mounted) return;
                setState(() => _ctxBoardSnapshot = v);
              },
              onBoardPanelsJsonChanged: (v) {
                setState(() => _ctxBoardPanelsJson = v);
              },
              onSystemPromptChanged: (v) {
                setState(() => _ctxSystemPrompt = v);
              },
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Model selector (bottom-left)
              Builder(
                builder:
                    (btnContext) => ChatActionButton(
                      icon: Icons.auto_awesome,
                      onTap: () => _showModelPicker(btnContext),
                      backgroundColor: colors.surfaceElevated,
                      iconColor: colors.terminalPrompt,
                    ),
              ),
              const SizedBox(width: 8),
              if (_config.provider == 'local') ...[
                ChatActionButton(
                  icon: Icons.settings_input_component_outlined,
                  onTap: _showLocalToolsDialog,
                  tooltip:
                      'Choose local YoLoIT tools (${_enabledLocalToolCount()} enabled)',
                  backgroundColor: colors.surfaceElevated,
                  iconColor:
                      _config.disabledLocalToolNames.isEmpty
                          ? colors.terminalPrompt
                          : Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }

                    if (_isModelSlash) {
                      final isUp =
                          event.logicalKey == LogicalKeyboardKey.arrowUp;
                      final isDown =
                          event.logicalKey == LogicalKeyboardKey.arrowDown;
                      final isEnter =
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter;
                      final isEscape =
                          event.logicalKey == LogicalKeyboardKey.escape;
                      final isTab = event.logicalKey == LogicalKeyboardKey.tab;

                      if (isTab && _filteredModels.isNotEmpty) {
                        // Tab: select highlighted model
                        _selectModelFromSlash(
                          _filteredModels[_modelSelectedIndex].id,
                        );
                        return KeyEventResult.handled;
                      }

                      if (isUp || isDown) {
                        final delta = isDown ? 1 : -1;
                        final next = (_modelSelectedIndex + delta).clamp(
                          0,
                          _filteredModels.length - 1,
                        );
                        if (next == _modelSelectedIndex) {
                          return KeyEventResult.handled;
                        }
                        setState(() {
                          _modelSelectedIndex = next;
                        });
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _scrollToModelSelection(),
                        );
                        return KeyEventResult.handled;
                      }

                      if (isEnter &&
                          !HardwareKeyboard.instance.isShiftPressed &&
                          _filteredModels.isNotEmpty) {
                        _selectModelFromSlash(
                          _filteredModels[_modelSelectedIndex].id,
                        );
                        return KeyEventResult.handled;
                      }

                      if (isEscape) {
                        _hideModelSlash();
                        return KeyEventResult.handled;
                      }
                    }

                    if (_isPlainSlash) {
                      final isTab = event.logicalKey == LogicalKeyboardKey.tab;
                      if (isTab) {
                        _autoCompleteSlash();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        _hideModelSlash();
                        return KeyEventResult.handled;
                      }
                    }

                    // Enter (without Shift) → send
                    final isEnter =
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter;
                    if (isEnter && !HardwareKeyboard.instance.isShiftPressed) {
                      _sendMessage();
                      return KeyEventResult.handled;
                    }
                    // Cmd+V (macOS) or Ctrl+V → smart paste
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
                    onChanged: _onInputChanged,
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
              ChatActionButton(
                icon:
                    _isRecordingMic
                        ? Icons.mic_rounded
                        : (_isTranscribingMic
                            ? Icons.hourglass_top_rounded
                            : Icons.mic_none),
                onTap: _isTranscribingMic ? null : _handleMicInput,
                backgroundColor: colors.surfaceElevated,
                iconColor:
                    _isRecordingMic
                        ? Theme.of(context).colorScheme.error
                        : colors.terminalPrompt,
                iconSize: 15,
              ),
              const SizedBox(width: 6),
              ChatActionButton(
                icon: _isSending ? Icons.stop_rounded : Icons.arrow_upward,
                onTap: _isSending ? _stopStreaming : _sendMessage,
                backgroundColor:
                    _isSending
                        ? Theme.of(context).colorScheme.error
                        : colors.terminalPrompt,
                iconColor: Theme.of(context).colorScheme.onPrimary,
                iconSize: 16,
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

  Future<void> _handleMicInput() async {
    final effectiveAsr = AgentConfigService.instance.effectiveAsr(
      _config.provider,
    );
    final useCloudAsr =
        effectiveAsr.mode == 'cloud' &&
        effectiveAsr.configId != null &&
        effectiveAsr.configId!.isNotEmpty;
    if (!useCloudAsr) {
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

    if (_isRecordingMic) {
      await _stopRecordingAndTranscribe();
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
  }

  Future<void> _stopRecordingAndTranscribe() async {
    final path = await _micRecorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecordingMic = false;
      _isTranscribingMic = true;
    });

    try {
      if (path == null || path.isEmpty) return;

      // Check if this agent has a cloud ASR configured (including global default).
      final effectiveAsr = AgentConfigService.instance.effectiveAsr(
        _config.provider,
      );
      final useCloud =
          effectiveAsr.mode == 'cloud' &&
          effectiveAsr.configId != null &&
          effectiveAsr.configId!.isNotEmpty;

      String transcript;
      if (useCloud) {
        final cloudCfg = await CloudLlmSettingsService.instance.loadConfigById(
          effectiveAsr.configId!,
        );
        if (cloudCfg == null) {
          throw StateError(
            'Cloud ASR provider "${effectiveAsr.configId}" not found. '
            'Please check your AI Agents settings.',
          );
        }
        final voiceSettings = VoiceSettings(
          useCloudAsr: true,
          useChatModelForCloudAsr: false,
          cloudAsrConfigId: cloudCfg.id,
          cloudAsrModel:
              effectiveAsr.model?.trim().isNotEmpty == true
                  ? effectiveAsr.model
                  : cloudCfg.model.trim().isNotEmpty
                  ? cloudCfg.model
                  : 'whisper-1',
        );
        transcript = await CloudAsrService().transcribeFromFile(
          audioPath: path,
          voiceSettings: voiceSettings,
        );
      } else {
        transcript = await LocalAiModelsService.instance
            .transcribeWithSelectedAsr(path);
      }

      if (!mounted) return;
      final text = transcript.trim();
      if (text.isNotEmpty) {
        _insertTextAtCursor(text);
      }
    } catch (e) {
      if (!mounted) return;
      await _showCopyableErrorDialog(
        title: 'ASR error',
        message: 'ASR failed:\n$e',
      );
    } finally {
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (f.existsSync()) {
          try {
            await f.delete();
          } on FileSystemException {
            // ignore cleanup failure for temp recording
          }
        }
      }
      if (mounted) {
        setState(() => _isTranscribingMic = false);
      }
    }
  }

  String _shortPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 3) return path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  Future<void> _copySessionToClipboard() async {
    final transcript = _buildSessionTranscript();
    await copyToClipboard(transcript);
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
                  await copyToClipboard(message);
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

  void _showModelPicker(BuildContext context) {
    final models = _provider.availableModels;
    final inputFill = Theme.of(context).colorScheme.surfaceContainerHighest;
    showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return ModelSearchDialog(
          models: models,
          selectedId: _config.model,
          inputFill: inputFill,
        );
      },
    ).then((selected) {
      if (!mounted) return;
      if (selected != null && selected != _config.model) {
        setState(() {
          _config = _config.copyWith(model: selected);
        });
        _session?.updateConfig(_config);
        _persistMessages();
      }
    });
  }

  List<ChatModelInfo> get _filteredModels {
    final models = _provider.availableModels;
    if (_modelQuery.isEmpty) return models;
    final q = _modelQuery.toLowerCase();
    return models
        .where(
          (m) =>
              m.displayName.toLowerCase().contains(q) ||
              m.id.toLowerCase().contains(q) ||
              (m.providerGroup?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  static const _slashCommands = [
    ChatSlashCommand(
      id: 'model',
      displayName: 'model',
      description: 'Switch AI model',
      triggers: ['/model', '.model'],
    ),
    ChatSlashCommand(
      id: 'context',
      displayName: 'context',
      description: 'Toggle context injections',
      triggers: ['/context', '.context'],
    ),
  ];

  ChatSlashCommand? _findMatchingCommand(String text) {
    for (final c in _slashCommands) {
      if (c.matches(text)) return c;
    }
    return null;
  }

  void _onInputChanged(String value) {
    final cmd = _findMatchingCommand(value);
    final needsScroll = value.startsWith('/') || value.startsWith('.');
    setState(() {
      if (cmd != null) {
        final trigger = cmd.triggers.firstWhere(value.startsWith);
        _modelQuery =
            value.length > trigger.length
                ? value.substring(trigger.length).trimLeft()
                : '';
        _modelSelectedIndex = 0;
        _isModelSlash = cmd.id == 'model';
        _isContextSlash = cmd.id == 'context';
      } else {
        _modelQuery = '';
        _isModelSlash = false;
        _isContextSlash = false;
      }
    });
    if (needsScroll) _ensureSuggestionsVisible();
  }

  bool _isModelSlash = false;
  bool _isContextSlash = false;

  // ── Context toggles state ─────────────────────────────────────────────────
  bool _ctxCliHelp = true;
  bool _ctxBoardSnapshot = false;
  bool _ctxBoardPanelsJson = true;
  bool _ctxSystemPrompt = true;

  bool get _isPlainSlash {
    final t = _inputController.text;
    return (t.startsWith('/') || t.startsWith('.')) &&
        !_isModelSlash &&
        !_isContextSlash;
  }

  void _ensureSuggestionsVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToModelSelection() {
    if (!_modelScrollCtrl.hasClients) return;
    final target = 4.0 + _modelSelectedIndex * 32.0;
    final viewport = _modelScrollCtrl.position.viewportDimension;
    final currentScroll = _modelScrollCtrl.offset;
    if (target < currentScroll || target + 32 > currentScroll + viewport) {
      _modelScrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  List<ChatSlashCommand> get _filteredSlashCommands {
    final text = _inputController.text;
    if (text.length <= 1) return _slashCommands;
    final query = text.substring(1).toLowerCase();
    return _slashCommands.where((cmd) {
      return cmd.displayName.toLowerCase().startsWith(query) ||
          cmd.triggers.any(
            (t) => t.substring(1).toLowerCase().startsWith(query),
          );
    }).toList();
  }

  void _autoCompleteSlash() {
    final filtered = _filteredSlashCommands;
    if (filtered.isEmpty) return;
    final cmd = filtered.first;
    setState(() {
      _inputController.text = '${cmd.triggers.first} ';
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
      if (cmd.id == 'model') {
        _isModelSlash = true;
        _modelQuery = '';
        _modelSelectedIndex = 0;
      }
    });
  }

  void _hideModelSlash() {
    setState(() {
      _isModelSlash = false;
      _modelQuery = '';
    });
  }

  void _selectModelFromSlash(String modelId) {
    if (modelId != _config.model) {
      setState(() {
        _config = _config.copyWith(model: modelId);
      });
      _persistMessages();
    }
    _hideModelSlash();
    _inputController.clear();
    _inputFocusNode.requestFocus();
  }

  void _showSessionHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => SessionHistoryDialog(
            currentPanelId: widget.panel.id,
            onRestore: (entry, messages) {
              setState(() {
                _config = _config.copyWith(
                  provider: entry.provider,
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







