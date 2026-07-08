import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/ui/board_panel_selection_metrics.dart';
import 'package:yoloit/features/board/ui/panel_settings_dialog.dart';
import 'package:yoloit/features/board/ui/sticky_note_chrome.dart';

/// Renders headerless panel chrome above all board panels so overlapping cards
/// cannot steal pointer events from the floating toolbar.
class BoardPanelFloatingChrome extends StatelessWidget {
  const BoardPanelFloatingChrome({
    super.key,
    required this.panel,
    required this.canvasOrigin,
    required this.capturingScreenshot,
    required this.onMove,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDelete,
    required this.onEditColor,
    required this.onEditNote,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onUpdateState,
  });

  final BoardPanelInstance panel;
  final Offset canvasOrigin;
  final bool capturingScreenshot;
  final ValueChanged<DragUpdateDetails> onMove;
  final ValueChanged<DragStartDetails> onDragStart;
  final FutureOr<void> Function() onDragEnd;
  final VoidCallback onDelete;
  final VoidCallback onEditColor;
  final VoidCallback? onEditNote;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final ValueChanged<Map<String, dynamic>> onUpdateState;

  Future<void> _showSettingsDialog(BuildContext context) async {
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    await showAdaptiveYoloDialog<void>(
      context: context,
      builder:
          (dialogContext) => PanelSettingsDialog(
            panel: panel,
            plugin: plugin,
            onEditPanel:
                onEditNote == null
                    ? null
                    : () {
                      Navigator.of(dialogContext).pop();
                      onEditNote!();
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

  void _startDrag(BuildContext context, DragStartDetails details) {
    context.read<BoardCubit>().focusPanel(panel.id);
    onDragStart(details);
  }

  @override
  Widget build(BuildContext context) {
    if (capturingScreenshot) {
      return const SizedBox.shrink();
    }

    final focusedPanelId = context.select<BoardCubit, String?>(
      (cubit) => cubit.state.activeBoard?.viewport.focusedPanelId,
    );
    if (panel.id != focusedPanelId) {
      return const SizedBox.shrink();
    }

    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    if (plugin?.showHeader ?? true) {
      return const SizedBox.shrink();
    }

    final origin = BoardPanelSelectionMetrics.floatingChromeOrigin(
      panel,
      canvasOrigin,
    );

    return Positioned(
      left: origin.dx,
      top: origin.dy,
      child: StickyNoteChrome(
        panel: panel,
        locked: panel.locked,
        onUpdateState: onUpdateState,
        onDragStart: (details) => _startDrag(context, details),
        onDragUpdate: panel.locked ? null : onMove,
        onDragEnd: onDragEnd,
        onDuplicate:
            () => context.read<BoardCubit>().duplicatePanels({panel.id}),
        onToggleLocked:
            () => context.read<BoardCubit>().updatePanel(
              panel.id,
              (p) => p.copyWith(locked: !p.locked),
            ),
        onBringToFront: onBringToFront,
        onSendToBack: onSendToBack,
        onSettings: () => _showSettingsDialog(context),
        onDelete: onDelete,
      ),
    );
  }
}
