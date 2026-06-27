import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/ui/panel_yolo_assistant_badge.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_layout.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_scope.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';

/// Anchored YoLo assistant docked to the host panel badge tab.
class YoloAnchoredAssistantPanel extends StatefulWidget {
  const YoloAnchoredAssistantPanel({
    super.key,
    required this.anchorPanel,
    required this.canvasOrigin,
    required this.chatController,
    required this.startMic,
    required this.onStartMicConsumed,
    required this.onClose,
    this.chatBuilder,
  });

  final BoardPanelInstance anchorPanel;
  final Offset canvasOrigin;
  final ChatPanelController chatController;
  final bool startMic;
  final VoidCallback onStartMicConsumed;
  final VoidCallback onClose;
  final Widget Function(
    BoardPanelInstance assistantPanel,
    ValueChanged<Map<String, dynamic>> onUpdateState,
  )?
  chatBuilder;

  @override
  State<YoloAnchoredAssistantPanel> createState() =>
      _YoloAnchoredAssistantPanelState();
}

class _YoloAnchoredAssistantPanelState extends State<YoloAnchoredAssistantPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entry;
  late BoardPanelInstance _assistantPanel;
  BoardCubit? _cubit;
  bool _providerBootstrapped = false;

  ChatPanelController get _chatController => widget.chatController;

  void _requestChatInputFocus() {
    if (widget.startMic) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatController.focusInput();
    });
  }

  @override
  void initState() {
    super.initState();
    _assistantPanel = _buildAssistantPanel(widget.anchorPanel);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _entry = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeInOutCubic,
    );
    _entryController.forward();
    unawaited(_bootstrapProvider());
    if (widget.startMic) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        widget.onStartMicConsumed();
        await _chatController.startMic();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit = context.read<BoardCubit>();
  }

  @override
  void didUpdateWidget(covariant YoloAnchoredAssistantPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorPanel.id != widget.anchorPanel.id) {
      _providerBootstrapped = false;
      _assistantPanel = _buildAssistantPanel(widget.anchorPanel);
      unawaited(_bootstrapProvider());
    }
    if (!oldWidget.startMic && widget.startMic) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        widget.onStartMicConsumed();
        await _chatController.startMic();
      });
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  BoardPanelInstance _buildAssistantPanel(BoardPanelInstance anchor) {
    const chatPlugin = ChatPanelPlugin();
    final persisted = anchor.state['yoloAssistant'] as Map<String, dynamic>?;
    final state =
        persisted == null
              ? Map<String, dynamic>.from(chatPlugin.initialState)
              : Map<String, dynamic>.from(chatPlugin.initialState)
          ..addAll(persisted ?? const {});
    state['targetPanelId'] = anchor.id;
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
      id: 'yolo-badge-${anchor.id}',
      type: ChatPanelPlugin.kTypeId,
      title: 'YoLo: ${anchor.title}',
      bounds: YoloAnchoredAssistantLayout.dockedPanelBounds(anchor),
      state: state,
    );
  }

  void _onAssistantStateChanged(Map<String, dynamic> state) {
    if (!mounted) return;
    _assistantPanel = _assistantPanel.copyWith(state: state);
    _cubit?.updatePanel(
      widget.anchorPanel.id,
      (panel) =>
          panel.copyWith(state: {...panel.state, 'yoloAssistant': state}),
    );
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _bootstrapProvider() async {
    try {
      await _resolveDefaultProvider();
    } catch (_) {
      // Still mount chat — provider errors surface on send.
    }
    if (!mounted) return;
    setState(() => _providerBootstrapped = true);
    _requestChatInputFocus();
  }

  Future<void> _resolveDefaultProvider() async {
    if (!mounted) return;
    String providerPref;
    try {
      providerPref =
          await CloudLlmSettingsService.instance.loadAssistantProviderType();
    } on MissingPluginException {
      providerPref = 'local';
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
    final resolved = await _resolveAssistantProvider(
      providerPref: providerPref,
      config: config,
    );
    final resolvedModel =
        resolved.provider.startsWith('cloud:') ? resolved.model : null;
    if (config.provider == resolved.provider &&
        config.model == resolvedModel &&
        _assistantPanel.state['assistantProviderResolved'] == true) {
      return;
    }

    final nextConfigJson = config.toJson()
      ..['provider'] = resolved.provider
      ..['model'] = resolvedModel;
    _onAssistantStateChanged({
      ..._assistantPanel.state,
      'config': nextConfigJson,
      'assistantProviderResolved': true,
    });
  }

  Future<({String provider, String? model})> _resolveAssistantProvider({
    required String providerPref,
    required ChatSessionConfig config,
  }) async {
    final service = CloudLlmSettingsService.instance;

    if (providerPref == 'local') {
      return (provider: 'local', model: null);
    }

    if (config.provider.startsWith('cloud:')) {
      final configId = config.provider.substring(6);
      final persisted = await service.loadConfigById(configId);
      if (persisted != null) {
        return (provider: config.provider, model: persisted.model);
      }
      return (provider: config.provider, model: config.model);
    }

    final active = await service.loadActiveConfig();
    if (active != null) {
      return (provider: 'cloud:${active.id}', model: active.model);
    }

    final configs = await service.loadConfigs();
    if (configs.isNotEmpty) {
      final first = configs.first;
      return (provider: 'cloud:${first.id}', model: first.model);
    }

    const defaultPresetId = 'openrouter';
    final preset = kCloudLlmPresets.firstWhere((p) => p.id == defaultPresetId);
    return (provider: 'cloud:$defaultPresetId', model: preset.defaultModel);
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

  Future<void> _handleClose() async {
    if (_entryController.status == AnimationStatus.reverse ||
        _entryController.value == 0) {
      widget.onClose();
      return;
    }
    await _entryController.reverse();
    if (mounted) widget.onClose();
  }

  Widget _buildToolbar(AppColorScheme colors) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
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
            onPressed: _handleClose,
          ),
        ],
      ),
    );
  }

  Widget _buildDockedPanel(
    AppColorScheme colors,
    double width,
    Widget panelContent,
  ) {
    const outerRadius = BorderRadius.all(Radius.circular(16));
    const innerRadius = BorderRadius.all(Radius.circular(14.5));
    final frame = YoloAnchoredAssistantLayout.frameWidth;

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: outerRadius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.accentBlue, colors.primary],
          ),
          boxShadow: [
            BoxShadow(
              color: colors.textMuted.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          margin: EdgeInsets.all(frame),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: innerRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: panelContent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final panelContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(colors),
        Expanded(
          child: ScrollableCardRegion(
            child: ScrollableCardMarker(
              child:
                  !_providerBootstrapped
                      ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : widget.chatBuilder?.call(
                        _assistantPanel,
                        _onAssistantStateChanged,
                      ) ??
                          ChatPanelWidget(
                            panel: _assistantPanel,
                            onUpdateState: _onAssistantStateChanged,
                            compact: true,
                            controller: _chatController,
                          ),
            ),
          ),
        ),
      ],
    );

    return YoloAnchoredAssistantScope(
      anchorPanelId: widget.anchorPanel.id,
      chatController: widget.chatController,
      child: AnimatedBuilder(
        animation: _entry,
        builder: (context, child) {
          final t = _entry.value;
          final frame = YoloAnchoredAssistantLayout.animatedPanelBounds(
            widget.anchorPanel,
            t,
          );
          final fullW = PanelYoloAssistantBadge.expandedWidth;
          final contentOpacity = ((t - 0.22) / 0.55).clamp(0.0, 1.0);

          return Positioned(
            left: frame.x + widget.canvasOrigin.dx,
            top: frame.y + widget.canvasOrigin.dy,
            width: math.max(frame.width, 1),
            height: frame.height,
            child: ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Opacity(
                  opacity: contentOpacity,
                  child: _buildDockedPanel(colors, fullW, child!),
                ),
              ),
            ),
          );
        },
        child: panelContent,
      ),
    );
  }
}
