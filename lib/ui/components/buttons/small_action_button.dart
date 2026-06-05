import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Compact square action button with hover highlight.
///
/// Used in mind-map card toolbars, run-card headers, and anywhere a
/// small icon-only affordance is needed.
class SmallActionButton extends StatefulWidget {
  const SmallActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onTap,
    this.size = 22,
    this.iconSize = 13,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  State<SmallActionButton> createState() => _SmallActionButtonState();
}

class _SmallActionButtonState extends State<SmallActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color:
                  _hovered
                      ? widget.color.withAlpha(40)
                      : colors.surfaceElevated,
              border: Border.all(
                color: _hovered ? widget.color : colors.border,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered ? widget.color : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
