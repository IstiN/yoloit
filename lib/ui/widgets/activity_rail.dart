import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class ActivityRailItem {
  const ActivityRailItem({
    this.icon,
    this.iconWidget,
    required this.tooltip,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String tooltip;
  final VoidCallback onTap;
}

/// A 32px-wide vertical strip showing icons for collapsed panels.
/// [side] determines border placement: left rail uses right border, right rail uses left border.
class ActivityRail extends StatelessWidget {
  const ActivityRail({
    super.key,
    required this.items,
    this.side = ActivityRailSide.left,
  });

  final List<ActivityRailItem> items;
  final ActivityRailSide side;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final border = side == ActivityRailSide.left
        ? Border(right: BorderSide(color: colors.divider, width: 1))
        : Border(left: BorderSide(color: colors.divider, width: 1));

    return Container(
      width: 32,
      decoration: BoxDecoration(
        color: colors.surface,
        border: border,
      ),
      child: Column(
        children: items.map((item) => _RailItemButton(item: item)).toList(),
      ),
    );
  }
}

enum ActivityRailSide { left, right }

class _RailItemButton extends StatefulWidget {
  const _RailItemButton({required this.item});
  final ActivityRailItem item;

  @override
  State<_RailItemButton> createState() => _RailItemButtonState();
}

class _RailItemButtonState extends State<_RailItemButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: widget.item.tooltip,
      preferBelow: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.item.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 32,
            height: 32,
            color: _hovering ? colors.surfaceElevated : Colors.transparent,
            child: Center(
              child: widget.item.iconWidget != null
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: widget.item.iconWidget,
                    )
                  : Icon(
                      widget.item.icon,
                      size: 16,
                      color: _hovering ? colors.primary : colors.textMuted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
