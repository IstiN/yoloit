import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_panel_actions.dart';
import 'package:yoloit/features/board/ui/board_panel_card.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';

/// Renders all visible board panels as [BoardPanelCard]s.
///
/// Kept separate from [BoardView] to reduce the size of the main board view
/// file and to isolate panel-specific rebuilds.
class BoardPanelLayer extends StatelessWidget {
  const BoardPanelLayer({
    super.key,
    required this.board,
    required this.canvasOrigin,
    required this.isCapturingScreenshot,
    required this.preview,
    required this.selectedPanelIds,
    required this.activeTool,
    required this.connectSourceId,
    required this.onMovePanel,
    required this.onResizePanel,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onConnectTap,
  });

  final BoardDocument board;
  final Offset canvasOrigin;
  final bool isCapturingScreenshot;
  final bool preview;
  final Set<String> selectedPanelIds;
  final BoardToolId activeTool;
  final String? connectSourceId;
  final void Function(BuildContext context, String panelId, DragUpdateDetails details)
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

  @override
  Widget build(BuildContext context) {
    final visiblePanels =
        board.panels
            .where((panel) => !panel.hidden)
            .toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return Stack(
      clipBehavior: Clip.none,
      children:
          visiblePanels.map((panel) {
            final boardCubit = context.read<BoardCubit>();
            final isInCollapsedGroup = board.groups.any(
              (group) =>
                  group.collapsed && group.panelIds.contains(panel.id),
            );
            final card = BoardPanelCard(
              key: ValueKey(panel.id),
              panel: panel,
              positionOffset: canvasOrigin,
              capturingScreenshot: isCapturingScreenshot,
              selected:
                  !isInCollapsedGroup && selectedPanelIds.contains(panel.id),
              preview: preview,
              onTap: () => boardCubit.focusPanel(panel.id),
              onMove: (details) => onMovePanel(context, panel.id, details),
              onResize: (update) => onResizePanel(context, panel, update),
              onDragStart: (details) => onDragStart(panel.id, details),
              onDragEnd: onDragEnd,
              onDelete: () async {
                if (panel.type == 'board.widget.custom') {
                  WidgetEngineManager.instance.remove(panel.id);
                }
                await boardCubit.removePanel(panel.id);
              },
              onEditColor: () => BoardPanelActions.showPanelColorDialog(
                context,
                panel,
              ),
              onEditNote: BoardPanelActions.createEditCallback(context, panel),
              onBringToFront: () {
                final activeBoard = boardCubit.state.activeBoard;
                if (activeBoard == null) return;
                final maxZ = activeBoard.panels.fold<int>(
                  0,
                  (value, panel) =>
                      panel.zIndex > value ? panel.zIndex : value,
                );
                boardCubit.updatePanel(
                  panel.id,
                  (p) => p.copyWith(zIndex: maxZ + 1),
                );
              },
              onSendToBack: () {
                final activeBoard = boardCubit.state.activeBoard;
                if (activeBoard == null) return;
                final minZ = activeBoard.panels.fold<int>(
                  0,
                  (value, panel) =>
                      panel.zIndex < value ? panel.zIndex : value,
                );
                boardCubit.updatePanel(
                  panel.id,
                  (p) => p.copyWith(zIndex: minZ - 1),
                );
              },
              onUpdateState: (newState) {
                boardCubit.updatePanel(
                  panel.id,
                  (p) => p.copyWith(state: newState),
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
              connectMode: activeTool == BoardToolId.connect,
              connectSourceId: connectSourceId,
              onConnectTap:
                  activeTool == BoardToolId.connect
                      ? () => onConnectTap(context, board, panel.id)
                      : null,
            );
            if (isInCollapsedGroup) {
              return IgnorePointer(child: card);
            }
            return card;
          }).toList(),
    );
  }
}
