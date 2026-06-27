import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_panel_actions.dart';
import 'package:yoloit/features/board/ui/board_panel_card.dart';
import 'package:yoloit/features/board/ui/board_panel_floating_chrome.dart';
import 'package:yoloit/features/board/ui/board_panel_resize_chrome.dart';
import 'package:yoloit/features/board/ui/board_panel_yolo_badge_overlay.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_panel.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_scope.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';

/// Renders all visible board panels as [BoardPanelCard]s.
///
/// Kept separate from [BoardView] to reduce the size of the main board view
/// file and to isolate panel-specific rebuilds.
class BoardPanelLayer extends StatefulWidget {
  const BoardPanelLayer({
    super.key,
    required this.board,
    required this.canvasOrigin,
    required this.isCapturingScreenshot,
    required this.selectedPanelIds,
    required this.activeTool,
    required this.connectSourceId,
    required this.onMovePanel,
    required this.onResizePanel,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onConnectTap,
    this.onFullscreenPanel,
  });

  final BoardDocument board;
  final Offset canvasOrigin;
  final bool isCapturingScreenshot;
  final Set<String> selectedPanelIds;
  final BoardToolId activeTool;
  final String? connectSourceId;
  final void Function(
    BuildContext context,
    String panelId,
    DragUpdateDetails details,
  )
  onMovePanel;
  final void Function(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelResizeUpdate update,
  )
  onResizePanel;
  final void Function(String panelId, DragStartDetails details) onDragStart;
  final VoidCallback onDragEnd;
  final void Function(BuildContext context, BoardDocument board, String panelId)
  onConnectTap;
  final void Function(BuildContext context, String panelId)? onFullscreenPanel;

  @override
  State<BoardPanelLayer> createState() => _BoardPanelLayerState();
}

