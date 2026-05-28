import 'dart:convert';

import 'package:flutter/material.dart';

/// Dynamic colour palette embedded in [ThemeData.extensions].
///
/// Every colour used by the app lives here — no hardcoded [AppColors] references
/// should exist in feature code.  When the user switches themes, every widget
/// that reads [context.appColors] rebuilds automatically.
///
/// Themes can be loaded from JSON or derived from a single accent colour via
/// [AppColorScheme.fromAccent].
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
    // ── Text ─────────────────────────────────────────────
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textHighlight,
    required this.terminalText,
    // ── Semantic accents ─────────────────────────────────
    required this.accentGreen,
    required this.accentGreenDim,
    required this.accentGreenGlow,
    required this.accentRed,
    required this.accentRedDim,
    required this.accentBlue,
    required this.accentOrange,
    // ── Diff ──────────────────────────────────────────────
    required this.diffAddBg,
    required this.diffAddText,
    required this.diffRemoveBg,
    required this.diffRemoveText,
    required this.diffContextBg,
    // ── Status ────────────────────────────────────────────
    required this.statusActive,
    required this.statusIdle,
    required this.statusError,
    required this.statusWarning,
    // ── YoLo orb visual identity ──────────────────────────
    required this.orbCyan,
    required this.orbPurple,
    required this.orbPink,
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

  // ── Text ──────────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textHighlight;
  final Color terminalText;

  // ── Semantic accents ──────────────────────────────────────────────────────────
  final Color accentGreen;
  final Color accentGreenDim;
  final Color accentGreenGlow;
  final Color accentRed;
  final Color accentRedDim;
  final Color accentBlue;
  final Color accentOrange;

  // ── Diff ──────────────────────────────────────────────────────────────────────
  final Color diffAddBg;
  final Color diffAddText;
  final Color diffRemoveBg;
  final Color diffRemoveText;
  final Color diffContextBg;

  // ── Status ────────────────────────────────────────────────────────────────────
  final Color statusActive;
  final Color statusIdle;
  final Color statusError;
  final Color statusWarning;

  // ── YoLo orb visual identity ──────────────────────────────────────────────────
  /// Primary cyan used across all orb modes.  Users can override this to shift
  /// the orb's "cool" pole colour.
  final Color orbCyan;

  /// Primary purple used in recording / thinking modes.  Overriding this
  /// shifts the orb's "warm" pole colour.
  final Color orbPurple;

  /// Hot-pink accent used in active modes.  Overriding this changes the
  /// energetic highlight colour across all orb states.
  final Color orbPink;

  // ── Shortcut ──────────────────────────────────────────────────────────────────
  static AppColorScheme of(BuildContext context) =>
      Theme.of(context).extension<AppColorScheme>() ??
      AppColorScheme.fromAccent(const Color(0xFF7C3AED));

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
      textPrimary: const Color(0xFFE8E8FF),
      textSecondary: const Color(0xFF8888BB),
      textMuted: const Color(0xFF44446A),
      textHighlight: const Color(0xFFFFFFFF),
      terminalText: const Color(0xFFCECEEE),
      accentGreen: const Color(0xFF00FF9F),
      accentGreenDim: const Color(0xFF00CC7A),
      accentGreenGlow: const Color(0x2200FF9F),
      accentRed: const Color(0xFFFF4F6A),
      accentRedDim: const Color(0xFFCC3D54),
      accentBlue: const Color(0xFF00B4FF),
      accentOrange: const Color(0xFFFF9500),
      diffAddBg: const Color(0xFF0D2A1A),
      diffAddText: const Color(0xFF00FF9F),
      diffRemoveBg: const Color(0xFF2A0D12),
      diffRemoveText: const Color(0xFFFF4F6A),
      diffContextBg: _mixBg(bg, accent, 0.04),
      statusActive: const Color(0xFF00DD88),
      statusIdle: const Color(0xFF888888),
      statusError: const Color(0xFFFF4F6A),
      statusWarning: const Color(0xFFFF9500),
      orbCyan: const Color(0xFF3CE8FF),
      orbPurple: const Color(0xFFAA66FF),
      orbPink: const Color(0xFFE060E0),
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
      textPrimary: const Color(0xFF1A1A2E),
      textSecondary: const Color(0xFF64748B),
      textMuted: const Color(0xFF94A3B8),
      textHighlight: const Color(0xFF000000),
      terminalText: const Color(0xFF1E293B),
      accentGreen: const Color(0xFF067D17),
      accentGreenDim: const Color(0xFF059212),
      accentGreenGlow: const Color(0x22067D17),
      accentRed: const Color(0xFFDE1B2E),
      accentRedDim: const Color(0xFFB5152A),
      accentBlue: const Color(0xFF0066CC),
      accentOrange: const Color(0xFFCC7700),
      diffAddBg: const Color(0xFFE6F7ED),
      diffAddText: const Color(0xFF067D17),
      diffRemoveBg: const Color(0xFFFDE8E8),
      diffRemoveText: const Color(0xFFDE1B2E),
      diffContextBg: const Color(0xFFF8FAFC),
      statusActive: const Color(0xFF067D17),
      statusIdle: const Color(0xFF94A3B8),
      statusError: const Color(0xFFDE1B2E),
      statusWarning: const Color(0xFFCC7700),
      orbCyan: const Color(0xFF00A8C8),
      orbPurple: const Color(0xFF7C3AED),
      orbPink: const Color(0xFFD946EF),
    );
  }

  static Color _mixBg(Color bg, Color accent, double t) =>
      Color.lerp(bg, accent, t)!;

  // ── JSON serialization ────────────────────────────────────────────────────────

  static String _colorToHex(Color c) =>
      c.value.toRadixString(16).padLeft(8, '0');

  static Color _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    return Color(int.parse(h, radix: 16));
  }

  /// Serialises the full colour scheme to a JSON-compatible map.
  Map<String, String> toJson() => {
    'primary': _colorToHex(primary),
    'primaryLight': _colorToHex(primaryLight),
    'primaryDark': _colorToHex(primaryDark),
    'primaryGlow': _colorToHex(primaryGlow),
    'background': _colorToHex(background),
    'surface': _colorToHex(surface),
    'surfaceElevated': _colorToHex(surfaceElevated),
    'surfaceHighlight': _colorToHex(surfaceHighlight),
    'border': _colorToHex(border),
    'divider': _colorToHex(divider),
    'terminalBackground': _colorToHex(terminalBackground),
    'sidebar': _colorToHex(sidebar),
    'sidebarGlow': _colorToHex(sidebarGlow),
    'terminalPrompt': _colorToHex(terminalPrompt),
    'tabBorder': _colorToHex(tabBorder),
    'tabActiveBg': _colorToHex(tabActiveBg),
    'tabInactiveBg': _colorToHex(tabInactiveBg),
    'textPrimary': _colorToHex(textPrimary),
    'textSecondary': _colorToHex(textSecondary),
    'textMuted': _colorToHex(textMuted),
    'textHighlight': _colorToHex(textHighlight),
    'terminalText': _colorToHex(terminalText),
    'accentGreen': _colorToHex(accentGreen),
    'accentGreenDim': _colorToHex(accentGreenDim),
    'accentGreenGlow': _colorToHex(accentGreenGlow),
    'accentRed': _colorToHex(accentRed),
    'accentRedDim': _colorToHex(accentRedDim),
    'accentBlue': _colorToHex(accentBlue),
    'accentOrange': _colorToHex(accentOrange),
    'diffAddBg': _colorToHex(diffAddBg),
    'diffAddText': _colorToHex(diffAddText),
    'diffRemoveBg': _colorToHex(diffRemoveBg),
    'diffRemoveText': _colorToHex(diffRemoveText),
    'diffContextBg': _colorToHex(diffContextBg),
    'statusActive': _colorToHex(statusActive),
    'statusIdle': _colorToHex(statusIdle),
    'statusError': _colorToHex(statusError),
    'statusWarning': _colorToHex(statusWarning),
    'orbCyan': _colorToHex(orbCyan),
    'orbPurple': _colorToHex(orbPurple),
    'orbPink': _colorToHex(orbPink),
  };

  /// Exports the scheme as a pretty-printed JSON string.
  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  /// Creates a scheme from a JSON map.  Missing keys fall back to a dark
  /// default derived from [fallbackAccent].
  factory AppColorScheme.fromJson(
    Map<String, dynamic> json, {
    Color fallbackAccent = const Color(0xFF7C3AED),
    Brightness brightness = Brightness.dark,
  }) {
    final fallback = AppColorScheme.fromAccent(
      fallbackAccent,
      brightness: brightness,
    );
    Color c(String key, Color fb) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return _hexToColor(v);
      return fb;
    }
    return AppColorScheme(
      primary: c('primary', fallback.primary),
      primaryLight: c('primaryLight', fallback.primaryLight),
      primaryDark: c('primaryDark', fallback.primaryDark),
      primaryGlow: c('primaryGlow', fallback.primaryGlow),
      background: c('background', fallback.background),
      surface: c('surface', fallback.surface),
      surfaceElevated: c('surfaceElevated', fallback.surfaceElevated),
      surfaceHighlight: c('surfaceHighlight', fallback.surfaceHighlight),
      border: c('border', fallback.border),
      divider: c('divider', fallback.divider),
      terminalBackground: c('terminalBackground', fallback.terminalBackground),
      sidebar: c('sidebar', fallback.sidebar),
      sidebarGlow: c('sidebarGlow', fallback.sidebarGlow),
      terminalPrompt: c('terminalPrompt', fallback.terminalPrompt),
      tabBorder: c('tabBorder', fallback.tabBorder),
      tabActiveBg: c('tabActiveBg', fallback.tabActiveBg),
      tabInactiveBg: c('tabInactiveBg', fallback.tabInactiveBg),
      textPrimary: c('textPrimary', fallback.textPrimary),
      textSecondary: c('textSecondary', fallback.textSecondary),
      textMuted: c('textMuted', fallback.textMuted),
      textHighlight: c('textHighlight', fallback.textHighlight),
      terminalText: c('terminalText', fallback.terminalText),
      accentGreen: c('accentGreen', fallback.accentGreen),
      accentGreenDim: c('accentGreenDim', fallback.accentGreenDim),
      accentGreenGlow: c('accentGreenGlow', fallback.accentGreenGlow),
      accentRed: c('accentRed', fallback.accentRed),
      accentRedDim: c('accentRedDim', fallback.accentRedDim),
      accentBlue: c('accentBlue', fallback.accentBlue),
      accentOrange: c('accentOrange', fallback.accentOrange),
      diffAddBg: c('diffAddBg', fallback.diffAddBg),
      diffAddText: c('diffAddText', fallback.diffAddText),
      diffRemoveBg: c('diffRemoveBg', fallback.diffRemoveBg),
      diffRemoveText: c('diffRemoveText', fallback.diffRemoveText),
      diffContextBg: c('diffContextBg', fallback.diffContextBg),
      statusActive: c('statusActive', fallback.statusActive),
      statusIdle: c('statusIdle', fallback.statusIdle),
      statusError: c('statusError', fallback.statusError),
      statusWarning: c('statusWarning', fallback.statusWarning),
      orbCyan: c('orbCyan', fallback.orbCyan),
      orbPurple: c('orbPurple', fallback.orbPurple),
      orbPink: c('orbPink', fallback.orbPink),
    );
  }

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
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textHighlight,
    Color? terminalText,
    Color? accentGreen,
    Color? accentGreenDim,
    Color? accentGreenGlow,
    Color? accentRed,
    Color? accentRedDim,
    Color? accentBlue,
    Color? accentOrange,
    Color? diffAddBg,
    Color? diffAddText,
    Color? diffRemoveBg,
    Color? diffRemoveText,
    Color? diffContextBg,
    Color? statusActive,
    Color? statusIdle,
    Color? statusError,
    Color? statusWarning,
    Color? orbCyan,
    Color? orbPurple,
    Color? orbPink,
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
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textHighlight: textHighlight ?? this.textHighlight,
      terminalText: terminalText ?? this.terminalText,
      accentGreen: accentGreen ?? this.accentGreen,
      accentGreenDim: accentGreenDim ?? this.accentGreenDim,
      accentGreenGlow: accentGreenGlow ?? this.accentGreenGlow,
      accentRed: accentRed ?? this.accentRed,
      accentRedDim: accentRedDim ?? this.accentRedDim,
      accentBlue: accentBlue ?? this.accentBlue,
      accentOrange: accentOrange ?? this.accentOrange,
      diffAddBg: diffAddBg ?? this.diffAddBg,
      diffAddText: diffAddText ?? this.diffAddText,
      diffRemoveBg: diffRemoveBg ?? this.diffRemoveBg,
      diffRemoveText: diffRemoveText ?? this.diffRemoveText,
      diffContextBg: diffContextBg ?? this.diffContextBg,
      statusActive: statusActive ?? this.statusActive,
      statusIdle: statusIdle ?? this.statusIdle,
      statusError: statusError ?? this.statusError,
      statusWarning: statusWarning ?? this.statusWarning,
      orbCyan: orbCyan ?? this.orbCyan,
      orbPurple: orbPurple ?? this.orbPurple,
      orbPink: orbPink ?? this.orbPink,
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
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textHighlight: Color.lerp(textHighlight, other.textHighlight, t)!,
      terminalText: Color.lerp(terminalText, other.terminalText, t)!,
      accentGreen: Color.lerp(accentGreen, other.accentGreen, t)!,
      accentGreenDim: Color.lerp(accentGreenDim, other.accentGreenDim, t)!,
      accentGreenGlow: Color.lerp(accentGreenGlow, other.accentGreenGlow, t)!,
      accentRed: Color.lerp(accentRed, other.accentRed, t)!,
      accentRedDim: Color.lerp(accentRedDim, other.accentRedDim, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      accentOrange: Color.lerp(accentOrange, other.accentOrange, t)!,
      diffAddBg: Color.lerp(diffAddBg, other.diffAddBg, t)!,
      diffAddText: Color.lerp(diffAddText, other.diffAddText, t)!,
      diffRemoveBg: Color.lerp(diffRemoveBg, other.diffRemoveBg, t)!,
      diffRemoveText: Color.lerp(diffRemoveText, other.diffRemoveText, t)!,
      diffContextBg: Color.lerp(diffContextBg, other.diffContextBg, t)!,
      statusActive: Color.lerp(statusActive, other.statusActive, t)!,
      statusIdle: Color.lerp(statusIdle, other.statusIdle, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      orbCyan: Color.lerp(orbCyan, other.orbCyan, t)!,
      orbPurple: Color.lerp(orbPurple, other.orbPurple, t)!,
      orbPink: Color.lerp(orbPink, other.orbPink, t)!,
    );
  }
}

/// Convenience extension: `context.appColors.primary`.
extension AppColorSchemeX on BuildContext {
  AppColorScheme get appColors => AppColorScheme.of(this);
}
