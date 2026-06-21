import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/buttons/toolbar_button.dart';
import 'package:yoloit/ui/components/chips/panel_id_chip.dart';
import 'package:yoloit/ui/components/layout/showcase_scaffold.dart';
import 'package:yoloit/ui/components/typography/section_title.dart';

/// Debug UI prototype for the redesigned panel chrome.
///
/// Goal: unify the floating toolbar and the panel header into a single,
/// always-visible header. Primary actions are shown inline; secondary actions
/// appear in a hover-reveal overflow menu.
class PanelChromePrototype extends StatelessWidget {
  const PanelChromePrototype({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ShowcaseScaffold(
      children: [
        const SectionTitle('Selected panel — full chrome'),
        const SizedBox(height: 8),
        _MockPanel(
          title: 'Table',
          icon: Icons.table_chart_outlined,
          accentColor: colors.accentGreen,
          isSelected: true,
          onClose: () {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('Unselected panel — chrome dimmed'),
        const SizedBox(height: 8),
        _MockPanel(
          title: 'Chart',
          icon: Icons.bar_chart,
          accentColor: colors.accentBlue,
          isSelected: false,
          onClose: () {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('Locked panel'),
        const SizedBox(height: 8),
        _MockPanel(
          title: 'Board notes',
          icon: Icons.note_outlined,
          accentColor: colors.accentOrange,
          isSelected: true,
          initialLocked: true,
          onClose: () {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('Content toolbar — primary + hover overflow'),
        const SizedBox(height: 8),
        _ContentToolbar(
          children: [
            ToolbarButton(
              icon: Icons.add,
              label: 'Row',
              onPressed: () {},
            ),
            ToolbarButton(
              icon: Icons.remove,
              label: 'Row',
              onPressed: () {},
            ),
            ToolbarButton(
              icon: Icons.view_column,
              label: 'Col',
              onPressed: () {},
            ),
            const _HoverOverflowMenu(
              items: [
                _OverflowItem(icon: Icons.delete_outline, label: 'Remove col'),
                _OverflowItem(icon: Icons.clear_all, label: 'Clear rows'),
                _OverflowItem(icon: Icons.file_download, label: 'Export'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('Panel ID chip — editable / copyable'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PanelIdChip(id: 'sales-data', onEdit: () {}, onCopy: () {}),
            PanelIdChip(id: 'panel-abc123', onEdit: () {}, onCopy: () {}),
          ],
        ),
      ],
    );
  }
}

class _MockPanel extends StatefulWidget {
  const _MockPanel({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onClose,
    this.initialLocked = false,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onClose;
  final bool initialLocked;

  @override
  State<_MockPanel> createState() => _MockPanelState();
}

class _MockPanelState extends State<_MockPanel> {
  late bool _locked;

  @override
  void initState() {
    super.initState();
    _locked = widget.initialLocked;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isSelected ? colors.primary : colors.border,
        ),
        boxShadow: widget.isSelected
            ? [
                BoxShadow(
                  color: colors.textMuted.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? colors.surfaceElevated
                    : colors.surface,
                border: Border(
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                children: [
                    _HeaderIconButton(
                      icon: Icons.drag_indicator,
                      tooltip: 'Drag',
                      onPressed: () {},
                      colors: colors,
                    ),
                    const SizedBox(width: 8),
                    Icon(widget.icon, size: 16, color: widget.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _HeaderIconButton(
                      icon: Icons.copy,
                      tooltip: 'Duplicate',
                      onPressed: () {},
                      colors: colors,
                    ),
                    _HeaderIconButton(
                      icon: _locked ? Icons.lock : Icons.lock_open,
                      tooltip: _locked ? 'Unlock' : 'Lock',
                      onPressed: () => setState(() => _locked = !_locked),
                      colors: colors,
                      active: _locked,
                      
                    ),
                    _HeaderIconButton(
                      icon: Icons.format_color_fill,
                      tooltip: 'Color',
                      onPressed: () {},
                      colors: colors,
                      swatch: widget.accentColor,
                      
                    ),
                    _HoverOverflowMenu(
                      items: [
                        _OverflowItem(
                          icon: Icons.content_copy,
                          label: 'Duplicate',
                          onTap: () {},
                        ),
                        _OverflowItem(
                          icon: Icons.flip_to_front,
                          label: 'Bring to front',
                          onTap: () {},
                        ),
                        _OverflowItem(
                          icon: Icons.flip_to_back,
                          label: 'Send to back',
                          onTap: () {},
                        ),
                        _OverflowItem(
                          icon: Icons.open_in_full,
                          label: 'Fullscreen',
                          onTap: () {},
                        ),
                        _OverflowItem(
                          icon: Icons.settings,
                          label: 'Settings',
                          onTap: () {},
                        ),
                        _OverflowItem(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          onTap: () {},
                        ),
                      ],
                    ),
                    _HeaderIconButton(
                      icon: Icons.close,
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                      colors: colors,
                    ),
                  ],
                ),
              ),
            Container(
              height: 120,
              color: colors.surface,
              child: Center(
                child: Text(
                  'Panel body placeholder',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.colors,
    this.active = false,
    this.swatch,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final AppColorScheme colors;
  final bool active;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
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
              color: swatch ??
                  (active ? colors.primary : colors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverOverflowMenu extends StatefulWidget {
  const _HoverOverflowMenu({
    required this.items,
  });

  final List<_OverflowItem> items;

  @override
  State<_HoverOverflowMenu> createState() => _HoverOverflowMenuState();
}

class _HoverOverflowMenuState extends State<_HoverOverflowMenu> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hideTimer;

  void _show() {
    _hideTimer?.cancel();
    if (!_controller.isShowing) {
      setState(() => _controller.show());
    }
  }

  void _delayedHide() {
    _hideTimer = Timer(const Duration(milliseconds: 80), () {
      if (_controller.isShowing) {
        setState(() => _controller.hide());
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
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) {
          return CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.centerLeft,
            followerAnchor: Alignment.centerRight,
            showWhenUnlinked: false,
            child: MouseRegion(
              onEnter: (_) => _show(),
              onExit: (_) => _delayedHide(),
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in widget.items)
                      _HeaderIconButton(
                        icon: item.icon,
                        tooltip: item.label,
                        onPressed: item.onTap ?? () {},
                        colors: colors,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _delayedHide(),
          child: _HeaderIconButton(
            icon: Icons.more_vert,
            tooltip: 'More',
            onPressed: () {},
            colors: colors,
          ),
        ),
      ),
    );
  }
}

class _OverflowItem {
  const _OverflowItem({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

class _ContentToolbar extends StatelessWidget {
  const _ContentToolbar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
