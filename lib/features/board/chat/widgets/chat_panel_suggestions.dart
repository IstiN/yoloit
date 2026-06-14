import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Inline suggestion list of board panels for the `/yolo` slash command.
class ChatPanelSuggestions extends StatelessWidget {
  const ChatPanelSuggestions({
    required this.panels,
    required this.selectedIds,
    required this.onSelect,
    super.key,
  });

  final List<BoardPanelInstance> panels;
  final Set<String> selectedIds;
  final ValueChanged<BoardPanelInstance> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (panels.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'No panels on this board',
          style: TextStyle(fontSize: 12, color: colors.textMuted),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: panels.length,
        itemBuilder: (context, i) {
          final panel = panels[i];
          final isSelected = selectedIds.contains(panel.id);
          return InkWell(
            onTap: () => onSelect(panel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color:
                        isSelected
                            ? colors.terminalPrompt
                            : colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          panel.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          panel.type,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
