import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Shared visual shell for mind-map presentation cards.
///
/// Wraps content in a bordered, shadowed container with an optional
/// header row (icon + title + trailing widgets). Used by
/// [DiffCard], [FileTreeCard], [RunCard] and similar node cards
/// to eliminate duplicated BoxDecoration / ClipRRect / header
/// boilerplate.
class MindmapCardShell extends StatelessWidget {
  const MindmapCardShell({
    super.key,
    required this.child,
    this.headerIcon,
    this.headerIconColor,
    this.headerTitle,
    this.headerTrailing,
    this.borderColor,
    this.backgroundColor,
    this.headerBackgroundColor,
    this.showHeaderDivider = true,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.bodyPadding,
  });

  final Widget child;
  final IconData? headerIcon;
  final Color? headerIconColor;
  final String? headerTitle;
  final List<Widget>? headerTrailing;
  final Color? borderColor;
  final Color? backgroundColor;
  final Color? headerBackgroundColor;
  final bool showHeaderDivider;
  final EdgeInsets headerPadding;
  final EdgeInsets? bodyPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effectiveBorder = borderColor ?? colors.border;
    final effectiveBg = backgroundColor ?? colors.surface;

    return Container(
      decoration: BoxDecoration(
        color: effectiveBg,
        border: Border.all(color: effectiveBorder, width: 1.5),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: colors.background.withAlpha(144),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (headerTitle != null) _buildHeader(colors, effectiveBg),
            Expanded(
              child: bodyPadding != null
                  ? Padding(padding: bodyPadding!, child: child)
                  : child,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColorScheme colors, Color effectiveBg) {
    return Container(
      padding: headerPadding,
      decoration: BoxDecoration(
        color: headerBackgroundColor ?? colors.surfaceElevated,
        border: showHeaderDivider
            ? Border(bottom: BorderSide(color: colors.divider))
            : null,
      ),
      child: Row(
        children: [
          if (headerIcon != null) ...[
            Icon(headerIcon!, size: 12, color: headerIconColor ?? colors.accentGreen),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              headerTitle!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (headerTrailing != null) ...headerTrailing!,
        ],
      ),
    );
  }
}
