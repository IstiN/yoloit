import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool useFullscreenDialogs(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) return true;
  return size.shortestSide < 600;
}

Future<T?> showAdaptiveYoloDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final child = builder(dialogContext);
      if (!useFullscreenDialogs(dialogContext)) return child;
      return Dialog.fullscreen(child: child);
    },
  );
}

class AdaptiveDialogScaffold extends StatelessWidget {
  const AdaptiveDialogScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.icon,
    this.maxWidth,
    this.maxHeight,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? icon;
  final double? maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    if (!useFullscreenDialogs(context)) {
      return AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(width: maxWidth, height: maxHeight, child: body),
        actions: actions,
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 10)],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(padding: const EdgeInsets.all(16), child: body),
            ),
            if (actions.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
