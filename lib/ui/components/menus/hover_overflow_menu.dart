import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';

/// An item shown inside a [HoverOverflowMenu].
class HoverOverflowItem {
  const HoverOverflowItem({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

/// A three-dots trigger that opens a horizontal row of icon actions on hover.
///
/// The menu is anchored on the trigger and opens above it by default.
class HoverOverflowMenu extends StatefulWidget {
  const HoverOverflowMenu({
    super.key,
    required this.items,
    this.alignmentOffset = const Offset(0, -56),
  });

  final List<HoverOverflowItem> items;
  final Offset alignmentOffset;

  @override
  State<HoverOverflowMenu> createState() => _HoverOverflowMenuState();
}

class _HoverOverflowMenuState extends State<HoverOverflowMenu> {
  final _controller = MenuController();
  Timer? _hideTimer;

  void _show() {
    _hideTimer?.cancel();
    if (!_controller.isOpen) {
      _controller.open();
    }
  }

  void _delayedHide() {
    _hideTimer = Timer(const Duration(milliseconds: 80), () {
      if (_controller.isOpen) {
        _controller.close();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: widget.alignmentOffset,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceElevated),
        side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
      ),
      menuChildren: [
        MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _delayedHide(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in widget.items)
                HeaderIconButton(
                  icon: item.icon,
                  tooltip: item.label,
                  onPressed: item.onTap ?? () {},
                ),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _delayedHide(),
        child: HeaderIconButton(
          icon: Icons.more_vert,
          tooltip: 'More actions',
          onPressed: _show,
        ),
      ),
    );
  }
}
