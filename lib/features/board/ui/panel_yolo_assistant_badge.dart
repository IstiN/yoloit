import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/ui/yolo_assistant_overlay_shell.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';

/// Hover-triggered inline YoLo assistant badge anchored to a board panel.
///
/// When collapsed it shows a gradient-bordered badge; when expanded it
/// renders the same [ChatPanelWidget] used by AI/Copilot/Yolo chat panels,
/// keeping the chat experience unified across the app.
class PanelYoloAssistantBadge extends StatefulWidget {
  const PanelYoloAssistantBadge({
    super.key,
    required this.targetPanel,
    required this.expanded,
    required this.onExpandedChanged,
    this.chatBuilder,
  });

  final BoardPanelInstance targetPanel;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// Optional builder used by tests to inject a stub chat body.
  final Widget Function(
    BoardPanelInstance assistantPanel,
    ValueChanged<Map<String, dynamic>> onUpdateState,
  )?
  chatBuilder;

  static const double badgeSize = 36;
  static const double expandedWidth = 360;
  static const double expandedHeight = 420;

  @override
  State<PanelYoloAssistantBadge> createState() =>
      _PanelYoloAssistantBadgeState();
}

class _PanelYoloAssistantBadgeState extends State<PanelYoloAssistantBadge> {
  bool _expanded = false;
  late BoardPanelInstance _assistantPanel;
  BoardCubit? _cubit;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded;
    _assistantPanel = _buildAssistantPanel();
    if (widget.targetPanel.state['yoloAssistant'] == null ||
        _assistantPanel.state['assistantProviderResolved'] != true) {
      _resolveDefaultProvider();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit = context.read<BoardCubit>();
  }

