import 'package:flutter/material.dart';

/// Dynamic colour palette embedded in [ThemeData.extensions].
///
/// Because this is an [InheritedWidget]-backed extension, any widget that
/// calls [Theme.of(context)] — including widgets created with `const` — will
/// automatically rebuild when the theme changes. This is the correct Flutter
/// pattern for dynamic colours.
///
/// Usage:
/// ```dart
/// final colors = context.appColors;
/// Text('hello', style: TextStyle(color: colors.primary));
/// ```
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  const AppColorScheme({
    // ── Accent ──────────────────────────────────────────
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryGlow,
    // ── Backgrounds ──────────────────────────────────────
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHighlight,
    required this.border,
    required this.divider,
    required this.terminalBackground,
    // ── Semantic accent slots ─────────────────────────────
    required this.sidebar,
    required this.sidebarGlow,
    required this.terminalPrompt,
    required this.tabBorder,
    required this.tabActiveBg,
    required this.tabInactiveBg,
  });

  // ── Accent ──────────────────────────────────────────────────────────────────
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color primaryGlow;

  // ── Backgrounds ──────────────────────────────────────────────────────────────
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHighlight;
  final Color border;
  final Color divider;
  final Color terminalBackground;

  // ── Semantic accent slots ─────────────────────────────────────────────────────
  final Color sidebar;
  final Color sidebarGlow;
  final Color terminalPrompt;
  final Color tabBorder;
  final Color tabActiveBg;
  final Color tabInactiveBg;

  // ── Shortcut ──────────────────────────────────────────────────────────────────
  static AppColorScheme of(BuildContext context) =>
      Theme.of(context).extension<AppColorScheme>()!;

  // ── Factory helpers ──────────────────────────────────────────────────────────

  /// Derives a full scheme from an accent [color] and optional [bg] tint seed.
  factory AppColorScheme.fromAccent(
    Color accent, {
    Color? bgSeed,
    Brightness brightness = Brightness.dark,
  }) {
    if (brightness == Brightness.light) {
      return AppColorScheme._lightFromAccent(accent);
    }
    final bg = bgSeed ?? const Color(0xFF090918);
    final sur = _mixBg(bg, accent, 0.04);
    final surEl = _mixBg(bg, accent, 0.08);
    final surHi = _mixBg(bg, accent, 0.12);
    final bor = _mixBg(bg, accent, 0.18);
    final div = _mixBg(bg, accent, 0.14);
    final termBg = Color.lerp(bg, Colors.black, 0.35)!;
    return AppColorScheme(
      primary: accent,
      primaryLight: Color.lerp(accent, Colors.white, 0.35)!,
      primaryDark: Color.lerp(accent, Colors.black, 0.35)!,
      primaryGlow: accent.withAlpha(51),
      background: bg,
      surface: sur,
      surfaceElevated: surEl,
      surfaceHighlight: surHi,
      border: bor,
      divider: div,
      terminalBackground: termBg,
      sidebar: accent,
      sidebarGlow: accent.withAlpha(30),
      terminalPrompt: accent,
      tabBorder: accent,
      tabActiveBg: _mixBg(bg, accent, 0.15),
      tabInactiveBg: _mixBg(bg, accent, 0.06),
    );
  }

  factory AppColorScheme._lightFromAccent(Color accent) {
    const bg = Color(0xFFF5F7FB);
    final sur = Color.lerp(const Color(0xFFEEF2F8), accent, 0.03)!;
    final surEl = Color.lerp(const Color(0xFFE8EEF7), accent, 0.05)!;
    final surHi = Color.lerp(const Color(0xFFE1E9F4), accent, 0.08)!;
    final bor = Color.lerp(const Color(0xFFC9D2DF), accent, 0.10)!;
    final div = Color.lerp(const Color(0xFFD8DFEA), accent, 0.06)!;
    final termBg = Color.lerp(bg, const Color(0xFFEFF3F9), 0.6)!;
    final accentDark = Color.lerp(accent, Colors.black, 0.20)!;
    return AppColorScheme(
      primary: accentDark,
      primaryLight: Color.lerp(accent, Colors.white, 0.40)!,
      primaryDark: Color.lerp(accent, Colors.black, 0.35)!,
      primaryGlow: accent.withAlpha(30),
      background: bg,
      surface: sur,
      surfaceElevated: surEl,
      surfaceHighlight: surHi,
      border: bor,
      divider: div,
      terminalBackground: termBg,
      sidebar: accentDark,
      sidebarGlow: accent.withAlpha(20),
      terminalPrompt: accentDark,
      tabBorder: accentDark,
      tabActiveBg: Color.lerp(bg, accent, 0.12)!,
      tabInactiveBg: Color.lerp(bg, accent, 0.04)!,
    );
  }

  static Color _mixBg(Color bg, Color accent, double t) =>
      Color.lerp(bg, accent, t)!;

  // ── ThemeExtension boilerplate ────────────────────────────────────────────────

  @override
  AppColorScheme copyWith({
    Color? primary,
    Color? primaryLight,
    Color? primaryDark,
    Color? primaryGlow,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHighlight,
    Color? border,
    Color? divider,
    Color? terminalBackground,
    Color? sidebar,
    Color? sidebarGlow,
    Color? terminalPrompt,
    Color? tabBorder,
    Color? tabActiveBg,
    Color? tabInactiveBg,
  }) {
    return AppColorScheme(
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryGlow: primaryGlow ?? this.primaryGlow,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighlight: surfaceHighlight ?? this.surfaceHighlight,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      terminalBackground: terminalBackground ?? this.terminalBackground,
      sidebar: sidebar ?? this.sidebar,
      sidebarGlow: sidebarGlow ?? this.sidebarGlow,
      terminalPrompt: terminalPrompt ?? this.terminalPrompt,
      tabBorder: tabBorder ?? this.tabBorder,
      tabActiveBg: tabActiveBg ?? this.tabActiveBg,
      tabInactiveBg: tabInactiveBg ?? this.tabInactiveBg,
    );
  }

  @override
  AppColorScheme lerp(AppColorScheme? other, double t) {
    if (other == null) return this;
    return AppColorScheme(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryGlow: Color.lerp(primaryGlow, other.primaryGlow, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceHighlight: Color.lerp(surfaceHighlight, other.surfaceHighlight, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      terminalBackground: Color.lerp(terminalBackground, other.terminalBackground, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarGlow: Color.lerp(sidebarGlow, other.sidebarGlow, t)!,
      terminalPrompt: Color.lerp(terminalPrompt, other.terminalPrompt, t)!,
      tabBorder: Color.lerp(tabBorder, other.tabBorder, t)!,
      tabActiveBg: Color.lerp(tabActiveBg, other.tabActiveBg, t)!,
      tabInactiveBg: Color.lerp(tabInactiveBg, other.tabInactiveBg, t)!,
    );
  }
}

/// Convenience extension: `context.appColors.primary`.
extension AppColorSchemeX on BuildContext {
  AppColorScheme get appColors => AppColorScheme.of(this);
}
