import 'package:flutter/material.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Copy-to-clipboard menu button shown on chat bubbles.
class ChatBubbleMenu extends StatelessWidget {
  const ChatBubbleMenu({
    super.key,
    required this.textToCopy,
    this.light = false,
  });

  final String textToCopy;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color =
        light
            ? context.appColors.textPrimary.withAlpha(153)
            : (context.appColors.textMuted);
    return SizedBox(
      width: 24,
      height: 28,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () {
            copyToClipboard(textToCopy);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Icon(Icons.more_vert, size: 16, color: color),
        ),
      ),
    );
  }
}
