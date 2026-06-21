import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
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
            _ToolbarAction(
              icon: Icons.add,
              label: 'Row',
              onTap: () {},
            ),
            _ToolbarAction(
              icon: Icons.remove,
              label: 'Row',
              onTap: () {},
            ),
            _ToolbarAction(
              icon: Icons.view_column,
              label: 'Col',
              onTap: () {},
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
            _PanelIdChip(id: 'sales-data', onEdit: () {}, onCopy: () {}),
            _PanelIdChip(id: 'panel-abc123', onEdit: () {}, onCopy: () {}),
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
  bool _hovered = false;

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
            MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Container(
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
                      visible: true,
                    ),
                    _HeaderIconButton(
                      icon: _locked ? Icons.lock : Icons.lock_open,
                      tooltip: _locked ? 'Unlock' : 'Lock',
                      onPressed: () => setState(() => _locked = !_locked),
                      colors: colors,
                      active: _locked,
                      visible: true,
                    ),
                    _HeaderIconButton(
                      icon: Icons.format_color_fill,
                      tooltip: 'Color',
                      onPressed: () {},
                      colors: colors,
                      swatch: widget.accentColor,
                      visible: true,
                    ),
                    _HoverOverflowMenu(
                      visible: _hovered || _locked,
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
                      visible: true,
                    ),
                  ],
                ),
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
    this.visible = false,
    this.active = false,
    this.swatch,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final AppColorScheme colors;
  final bool visible;
  final bool active;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
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
    this.visible = true,
    required this.items,
  });

  final bool visible;
  final List<_OverflowItem> items;

  @override
  State<_HoverOverflowMenu> createState() => _HoverOverflowMenuState();
}

class _HoverOverflowMenuState extends State<_HoverOverflowMenu> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (!widget.visible) return const SizedBox.shrink();
    return MouseRegion(
      onEnter: (_) => setState(() => _open = true),
      onExit: (_) => setState(() => _open = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _open ? null : 28,
        height: 28,
        decoration: BoxDecoration(
          color: _open ? colors.surfaceElevated : null,
          borderRadius: BorderRadius.circular(6),
          border: _open ? Border.all(color: colors.border) : null,
        ),
        child: _open
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in widget.items)
                    _HeaderIconButton(
                      icon: item.icon,
                      tooltip: item.label,
                      onPressed: item.onTap ?? () {},
                      colors: colors,
                      visible: true,
                    ),
                ],
              )
            : const Center(
                child: Icon(Icons.more_vert, size: 16),
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

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: colors.textSecondary),
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: colors.textSecondary),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _PanelIdChip extends StatelessWidget {
  const _PanelIdChip({
    required this.id,
    required this.onEdit,
    required this.onCopy,
  });

  final String id;
  final VoidCallback onEdit;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: 'Table ID: $id\nTap to copy, ✎ to edit',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: onCopy,
            icon: Icon(Icons.fingerprint, size: 12, color: colors.textMuted),
            label: Text(
              id.length > 14 ? '${id.substring(0, 14)}...' : id,
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.edit, size: 12, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
