import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A small icon button with tooltip, designed for floating overlay toolbars.
/// Highlights with primary color when [active] is true.
///
/// Set [mini] to `true` for a compact 24×24 variant used inside text fields
/// (e.g. the search-replace bar).
class OverlayIconButton extends StatelessWidget {
  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.active = false,
    this.mini = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool active;

  /// When `true` renders a compact 24×24 variant without padding or border.
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(mini ? 4 : 8),
        child: Container(
          width: mini ? 24 : null,
          height: mini ? 24 : null,
          padding: mini ? EdgeInsets.zero : const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                mini
                    ? (active
                        ? colors.primary.withAlpha(50)
                        : Colors.transparent)
                    : (Theme.of(context).brightness == Brightness.light
                        ? colors.surface
                        : colors.surface.withAlpha(0xE5)),
            borderRadius: BorderRadius.circular(mini ? 4 : 8),
            border:
                mini
                    ? null
                    : Border.all(
                      color:
                          active
                              ? colors.primary.withAlpha(128)
                              : colors.border,
                    ),
          ),
          child: Icon(
            icon,
            size: mini ? 14 : 15,
            color:
                active
                    ? colors.primary
                    : (mini ? colors.textSecondary : colors.textMuted),
          ),
        ),
      ),
    );
  }
}
