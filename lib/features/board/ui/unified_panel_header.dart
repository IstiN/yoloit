import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';
import 'package:yoloit/ui/components/menus/panel_overflow_menu.dart';

/// Unified header bar for board panels.
///
/// Always shows the primary actions (duplicate, lock, color) and a close
/// button. Secondary actions live in the hover-reveal overflow menu.
class UnifiedPanelHeader extends StatelessWidget {
  const UnifiedPanelHeader({
    required this.panel,
    required this.isSelected,
    required this.isFocused,
    required this.onDuplicate,
    required this.onToggleLocked,
    required this.onEditColor,
    required this.onBringToFront,
    required this.onSendToBack,
    this.onEdit,
    this.onFullscreen,
    required this.onSettings,
    required this.onDelete,
    this.leadingIcon,
    this.pluginActions = const [],
    super.key,
  });

  final BoardPanelInstance panel;
  final bool isSelected;
  final bool isFocused;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleLocked;
  final VoidCallback onEditColor;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback? onEdit;
  final VoidCallback? onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onDelete;
  final Widget? leadingIcon;
  final List<Widget> pluginActions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    final accent = panel.color ?? plugin?.accentColor;
    final headerColor = isSelected || isFocused
        ? colors.surfaceElevated
        : colors.surface;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: headerColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
        border: Border(
          bottom: BorderSide(color: colors.divider),
        ),
      ),
      child: Row(
        children: [
          HeaderIconButton(
            icon: Icons.drag_indicator,
            tooltip: panel.locked ? 'Panel is locked' : 'Move panel',
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          leadingIcon ?? _PanelIcon(plugin: plugin),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              panel.title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          HeaderIconButton(
            icon: Icons.copy,
            tooltip: 'Duplicate panel',
            onPressed: onDuplicate,
          ),
          HeaderIconButton(
            icon: Icons.format_color_fill,
            tooltip: 'Panel color',
            onPressed: onEditColor,
            swatch: accent == Colors.transparent ? null : accent,
          ),
          if (onEdit != null)
            HeaderIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit content',
              onPressed: onEdit!,
            ),
          ...pluginActions,
          PanelOverflowMenu(
            onToggleLocked: onToggleLocked,
            locked: panel.locked,
            onBringToFront: onBringToFront,
            onSendToBack: onSendToBack,
            onFullscreen: onFullscreen,
            onSettings: onSettings,
            onDelete: onDelete,
          ),
          HeaderIconButton(
            icon: Icons.close,
            tooltip: 'Remove panel',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _PanelIcon extends StatelessWidget {
  const _PanelIcon({this.plugin});

  final BoardPanelPlugin? plugin;

  @override
  Widget build(BuildContext context) {
    final svgIcon = plugin?.buildIconWidget(context, size: 16);
    if (svgIcon != null) return svgIcon;
    return Icon(
      plugin?.icon ?? Icons.dashboard_customize_outlined,
      size: 16,
      color: context.appColors.textSecondary,
    );
  }
}
