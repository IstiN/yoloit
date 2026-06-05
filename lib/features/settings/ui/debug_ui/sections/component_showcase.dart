import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/ui/components/buttons/icon_text_button.dart';
import 'package:yoloit/ui/components/buttons/markdown_tool_button.dart';
import 'package:yoloit/ui/components/buttons/overlay_icon_button.dart';
import 'package:yoloit/ui/components/buttons/panel_header_icon_button.dart';
import 'package:yoloit/ui/components/chip/toolbar_chip.dart';
import 'package:yoloit/ui/components/feedback/neon_badge.dart';
import 'package:yoloit/ui/components/layout/panel_header.dart';
import 'package:yoloit/ui/components/layout/showcase_scaffold.dart';
import 'package:yoloit/ui/components/menus/miro_toolbar_primitives.dart';
import 'package:yoloit/ui/components/typography/caption.dart';
import 'package:yoloit/ui/components/typography/label.dart';
import 'package:yoloit/ui/components/typography/section_title.dart';

class ComponentShowcase extends StatelessWidget {
  const ComponentShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ShowcaseScaffold(
      children: [
        const SectionTitle('NeonBadge'),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NeonBadge(label: 'Live', color: AppColors.neonGreen, showPulse: true),
            NeonBadge(label: 'Idle', color: AppColors.textSecondary),
            NeonBadge(label: 'Error', color: AppColors.neonRed),
            NeonBadge(label: 'Beta', color: AppColors.neonBlue),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('PanelHeader'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const PanelHeader(
            title: 'Panel Title',
            subtitle: 'subtitle',
            trailing: Icon(Icons.more_vert, size: 16, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 24),
        const SectionTitle('IconTextButton'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IconTextButton(
              label: 'Normal',
              icon: Icons.play_arrow,
              onTap: () {},
            ),
            IconTextButton(
              label: 'Active',
              icon: Icons.check,
              isActive: true,
              onTap: () {},
            ),
            IconTextButton(
              label: 'Dense',
              icon: Icons.settings,
              dense: true,
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('ToolbarChip'),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ToolbarChip(icon: Icons.brush, label: 'Brush'),
            ToolbarChip(icon: Icons.auto_fix_high, label: 'Auto'),
            ToolbarChip(icon: Icons.format_paint, label: 'Paint'),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('OverlayIconButton'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OverlayIconButton(
              icon: Icons.edit,
              tooltip: 'Edit',
              onTap: () {},
            ),
            OverlayIconButton(
              icon: Icons.check,
              tooltip: 'Active',
              onTap: () {},
              active: true,
            ),
            OverlayIconButton(
              icon: Icons.delete,
              tooltip: 'Delete',
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('PanelHeaderIconButton'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PanelHeaderIconButton(
              tooltip: 'Settings',
              icon: Icons.settings,
              onPressed: () {},
            ),
            PanelHeaderIconButton(
              tooltip: 'Close',
              icon: Icons.close,
              onPressed: () {},
            ),
            PanelHeaderIconButton(
              tooltip: 'More',
              icon: Icons.more_vert,
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('MarkdownToolButton'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            MarkdownToolButton(
              icon: Icons.format_bold,
              tooltip: 'Bold',
              onTap: () {},
            ),
            MarkdownToolButton(
              icon: Icons.format_italic,
              tooltip: 'Italic',
              onTap: () {},
            ),
            MarkdownToolButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'List',
              onTap: () {},
            ),
            MarkdownToolButton(
              icon: Icons.link,
              tooltip: 'Link',
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('MiroToolbarIcon'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MiroToolbarIcon(
              tooltip: 'Undo',
              icon: Icons.undo,
              onTap: () {},
              color: colors.textPrimary,
            ),
            MiroToolbarIcon(
              tooltip: 'Redo',
              icon: Icons.redo,
              onTap: () {},
              color: colors.textPrimary,
            ),
            MiroToolbarIcon(
              tooltip: 'Color',
              icon: Icons.format_color_fill,
              onTap: () {},
              color: colors.textPrimary,
              swatch: Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('MiroToolbarColorMenu'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MiroToolbarColorMenu(
              tooltip: 'Fill color',
              icon: Icons.format_color_fill,
              selected: Colors.red,
              colors: const [Colors.red, Colors.green, Colors.blue, Colors.transparent],
              onSelected: (_) {},
              onCustomSelected: (_) async => null,
            ),
            MiroToolbarColorMenu(
              tooltip: 'Stroke color',
              icon: Icons.border_color,
              selected: Colors.blue,
              colors: const [Colors.black, Colors.grey, Colors.blue],
              onSelected: (_) {},
              onCustomSelected: (_) async => null,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('MiroToolbarValueMenu'),
        const SizedBox(height: 8),
        MiroToolbarValueMenu<int>(
          tooltip: 'Font size',
          valueLabel: '14',
          values: const [10, 12, 14, 16, 18, 20],
          itemLabel: (v) => '$v px',
          onSelected: (_) {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('MiroToolbarShapeMenu'),
        const SizedBox(height: 8),
        MiroToolbarShapeMenu(
          selectedShape: 'rectangle',
          onSelected: (_) {},
        ),
        const SizedBox(height: 24),
        const SectionTitle('MiroToolbarColorDot'),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MiroToolbarColorDot(color: Colors.red),
            MiroToolbarColorDot(color: Colors.green, selected: true),
            MiroToolbarColorDot(color: Colors.blue),
            MiroToolbarColorDot(color: Colors.transparent),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle('MiroToolbarDivider'),
        const SizedBox(height: 8),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8),
              Icon(Icons.edit, size: 20, color: colors.textMuted),
              MiroToolbarDivider(colors: colors),
              Icon(Icons.delete, size: 20, color: colors.textMuted),
              MiroToolbarDivider(colors: colors),
              Icon(Icons.copy, size: 20, color: colors.textMuted),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Typography'),
        const SizedBox(height: 8),
        const Caption('Caption — small muted text'),
        const Label('Label — emphasised text'),
        const SectionTitle('SectionTitle — bold header'),
      ],
    );
  }
}
