import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/typography/caption.dart';
import 'package:yoloit/ui/components/typography/label.dart';
import 'package:yoloit/ui/components/typography/section_title.dart';

class TypographyShowcase extends StatelessWidget {
  const TypographyShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Typography Components'),
          const SizedBox(height: 24),
          _showcaseRow('SectionTitle', const SectionTitle('Section Title Example')),
          _showcaseRow('Label (default)', const Label('Label default')),
          _showcaseRow('Label (fontSize 12)', const Label('Label small', fontSize: 12)),
          _showcaseRow('Caption (default)', const Caption('Caption default')),
          _showcaseRow('Caption (fontSize 12)', const Caption('Caption larger', fontSize: 12)),
          const Divider(height: 32),
          const SectionTitle('Raw Theme TextStyles'),
          const SizedBox(height: 12),
          Text('headlineLarge', style: Theme.of(context).textTheme.headlineLarge),
          Text('headlineMedium', style: Theme.of(context).textTheme.headlineMedium),
          Text('titleLarge', style: Theme.of(context).textTheme.titleLarge),
          Text('titleMedium', style: Theme.of(context).textTheme.titleMedium),
          Text('bodyLarge', style: Theme.of(context).textTheme.bodyLarge),
          Text('bodyMedium', style: Theme.of(context).textTheme.bodyMedium),
          Text('bodySmall', style: Theme.of(context).textTheme.bodySmall),
          Text('labelSmall', style: Theme.of(context).textTheme.labelSmall),
          const Divider(height: 32),
          const SectionTitle('AppColorScheme Text Colors'),
          const SizedBox(height: 12),
          _colorRow('textPrimary', colors.textPrimary),
          _colorRow('textSecondary', colors.textSecondary),
          _colorRow('textMuted', colors.textMuted),
          _colorRow('textHighlight', colors.textHighlight),
        ],
      ),
    );
  }

  Widget _showcaseRow(String name, Widget widget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Caption(name, fontWeight: FontWeight.w600),
          ),
          Expanded(child: widget),
        ],
      ),
    );
  }

  Widget _colorRow(String name, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(width: 12),
          Caption(name),
        ],
      ),
    );
  }
}
