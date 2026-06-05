import 'package:flutter/material.dart';

/// Standard dialog action row used across board-plugin editors.
///
/// Replaces the repeated `actions: [TextButton(Cancel), FilledButton(Apply)]`
/// boilerplate in editor dialogs.
class EditorDialogActions extends StatelessWidget {
  const EditorDialogActions({
    super.key,
    this.onCancel,
    this.onApply,
    this.cancelLabel = 'Cancel',
    this.applyLabel = 'Apply',
    this.applyResult,
    this.applyResultBuilder,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onApply;
  final String cancelLabel;
  final String applyLabel;

  /// When non-null, the Apply button pops the Navigator with this value
  /// instead of calling [onApply].
  ///
  /// Prefer [applyResultBuilder] when the result depends on mutable widget
  /// state (e.g. [ChoiceChip] selections) so the map is built at tap-time
  /// rather than at build-time.
  final Object? applyResult;

  /// Lazily builds the result when Apply is tapped.
  ///
  /// Use this instead of [applyResult] when the dialog state may change
  /// between the last build and the button press (e.g. in widget tests
  /// that tap controls without pumping between actions).
  final Object? Function()? applyResultBuilder;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: onCancel ?? () => Navigator.of(context).pop(),
          child: Text(cancelLabel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            if (applyResultBuilder != null) {
              Navigator.of(context).pop(applyResultBuilder!());
            } else if (applyResult != null) {
              Navigator.of(context).pop(applyResult);
            } else {
              onApply?.call();
            }
          },
          child: Text(applyLabel),
        ),
      ],
    );
  }
}
