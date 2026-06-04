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

    // ── Collect <colors> ──────────────────────────────────────────────────
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

    // ── Collect <attributes> foreground/background ────────────────────────
    final attrFg = <String, String>{};
    final attrBg = <String, String>{};
    for (final attrsEl in root.findAllElements('attributes')) {
      for (final opt in attrsEl.findAllElements('option')) {
        final name = opt.getAttribute('name');
        if (name == null) continue;
        final valueEl = opt.findElements('value').firstOrNull;
        if (valueEl == null) continue;
        for (final inner in valueEl.findElements('option')) {
          final k = inner.getAttribute('name');
          final v = inner.getAttribute('value');
          if (v == null || v.isEmpty) continue;
          if (k == 'FOREGROUND') attrFg[name] = v;
          if (k == 'BACKGROUND') attrBg[name] = v;
        }
      }
    }

    // ── Resolve colours ──────────────────────────────────────────────────

    Color? c(String hex) => parseHexColor(hex);
    Color? fromColors(String key) {
      final v = colorMap[key];
      return v != null ? c(v) : null;
    }
    Color? fromAttrFg(String key) {
      final v = attrFg[key];
      return v != null ? c(v) : null;
    }
    Color? fromAttrBg(String key) {
      final v = attrBg[key];
      return v != null ? c(v) : null;
    }

    // Background
    final bg = fromAttrBg('TEXT') ??
        fromColors('CONSOLE_BACKGROUND_KEY') ??
        (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF));

    // Primary accent — pick from keyword or hyperlink foreground
    final accent = fromAttrFg('DEFAULT_KEYWORD') ??
        fromAttrFg('HYPERLINK_ATTRIBUTES') ??
        fromAttrFg('DEFAULT_FUNCTION_DECLARATION') ??
        (isDark ? const Color(0xFF548AF7) : const Color(0xFF0033B3));

    // Derive base scheme from accent + bg
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final base = AppColorScheme.fromAccent(
      accent,
      bgSeed: bg,
      brightness: brightness,
    );

    // Text
    final textFg = fromAttrFg('TEXT');
    final lineNumColor = fromColors('LINE_NUMBERS_COLOR');

    // Semantic colours from ICLS
    final greenFg = fromAttrFg('DEFAULT_STRING');
    final redFg = fromColors('FILESTATUS_IDEA_FILESTATUS_MERGED_WITH_CONFLICTS');
    final orangeFg = fromColors('FILESTATUS_IDEA_FILESTATUS_IGNORED');
    final blueFg = fromAttrFg('DEFAULT_FUNCTION_DECLARATION') ??
        fromAttrFg('HYPERLINK_ATTRIBUTES');

    // Diff
    final addedColor = fromColors('ADDED_LINES_COLOR');
    final deletedColor = fromColors('DELETED_LINES_COLOR');
    final modifiedColor = fromColors('MODIFIED_LINES_COLOR');
    final diffModBg = fromAttrBg('DIFF_MODIFIED');

    // Surfaces
    final caretRow = fromColors('CARET_ROW_COLOR');
    final gutterBg = fromColors('GUTTER_BACKGROUND');
    final selectionBg = fromColors('SELECTION_BACKGROUND');
    final indentGuide = fromColors('INDENT_GUIDE') ??
        fromColors('VISUAL_INDENT_GUIDE');

    return (
      name: schemeName,
      scheme: base.copyWith(
        background: bg,
        surface: caretRow ?? _shift(bg, isDark ? 0.06 : -0.04),
        surfaceElevated: gutterBg ?? _shift(bg, isDark ? 0.10 : -0.06),
        surfaceHighlight: selectionBg,
        border: indentGuide ?? _shift(bg, isDark ? 0.18 : -0.12),
        divider: _shift(bg, isDark ? 0.14 : -0.08),
        terminalBackground: _shift(bg, isDark ? -0.10 : 0.03),
        primary: accent,
        primaryLight: Color.lerp(accent, Colors.white, 0.35),
        primaryDark: Color.lerp(accent, Colors.black, 0.30),
        primaryGlow: accent.withAlpha(isDark ? 51 : 30),
        textPrimary: textFg,
        textSecondary: lineNumColor ?? _shift(textFg ?? base.textSecondary, isDark ? -0.25 : 0.30),
        textMuted: _shift(textFg ?? base.textMuted, isDark ? -0.50 : 0.55),
        textHighlight: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
        terminalText: textFg,
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
        diffAddBg: addedColor?.withAlpha(isDark ? 40 : 30),
        diffAddText: greenFg ?? addedColor,
        diffRemoveBg: deletedColor?.withAlpha(isDark ? 40 : 30),
        diffRemoveText: redFg ?? deletedColor,
        diffContextBg: diffModBg ?? caretRow,
        statusActive: greenFg ?? addedColor,
        statusError: redFg,
        statusWarning: orangeFg,
      ),
    );
  }

  /// Shifts a colour lighter (positive) or darker (negative) by [amount].
  static Color _shift(Color c, double amount) {
    if (amount > 0) return Color.lerp(c, Colors.white, amount)!;
    return Color.lerp(c, Colors.black, -amount)!;
  }
}
