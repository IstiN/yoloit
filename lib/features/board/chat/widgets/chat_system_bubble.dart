import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Centered error/status bubble with a red background.
class ChatSystemBubble extends StatelessWidget {
  const ChatSystemBubble({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.statusError.withAlpha(21),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '✕ ',
                style: TextStyle(fontSize: 12, color: colors.statusError),
              ),
              Flexible(
                child: SelectableText(
                  content,
                  style: TextStyle(fontSize: 12, color: colors.statusError),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
