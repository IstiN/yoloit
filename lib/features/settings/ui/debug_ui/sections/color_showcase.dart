import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/typography/caption.dart';
import 'package:yoloit/ui/components/typography/section_title.dart';

class ColorShowcase extends StatelessWidget {
  const ColorShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Accent'),
          const SizedBox(height: 8),
          _colorGrid([
            ('primary', colors.primary),
            ('primaryLight', colors.primaryLight),
            ('primaryDark', colors.primaryDark),
            ('primaryGlow', colors.primaryGlow),
          ]),
          const SizedBox(height: 24),
          const SectionTitle('Backgrounds'),
          const SizedBox(height: 8),
          _colorGrid([
            ('background', colors.background),
            ('surface', colors.surface),
            ('surfaceElevated', colors.surfaceElevated),
            ('surfaceHighlight', colors.surfaceHighlight),
            ('border', colors.border),
            ('divider', colors.divider),
            ('terminalBackground', colors.terminalBackground),
          ]),
          const SizedBox(height: 24),
          const SectionTitle('Semantic Accents'),
          const SizedBox(height: 8),
          _colorGrid([
            ('sidebar', colors.sidebar),
            ('sidebarGlow', colors.sidebarGlow),
            ('terminalPrompt', colors.terminalPrompt),
            ('tabBorder', colors.tabBorder),
            ('tabActiveBg', colors.tabActiveBg),
            ('tabInactiveBg', colors.tabInactiveBg),
          ]),
          const SizedBox(height: 24),
          const SectionTitle('Text'),
          const SizedBox(height: 8),
          _colorGrid([
            ('textPrimary', colors.textPrimary),
            ('textSecondary', colors.textSecondary),
            ('textMuted', colors.textMuted),
            ('textHighlight', colors.textHighlight),
            ('terminalText', colors.terminalText),
          ]),
          const SizedBox(height: 24),
          const SectionTitle('Status'),
          const SizedBox(height: 8),
          _colorGrid([
            ('statusActive', colors.statusActive),
            ('statusIdle', colors.statusIdle),
            ('statusError', colors.statusError),
            ('statusWarning', colors.statusWarning),
          ]),
          const SizedBox(height: 24),
          const SectionTitle('YoLo Orb'),
          const SizedBox(height: 8),
          _colorGrid([
            ('orbCyan', colors.orbCyan),
            ('orbPurple', colors.orbPurple),
            ('orbPink', colors.orbPink),
          ]),
        ],
      ),
    );
  }

  Widget _colorGrid(List<(String, Color)> items) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (name, color) in items)
          Container(
            width: 120,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(color.alpha < 255 ? 255 : 20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Caption(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
      ],
    );
  }
}