class _BoardPanelLayerState extends State<BoardPanelLayer> {
  final ChatPanelController _yoloChatController = ChatPanelController();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BoardCubit, BoardState>(
      builder: (context, boardState) {
        final board = boardState.boards.firstWhere(
          (candidate) => candidate.id == widget.board.id,
          orElse: () => widget.board,
        );
        final visiblePanels =
            board.panels.where((panel) => !panel.hidden).toList()
              ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
        final anchorId = boardState.yoloAssistantAnchorPanelId;
        BoardPanelInstance? anchorPanel;
        BoardPanelInstance? focusedPanel;
        if (anchorId != null) {
          for (final panel in board.panels) {
            if (panel.id == anchorId) {
              anchorPanel = panel;
              break;
            }
          }
        }

        final focusedPanelId = board.viewport.focusedPanelId;
        if (focusedPanelId != null) {
          for (final panel in visiblePanels) {
            if (panel.id == focusedPanelId) {
              focusedPanel = panel;
              break;
            }
          }
        }

        final resizePanel = focusedPanel;

        return YoloAnchoredAssistantScope(
          anchorPanelId: anchorPanel?.id,
          chatController: anchorPanel != null ? _yoloChatController : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ...visiblePanels.map(
                (panel) => _buildPanelCard(context, board, panel),
              ),
              if (focusedPanel != null)
                _buildFloatingChrome(context, focusedPanel),
              if (anchorPanel != null && !widget.isCapturingScreenshot)
                YoloAnchoredAssistantPanel(
                  key: ValueKey('yolo-anchor-${anchorPanel.id}'),
                  anchorPanel: anchorPanel,
                  canvasOrigin: widget.canvasOrigin,
                  chatController: _yoloChatController,
                  startMic: boardState.yoloAssistantStartMic,
                  onStartMicConsumed:
                      () =>
                          context
                              .read<BoardCubit>()
                              .consumeYoloAssistantStartMic(),
                  onClose:
                      () => context.read<BoardCubit>().closeYoloAssistant(),
                ),
              if (resizePanel != null) _buildResizeChrome(context, resizePanel),
              if (resizePanel != null)
                BoardPanelYoloBadgeOverlay(
                  key: ValueKey('yolo-badge-${resizePanel.id}'),
                  panel: resizePanel,
                  canvasOrigin: widget.canvasOrigin,
                  capturingScreenshot: widget.isCapturingScreenshot,
                  connectMode: widget.activeTool == BoardToolId.connect,
                  selected: widget.selectedPanelIds.contains(resizePanel.id),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPanelCard(
    BuildContext context,
    BoardDocument board,
    BoardPanelInstance panel,
  ) {
    final boardCubit = context.read<BoardCubit>();
    final isInCollapsedGroup = board.groups.any(
      (group) => group.collapsed && group.panelIds.contains(panel.id),
    );
    final card = BoardPanelCard(
      key: ValueKey(panel.id),
      panel: panel,
      positionOffset: widget.canvasOrigin,
      capturingScreenshot: widget.isCapturingScreenshot,
      selected:
          !isInCollapsedGroup && widget.selectedPanelIds.contains(panel.id),
      onTap: () => boardCubit.focusPanel(panel.id),
      onMove: (details) => widget.onMovePanel(context, panel.id, details),
      onResize: (update) => widget.onResizePanel(context, panel, update),
      onDragStart: (details) => widget.onDragStart(panel.id, details),
      onDragEnd: widget.onDragEnd,
      onDelete: () async {
        if (panel.type == 'board.widget.custom') {
          WidgetEngineManager.instance.remove(panel.id);
        }
        await boardCubit.removePanel(panel.id);
      },
      onEditColor: () => BoardPanelActions.showPanelColorDialog(context, panel),
      onEditNote: BoardPanelActions.createEditCallback(context, panel),
      onBringToFront: () {
        final activeBoard = boardCubit.state.activeBoard;
        if (activeBoard == null) return;
        final maxZ = activeBoard.panels.fold<int>(
          0,
          (value, panel) => panel.zIndex > value ? panel.zIndex : value,
        );
        boardCubit.updatePanel(panel.id, (p) => p.copyWith(zIndex: maxZ + 1));
      },
      onSendToBack: () {
        final activeBoard = boardCubit.state.activeBoard;
        if (activeBoard == null) return;
        final minZ = activeBoard.panels.fold<int>(
          0,
          (value, panel) => panel.zIndex < value ? panel.zIndex : value,
        );
        boardCubit.updatePanel(panel.id, (p) => p.copyWith(zIndex: minZ - 1));
      },
      onFullscreen: () => widget.onFullscreenPanel?.call(context, panel.id),
      onUpdateState: (newState) {
        boardCubit.updatePanel(
          panel.id,
          (p) => p.copyWith(state: newState),
          boardId: board.id,
        );
      },
      onCreateLinkedPanel: (typeId, state, title) async {
        final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
        final size = plugin?.defaultSize ?? const Size(460, 380);
        final activeBoard = boardCubit.state.activeBoard;
        if (activeBoard == null) return null;
        final newBounds = boardCubit.nextAvailableBounds(
          activeBoard,
          preferredWidth: size.width,
          preferredHeight: size.height,
        );
        final ts = DateTime.now().microsecondsSinceEpoch;
        final newPanel = BoardPanelInstance(
          id: 'panel-$ts',
          type: typeId,
          title: title,
          bounds: newBounds,
          state: state,
          zIndex:
              activeBoard.panels.fold<int>(
                0,
                (v, p) => p.zIndex > v ? p.zIndex : v,
              ) +
              1,
        );
        await boardCubit.addPanel(newPanel);
        await boardCubit.upsertLink(
          BoardPanelLink(
            id: 'link-$ts',
            fromPanelId: panel.id,
            toPanelId: newPanel.id,
            style: BoardLinkStyle.arrow,
            behavior: BoardLinkBehavior.dynamic,
            geometry: BoardLinkGeometry.bezier,
          ),
        );
        return newPanel.id;
      },
      connectMode: widget.activeTool == BoardToolId.connect,
      connectSourceId: widget.connectSourceId,
      onConnectTap:
          widget.activeTool == BoardToolId.connect
              ? () => widget.onConnectTap(context, board, panel.id)
              : null,
    );
    if (isInCollapsedGroup) {
      return IgnorePointer(child: card);
    }
    return card;
  }

  Widget _buildResizeChrome(BuildContext context, BoardPanelInstance panel) {
    return BoardPanelResizeChrome(
      key: ValueKey('resize-chrome-${panel.id}'),
      panel: panel,
      canvasOrigin: widget.canvasOrigin,
      capturingScreenshot: widget.isCapturingScreenshot,
      onResize: (update) => widget.onResizePanel(context, panel, update),
      onDragStart: (details) => widget.onDragStart(panel.id, details),
      onDragEnd: widget.onDragEnd,
    );
  }

  Widget _buildFloatingChrome(BuildContext context, BoardPanelInstance panel) {
    final boardCubit = context.read<BoardCubit>();
    final isInCollapsedGroup = widget.board.groups.any(
      (group) => group.collapsed && group.panelIds.contains(panel.id),
    );
    if (isInCollapsedGroup) {
      return const SizedBox.shrink();
    }

    return BoardPanelFloatingChrome(
      key: ValueKey('floating-chrome-${panel.id}'),
      panel: panel,
      canvasOrigin: widget.canvasOrigin,
      capturingScreenshot: widget.isCapturingScreenshot,
      onMove: (details) => widget.onMovePanel(context, panel.id, details),
      onDragStart: (details) => widget.onDragStart(panel.id, details),
      onDragEnd: widget.onDragEnd,
      onDelete: () async {
        if (panel.type == 'board.widget.custom') {
          WidgetEngineManager.instance.remove(panel.id);
        }
        await boardCubit.removePanel(panel.id);
      },
      onEditColor: () => BoardPanelActions.showPanelColorDialog(context, panel),
      onEditNote: BoardPanelActions.createEditCallback(context, panel),
      onBringToFront: () {
        final activeBoard = boardCubit.state.activeBoard;
        if (activeBoard == null) return;
        final maxZ = activeBoard.panels.fold<int>(
          0,
          (value, item) => item.zIndex > value ? item.zIndex : value,
        );
        boardCubit.updatePanel(panel.id, (p) => p.copyWith(zIndex: maxZ + 1));
      },
      onSendToBack: () {
        final activeBoard = boardCubit.state.activeBoard;
        if (activeBoard == null) return;
        final minZ = activeBoard.panels.fold<int>(
          0,
          (value, item) => item.zIndex < value ? item.zIndex : value,
        );
        boardCubit.updatePanel(panel.id, (p) => p.copyWith(zIndex: minZ - 1));
      },
      onUpdateState: (newState) {
        boardCubit.updatePanel(
          panel.id,
          (p) => p.copyWith(state: newState),
          boardId: widget.board.id,
        );
      },
    );
  }
}
