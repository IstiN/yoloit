import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    if (widget.targetPanel.state['yoloAssistant'] == null) {
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
      if (widget.targetPanel.state['yoloAssistant'] == null) {
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
    const defaultConfig = ChatSessionConfig(
      sessionName: '',
      workingDir: '',
      provider: 'local',
    );
    final savedConfig = state['config'];
    if (savedConfig is Map) {
      final saved = ChatSessionConfig.fromJson(
        Map<String, dynamic>.from(savedConfig),
      );
      state['config'] =
          defaultConfig
              .copyWith(
                sessionName: saved.sessionName,
                workingDir: saved.workingDir,
              )
              .toJson();
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

    final rawConfig = _assistantPanel.state['config'];
    final config =
        rawConfig is Map
            ? ChatSessionConfig.fromJson(Map<String, dynamic>.from(rawConfig))
            : const ChatSessionConfig(
              sessionName: '',
              workingDir: '',
              provider: 'local',
            );
    if (config.provider == providerType) return;

    final newState = {
      ..._assistantPanel.state,
      'config': config.copyWith(provider: providerType).toJson(),
    };
    _onAssistantStateChanged(newState);
  }

  void _toggleExpanded() {
    final next = !_expanded;
    widget.onExpandedChanged(next);
    setState(() => _expanded = next);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      left: 12,
      bottom: 12,
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
              headerTrailing: HeaderIconButton(
                icon: Icons.close,
                tooltip: 'Close YoLo assistant',
                onPressed: _toggleExpanded,
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
    );
  }
}
