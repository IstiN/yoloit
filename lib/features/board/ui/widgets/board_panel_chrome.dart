import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';

/// Builds the standard panel chrome used by board overview previews and
/// offscreen renders.
///
/// This widget is intentionally simple and avoids dependencies on panel
/// content so it can be reused in both contexts.
class BoardPanelChrome extends StatelessWidget {
  const BoardPanelChrome({
    super.key,
    required this.panel,
    required this.colors,
    this.clipContent = true,
    required this.content,
  });

  final BoardPanelInstance panel;
  final AppColorScheme colors;
  final bool clipContent;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final accent = panel.color;
    final panelFill =
        accent == null
            ? colors.surface
            : Color.lerp(colors.surface, accent, 0.12) ?? colors.surface;
    final panelHeaderFill =
        accent == null
            ? colors.surfaceElevated
            : Color.lerp(colors.surfaceElevated, accent, 0.18) ??
                colors.surfaceElevated;
    final borderColor =
        accent == null
            ? colors.border
            : Color.lerp(colors.border, accent, 0.65) ?? colors.border;

    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type) ??
        BoardPluginRegistry.instance.fallback;

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: panelHeaderFill,
            border: Border(
              bottom: BorderSide(color: colors.divider, width: 1.0),
            ),
          ),
          child: Row(
            children: [
              Icon(
                plugin.icon,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withAlpha(180),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  panel.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: clipContent ? ClipRect(child: content) : content),
      ],
    );

    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panelFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: child,
        ),
      ),
    );
  }
}
