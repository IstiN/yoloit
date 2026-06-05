import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/ui/components/buttons/icon_text_button.dart';
import 'package:yoloit/ui/components/feedback/neon_badge.dart';
import 'package:yoloit/ui/components/layout/panel_header.dart';
import 'package:yoloit/ui/components/layout/showcase_scaffold.dart';
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
          const SectionTitle('Typography'),
          const SizedBox(height: 8),
          const Caption('Caption — small muted text'),
          const Label('Label — emphasised text'),
          const SectionTitle('SectionTitle — bold header'),
      ],
    );
  }
}
