import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:yoloit/features/board/terminal/board_terminal_panel_plugin.dart';
import 'package:yoloit/features/board/ui/chat_glow_wrapper.dart';
import 'package:yoloit/features/board/ui/chat_header_menu.dart';
import 'package:yoloit/features/board/ui/dialogs/board_settings_dialog.dart';
import 'package:yoloit/features/board/ui/miro_panel_toolbar.dart';
import 'package:yoloit/ui/components/buttons/panel_header_icon_button.dart';

enum BoardPanelResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get affectsLeft => this == left || this == topLeft || this == bottomLeft;
  bool get affectsRight =>
      this == right || this == topRight || this == bottomRight;
  bool get affectsTop => this == top || this == topLeft || this == topRight;
  bool get affectsBottom =>
      this == bottom || this == bottomLeft || this == bottomRight;

  SystemMouseCursor get cursor => switch (this) {
    topLeft || bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    topRight || bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    left || right => SystemMouseCursors.resizeLeftRight,
    top || bottom => SystemMouseCursors.resizeUpDown,
  };

  String get tooltip => switch (this) {
    topLeft => 'Resize from top left',
    top => 'Resize height',
    topRight => 'Resize from top right',
    right => 'Resize width',
    bottomRight => 'Resize from bottom right',
    bottom => 'Resize height',
    bottomLeft => 'Resize from bottom left',
    left => 'Resize width',
  };
}

class BoardPanelResizeUpdate {
  const BoardPanelResizeUpdate({
    required this.handle,
    required this.delta,
    required this.globalPosition,
  });

