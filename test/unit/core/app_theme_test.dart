import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('buildTheme returns dark brightness', () {
      final theme = AppTheme.buildTheme(AppColors.primary);
      expect(theme.brightness, Brightness.dark);
    });

    test('each preset creates a valid theme', () {
      for (final preset in AppThemePreset.values) {
        final theme = preset.theme;
        expect(theme, isNotNull);
        expect(
          theme.brightness,
          preset.defaultBrightness ?? Brightness.dark,
        );
      }
    });

    test('preset color is set as primary in scheme', () {
      final theme = AppTheme.buildTheme(AppColors.presetCyberGreen);
      expect(theme.colorScheme.primary, AppColors.presetCyberGreen);
    });

    test('scaffold background is app background color', () {
      final theme = AppTheme.buildTheme(AppColors.primary);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
    });
  });

  group('AppThemePreset', () {
    test('has 7 presets', () {
      expect(AppThemePreset.values, hasLength(7));
    });

    test('all presets have non-empty labels', () {
      for (final preset in AppThemePreset.values) {
        expect(preset.label, isNotEmpty);
      }
    });

    test('neonPurple preset name matches enum', () {
      expect(AppThemePreset.neonPurple.name, 'neonPurple');
      expect(AppThemePreset.cyberGreen.name, 'cyberGreen');
    });
  });
}
