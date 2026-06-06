import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A small inline list of check-box toggles for chat context injection options.
class ChatContextToggles extends StatelessWidget {
  const ChatContextToggles({
    required this.cliHelp,
    required this.boardSnapshot,
    required this.boardPanelsJson,
    required this.systemPrompt,
    required this.onCliHelpChanged,
    required this.onBoardSnapshotChanged,
    required this.onBoardPanelsJsonChanged,
    required this.onSystemPromptChanged,
    super.key,
  });

  final bool cliHelp;
  final bool boardSnapshot;
  final bool boardPanelsJson;
  final bool systemPrompt;
  final ValueChanged<bool> onCliHelpChanged;
  final ValueChanged<bool> onBoardSnapshotChanged;
  final ValueChanged<bool> onBoardPanelsJsonChanged;
  final ValueChanged<bool> onSystemPromptChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final items = <({String label, IconData icon, bool value, void Function(bool) onChanged})>[
      (label: 'CLI Help', icon: Icons.terminal, value: cliHelp, onChanged: onCliHelpChanged),
      (
        label: 'Board Screenshot',
        icon: Icons.screenshot_monitor_outlined,
        value: boardSnapshot,
        onChanged: onBoardSnapshotChanged
      ),
      (label: 'Board Panels JSON', icon: Icons.data_object, value: boardPanelsJson, onChanged: onBoardPanelsJsonChanged),
      (
        label: 'System Prompt',
        icon: Icons.psychology_outlined,
        value: systemPrompt,
        onChanged: onSystemPromptChanged
      ),
    ];

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        separatorBuilder:
            (_, __) =>
                Divider(height: 1, color: colors.border.withValues(alpha: 0.3)),
        itemBuilder: (context, i) {
          final item = items[i];
          return InkWell(
            onTap: () => item.onChanged(!item.value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 14,
                    color:
                        item.value
                            ? colors.terminalPrompt
                            : colors.textPrimary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            item.value
                                ? colors.textPrimary
                                : colors.textPrimary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Icon(
                    item.value
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 16,
                    color:
                        item.value
                            ? colors.terminalPrompt
                            : colors.textPrimary.withValues(alpha: 0.3),
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
