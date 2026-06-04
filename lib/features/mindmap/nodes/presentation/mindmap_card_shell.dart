import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Reusable outer shell for mind-map node cards.
///
/// Handles the common decoration pattern (background, border, radius, shadow)
/// and optional [ClipRRect] wrapping.  Use with [MindmapCardHeader] for the
/// standard header row.
class MindmapCardShell extends StatelessWidget {
  const MindmapCardShell({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
    this.borderWidth = 1.5,
    this.borderRadius = 10.0,
    this.shadowBlur = 14.0,
    this.shadowOffset = const Offset(0, 4),
    this.shadowAlpha = 112,
    this.clip = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final double shadowBlur;
  final Offset shadowOffset;
  final int shadowAlpha;
  final bool clip;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colors.surfaceElevated,
        border: Border.all(
          color: borderColor ?? colors.border.withAlpha(85),
          width: borderWidth,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: colors.background.withAlpha(shadowAlpha),
            blurRadius: shadowBlur,
            offset: shadowOffset,
          ),
        ],
      ),
      child: child,
    );
    if (!clip) return container;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius - 0.5),
      child: container,
    );
  }
}

/// Reusable header row for mind-map node cards.
///
/// Displays an [icon] + [title] with the standard background tint and
/// bottom/top radius.  Additional trailing widgets can be supplied via
/// [actions].
class MindmapCardHeader extends StatelessWidget {
  const MindmapCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
    this.iconSize = 12.0,
    this.gap = 6.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    this.backgroundColor,
    this.titleStyle,
    this.actions = const [],
    this.bottomBorder,
  });

  final IconData icon;
  final String title;
  final Color? iconColor;
  final double iconSize;
  final double gap;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final TextStyle? titleStyle;
  final List<Widget> actions;
  final BorderSide? bottomBorder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
        border:
            bottomBorder != null
                ? Border(bottom: bottomBorder!)
                : null,
      ),
      child: Row(
        children: [
          Icon(icon, size: iconSize, color: iconColor ?? colors.textSecondary),
          SizedBox(width: gap),
          Expanded(
            child: Text(
              title,
              style:
                  titleStyle ??
                  TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
