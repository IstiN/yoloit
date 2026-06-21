import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';
import 'package:yoloit/ui/components/buttons/toolbar_button.dart';
import 'package:yoloit/ui/components/chips/panel_id_chip.dart';
import 'package:yoloit/ui/components/layout/panel_content_toolbar.dart';
import 'package:yoloit/ui/components/layout/showcase_scaffold.dart';
import 'package:yoloit/ui/components/menus/hover_overflow_menu.dart';
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
        PanelContentToolbar(
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
            const HoverOverflowMenu(
              items: [
                HoverOverflowItem(icon: Icons.delete_outline, label: 'Remove col'),
                HoverOverflowItem(icon: Icons.clear_all, label: 'Clear rows'),
                HoverOverflowItem(icon: Icons.file_download, label: 'Export'),
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
                  HeaderIconButton(
                    icon: Icons.drag_indicator,
                    tooltip: 'Drag',
                    onPressed: () {},
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
                  HeaderIconButton(
                    icon: Icons.copy,
                    tooltip: 'Duplicate',
                    onPressed: () {},
                  ),
                  HeaderIconButton(
                    icon: Icons.format_color_fill,
                    tooltip: 'Color',
                    onPressed: () {},
                    swatch: widget.accentColor,
                  ),
                  HoverOverflowMenu(
                    items: [
                      HoverOverflowItem(
                        icon: _locked ? Icons.lock : Icons.lock_open,
                        label: _locked ? 'Unlock' : 'Lock',
                        onTap: () => setState(() => _locked = !_locked),
                      ),
                      HoverOverflowItem(
                        icon: Icons.flip_to_front,
                        label: 'Bring to front',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.flip_to_back,
                        label: 'Send to back',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.open_in_full,
                        label: 'Fullscreen',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.settings,
                        label: 'Settings',
                        onTap: () {},
                      ),
                      HoverOverflowItem(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        onTap: () {},
                      ),
                    ],
                  ),
                  HeaderIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: widget.onClose,
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


