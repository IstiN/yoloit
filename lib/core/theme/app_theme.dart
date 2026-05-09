import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData buildTheme(
    Color accentColor, {
    Color? bgSeed,
    Brightness brightness = Brightness.dark,
  }) {
    final scheme = AppColorScheme.fromAccent(
      accentColor,
      bgSeed: bgSeed,
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;
    final textPrimary =
        isLight ? const Color(0xFF1A1A2E) : AppColors.textPrimary;
    final textSecondary =
        isLight ? const Color(0xFF64748B) : AppColors.textSecondary;
    final textMuted = isLight ? const Color(0xFF94A3B8) : AppColors.textMuted;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: scheme.background,
      colorScheme:
          isLight
              ? ColorScheme.light(
                primary: scheme.primary,
                secondary: scheme.primary,
                surface: scheme.surface,
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: textPrimary,
                outline: scheme.border,
              )
              : ColorScheme.dark(
                primary: accentColor,
                secondary: accentColor,
                surface: scheme.surface,
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: AppColors.textPrimary,
                outline: scheme.border,
              ),
      splashColor: scheme.primary.withAlpha(30),
      highlightColor: scheme.primary.withAlpha(20),
      fontFamily: 'SF Pro Display',
      extensions: [scheme],
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        titleMedium: TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: TextStyle(
          color: textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.divider,
        thickness: 1,
        space: 0,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(scheme.border),
        thickness: WidgetStateProperty.all(4),
      ),
    );
  }
}

enum AppThemePreset {
  neonPurple('Neon Purple', AppColors.presetNeonPurple, Color(0xFF090918)),
  cyberGreen('Cyber Green', AppColors.presetCyberGreen, Color(0xFF07100A)),
  deepBlue('Deep Blue', AppColors.presetDeepBlue, Color(0xFF07090F)),
  solarOrange('Solar Orange', AppColors.presetSolarOrange, Color(0xFF100A07)),
  crimsonRed('Crimson Red', AppColors.presetCrimsonRed, Color(0xFF100707));

  const AppThemePreset(this.label, this.color, this.bgSeed);
  final String label;
  final Color color;
  final Color bgSeed;

  ThemeData get theme => themeForBrightness(Brightness.dark);

  ThemeData themeForBrightness(Brightness brightness) =>
      AppTheme.buildTheme(color, bgSeed: bgSeed, brightness: brightness);
}

