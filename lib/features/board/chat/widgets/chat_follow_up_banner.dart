import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Banner that shows a queued follow-up message that will be auto-sent when
/// the current agent turn completes.
class ChatFollowUpBanner extends StatelessWidget {
  const ChatFollowUpBanner({
    required this.text,
    required this.onEdit,
    required this.onCancel,
    super.key,
  });

  final String text;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.terminalPrompt.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colors.terminalPrompt.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule_send_outlined,
            size: 14,
            color: colors.terminalPrompt,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Will send after this turn:',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.terminalPrompt,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(fontSize: 12, color: textColor),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _ActionButton(
            tooltip: 'Edit',
            icon: Icons.edit_outlined,
            onTap: onEdit,
          ),
          const SizedBox(width: 4),
          _ActionButton(
            tooltip: 'Cancel',
            icon: Icons.close,
            onTap: onCancel,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            child: Icon(icon, size: 13, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
