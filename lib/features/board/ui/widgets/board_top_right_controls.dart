import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_minimap.dart';
import 'package:yoloit/ui/components/buttons/overlay_icon_button.dart';

class BoardTopRightControls extends StatelessWidget {
  const BoardTopRightControls({
    super.key,
    required this.showMinimap,
    required this.onToggleMinimap,
    required this.onFitBoard,
    required this.panels,
    required this.transformController,
    required this.viewportSize,
    required this.origin,
    required this.onPanTo,
  });

  final bool showMinimap;
  final VoidCallback onToggleMinimap;
  final VoidCallback onFitBoard;
  final List<BoardPanelInstance> panels;
  final TransformationController transformController;
  final Size viewportSize;
  final Offset origin;
  final ValueChanged<Offset> onPanTo;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OverlayIconButton(
                icon: Icons.fit_screen_outlined,
                tooltip: 'Fit board to content',
                onTap: onFitBoard,
              ),
              const SizedBox(width: 6),
              OverlayIconButton(
                icon: showMinimap ? Icons.map : Icons.map_outlined,
                tooltip: showMinimap ? 'Hide minimap' : 'Show minimap',
                active: showMinimap,
                onTap: onToggleMinimap,
              ),
            ],
          ),
          if (showMinimap) ...[
            const SizedBox(height: 6),
            ValueListenableBuilder<int>(
              valueListenable: ChatPanelWidget.processingChangeNotifier,
              builder: (context, value, child) => BoardMiniMap(
                panels: panels,
                processingPanelIds: ChatPanelWidget.processingNotifiers.entries
                    .where((e) => e.value.value)
                    .map((e) => e.key)
                    .toSet(),
                transformCtrl: transformController,
                viewportSize: viewportSize,
                origin: origin,
                onPanTo: onPanTo,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
