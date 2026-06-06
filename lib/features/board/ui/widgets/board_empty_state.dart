import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class BoardEmptyState extends StatelessWidget {
  const BoardEmptyState({super.key, required this.onAddNote});

  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
              boxShadow: [
                BoxShadow(
                  color: colors.background.withAlpha(45),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.dashboard_customize_outlined,
                  size: 32,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                const SizedBox(height: 12),
                Text(
                  'Board foundation is ready',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create named boards and start with markdown notes. '
                  'The first panel will open in a free slot, and links will support static and dynamic lines/arrows.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAddNote,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add note'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
