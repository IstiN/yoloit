import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A compact 28×28 header icon button with optional active state and swatch.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.swatch,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: active
                ? BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Icon(
              icon,
              size: 16,
              color: swatch ?? (active ? colors.primary : colors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
