import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_settings_panels.dart';
import 'package:yoloit/ui/components/buttons/overlay_icon_button.dart';

class BoardToolsPanel extends StatelessWidget {
  const BoardToolsPanel({
    super.key,
    required this.board,
    required this.platform,
    required this.visible,
    required this.activeTool,
    required this.drawSettings,
    required this.connectSettings,
    required this.onToolChanged,
    required this.onDrawSettingsChanged,
    required this.onConnectSettingsChanged,
    required this.historyPanelVisible,
    required this.onToggle,
    required this.onShowHistory,
    this.onUndo,
    this.onRedo,
    this.onAddNote,
    this.onAddChat,
    this.onAddTerminal,
    this.onAddGeneric,
  });

  final BoardDocument board;
  final String platform;
  final bool visible;
  final BoardToolId activeTool;
  final DrawSettings drawSettings;
  final ConnectSettings connectSettings;
  final ValueChanged<BoardToolId> onToolChanged;
  final ValueChanged<DrawSettings> onDrawSettingsChanged;
  final ValueChanged<ConnectSettings> onConnectSettingsChanged;
  final bool historyPanelVisible;
  final VoidCallback onToggle;
  final VoidCallback onShowHistory;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onAddNote;
  final VoidCallback? onAddChat;
  final VoidCallback? onAddTerminal;
  final ValueChanged<String>? onAddGeneric;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final mutedColor =
        isLight
            ? const Color(0xFF252A31)
            : (context.appColors.textMuted);
    final panelBg =
        isLight ? Colors.white : colors.surfaceElevated.withAlpha(0xF2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Toggle button ─────────────────────────────────────────────────
        OverlayIconButton(
          icon: visible ? Icons.tune : Icons.tune_outlined,
          tooltip: visible ? 'Hide tools' : 'Show tools',
          active: visible,
          onTap: onToggle,
        ),
        if (visible) ...[
          const SizedBox(height: 6),
          // ── Tool buttons ────────────────────────────────────────────────
          _toolGroup(
            colors: colors,
            panelBg: panelBg,
            isLight: isLight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in kBoardTools) ...[
                  if (kBoardTools.indexOf(tool) > 0) const SizedBox(height: 4),
                  Tooltip(
                    message:
                        tool.shortcutHint != null
                            ? '${tool.label} (${tool.shortcutHint})'
                            : tool.label,
                    child: GestureDetector(
                      onTap: () => onToolChanged(tool.id),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              activeTool == tool.id
                                  ? tool.accentColor.withAlpha(50)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              activeTool == tool.id
                                  ? Border.all(
                                    color: tool.accentColor.withAlpha(180),
                                  )
                                  : null,
                        ),
                        child: Icon(
                          tool.icon,
                          size: 18,
                          color:
                              activeTool == tool.id
                                  ? tool.accentColor
                                  : mutedColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Draw settings ────────────────────────────────────────────────
          if (activeTool == BoardToolId.draw) ...[
            const SizedBox(height: 6),
            DrawSettingsPanel(
              settings: drawSettings,
              onChanged: onDrawSettingsChanged,
            ),
          ],
          // ── Connect settings ─────────────────────────────────────────────
          if (activeTool == BoardToolId.connect) ...[
            const SizedBox(height: 6),
            ConnectSettingsPanel(
              settings: connectSettings,
              onChanged: onConnectSettingsChanged,
            ),
          ],
          const SizedBox(height: 8),
          _toolGroup(
            colors: colors,
            panelBg: panelBg,
            isLight: isLight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiroLeftToolbarButton(
                  icon: Icons.undo_rounded,
                  tooltip: 'Undo latest panel change',
                  onTap: onUndo,
                  color: mutedColor,
                ),
                const SizedBox(height: 4),
                MiroLeftToolbarButton(
                  icon: Icons.redo_rounded,
                  tooltip: 'Redo',
                  onTap: onRedo,
                  color: mutedColor,
                ),
                const SizedBox(height: 4),
                MiroLeftToolbarButton(
                  icon: Icons.manage_history_rounded,
                  tooltip:
                      historyPanelVisible
                          ? 'Hide board history'
                          : 'Show board history',
                  active: historyPanelVisible,
                  onTap: onShowHistory,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ],
        // ── Add panel buttons (always visible) ───────────────────────────
        const SizedBox(height: 8),
        _toolGroup(
          colors: colors,
          panelBg: panelBg,
          isLight: isLight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: PanelCatalogCategory.basics,
                icon: Icons.category_outlined,
                tooltip: 'Miro basics',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: PanelCatalogCategory.ai,
                icon: Icons.auto_awesome,
                tooltip: 'AI and terminal',
                color: colors.statusActive,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: PanelCatalogCategory.files,
                icon: Icons.folder_outlined,
                tooltip: 'Files and web',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: PanelCatalogCategory.planning,
                icon: Icons.view_kanban_outlined,
                tooltip: 'Planning',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: PanelCatalogCategory.advanced,
                icon: Icons.extension_outlined,
                tooltip: 'Advanced',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolGroup({
    required AppColorScheme colors,
    required Color panelBg,
    required bool isLight,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withAlpha(180)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isLight ? 18 : 70),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MiroLeftToolbarButton extends StatelessWidget {
  const MiroLeftToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active ? colors.primary.withAlpha(32) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:
                active
                    ? Border.all(color: colors.primary.withAlpha(180))
                    : null,
          ),
          child: Icon(
            icon,
            size: 23,
            color:
                enabled
                    ? (active ? colors.primary : color)
                    : color.withAlpha(90),
          ),
        ),
      ),
    );
  }
}

class PanelCatalogCategoryButton extends StatelessWidget {
  const PanelCatalogCategoryButton({
    super.key,
    required this.board,
    required this.platform,
    required this.category,
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onAddGeneric,
    this.onAddNote,
    this.onAddChat,
    this.onAddTerminal,
  });

  final BoardDocument board;
  final String platform;
  final PanelCatalogCategory category;
  final IconData icon;
  final String tooltip;
  final ValueChanged<String>? onAddGeneric;
  final Color color;
  final VoidCallback? onAddNote;
  final VoidCallback? onAddChat;
  final VoidCallback? onAddTerminal;

  @override
  Widget build(BuildContext context) {
    final hasItems = _itemsFor(context, category).isNotEmpty;
    return Builder(
      builder:
          (btnCtx) => Tooltip(
            message: hasItems ? tooltip : '$tooltip unavailable on this board',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: hasItems ? () => _showCategoryItems(btnCtx) : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: hasItems ? color : color.withAlpha(80),
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _showCategoryItems(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset(box.size.width, 0));
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx + 4,
        pos.dy,
        pos.dx + 340,
        pos.dy + 100,
      ),
      color: _menuColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: _itemsFor(context, category),
    );
    if (selected == null) return;
    if (selected == '__note') {
      onAddNote?.call();
      return;
    }
    if (selected == '__chat') {
      onAddChat?.call();
      return;
    }
    if (selected == '__terminal') {
      onAddTerminal?.call();
      return;
    }
    onAddGeneric?.call(selected);
  }

  List<PopupMenuEntry<String>> _itemsFor(
    BuildContext context,
    PanelCatalogCategory category,
  ) {
    PopupMenuEntry<String>? pluginItem(String typeId) {
      if (onAddGeneric == null) return null;
      if (!_isPanelTypeAvailable(typeId)) return null;
      final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
      if (plugin == null) return null;
      return _catalogItem(
        context,
        value: plugin.typeId,
        icon: plugin.icon,
        iconColor: plugin.accentColor,
        label: plugin.displayName,
      );
    }

    final items = switch (category) {
      PanelCatalogCategory.basics => <PopupMenuEntry<String>?>[
        if (onAddNote != null && _isPanelTypeAvailable('board.note.markdown'))
          _catalogItem(
            context,
            value: '__note',
            icon: Icons.notes_rounded,
            iconColor: context.appColors.textMuted,
            label: 'Markdown Note',
          ),
        pluginItem('board.sticky'),
        if (onAddGeneric != null && _isPanelTypeAvailable('board.shape'))
          _catalogItem(
            context,
            value: '__shape:frame',
            icon: Icons.interests_outlined,
            iconColor: context.appColors.accentBlue,
            label: 'Shape / Frame',
          ),
      ],
      PanelCatalogCategory.ai => <PopupMenuEntry<String>?>[
        if (onAddChat != null && _isPanelTypeAvailable('board.chat'))
          _catalogItem(
            context,
            value: '__chat',
            icon: Icons.auto_awesome,
            iconColor: context.appColors.statusActive,
            label: 'AI Chat',
          ),
        if (onAddTerminal != null && _isPanelTypeAvailable('board.terminal'))
          _catalogItem(
            context,
            value: '__terminal',
            icon: Icons.terminal,
            iconColor: context.appColors.statusActive,
            label: 'Terminal',
          ),
        pluginItem('board.yolo_assistant'),
      ],
      PanelCatalogCategory.files => <PopupMenuEntry<String>?>[
        pluginItem('board.filetree'),
        pluginItem('board.files'),
        pluginItem('board.file.preview'),
        pluginItem('board.webpage'),
      ],
      PanelCatalogCategory.planning => <PopupMenuEntry<String>?>[
        pluginItem('board.kanban'),
        pluginItem('board.checklist'),
        pluginItem('board.timer'),
        pluginItem('board.calendar'),
        pluginItem('board.table'),
        pluginItem('board.chart'),
      ],
      PanelCatalogCategory.advanced => <PopupMenuEntry<String>?>[
        pluginItem('board.setup_guide'),
        pluginItem('board.code.snippet'),
        pluginItem('board.playlist'),
        pluginItem('board.run_configs'),
        pluginItem('board.widget.custom'),
      ],
    };
    return items.whereType<PopupMenuEntry<String>>().toList();
  }

  bool _isPanelTypeAvailable(String typeId) {
    return yoloitdPanelTypeAvailableOn(
      typeId,
      platform: platform,
      remote: isRemoteBoard(board),
    );
  }

  PopupMenuItem<String> _catalogItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 52,
      child: Row(
        children: [
          Icon(icon, size: 21, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _menuTextColor(context),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _menuColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? context.appColors.surface
        : context.appColors.surfaceElevated;
  }

  Color _menuTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF252A31)
        : (Theme.of(context).textTheme.bodyMedium?.color ??
            Theme.of(context).colorScheme.onSurface);
  }
}

enum PanelCatalogCategory { basics, ai, files, planning, advanced }
