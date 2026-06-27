import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Shared animated shell for the inline YoLo assistant overlay.
///
/// Handles the collapsible badge ↔ expanded card transition, gradient border,
/// shadow, and badge/content cross-fade. Used by the production panel badge
/// and the debug panel-chrome prototype.
class YoloAssistantOverlayShell extends StatelessWidget {
  const YoloAssistantOverlayShell({
    super.key,
    required this.expanded,
    required this.badgeSize,
    required this.expandedWidth,
    required this.expandedHeight,
    required this.badgeIcon,
    this.badgeOpacity = 0.55,
    required this.headerTrailing,
    required this.content,
    this.border,
    this.duration = const Duration(milliseconds: 350),
  });

  final bool expanded;
  final double badgeSize;
  final double expandedWidth;
  final double expandedHeight;
  final Widget badgeIcon;
  final double badgeOpacity;
  final Widget headerTrailing;
  final Widget content;
  final BoxBorder? border;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : (expanded ? expandedWidth : badgeSize);
        final height =
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : (expanded ? expandedHeight : badgeSize);
        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeInOutCubic,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(expanded ? 16 : 18),
            border: border,
            gradient:
                border == null
                    ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colors.accentBlue, colors.primary],
                    )
                    : null,
            boxShadow: [
              BoxShadow(
                color: colors.textMuted.withValues(alpha: expanded ? 0.2 : 0.15),
                blurRadius: expanded ? 20 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            margin: border == null ? const EdgeInsets.all(1.5) : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(
                border == null ? (expanded ? 14.5 : 16.5) : (expanded ? 16 : 18),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              child:
                  expanded
                      ? OverflowBox(
                        key: const ValueKey('yolo-expanded'),
                        maxWidth: expandedWidth,
                        maxHeight: expandedHeight,
                        alignment: Alignment.topCenter,
                        child: _ExpandedContent(
                          headerTrailing: headerTrailing,
                          content: content,
                        ),
                      )
                      : _BadgeIcon(
                        key: const ValueKey('yolo-badge'),
                        icon: badgeIcon,
                        opacity: badgeOpacity,
                      ),
            ),
          ),
        );
      },
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({super.key, required this.icon, required this.opacity});

  final Widget icon;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(opacity: opacity, child: icon),
    );
  }
}

class _ExpandedContent extends StatelessWidget {
  const _ExpandedContent({required this.headerTrailing, required this.content});

  final Widget headerTrailing;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YoloAssistantHeader(trailing: headerTrailing),
        Expanded(child: content),
      ],
    );
  }
}

/// Gradient "YOLO" header shared by the inline assistant overlay.
class YoloAssistantHeader extends StatelessWidget {
  const YoloAssistantHeader({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTrailing = trailing != null && constraints.maxWidth >= 60;
          return Row(
            children: [
              Expanded(
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback:
                      (bounds) => LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.accentBlue, colors.primary],
                      ).createShader(bounds),
                  child: Text(
                    'YOLO',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textHighlight,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              if (showTrailing) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          );
        },
      ),
    );
  }
}