  @override
  void didUpdateWidget(covariant PanelYoloAssistantBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != _expanded) {
      setState(() => _expanded = widget.expanded);
    }
    if (oldWidget.targetPanel.id != widget.targetPanel.id) {
      _assistantPanel = _buildAssistantPanel();
      if (widget.targetPanel.state['yoloAssistant'] == null ||
          _assistantPanel.state['assistantProviderResolved'] != true) {
        _resolveDefaultProvider();
      }
    }
  }

  BoardPanelInstance _buildAssistantPanel() {
    const chatPlugin = ChatPanelPlugin();
    final persisted =
        widget.targetPanel.state['yoloAssistant'] as Map<String, dynamic>?;
    final state =
        persisted == null
              ? Map<String, dynamic>.from(chatPlugin.initialState)
              : Map<String, dynamic>.from(chatPlugin.initialState)
          ..addAll(persisted ?? const {});
    state['targetPanelId'] = widget.targetPanel.id;
    state['configured'] = true;
    state['assistantProviderResolved'] =
        (persisted?['assistantProviderResolved'] as bool?) ?? false;
    const defaultConfig = ChatSessionConfig(
      sessionName: '',
      workingDir: '',
      provider: 'local',
    );
    final savedConfig = state['config'];
    if (savedConfig is Map) {
      state['config'] =
          ChatSessionConfig.fromJson(
            Map<String, dynamic>.from(savedConfig),
          ).toJson();
    } else {
      state['config'] = defaultConfig.toJson();
    }
    return BoardPanelInstance(
      id: 'yolo-badge-${widget.targetPanel.id}',
      type: ChatPanelPlugin.kTypeId,
      title: 'YoLo: ${widget.targetPanel.title}',
      bounds: const BoardPanelBounds(
        x: 0,
        y: 0,
        width: PanelYoloAssistantBadge.expandedWidth,
        height: PanelYoloAssistantBadge.expandedHeight,
      ),
      state: state,
    );
  }

  void _onAssistantStateChanged(Map<String, dynamic> state) {
    if (!mounted) return;
    setState(() {
      _assistantPanel = _assistantPanel.copyWith(state: state);
    });
    _cubit?.updatePanel(
      widget.targetPanel.id,
      (panel) =>
          panel.copyWith(state: {...panel.state, 'yoloAssistant': state}),
    );
  }

  Future<void> _resolveDefaultProvider() async {
    if (!mounted) return;
    final providerPref =
        await CloudLlmSettingsService.instance.loadAssistantProviderType();
    final cloudConfig =
        providerPref == 'cloud'
            ? await CloudLlmSettingsService.instance.loadActiveConfig()
            : null;
    final String providerType;
    final String? model;
    if (providerPref == 'cloud' && cloudConfig != null && cloudConfig.isValid) {
      providerType = 'cloud:${cloudConfig.id}';
      model = cloudConfig.model;
    } else {
      providerType = 'local';
      model = null;
    }

    final rawConfig = _assistantPanel.state['config'];
    final config =
        rawConfig is Map
            ? ChatSessionConfig.fromJson(Map<String, dynamic>.from(rawConfig))
            : const ChatSessionConfig(
              sessionName: '',
              workingDir: '',
              provider: 'local',
            );
    final alreadyResolved = _assistantPanel.state['assistantProviderResolved'] == true;
    if (alreadyResolved &&
        config.provider == providerType &&
        (model == null || config.model == model)) {
      return;
    }

    final newState = {
      ..._assistantPanel.state,
      'config': config.copyWith(
        provider: providerType,
        model: model,
      ).toJson(),
      'assistantProviderResolved': true,
    };
    _onAssistantStateChanged(newState);
  }

  Future<void> _copyHistory() async {
    final messagesRaw = _assistantPanel.state['messages'];
    final buffer = StringBuffer();
    if (messagesRaw is List) {
      for (final raw in messagesRaw) {
        if (raw is! Map) continue;
        try {
          final message = ChatMessage.fromJson(
            Map<String, dynamic>.from(raw),
          );
          final ts = message.timestamp?.toIso8601String() ?? '-';
          final role = message.role.name.toUpperCase();
          final title =
              message.toolName?.isNotEmpty == true
                  ? '[$ts] $role (${message.toolName})'
                  : '[$ts] $role';
          buffer.writeln(title);
          if (message.attachments.isNotEmpty) {
            buffer.writeln(
              'Attachments: ${message.attachments.join(', ')}',
            );
          }
          buffer.writeln(message.content.trimRight());
          buffer.writeln('');
        } catch (_) {}
      }
    }
    await copyToClipboard(buffer.toString().trimRight());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('YoLo history copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleExpanded() {
    final next = !_expanded;
    widget.onExpandedChanged(next);
    setState(() => _expanded = next);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        width:
            _expanded
                ? PanelYoloAssistantBadge.expandedWidth
                : PanelYoloAssistantBadge.badgeSize,
        height:
            _expanded
                ? PanelYoloAssistantBadge.expandedHeight
                : PanelYoloAssistantBadge.badgeSize,
        child: Tooltip(
          message: 'Ask YoLo about this panel',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _toggleExpanded,
              child: YoloAssistantOverlayShell(
                expanded: _expanded,
                badgeSize: PanelYoloAssistantBadge.badgeSize,
                expandedWidth: PanelYoloAssistantBadge.expandedWidth,
                expandedHeight: PanelYoloAssistantBadge.expandedHeight,
                badgeOpacity: 1.0,
                badgeIcon: SvgPicture.asset(
                  'assets/images/yolo_voice_badge.svg',
                  width: 28,
                  height: 28,
                ),
                headerTrailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeaderIconButton(
                      icon: Icons.copy,
                      tooltip: 'Copy YoLo history',
                      onPressed: _copyHistory,
                    ),
                    const SizedBox(width: 4),
                    HeaderIconButton(
                      icon: Icons.close,
                      tooltip: 'Close YoLo assistant',
                      onPressed: _toggleExpanded,
                    ),
                  ],
                ),
                content:
                    widget.chatBuilder?.call(
                      _assistantPanel,
                      _onAssistantStateChanged,
                    ) ??
                    ChatPanelWidget(
                      panel: _assistantPanel,
                      onUpdateState: _onAssistantStateChanged,
                      compact: true,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
