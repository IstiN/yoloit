import 'dart:async';

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
    required this.onToggle,
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
  final VoidCallback onToggle;
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
        ],
        // ── Add panel buttons (always visible) ───────────────────────────
        const SizedBox(height: 8),
        _toolGroup(
          colors: colors,
          panelBg: panelBg,
          isLight: isLight,
          child: _CategoryMenuHost(
            board: board,
            platform: platform,
            mutedColor: mutedColor,
            statusActive: colors.statusActive,
            onAddNote: onAddNote,
            onAddChat: onAddChat,
            onAddTerminal: onAddTerminal,
            onAddGeneric: onAddGeneric,
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

class _CategoryMenuHost extends StatefulWidget {
  const _CategoryMenuHost({
    required this.board,
    required this.platform,
    required this.mutedColor,
    required this.statusActive,
    this.onAddNote,
    this.onAddChat,
    this.onAddTerminal,
    this.onAddGeneric,
  });

  final BoardDocument board;
  final String platform;
  final Color mutedColor;
  final Color statusActive;
  final VoidCallback? onAddNote;
  final VoidCallback? onAddChat;
  final VoidCallback? onAddTerminal;
  final ValueChanged<String>? onAddGeneric;

  @override
  State<_CategoryMenuHost> createState() => _CategoryMenuHostState();
}

class _CategoryMenuHostState extends State<_CategoryMenuHost> {
  PanelCatalogCategory? _open;
  Timer? _closeTimer;

  void _setOpen(PanelCatalogCategory c) {
    _cancelClose();
    setState(() => _open = c);
  }

  void _close() {
    _cancelClose();
    if (_open != null) setState(() => _open = null);
  }

  void _scheduleClose() {
    _cancelClose();
    _closeTimer = Timer(const Duration(milliseconds: 150), _close);
  }

  void _cancelClose() {
    _closeTimer?.cancel();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget button(
      PanelCatalogCategory category,
      IconData icon,
      String tooltip,
      Color color,
    ) {
      return PanelCatalogCategoryButton(
        board: widget.board,
        platform: widget.platform,
        category: category,
        icon: icon,
        tooltip: tooltip,
        color: color,
        onAddNote: widget.onAddNote,
        onAddChat: widget.onAddChat,
        onAddTerminal: widget.onAddTerminal,
        onAddGeneric: widget.onAddGeneric,
        isOpen: _open == category,
        onHoverOpen: _setOpen,
        onScheduleClose: _scheduleClose,
        onCancelClose: _cancelClose,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          PanelCatalogCategory.basics,
          Icons.category_outlined,
          'Miro basics',
          widget.mutedColor,
        ),
        const SizedBox(height: 4),
        button(
          PanelCatalogCategory.ai,
          Icons.auto_awesome,
          'AI and terminal',
          widget.statusActive,
        ),
        const SizedBox(height: 4),
        button(
          PanelCatalogCategory.files,
          Icons.folder_outlined,
          'Files and web',
          widget.mutedColor,
        ),
        const SizedBox(height: 4),
        button(
          PanelCatalogCategory.planning,
          Icons.view_kanban_outlined,
          'Planning',
          widget.mutedColor,
        ),
        const SizedBox(height: 4),
        button(
          PanelCatalogCategory.advanced,
          Icons.extension_outlined,
          'Advanced',
          widget.mutedColor,
        ),
      ],
    );
  }
}

class PanelCatalogCategoryButton extends StatefulWidget {
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
    this.isOpen = false,
    this.onHoverOpen,
    this.onScheduleClose,
    this.onCancelClose,
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

  /// When [onHoverOpen] is provided, the open state is owned by a host that
  /// coordinates a single open submenu, instant hover-switching and
  /// close-on-leave. When null, the button manages its own submenu (used by
  /// tests and standalone usage).
  final bool isOpen;
  final void Function(PanelCatalogCategory)? onHoverOpen;
  final VoidCallback? onScheduleClose;
  final VoidCallback? onCancelClose;

  @override
  State<PanelCatalogCategoryButton> createState() =>
      _PanelCatalogCategoryButtonState();
}

class _PanelCatalogCategoryButtonState extends State<PanelCatalogCategoryButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  // Standalone (un-hosted) state. Used when no host coordinates this button.
  bool _localOpen = false;
  Timer? _hoverTimer;
  Timer? _closeTimer;

  /// Vertical shift (in logical pixels, upward) applied to the submenu overlay
  /// so it never overflows the bottom edge of the screen on small windows.
  double _overlayShiftUp = 0;

  bool get _hosted => widget.onHoverOpen != null;

  @override
  void didUpdateWidget(covariant PanelCatalogCategoryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hosted && widget.isOpen != oldWidget.isOpen) {
      // Inserting/removing an OverlayEntry marks the Overlay dirty, which must
      // not happen during the build phase (didUpdateWidget runs while the host
      // is building). Defer the mutation to the end of the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.isOpen) {
          _insertOverlay();
        } else {
          _removeOverlay();
        }
      });
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _closeTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  bool _hasItems(BuildContext context) => _hasAnyItems();

  void _insertOverlay() {
    if (_overlayEntry != null) return;
    _overlayShiftUp = _computeShiftUp();
    final entry = OverlayEntry(builder: _buildOverlay);
    _overlayEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Computes how far the submenu would extend past the bottom of the screen
  /// and returns the upward shift needed to keep it fully visible. The shift is
  /// clamped so the menu top never goes above the top margin.
  double _computeShiftUp() {
    const margin = 12.0;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return 0;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxMenuHeight = screenHeight - margin * 2;
    final rawHeight =
        _estimatedItemCount() * 52.0 + 12.0;
    final menuHeight = rawHeight > maxMenuHeight ? maxMenuHeight : rawHeight;
    final overflow = top + menuHeight + margin - screenHeight;
    if (overflow <= 0) return 0;
    final maxShift = top - margin;
    if (maxShift <= 0) return 0;
    return overflow > maxShift ? maxShift : overflow;
  }

  // ── Standalone open/close (no host) ──────────────────────────────────────
  void _onStandaloneHoverEnter() {
    _hoverTimer?.cancel();
    _cancelLocalClose();
    if (_localOpen || !_hasItems(context)) return;
    // Short debounce so merely scrubbing across the toolbar does not flicker
    // every submenu open; still feels instant to the user.
    _hoverTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _localOpen) return;
      _openLocal();
    });
  }

  void _openLocal() {
    if (_localOpen || !_hasItems(context)) return;
    setState(() => _localOpen = true);
    _insertOverlay();
  }

  void _scheduleLocalClose() {
    _cancelLocalClose();
    _closeTimer = Timer(const Duration(milliseconds: 150), _closeLocal);
  }

  void _closeLocal() {
    _cancelLocalClose();
    _removeOverlay();
    if (mounted && _localOpen) setState(() => _localOpen = false);
  }

  void _cancelLocalClose() {
    _closeTimer?.cancel();
  }

  // ── Tap / selection ──────────────────────────────────────────────────────
  void _onTap() {
    if (!_hasItems(context)) return;
    if (_hosted) {
      widget.onHoverOpen!(widget.category);
    } else {
      _openLocal();
    }
  }

  void _handleSelect(String value) {
    if (value == '__note') {
      widget.onAddNote?.call();
    } else if (value == '__chat') {
      widget.onAddChat?.call();
    } else if (value == '__terminal') {
      widget.onAddTerminal?.call();
    } else {
      widget.onAddGeneric?.call(value);
    }
    if (_hosted) {
      widget.onScheduleClose!();
    } else {
      _closeLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = _hasItems(context);
    final submenuOpen = _hosted ? widget.isOpen : _localOpen;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          if (_hosted) {
            if (hasItems) widget.onHoverOpen!(widget.category);
          } else {
            _onStandaloneHoverEnter();
          }
        },
        onExit: (_) {
          if (_hosted) {
            widget.onScheduleClose!();
          } else {
            _hoverTimer?.cancel();
            _scheduleLocalClose();
          }
        },
        child: Tooltip(
          // No point showing the hint while its submenu is already open.
          message:
              submenuOpen
                  ? ''
                  : hasItems
                      ? widget.tooltip
                      : '${widget.tooltip} unavailable on this board',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: hasItems ? _onTap : null,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: hasItems ? widget.color : widget.color.withAlpha(80),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Stack(
      children: [
        // Tap-outside dismissal. On touch platforms MouseRegion never fires,
        // so without this barrier a tap-opened submenu would float forever.
        // Translucent so desktop hover events still reach the toolbar
        // buttons underneath (hover-switching between categories).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_hosted) {
                widget.onScheduleClose!();
              } else {
                _closeLocal();
              }
            },
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          offset: Offset(4, -_overlayShiftUp),
          child: MouseRegion(
            onEnter: (_) {
              if (_hosted) {
                widget.onCancelClose!();
              } else {
                _cancelLocalClose();
              }
            },
            onExit: (_) {
              if (_hosted) {
                widget.onScheduleClose!();
              } else {
                _scheduleLocalClose();
              }
            },
            // Light entrance: fade + short slide from the toolbar side so
            // opening and hover-switching between submenus feels smooth
            // instead of popping in.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              builder:
                  (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(-6 * (1 - t), 0),
                      child: child,
                    ),
                  ),
              child: _buildMenu(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenu(BuildContext context) {
    // Cap the menu height to the available screen space and make it scrollable
    // so a long category never gets clipped off-screen on small windows.
    final maxHeight = MediaQuery.sizeOf(context).height - 24;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        width: 264,
        decoration: BoxDecoration(
          color: _menuColor(context),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _itemsFor(context, widget.category),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _itemsFor(
    BuildContext context,
    PanelCatalogCategory category,
  ) {
    Widget? pluginItem(String typeId) {
      if (widget.onAddGeneric == null) return null;
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
      PanelCatalogCategory.basics => <Widget?>[
        if (widget.onAddNote != null && _isPanelTypeAvailable('board.note.markdown'))
          _catalogItem(
            context,
            value: '__note',
            icon: Icons.notes_rounded,
            iconColor: context.appColors.textMuted,
            label: 'Markdown Note',
          ),
        pluginItem('board.sticky'),
        if (widget.onAddGeneric != null && _isPanelTypeAvailable('board.shape'))
          _catalogItem(
            context,
            value: '__shape:frame',
            icon: Icons.interests_outlined,
            iconColor: context.appColors.accentBlue,
            label: 'Shape / Frame',
          ),
      ],
      PanelCatalogCategory.ai => <Widget?>[
        if (widget.onAddChat != null && _isPanelTypeAvailable('board.chat'))
          _catalogItem(
            context,
            value: '__chat',
            icon: Icons.auto_awesome,
            iconColor: context.appColors.statusActive,
            label: 'AI Chat',
          ),
        if (widget.onAddTerminal != null && _isPanelTypeAvailable('board.terminal'))
          _catalogItem(
            context,
            value: '__terminal',
            icon: Icons.terminal,
            iconColor: context.appColors.statusActive,
            label: 'Terminal',
          ),
        pluginItem('board.yolo_assistant'),
      ],
      PanelCatalogCategory.files => <Widget?>[
        pluginItem('board.filetree'),
        pluginItem('board.files'),
        pluginItem('board.file.preview'),
        pluginItem('board.webpage'),
      ],
      PanelCatalogCategory.planning => <Widget?>[
        pluginItem('board.kanban'),
        pluginItem('board.checklist'),
        pluginItem('board.timer'),
        pluginItem('board.calendar'),
        pluginItem('board.table'),
        pluginItem('board.chart'),
      ],
      PanelCatalogCategory.advanced => <Widget?>[
        pluginItem('board.setup_guide'),
        pluginItem('board.code.snippet'),
        pluginItem('board.playlist'),
        pluginItem('board.audio_recorder'),
        pluginItem('board.run_configs'),
        pluginItem('board.widget.custom'),
        pluginItem('board.ui'),
      ],
    };
    return items.whereType<Widget>().toList();
  }

  bool _isPanelTypeAvailable(String typeId) {
    return yoloitdPanelTypeAvailableOn(
      typeId,
      platform: widget.platform,
      remote: isRemoteBoard(widget.board),
    );
  }

  /// Type ids considered by each category, in display order. Used for the
  /// cheap availability probe below — building the full item widget list just
  /// to check `isNotEmpty` showed up as a CPU hotspot on every toolbar
  /// rebuild.
  static const Map<PanelCatalogCategory, List<String>> _categoryTypeIds =
      <PanelCatalogCategory, List<String>>{
        PanelCatalogCategory.basics: <String>[
          'board.note.markdown',
          'board.sticky',
          'board.shape',
        ],
        PanelCatalogCategory.ai: <String>[
          'board.chat',
          'board.terminal',
          'board.yolo_assistant',
        ],
        PanelCatalogCategory.files: <String>[
          'board.filetree',
          'board.files',
          'board.file.preview',
          'board.webpage',
        ],
        PanelCatalogCategory.planning: <String>[
          'board.kanban',
          'board.checklist',
          'board.timer',
          'board.calendar',
          'board.table',
          'board.chart',
        ],
        PanelCatalogCategory.advanced: <String>[
          'board.setup_guide',
          'board.code.snippet',
          'board.playlist',
          'board.audio_recorder',
          'board.run_configs',
          'board.widget.custom',
          'board.ui',
        ],
      };

  static bool _typeOffered(
    PanelCatalogCategory category,
    String typeId,
    bool hasGeneric,
    bool hasNote,
    bool hasChat,
    bool hasTerminal,
  ) {
    switch (category) {
      case PanelCatalogCategory.basics:
        switch (typeId) {
          case 'board.note.markdown':
            return hasNote;
          case 'board.shape':
            return hasGeneric;
          default: // board.sticky — plugin registry entry
            return hasGeneric;
        }
      case PanelCatalogCategory.ai:
        switch (typeId) {
          case 'board.chat':
            return hasChat;
          case 'board.terminal':
            return hasTerminal;
          default: // board.yolo_assistant — plugin registry entry
            return hasGeneric;
        }
      default:
        return hasGeneric;
    }
  }

  /// Fast availability check without constructing any widgets.
  bool _hasAnyItems() {
    final hasGeneric = widget.onAddGeneric != null;
    final hasNote = widget.onAddNote != null;
    final hasChat = widget.onAddChat != null;
    final hasTerminal = widget.onAddTerminal != null;
    for (final typeId in _categoryTypeIds[widget.category]!) {
      if (!_typeOffered(
        widget.category,
        typeId,
        hasGeneric,
        hasNote,
        hasChat,
        hasTerminal,
      )) {
        continue;
      }
      if (_isPanelTypeAvailable(typeId)) return true;
    }
    return false;
  }

  /// Estimated menu item count for the upward-shift computation. Mirrors the
  /// order and conditions of [_itemsFor] without building widgets.
  int _estimatedItemCount() {
    final hasGeneric = widget.onAddGeneric != null;
    final hasNote = widget.onAddNote != null;
    final hasChat = widget.onAddChat != null;
    final hasTerminal = widget.onAddTerminal != null;
    var count = 0;
    for (final typeId in _categoryTypeIds[widget.category]!) {
      if (!_typeOffered(
        widget.category,
        typeId,
        hasGeneric,
        hasNote,
        hasChat,
        hasTerminal,
      )) {
        continue;
      }
      if (_isPanelTypeAvailable(typeId)) count++;
    }
    return count;
  }

  Widget _catalogItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return InkWell(
      onTap: () => _handleSelect(value),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _menuTextColor(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
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
