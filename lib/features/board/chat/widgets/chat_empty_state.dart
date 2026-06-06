import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(30),
          ),
          const SizedBox(height: 12),
          Text(
            'Send a message to start',
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.textMuted.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
