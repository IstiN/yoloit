import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/provider_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/ui/chat_glow_wrapper.dart';
import 'package:yoloit/features/board/ui/panel_settings_dialog.dart';
import 'package:yoloit/features/board/ui/board_panel_resize_chrome.dart';
import 'package:yoloit/features/board/ui/board_panel_selection_metrics.dart';
import 'package:yoloit/features/board/ui/unified_panel_header.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/ui/components/layout/panel_content_toolbar.dart';

class BoardPanelCard extends StatefulWidget {
  const BoardPanelCard({
    super.key,
    required this.panel,
    required this.positionOffset,
    required this.onTap,
    required this.onMove,
    required this.onResize,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDelete,
    required this.onEditColor,
    required this.onBringToFront,
    required this.onSendToBack,
    this.onFullscreen,
    this.onEditNote,
    this.onUpdateState,
    this.onCreateLinkedPanel,
    this.connectMode = false,
    this.connectSourceId,
    this.onConnectTap,
    this.capturingScreenshot = false,
    this.selected = false,
  });

  final BoardPanelInstance panel;
  final Offset positionOffset;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onMove;
  final ValueChanged<BoardPanelResizeUpdate> onResize;
  final ValueChanged<DragStartDetails> onDragStart;
  final FutureOr<void> Function() onDragEnd;
  final VoidCallback onDelete;
  final VoidCallback onEditColor;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback? onFullscreen;
  final VoidCallback? onEditNote;
  final ValueChanged<Map<String, dynamic>>? onUpdateState;
  final Future<String?> Function(
    String typeId,
    Map<String, dynamic> state,
    String title,
  )?
  onCreateLinkedPanel;
  final bool connectMode;
  final String? connectSourceId;
  final VoidCallback? onConnectTap;
  final bool capturingScreenshot;
  final bool selected;

  @override
  State<BoardPanelCard> createState() => BoardPanelCardState();
}