  final BoardPanelResizeHandle handle;
  final Offset delta;
  final Offset globalPosition;
}

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
    this.onEditNote,
    this.onUpdateState,
    this.onCreateLinkedPanel,
    this.connectMode = false,
    this.connectSourceId,
    this.onConnectTap,
    this.capturingScreenshot = false,
  });

  final BoardPanelInstance panel;
  final Offset positionOffset;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onMove;
  final ValueChanged<BoardPanelResizeUpdate> onResize;
  final ValueChanged<DragStartDetails> onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onDelete;
  final VoidCallback onEditColor;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
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
  VoidCallback get onDragEnd => widget.onDragEnd;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback get onEditColor => widget.onEditColor;
  VoidCallback get onBringToFront => widget.onBringToFront;
  VoidCallback get onSendToBack => widget.onSendToBack;
  VoidCallback? get onEditNote => widget.onEditNote;
  ValueChanged<Map<String, dynamic>>? get onUpdateState => widget.onUpdateState;
  Future<String?> Function(String, Map<String, dynamic>, String)?
  get onCreateLinkedPanel => widget.onCreateLinkedPanel;
  bool get connectMode => widget.connectMode;
  String? get connectSourceId => widget.connectSourceId;
  VoidCallback? get onConnectTap => widget.onConnectTap;

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

  void _endPanelTransform() {
    if (_isTransformingPanel) {
      setState(() => _isTransformingPanel = false);
    }
    onDragEnd();
  }

  void _resizeFromHandle(
    BoardPanelResizeHandle handle,
    DragUpdateDetails details,
  ) {
    onResize(
      BoardPanelResizeUpdate(
        handle: handle,
        delta: details.delta,
        globalPosition: details.globalPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final focusedPanelId = context.select<BoardCubit, String?>(
      (cubit) => cubit.state.activeBoard?.viewport.focusedPanelId,
    );
    final isFocused = panel.id == focusedPanelId;
    final isWebpage = panel.type == 'board.webpage';
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    final usePanelChrome = plugin?.usePanelChrome ?? true;
    final showHeader = plugin?.showHeader ?? true;
    final accent = panel.color;
    final isCapturing = widget.capturingScreenshot;
    final panelFill =
        !usePanelChrome
            ? Colors.transparent
            : isCapturing
            ? colors.background
            : accent == null
            ? colors.surface
            : Color.lerp(colors.surface, accent, 0.12) ?? colors.surface;
    final panelHeaderFill =
        isCapturing
            ? colors.background
            : accent == null
            ? colors.surfaceElevated
            : Color.lerp(colors.surfaceElevated, accent, 0.18) ??
                colors.surfaceElevated;
    final borderColor =
        !usePanelChrome
            ? Colors.transparent
            : isCapturing
            ? colors.background
            : accent == null
            ? colors.divider
            : Color.lerp(colors.divider, accent, 0.65) ?? colors.divider;
    final showSelectionChrome = isFocused && !isCapturing;
    const selectionSideGutter = 18.0;
    const selectionTopGutter = 62.0;
    const selectionBottomGutter = 18.0;
    const selectionHandleInset = 12.0;
    final selectionToolbarMinWidth =
        panel.type == 'board.sticky' || panel.type == 'board.shape'
            ? 680.0
            : 360.0;
    final selectionToolbarWidth =
        panel.bounds.width > selectionToolbarMinWidth
            ? panel.bounds.width
            : selectionToolbarMinWidth;
    final selectionWrapperWidth =
        panel.bounds.width + selectionSideGutter * 2 >
                selectionToolbarWidth + selectionSideGutter * 2
            ? panel.bounds.width + selectionSideGutter * 2
            : selectionToolbarWidth + selectionSideGutter * 2;
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
                    behavior: HitTestBehavior.deferToChild,
                    onPointerDown: (_) {
                      if (isWebpage) {
                        if (!isFocused) {
                          if (kDebugMode) {
                            debugPrint(
                              '[BoardWebFocus] panelPointerDown -> focus webpage panel=${panel.id}',
                            );
                          }
                          onTap();
                        } else {
                          if (kDebugMode) {
                            debugPrint(
                              '[BoardWebFocus] panelPointerDown -> already focused, releasing Flutter focus panel=${panel.id}',
                            );
                          }
                        }
                        // Release ALL Flutter keyboard focus so the native WKWebView
                        // can become firstResponder and receive keyboard input.
                        FocusManager.instance.primaryFocus?.unfocus();
                        return;
                      }
                      if (!isFocused) {
                        onTap();
                      }
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: panelFill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              isCapturing
                                  ? colors.background
                                  : isFocused
                                  ? colors.primary
                                  : borderColor,
                          width: isFocused && !isCapturing ? 1.5 : 1,
                        ),
                        boxShadow:
                            isCapturing || !usePanelChrome
                                ? null
                                : [
                                  BoxShadow(
                                    color: colors.background.withAlpha(35),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showHeader)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: _startPanelTransform,
                                  onPanUpdate:
                                      panel.locked
                                          ? null
                                          : (details) => onMove(details),
                                  onPanEnd: (_) => _endPanelTransform(),
                                  onPanCancel: _endPanelTransform,
                                  child: Container(
                                    height: 44,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: panelHeaderFill,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(16),
                                      ),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: colors.divider,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        if (panel.type ==
                                            ChatPanelPlugin.kTypeId)
                                          ChatProviderIcon(
                                            provider:
                                                (panel.state['config']
                                                        as Map?)?['provider']
                                                    as String? ??
                                                'copilot',
                                            size: 18,
                                          )
                                        else
                                          Builder(
                                            builder: (ctx) {
                                              final plugin = BoardPluginRegistry
                                                  .instance
                                                  .pluginFor(panel.type);
                                              final svgIcon = plugin
                                                  ?.buildIconWidget(
                                                    ctx,
                                                    size: 16,
                                                  );
                                              if (svgIcon != null) {
                                                return svgIcon;
                                              }
                                              return Icon(
                                                plugin?.icon ??
                                                    Icons
                                                        .dashboard_customize_outlined,
                                                size: 16,
                                                color:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.color ??
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                              );
                                            },
                                          ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            panel.title,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: TextStyle(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        if (panel.type !=
                                            ChatPanelPlugin.kTypeId) ...[
                                          GestureDetector(
                                            onTap: onEditColor,
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                color:
                                                    accent ??
                                                    (Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.color ??
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .onSurface),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: colors.textPrimary
                                                      .withAlpha(100),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (onEditNote != null)
                                            SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: IconButton(
                                                tooltip: 'Edit note',
                                                onPressed: onEditNote,
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 16,
                                                ),
                                                splashRadius: 14,
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                        ],
                                        if (panel.type ==
                                            ChatPanelPlugin.kTypeId)
                                          ChatHeaderMenu(
                                            panel: panel,
                                            onEditColor: onEditColor,
                                            onUpdateState: onUpdateState,
                                          ),
                                        // Plugin-specific header actions (e.g. env gear for widget panels)
                                        ...() {
                                          final plugin = BoardPluginRegistry
                                              .instance
                                              .pluginFor(panel.type);
                                          if (plugin == null ||
                                              onUpdateState == null) {
                                            return <Widget>[];
                                          }
                                          return plugin.buildHeaderActions(
                                            context,
                                            panel,
                                            onUpdateState!,
                                            onResize:
                                                (w, h) => context
                                                    .read<BoardCubit>()
                                                    .resizePanel(
                                                      panel.id,
                                                      width: w,
                                                      height: h,
                                                    ),
                                          );
                                        }(),
                                        PanelHeaderIconButton(
                                          tooltip: 'Panel settings',
                                          icon: Icons.tune_rounded,
                                          onPressed:
                                              () => _showPanelSettingsDialog(
                                                context,
                                                panel: panel,
                                                plugin: plugin,
                                                onEditPanel: onEditNote,
                                                onEditColor: onEditColor,
                                                onBringToFront: onBringToFront,
                                                onSendToBack: onSendToBack,
                                              ),
                                        ),
                                        PanelHeaderIconButton(
                                          tooltip: 'Bring to front',
                                          icon: Icons.flip_to_front_outlined,
                                          onPressed: onBringToFront,
                                        ),
                                        PanelHeaderIconButton(
                                          tooltip: 'Send to back',
                                          icon: Icons.flip_to_back_outlined,
                                          onPressed: onSendToBack,
                                        ),
                                        SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: IconButton(
                                            tooltip: 'Remove panel',
                                            onPressed: onDelete,
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            splashRadius: 14,
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding:
                                      !showHeader ||
                                              panel.type ==
                                                  ChatPanelPlugin.kTypeId ||
                                              panel.type ==
                                                  BoardTerminalPanelPlugin
                                                      .kTypeId ||
                                              panel.type == 'board.webpage'
                                          ? EdgeInsets.zero
                                          : const EdgeInsets.all(12),
                                  child: _buildPanelContent(context, panel),
                                ),
                              ),
                            ],
                          ),
                          // ── Connect mode overlay ──────────────────────────────────────
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
                                              : colors.statusActive.withAlpha(
                                                100,
                                              ),
                                      width:
                                          connectSourceId == panel.id
                                              ? 2.5
                                              : 1.5,
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
                                                color: colors.statusActive
                                                    .withAlpha(102),
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
                                                color: colors.statusActive
                                                    .withAlpha(102),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (showSelectionChrome)
                Positioned(
                  top: 8,
                  left: selectionSideGutter,
                  child: MiroPanelToolbar(
                    maxWidth: selectionToolbarWidth,
                    panel: panel,
                    plugin: plugin,
                    canEdit: onEditNote != null,
                    onEdit: onEditNote,
                    onEditColor: onEditColor,
                    onBringToFront: onBringToFront,
                    onSendToBack: onSendToBack,
                    onDelete: onDelete,
                    onToggleLocked: () {
                      context.read<BoardCubit>().updatePanel(
                        panel.id,
                        (p) => p.copyWith(locked: !p.locked),
                      );
                    },
                    onMoveStart: _startPanelTransform,
                    onMoveUpdate:
                        panel.locked ? null : (details) => onMove(details),
                    onMoveEnd: _endPanelTransform,
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
                    onUpdateState: onUpdateState,
                  ),
                ),
              if (showSelectionChrome)
                Positioned(
                  left: selectionSideGutter - selectionHandleInset,
                  top: selectionTopGutter - selectionHandleInset,
                  width: panel.bounds.width + selectionHandleInset * 2,
                  height: panel.bounds.height + selectionHandleInset * 2,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: BoardPanelResizeOverlay.handles(
                      locked: panel.locked,
                      onStart: _startPanelTransform,
                      onUpdate: _resizeFromHandle,
                      onEnd: _endPanelTransform,
                      colors: colors,
                    ),
                  ),
                ),
            ],
          ),
        ), // ScaleTransition
      ), // FadeTransition
    );
  }

  Widget _buildPanelContent(BuildContext context, BoardPanelInstance panel) {
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    if (plugin != null) {
      final activeBoard = context.read<BoardCubit>().state.activeBoard;
      return plugin.buildContent(
        context,
        panel,
        BoardPanelRenderContext(
          isSelected:
              panel.id ==
              context.select<BoardCubit, String?>(
                (cubit) => cubit.state.activeBoard?.viewport.focusedPanelId,
              ),
          onFocus: onTap,
          onDelete: onDelete,
          onUpdateState: onUpdateState ?? (_) {},
          onShowEditor: onEditNote ?? () {},
          remoteInfo:
              activeBoard == null ? null : remoteInfoForBoard(activeBoard),
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
          onResize:
              (w, h) => context.read<BoardCubit>().resizePanel(
                panel.id,
                width: w,
                height: h,
              ),
        ),
      );
    }
    // Fallback for unknown types
    return Center(
      child: Text(
        'Unknown: ${panel.type}',
        style: TextStyle(
          color: context.appColors.textMuted,
          fontSize: 12,
        ),
      ),
    );
  }
}

