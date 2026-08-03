import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/color_utils.dart';

/// Converts a JetBrains `.icls` (IntelliJ Color Scheme) XML file into an
/// [AppColorScheme].
///
/// ICLS files define editor-specific colours (syntax highlighting, gutter,
/// etc.).  This adapter maps the most relevant UI and editor colours to our
/// app's semantic colour slots.  Missing colours are derived from the
/// background and accent via [AppColorScheme.fromAccent].
class IclsThemeAdapter {
  IclsThemeAdapter._();

  /// Parses [xmlContent] (the raw `.icls` file) and returns the scheme name
  /// and an [AppColorScheme].
  static ({String name, AppColorScheme scheme}) parse(String xmlContent) {
    final doc = XmlDocument.parse(xmlContent);
    final root = doc.rootElement;
    final schemeName = root.getAttribute('name') ?? 'Imported Theme';
    final parentScheme = root.getAttribute('parent_scheme') ?? '';
    final isDark = parentScheme.toLowerCase().contains('darcula') ||
        schemeName.toLowerCase().contains('dark');

    // ── Collect <colors> and <attributes> ───────────────────────────────
    final colorMap = _collectColors(root);
    final attrs = _collectAttributes(root);
    final colors = _IclsColors(
      colorMap: colorMap,
      attrFg: attrs.fg,
      attrBg: attrs.bg,
      isDark: isDark,
    );

    return (name: schemeName, scheme: _buildScheme(colors));
  }

  // ── Collect <colors> ──────────────────────────────────────────────────
  static Map<String, String> _collectColors(XmlElement root) {
    final colorMap = <String, String>{};
    for (final colorsEl in root.findAllElements('colors')) {
      for (final opt in colorsEl.findAllElements('option')) {
        final name = opt.getAttribute('name');
        final value = opt.getAttribute('value');
        if (name != null && value != null && value.isNotEmpty) {
          colorMap[name] = value;
        }
      }
    }
    return colorMap;
  }

  // ── Collect <attributes> foreground/background ────────────────────────
  static ({Map<String, String> fg, Map<String, String> bg})
  _collectAttributes(XmlElement root) {
    final attrFg = <String, String>{};
    final attrBg = <String, String>{};
    for (final attrsEl in root.findAllElements('attributes')) {
      for (final opt in attrsEl.findAllElements('option')) {
        _collectAttributeOption(attrFg, attrBg, opt);
      }
    }
    return (fg: attrFg, bg: attrBg);
  }

  static void _collectAttributeOption(
    Map<String, String> attrFg,
    Map<String, String> attrBg,
    XmlElement opt,
  ) {
    final name = opt.getAttribute('name');
    if (name == null) return;
    final valueEl = opt.findElements('value').firstOrNull;
    if (valueEl == null) return;
    for (final inner in valueEl.findElements('option')) {
      final k = inner.getAttribute('name');
      final v = inner.getAttribute('value');
      if (v == null || v.isEmpty) continue;
      if (k == 'FOREGROUND') attrFg[name] = v;
      if (k == 'BACKGROUND') attrBg[name] = v;
    }
  }

  // ── Resolve colours ──────────────────────────────────────────────────

  static AppColorScheme _buildScheme(_IclsColors colors) {
    final isDark = colors.isDark;

    // Background
    final bg = _resolveBackground(colors);

    // Primary accent — pick from keyword or hyperlink foreground
    final accent = _resolveAccent(colors);

    // Derive base scheme from accent + bg
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final base = AppColorScheme.fromAccent(
      accent,
      bgSeed: bg,
      brightness: brightness,
    );

    var scheme = _applySurfaces(base, colors, bg);
    scheme = _applyBorders(scheme, colors, bg);
    scheme = _applyPrimary(scheme, accent, isDark);
    scheme = _applyText(scheme, colors, base);
    scheme = _applyAccents(scheme, colors);
    scheme = _applyDiff(scheme, colors);
    scheme = _applyStatus(scheme, colors);
    return scheme;
  }