class BoardPanelCardState extends State<BoardPanelCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  bool _isTransformingPanel = false;

  // Convenience getters so build code can still use widget.panel etc.
  BoardPanelInstance get panel => widget.panel;
  Offset get positionOffset => widget.positionOffset;
  VoidCallback get onTap => widget.onTap;
  ValueChanged<DragUpdateDetails> get onMove => widget.onMove;
  ValueChanged<BoardPanelResizeUpdate> get onResize => widget.onResize;
  ValueChanged<DragStartDetails> get onDragStart => widget.onDragStart;
  FutureOr<void> Function() get onDragEnd => widget.onDragEnd;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback get onEditColor => widget.onEditColor;
  VoidCallback get onBringToFront => widget.onBringToFront;
  VoidCallback get onSendToBack => widget.onSendToBack;
  VoidCallback? get onFullscreen => widget.onFullscreen;
  VoidCallback? get onEditNote => widget.onEditNote;
  ValueChanged<Map<String, dynamic>>? get onUpdateState => widget.onUpdateState;
  Future<String?> Function(String, Map<String, dynamic>, String)?
  get onCreateLinkedPanel => widget.onCreateLinkedPanel;
  bool get connectMode => widget.connectMode;
  String? get connectSourceId => widget.connectSourceId;
  VoidCallback? get onConnectTap => widget.onConnectTap;
  bool get selected => widget.selected;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _opacity = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack),
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _showPanelSettingsDialog(
    BuildContext context, {
    required BoardPanelInstance panel,
    required BoardPanelPlugin? plugin,
    required VoidCallback? onEditPanel,
    required VoidCallback onEditColor,
    required VoidCallback onBringToFront,
    required VoidCallback onSendToBack,
  }) async {
    await showAdaptiveYoloDialog<void>(
      context: context,
      builder:
          (dialogContext) => PanelSettingsDialog(
            panel: panel,
            plugin: plugin,
            onEditPanel:
                onEditPanel == null
                    ? null
                    : () {
                      Navigator.of(dialogContext).pop();
                      onEditPanel();
                    },
            onEditColor: () {
              Navigator.of(dialogContext).pop();
              onEditColor();
            },
            onBringToFront: () {
              Navigator.of(dialogContext).pop();
              onBringToFront();
            },
            onSendToBack: () {
              Navigator.of(dialogContext).pop();
              onSendToBack();
            },
          ),
    );
  }

  void _startPanelTransform(DragStartDetails details) {
    onTap();
    setState(() => _isTransformingPanel = true);
    onDragStart(details);
  }

  Future<void> _endPanelTransform() async {
    if (_isTransformingPanel) {
      setState(() => _isTransformingPanel = true);
    }
    await widget.onDragEnd();
    if (mounted) {
      setState(() => _isTransformingPanel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<BoardCubit>();
    final focusedPanelId = context.select<BoardCubit, String?>(
      (c) => c.state.activeBoard?.viewport.focusedPanelId,
    );
    final activeBoard = cubit.state.activeBoard;
    final remoteLockActor = activeBoard == null
        ? null
        : cubit.panelLockActor(activeBoard, panel.id);
    final isFocused = panel.id == focusedPanelId;
    final isWebpage = panel.type == 'board.webpage';
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    final usePanelChrome = plugin?.usePanelChrome ?? true;
    final showHeader = plugin?.showHeader ?? true;
    final accent = panel.color;
    final isCapturing = widget.capturingScreenshot;
    final panelFill = _panelFill(
      colors,
      usePanelChrome: usePanelChrome,
      isCapturing: isCapturing,
      accent: accent,
    );
    final borderColor = _panelBorderColor(
      colors,
      usePanelChrome: usePanelChrome,
      isCapturing: isCapturing,
      accent: accent,
    );
    const selectionSideGutter = BoardPanelSelectionMetrics.sideGutter;
    const selectionTopGutter = BoardPanelSelectionMetrics.topGutter;
    const selectionBottomGutter = BoardPanelSelectionMetrics.bottomGutter;
    final selectionWrapperWidth = panel.bounds.width + selectionSideGutter * 2;
    final contentToolbar = _buildContentToolbar(context, panel);
    return AnimatedPositioned(
      duration:
          _isTransformingPanel
              ? Duration.zero
              : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: panel.bounds.x + positionOffset.dx - selectionSideGutter,
      top: panel.bounds.y + positionOffset.dy - selectionTopGutter,
      width: selectionWrapperWidth,
      height: panel.bounds.height + selectionTopGutter + selectionBottomGutter,
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          alignment: Alignment.topLeft,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: selectionSideGutter,
                top: selectionTopGutter,
                width: panel.bounds.width,
                height: panel.bounds.height,
                child: ChatGlowWrapper(
                  panelId: panel.id,
                  borderRadius: BorderRadius.circular(16),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown:
                        (_) => _handlePanelPointerDown(
                          isWebpage: isWebpage,
                          isFocused: isFocused,
                        ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: panelFill,
                        borderRadius: BorderRadius.circular(16),
                        border: _panelBorder(
                          colors,
                          isCapturing: isCapturing,
                          isFocused: isFocused,
                          borderColor: borderColor,
                        ),
                        boxShadow: _panelBoxShadow(
                          colors,
                          isCapturing: isCapturing,
                          usePanelChrome: usePanelChrome,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ..._focusRingSection(
                            colors,
                            isFocused: isFocused,
                            isCapturing: isCapturing,
                            usePanelChrome: usePanelChrome,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ..._headerSection(
                                context,
                                plugin: plugin,
                                showHeader: showHeader,
                                isFocused: isFocused,
                                remoteLockActor: remoteLockActor,
                              ),
                              ..._contentToolbarSection(contentToolbar),
                              _contentArea(
                                context,
                                plugin: plugin,
                                showHeader: showHeader,
                                contentToolbar: contentToolbar,
                              ),
                            ],
                          ),
                          // ── Connect mode overlay ──────────────────────────────────────
                          ..._connectOverlaySection(colors),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ), // Stack
        ), // ScaleTransition
      ), // FadeTransition
    );
  }

  void _handlePanelPointerDown({
    required bool isWebpage,
    required bool isFocused,
  }) {
    if (kDebugMode) {
      debugPrint(
        '[BoardPanelCard] onPointerDown panelId=${panel.id} isWebpage=$isWebpage isFocused=$isFocused',
      );
    }
    if (isWebpage) {
      if (!isFocused) {
        if (kDebugMode) {
          assert(() {
            debugPrint(
              '[BoardWebFocus] panelPointerDown -> focus webpage panel=${panel.id}',
            );
            return true;
          }());
        }
        onTap();
      } else {
        if (kDebugMode) {
          assert(() {
            debugPrint(
              '[BoardWebFocus] panelPointerDown -> already focused, releasing Flutter focus panel=${panel.id}',
            );
            return true;
          }());
        }
      }
      // On the web the panel renders inline, so Flutter
      // widgets (URL text field, etc.) must keep focus.
      // Only release first responder for the native desktop
      // overlay webview.
      if (!kIsWeb) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      return;
    }
    if (!isFocused) {
      onTap();
    }
  }

  Color _panelFill(
    AppColorScheme colors, {
    required bool usePanelChrome,
    required bool isCapturing,
    required Color? accent,
  }) {
    return !usePanelChrome
        ? Colors.transparent
        : isCapturing
        ? colors.background
        : accent == null
        ? colors.surface
        : Color.lerp(colors.surface, accent, 0.12) ?? colors.surface;
  }

  Color _panelBorderColor(
    AppColorScheme colors, {
    required bool usePanelChrome,
    required bool isCapturing,
    required Color? accent,
  }) {
    return !usePanelChrome
        ? Colors.transparent
        : isCapturing
        ? colors.background
        : selected
        ? colors.statusActive
        : accent == null
        ? colors.divider
        : Color.lerp(colors.divider, accent, 0.65) ?? colors.divider;
  }

  Border _panelBorder(
    AppColorScheme colors, {
    required bool isCapturing,
    required bool isFocused,
    required Color borderColor,
  }) {
    return Border.all(
      color:
          isCapturing
              ? colors.background
              : selected
              ? colors.statusActive
              : isFocused
              ? colors.primary
              : borderColor,
      width: (selected || isFocused) && !isCapturing ? 2 : 1,
    );
  }

  List<BoxShadow>? _panelBoxShadow(
    AppColorScheme colors, {
    required bool isCapturing,
    required bool usePanelChrome,
  }) {
    return isCapturing || !usePanelChrome
        ? null
        : [
          BoxShadow(
            color: colors.background.withAlpha(35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ];
  }

  List<Widget> _focusRingSection(
    AppColorScheme colors, {
    required bool isFocused,
    required bool isCapturing,
    required bool usePanelChrome,
  }) {
    return [
      if (isFocused && !isCapturing)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.primary,
                  width: usePanelChrome ? 1.6 : 2.0,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _headerSection(
    BuildContext context, {
    required BoardPanelPlugin? plugin,
    required bool showHeader,
    required bool isFocused,
    required String? remoteLockActor,
  }) {
    return [
      if (showHeader)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _startPanelTransform,
          onPanUpdate: panel.locked ? null : (details) => onMove(details),
          onPanEnd: (_) => _endPanelTransform(),
          onPanCancel: _endPanelTransform,
          child: UnifiedPanelHeader(
            panel: panel,
            isSelected: selected,
            isFocused: isFocused,
            leadingIcon:
                panel.type == ChatPanelPlugin.kTypeId
                    ? ChatProviderIcon(
                      provider:
                          (panel.state['config'] as Map?)?['provider']
                              as String? ??
                          'copilot',
                      size: 18,
                    )
                    : null,
            pluginActions: _buildPluginHeaderActions(context, panel),
            onDuplicate: () => _duplicatePanel(panel),
            onToggleLocked: () => _toggleLocked(panel),
            onEditColor: onEditColor,
            onBringToFront: onBringToFront,
            onSendToBack: onSendToBack,
            onEdit: onEditNote,
            onFullscreen: onFullscreen,
            remoteLockActor: remoteLockActor,
            onSettings:
                () => _showPanelSettingsDialog(
                  context,
                  panel: panel,
                  plugin: plugin,
                  onEditPanel: onEditNote,
                  onEditColor: onEditColor,
                  onBringToFront: onBringToFront,
                  onSendToBack: onSendToBack,
                ),
            onDelete: onDelete,
          ),
        ),
    ];
  }

  List<Widget> _contentToolbarSection(List<Widget>? contentToolbar) {
    return [
      if (contentToolbar != null)
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
          child: PanelContentToolbar(children: contentToolbar),
        ),
    ];
  }

  Widget _contentArea(
    BuildContext context, {
    required BoardPanelPlugin? plugin,
    required bool showHeader,
    required List<Widget>? contentToolbar,
  }) {
    return Expanded(
      child: Padding(
        padding:
            !showHeader || contentToolbar != null
                ? EdgeInsets.zero
                : plugin?.contentPadding ?? const EdgeInsets.all(12),
        child: _buildPanelContent(context, panel),
      ),
    );
  }

  List<Widget> _connectOverlaySection(AppColorScheme colors) {
    return [
      if (connectMode)
        Positioned.fill(
          child: GestureDetector(
            onTap: onConnectTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      connectSourceId == panel.id
                          ? colors.statusActive
                          : colors.statusActive.withAlpha(100),
                  width: connectSourceId == panel.id ? 2.5 : 1.5,
                ),
                color:
                    connectSourceId == panel.id
                        ? colors.statusActive.withAlpha(21)
                        : Colors.transparent,
              ),
              child:
                  connectSourceId == null
                      ? Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.statusActive.withAlpha(102),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add_link,
                            size: 18,
                            color: colors.statusActive,
                          ),
                        ),
                      )
                      : connectSourceId == panel.id
                      ? Center(
                        child: Text(
                          'Source\n(tap to cancel)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.statusActive,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                      : Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.statusActive.withAlpha(102),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.call_made,
                            size: 18,
                            color: colors.statusActive,
                          ),
                        ),
                      ),
            ),
          ),
        ),
    ];
  }

  void _duplicatePanel(BoardPanelInstance panel) =>
      context.read<BoardCubit>().duplicatePanels({panel.id});

  void _toggleLocked(BoardPanelInstance panel) => context
      .read<BoardCubit>()
      .updatePanel(panel.id, (p) => p.copyWith(locked: !p.locked));

  List<Widget> _buildPluginHeaderActions(
    BuildContext context,
    BoardPanelInstance panel,
  ) {
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    final updateState = onUpdateState;
    if (plugin == null || updateState == null) return const [];
    return plugin.buildHeaderActions(
      context,
      panel,
      updateState,
      onResize:
          (w, h) => context.read<BoardCubit>().resizePanel(
            panel.id,
            width: w,
            height: h,
          ),
      onEditColor: onEditColor,
    );
  }

  List<Widget>? _buildContentToolbar(
    BuildContext context,
    BoardPanelInstance panel,
  ) {
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    if (plugin == null) return null;
    return plugin.buildContentToolbar(
      context,
      panel,
      _buildRenderContext(context, panel),
    );
  }

  BoardPanelRenderContext _buildRenderContext(
    BuildContext context,
    BoardPanelInstance panel,
  ) {
    final cubit = context.read<BoardCubit>();
    final activeBoard = cubit.state.activeBoard;
    final remoteLockActor = activeBoard == null
        ? null
        : cubit.panelLockActor(activeBoard, panel.id);
    return BoardPanelRenderContext(
      isSelected:
          panel.id ==
          context.select<BoardCubit, String?>(
            (c) => c.state.activeBoard?.viewport.focusedPanelId,
          ),
      onFocus: onTap,
      onDelete: onDelete,
      onUpdateState: onUpdateState ?? (_) {},
      onShowEditor: onEditNote ?? () {},
      remoteInfo: activeBoard == null ? null : remoteInfoForBoard(activeBoard),
      readOnly: remoteLockActor != null,
      onCreateLinkedPanel: onCreateLinkedPanel,
      onFindPanelByGroup: (typeId, group) {
        final board = context.read<BoardCubit>().state.activeBoard;
        if (board == null) return null;
        for (final p in board.panels) {
          if (p.type != typeId) continue;
          final panelGroup = p.state['group'];
          if (panelGroup is String && panelGroup.trim() == group.trim()) {
            return p.id;
          }
        }
        return null;
      },
      onRevealSessionInPanel: (panelId, sessionId) async {
        final cubit = context.read<BoardCubit>();
        await cubit.updatePanel(panelId, (p) {
          final hiddenRaw = p.state['hiddenSessionIds'];
          final hidden =
              hiddenRaw is List
                  ? hiddenRaw.whereType<String>().toSet()
                  : <String>{};
          hidden.remove(sessionId);
          return p.copyWith(
            state: {
              ...p.state,
              'activeSessionId': sessionId,
              'hiddenSessionIds': hidden.toList(),
            },
          );
        });
      },
      onFocusPanelById:
          (panelId) => context.read<BoardCubit>().focusPanel(panelId),
      onFindPanelById: (panelId) {
        final board = context.read<BoardCubit>().state.activeBoard;
        if (board == null) return null;
        for (final panel in board.panels) {
          if (panel.id == panelId) return panel;
          if (panel.type == 'board.table') {
            final customId = (panel.state['tableId'] as String?)?.trim() ?? '';
            if (customId.isNotEmpty && customId == panelId) return panel;
          }
        }
        return null;
      },
      onResize:
          (w, h) => context.read<BoardCubit>().resizePanel(
            panel.id,
            width: w,
            height: h,
          ),
    );
  }

  Widget _buildPanelContent(BuildContext context, BoardPanelInstance panel) {
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    if (plugin != null) {
      return ScrollConfiguration(
        behavior: const PanelScrollLockBehavior(),
        child: plugin.buildContent(
          context,
          panel,
          _buildRenderContext(context, panel),
        ),
      );
    }
    // Fallback for unknown types
    return Center(child: Text('Unknown: ${panel.type}'));
  }
}

