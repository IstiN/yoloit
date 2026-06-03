import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';

class IconTextButton extends StatefulWidget {
  const IconTextButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color = AppColors.textSecondary,
    this.activeColor,
    this.isActive = false,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final Color? activeColor;
  final bool isActive;
  final bool dense;

  @override
  State<IconTextButton> createState() => _IconTextButtonState();
}

class _IconTextButtonState extends State<IconTextButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effective = widget.activeColor ?? colors.primary;
    final color =
        widget.isActive
            ? effective
            : _hovering
            ? widget.color.withAlpha(200)
            : widget.color;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 8 : 12,
            vertical: widget.dense ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color:
                widget.isActive
                    ? effective.withAlpha(30)
                    : _hovering
                    ? colors.surfaceHighlight
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
