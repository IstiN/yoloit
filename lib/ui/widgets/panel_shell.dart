import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Wraps panel content with a unified header bar:
/// [icon] TITLE   [actions...] [collapse] [close]
class PanelShell extends StatelessWidget {
  const PanelShell({
    super.key,
    required this.title,
    this.icon,
    this.iconWidget,
    this.actions = const [],
    this.onCollapse,
    this.collapseIcon = Icons.keyboard_arrow_left,
    this.onClose,
    required this.child,
  });

  final String title;
  final IconData? icon;
  final Widget? iconWidget;
  final List<Widget> actions;
  final VoidCallback? onCollapse;
  final IconData collapseIcon;
  final VoidCallback? onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: title,
          icon: icon,
          iconWidget: iconWidget,
          actions: actions,
          onCollapse: onCollapse,
          collapseIcon: collapseIcon,
          onClose: onClose,
          colors: colors,
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    this.icon,
    this.iconWidget,
    required this.actions,
    this.onCollapse,
    required this.collapseIcon,
    this.onClose,
    required this.colors,
  });

  final String title;
  final IconData? icon;
  final Widget? iconWidget;
  final List<Widget> actions;
  final VoidCallback? onCollapse;
  final IconData collapseIcon;
  final VoidCallback? onClose;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.divider, width: 2),
          bottom: BorderSide(color: colors.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Icon
          if (iconWidget != null) ...[
            SizedBox(width: 13, height: 13, child: iconWidget),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: colors.textMuted),
            const SizedBox(width: 6),
          ],
          // Title — Expanded absorbs all remaining space, pushing buttons to right edge
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          // Action buttons
          ...actions,
          // Collapse button
          if (onCollapse != null) ...[
            const SizedBox(width: 2),
            PanelActionBtn(
              icon: collapseIcon,
              tooltip: 'Collapse',
              onTap: onCollapse!,
              colors: colors,
            ),
          ],
          // Close button
          if (onClose != null) ...[
            const SizedBox(width: 2),
            PanelActionBtn(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: onClose!,
              colors: colors,
            ),
          ],
        ],
      ),
    );
  }
}

/// An action button suitable for use in PanelShell.actions or headers.
class PanelActionBtn extends StatefulWidget {
  const PanelActionBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.colors,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final AppColorScheme? colors;

  @override
  State<PanelActionBtn> createState() => _PanelActionBtnState();
}

class _PanelActionBtnState extends State<PanelActionBtn> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors ?? context.appColors;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hovering ? colors.surfaceElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: _hovering ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
