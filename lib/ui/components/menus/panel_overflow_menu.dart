import 'package:flutter/material.dart';
import 'package:yoloit/ui/components/menus/hover_overflow_menu.dart';

/// Shared overflow menu for both the unified panel header and the
/// sticky-note floating chrome.
class PanelOverflowMenu extends StatelessWidget {
  const PanelOverflowMenu({
    super.key,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onSettings,
    required this.onDelete,
    this.onToggleLocked,
    this.locked = false,
    this.onFullscreen,
  });

  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onSettings;
  final VoidCallback onDelete;
  final VoidCallback? onToggleLocked;
  final bool locked;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    return HoverOverflowMenu(
      items: [
        if (onToggleLocked != null)
          HoverOverflowItem(
            icon: locked ? Icons.lock : Icons.lock_open,
            label: locked ? 'Unlock' : 'Lock',
            onTap: onToggleLocked!,
          ),
        HoverOverflowItem(
          icon: Icons.flip_to_front,
          label: 'Bring to front',
          onTap: onBringToFront,
        ),
        HoverOverflowItem(
          icon: Icons.flip_to_back,
          label: 'Send to back',
          onTap: onSendToBack,
        ),
        if (onFullscreen != null)
          HoverOverflowItem(
            icon: Icons.open_in_full,
            label: 'Fullscreen',
            onTap: onFullscreen!,
          ),
        HoverOverflowItem(
          icon: Icons.settings,
          label: 'Settings',
          onTap: onSettings,
        ),
        HoverOverflowItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          onTap: onDelete,
        ),
      ],
    );
  }
}