class BoardPanelResizeOverlay {
  const BoardPanelResizeOverlay._();

  static List<Widget> handles({
    required bool locked,
    required ValueChanged<DragStartDetails> onStart,
    required void Function(BoardPanelResizeHandle, DragUpdateDetails) onUpdate,
    required VoidCallback onEnd,
    required AppColorScheme colors,
  }) {
    if (locked) return const [];
    return BoardPanelResizeHandle.values
        .map(
          (handle) => PanelResizeHandleWidget(
            handle: handle,
            onStart: onStart,
            onUpdate: (details) => onUpdate(handle, details),
            onEnd: onEnd,
            colors: colors,
          ),
        )
        .toList(growable: false);
  }
}

class PanelResizeHandleWidget extends StatelessWidget {
  const PanelResizeHandleWidget({
    super.key,
    required this.handle,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.colors,
  });

  final BoardPanelResizeHandle handle;
  final ValueChanged<DragStartDetails> onStart;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final VoidCallback onEnd;
  final AppColorScheme colors;

  static const double _hitSize = 24;
  static const double _dotSize = 10;

  @override
  Widget build(BuildContext context) {
    final child = MouseRegion(
      cursor: handle.cursor,
      child: Tooltip(
        message: handle.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onStart,
          onPanUpdate: onUpdate,
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: SizedBox(
            width: _hitSize,
            height: _hitSize,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const SizedBox(width: _dotSize, height: _dotSize),
              ),
            ),
          ),
        ),
      ),
    );

    return switch (handle) {
      BoardPanelResizeHandle.topLeft => Positioned(
        left: 0,
        top: 0,
        child: child,
      ),
      BoardPanelResizeHandle.top => Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: _hitSize,
        child: Center(child: child),
      ),
      BoardPanelResizeHandle.topRight => Positioned(
        right: 0,
        top: 0,
        child: child,
      ),
      BoardPanelResizeHandle.right => Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: _hitSize,
        child: Center(child: child),
      ),
      BoardPanelResizeHandle.bottomRight => Positioned(
        right: 0,
        bottom: 0,
        child: child,
      ),
      BoardPanelResizeHandle.bottom => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: _hitSize,
        child: Center(child: child),
      ),
      BoardPanelResizeHandle.bottomLeft => Positioned(
        left: 0,
        bottom: 0,
        child: child,
      ),
      BoardPanelResizeHandle.left => Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: _hitSize,
        child: Center(child: child),
      ),
    };
  }
}
