import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';

/// Horizontal scrollable chips for slash-command suggestions.
class ChatSlashChips extends StatelessWidget {
  const ChatSlashChips({
    required this.commands,
    required this.onSelect,
    super.key,
  });

  final List<ChatSlashCommand> commands;
  final ValueChanged<ChatSlashCommand> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (commands.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final cmd = commands[i];
          final isActive = i == 0;
          return GestureDetector(
            onTap: () => onSelect(cmd),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:
                    isActive
                        ? colors.terminalPrompt.withValues(alpha: 0.2)
                        : colors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      isActive
                          ? colors.terminalPrompt.withValues(alpha: 0.5)
                          : colors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cmd.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    cmd.description,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
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
