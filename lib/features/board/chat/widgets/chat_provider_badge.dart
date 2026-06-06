import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Small grey provider badge used in model picker lists.
Widget buildProviderBadge(BuildContext context, String providerName) {
  final colors = context.appColors;
  final label = switch (providerName.toLowerCase()) {
    'openrouter' => 'OR',
    'opencode' => 'OC',
    'siliconflow' => 'SF',
    'anthropic' => 'ANT',
    'openai' => 'OAI',
    'google' => 'GGL',
    'mistral' => 'MST',
    'groq' => 'GRQ',
    _ =>
      providerName.length > 6
          ? providerName.substring(0, 2).toUpperCase()
          : providerName,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      color: colors.accentGreen.withAlpha(20),
      border: Border.all(
        color: colors.accentGreen.withAlpha(51),
        width: 0.5,
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w600,
        color: colors.textMuted,
        letterSpacing: 0.3,
      ),
    ),
  );
}
