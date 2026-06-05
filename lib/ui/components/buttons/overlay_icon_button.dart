import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A small icon button with tooltip, designed for floating overlay toolbars.
/// Highlights with primary color when [active] is true.
class OverlayIconButton extends StatelessWidget {
  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                Theme.of(context).brightness == Brightness.light
                    ? colors.surface
                    : colors.surface.withAlpha(0xE5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? colors.primary.withAlpha(128) : colors.border,
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color:
                active
                    ? colors.primary
                    : context.appColors.textMuted,
          ),
        ),
      ),
    );
  }
}
