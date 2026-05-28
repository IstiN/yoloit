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
    return buildThemeFromScheme(scheme, brightness: brightness);
  }

  /// Builds a [ThemeData] from a fully-specified [AppColorScheme].
  /// Used by both preset themes and custom JSON themes.
  static ThemeData buildThemeFromScheme(
    AppColorScheme scheme, {
    Brightness brightness = Brightness.dark,
  }) {
    final isLight = brightness == Brightness.light;
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
                onSurface: scheme.textPrimary,
                outline: scheme.border,
              )
              : ColorScheme.dark(
                primary: scheme.primary,
                secondary: scheme.primary,
                surface: scheme.surface,
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: scheme.textPrimary,
                outline: scheme.border,
              ),
      splashColor: scheme.primary.withAlpha(30),
      highlightColor: scheme.primary.withAlpha(20),
      fontFamily: 'SF Pro Display',
      extensions: [scheme],
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: scheme.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: scheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: scheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        titleMedium: TextStyle(
          color: scheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: scheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: scheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: scheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: TextStyle(
          color: scheme.textMuted,
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.textSecondary,
        ),
      ),
    );
  }
}

enum AppThemePreset {
  neonPurple('Neon Purple', AppColors.presetNeonPurple, Color(0xFF090918)),
  cyberGreen('Cyber Green', AppColors.presetCyberGreen, Color(0xFF07100A)),
  deepBlue('Deep Blue', AppColors.presetDeepBlue, Color(0xFF07090F)),
  solarOrange('Solar Orange', AppColors.presetSolarOrange, Color(0xFF100A07)),
  crimsonRed('Crimson Red', AppColors.presetCrimsonRed, Color(0xFF100707)),
  islandsDark(
    'Islands Dark',
    Color(0xFF548AF7),
    Color(0xFF191A1C),
    defaultBrightness: Brightness.dark,
  ),
  islandsLight(
    'Islands Light',
    Color(0xFF0033B3),
    Color(0xFFF5F7FB),
    defaultBrightness: Brightness.light,
  );

  const AppThemePreset(
    this.label,
    this.color,
    this.bgSeed, {
    this.defaultBrightness,
  });
  final String label;
  final Color color;
  final Color bgSeed;

  /// If set, this preset uses a fixed brightness instead of following the
  /// global toggle. Presets like "Islands Light" are inherently light.
  final Brightness? defaultBrightness;

  ThemeData get theme => themeForBrightness(defaultBrightness ?? Brightness.dark);

  ThemeData themeForBrightness(Brightness brightness) =>
      AppTheme.buildTheme(
        color,
        bgSeed: bgSeed,
        brightness: defaultBrightness ?? brightness,
      );
}