  static Color _resolveBackground(_IclsColors colors) {
    return colors.fromAttrBg('TEXT') ??
        colors.fromColors('CONSOLE_BACKGROUND_KEY') ??
        (colors.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF));
  }

  static Color _resolveAccent(_IclsColors colors) {
    return colors.fromAttrFg('DEFAULT_KEYWORD') ??
        colors.fromAttrFg('HYPERLINK_ATTRIBUTES') ??
        colors.fromAttrFg('DEFAULT_FUNCTION_DECLARATION') ??
        (colors.isDark ? const Color(0xFF548AF7) : const Color(0xFF0033B3));
  }

  // Surfaces
  static AppColorScheme _applySurfaces(
    AppColorScheme scheme,
    _IclsColors colors,
    Color bg,
  ) {
    final isDark = colors.isDark;
    final caretRow = colors.fromColors('CARET_ROW_COLOR');
    final gutterBg = colors.fromColors('GUTTER_BACKGROUND');
    final selectionBg = colors.fromColors('SELECTION_BACKGROUND');
    return scheme.copyWith(
      background: bg,
      surface: caretRow ?? _shift(bg, isDark ? 0.06 : -0.04),
      surfaceElevated: gutterBg ?? _shift(bg, isDark ? 0.10 : -0.06),
      surfaceHighlight: selectionBg,
    );
  }

  static AppColorScheme _applyBorders(
    AppColorScheme scheme,
    _IclsColors colors,
    Color bg,
  ) {
    final isDark = colors.isDark;
    final indentGuide = colors.fromColors('INDENT_GUIDE') ??
        colors.fromColors('VISUAL_INDENT_GUIDE');
    return scheme.copyWith(
      border: indentGuide ?? _shift(bg, isDark ? 0.18 : -0.12),
      divider: _shift(bg, isDark ? 0.14 : -0.08),
      terminalBackground: _shift(bg, isDark ? -0.10 : 0.03),
    );
  }

  static AppColorScheme _applyPrimary(
    AppColorScheme scheme,
    Color accent,
    bool isDark,
  ) {
    return scheme.copyWith(
      primary: accent,
      primaryLight: Color.lerp(accent, Colors.white, 0.35),
      primaryDark: Color.lerp(accent, Colors.black, 0.30),
      primaryGlow: accent.withAlpha(isDark ? 51 : 30),
    );
  }

  // Text
  static AppColorScheme _applyText(
    AppColorScheme scheme,
    _IclsColors colors,
    AppColorScheme base,
  ) {
    final isDark = colors.isDark;
    final textFg = colors.fromAttrFg('TEXT');
    final lineNumColor = colors.fromColors('LINE_NUMBERS_COLOR');
    return scheme.copyWith(
      textPrimary: textFg,
      textSecondary: lineNumColor ??
          _shift(textFg ?? base.textSecondary, isDark ? -0.25 : 0.30),
      textMuted: _shift(textFg ?? base.textMuted, isDark ? -0.50 : 0.55),
      textHighlight: isDark
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000),
      terminalText: textFg,
    );
  }

  // Semantic colours from ICLS
  static AppColorScheme _applyAccents(
    AppColorScheme scheme,
    _IclsColors colors,
  ) {
    final isDark = colors.isDark;
    final greenFg = colors.fromAttrFg('DEFAULT_STRING');
    final redFg = colors.fromColors(
      'FILESTATUS_IDEA_FILESTATUS_MERGED_WITH_CONFLICTS',
    );
    final orangeFg = colors.fromColors('FILESTATUS_IDEA_FILESTATUS_IGNORED');
    final blueFg = colors.fromAttrFg('DEFAULT_FUNCTION_DECLARATION') ??
        colors.fromAttrFg('HYPERLINK_ATTRIBUTES');
    final addedColor = colors.fromColors('ADDED_LINES_COLOR');
    final modifiedColor = colors.fromColors('MODIFIED_LINES_COLOR');
    return scheme.copyWith(
      accentGreen: greenFg ?? addedColor,
      accentGreenDim: greenFg != null
          ? Color.lerp(greenFg, isDark ? Colors.black : Colors.white, 0.20)
          : null,
      accentRed: redFg,
      accentRedDim: redFg != null
          ? Color.lerp(redFg, isDark ? Colors.black : Colors.white, 0.20)
          : null,
      accentBlue: blueFg ?? modifiedColor,
      accentOrange: orangeFg,
    );
  }

  // Diff
  static AppColorScheme _applyDiff(AppColorScheme scheme, _IclsColors colors) {
    final isDark = colors.isDark;
    final greenFg = colors.fromAttrFg('DEFAULT_STRING');
    final redFg = colors.fromColors(
      'FILESTATUS_IDEA_FILESTATUS_MERGED_WITH_CONFLICTS',
    );
    final addedColor = colors.fromColors('ADDED_LINES_COLOR');
    final deletedColor = colors.fromColors('DELETED_LINES_COLOR');
    final diffModBg = colors.fromAttrBg('DIFF_MODIFIED');
    final caretRow = colors.fromColors('CARET_ROW_COLOR');
    return scheme.copyWith(
      diffAddBg: addedColor?.withAlpha(isDark ? 40 : 30),
      diffAddText: greenFg ?? addedColor,
      diffRemoveBg: deletedColor?.withAlpha(isDark ? 40 : 30),
      diffRemoveText: redFg ?? deletedColor,
      diffContextBg: diffModBg ?? caretRow,
    );
  }

  static AppColorScheme _applyStatus(
    AppColorScheme scheme,
    _IclsColors colors,
  ) {
    final greenFg = colors.fromAttrFg('DEFAULT_STRING');
    final redFg = colors.fromColors(
      'FILESTATUS_IDEA_FILESTATUS_MERGED_WITH_CONFLICTS',
    );
    final orangeFg = colors.fromColors('FILESTATUS_IDEA_FILESTATUS_IGNORED');
    final addedColor = colors.fromColors('ADDED_LINES_COLOR');
    return scheme.copyWith(
      statusActive: greenFg ?? addedColor,
      statusError: redFg,
      statusWarning: orangeFg,
    );
  }

  /// Shifts a colour lighter (positive) or darker (negative) by [amount].
  static Color _shift(Color c, double amount) {
    if (amount > 0) return Color.lerp(c, Colors.white, amount)!;
    return Color.lerp(c, Colors.black, -amount)!;
  }
}

/// Raw colour tables parsed from an `.icls` document, plus the darkness flag.
/// Provides typed lookup helpers that resolve hex strings into [Color]s.
class _IclsColors {
  const _IclsColors({
    required this.colorMap,
    required this.attrFg,
    required this.attrBg,
    required this.isDark,
  });

  final Map<String, String> colorMap;
  final Map<String, String> attrFg;
  final Map<String, String> attrBg;
  final bool isDark;

  Color? fromColors(String key) {
    final v = colorMap[key];
    return v != null ? parseHexColor(v) : null;
  }

  Color? fromAttrFg(String key) {
    final v = attrFg[key];
    return v != null ? parseHexColor(v) : null;
  }

  Color? fromAttrBg(String key) {
    final v = attrBg[key];
    return v != null ? parseHexColor(v) : null;
  }
}
