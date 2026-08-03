import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Theme bundle computed from the current [AppColorScheme] and [Brightness].
class MermaidThemeOptions {
  const MermaidThemeOptions({
    required this.renderOptions,
    required this.cacheToken,
    required this.canvasColor,
    required this.scrimColor,
  });

  final MermaidRenderOptions renderOptions;
  final String cacheToken;
  final Color canvasColor;
  final Color scrimColor;
}

/// Builds a [MermaidThemeOptions] that matches the current app theme.
MermaidThemeOptions buildMermaidThemeOptions(
  BuildContext context,
  AppColorScheme colors,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final onSurface = theme.colorScheme.onSurface;
  final palette =
      isDark
          ? _MermaidPalette.dark(colors, onSurface)
          : _MermaidPalette.light(colors, onSurface);
  final backgroundHex = _hexColor(palette.canvasColor);
  final textHex = _hexColor(onSurface);
  final borderHex = _hexColor(palette.borderColor);
  final lineHex = _hexColor(palette.lineColor);
  final renderOptions = MermaidRenderOptions(
    backgroundColor: backgroundHex,
    config: <String, Object?>{
      'theme': 'base',
      'darkMode': isDark,
      'themeVariables': <String, Object?>{
        'background': backgroundHex,
        'textColor': textHex,
        'lineColor': lineHex,
        'mainBkg': _hexColor(palette.nodeFill),
        'secondBkg': _hexColor(palette.clusterFill),
        'tertiaryBkg': _hexColor(palette.tertiaryFill),
        'primaryColor': _hexColor(palette.nodeFill),
        'primaryBorderColor': borderHex,
        'primaryTextColor': textHex,
        'secondaryColor': _hexColor(palette.secondaryFill),
        'secondaryBorderColor': borderHex,
        'secondaryTextColor': textHex,
        'tertiaryColor': _hexColor(palette.tertiaryFill),
        'tertiaryBorderColor': borderHex,
        'tertiaryTextColor': textHex,
        'clusterBkg': _hexColor(palette.clusterFill),
        'clusterBorder': borderHex,
        'nodeBorder': borderHex,
        'edgeLabelBackground': _hexColor(palette.edgeLabelBackground),
        'labelBoxBkgColor': _hexColor(palette.edgeLabelBackground),
        'labelTextColor': textHex,
        'actorBkg': _hexColor(palette.nodeFill),
        'actorBorder': borderHex,
        'actorTextColor': textHex,
        'activationBorderColor': _hexColor(colors.primary),
        'activationBkgColor': _hexColor(palette.secondaryFill),
        'sequenceNumberColor': textHex,
        'signalColor': lineHex,
        'signalTextColor': textHex,
        'noteBkgColor': _hexColor(palette.noteFill),
        'noteBorderColor': borderHex,
        'noteTextColor': textHex,
      },
    },
  );
  return MermaidThemeOptions(
    renderOptions: renderOptions,
    cacheToken:
        '${isDark ? 'dark' : 'light'}:${_hexColor(colors.primary)}:$backgroundHex:$textHex',
    canvasColor: palette.canvasColor,
    scrimColor: palette.canvasColor.withValues(alpha: isDark ? 0.62 : 0.52),
  );
}

/// Per-brightness palette of derived mermaid colours.
class _MermaidPalette {
  const _MermaidPalette._({
    required this.canvasColor,
    required this.clusterFill,
    required this.nodeFill,
    required this.secondaryFill,
    required this.tertiaryFill,
    required this.noteFill,
    required this.borderColor,
    required this.lineColor,
    required this.edgeLabelBackground,
  });

  factory _MermaidPalette.dark(AppColorScheme colors, Color onSurface) {
    final canvasColor = Color.lerp(colors.background, colors.surface, 0.55)!;
    final clusterFill =
        Color.lerp(colors.surfaceElevated, colors.primary, 0.18)!;
    final nodeFill = Color.lerp(clusterFill, colors.textPrimary, 0.07)!;
    final secondaryFill = Color.lerp(nodeFill, colors.primaryLight, 0.10)!;
    final tertiaryFill =
        Color.lerp(clusterFill, colors.surfaceHighlight, 0.45)!;
    final noteFill = Color.lerp(nodeFill, colors.primary, 0.12)!;
    final borderColor = Color.lerp(colors.border, colors.primaryLight, 0.42)!;
    final lineColor = Color.lerp(onSurface, colors.primary, 0.48)!;
    final edgeLabelBackground =
        Color.lerp(canvasColor, colors.background, 0.16)!;
    return _MermaidPalette._(
      canvasColor: canvasColor,
      clusterFill: clusterFill,
      nodeFill: nodeFill,
      secondaryFill: secondaryFill,
      tertiaryFill: tertiaryFill,
      noteFill: noteFill,
      borderColor: borderColor,
      lineColor: lineColor,
      edgeLabelBackground: edgeLabelBackground,
    );
  }

  factory _MermaidPalette.light(AppColorScheme colors, Color onSurface) {
    final canvasColor = Color.lerp(colors.surface, colors.background, 0.45)!;
    final clusterFill =
        Color.lerp(colors.surfaceElevated, colors.primary, 0.10)!;
    final nodeFill = Color.lerp(colors.surface, colors.primary, 0.08)!;
    final secondaryFill = Color.lerp(nodeFill, colors.primary, 0.06)!;
    final tertiaryFill =
        Color.lerp(colors.surfaceHighlight, colors.surface, 0.18)!;
    final noteFill = Color.lerp(colors.surface, colors.primary, 0.14)!;
    final borderColor = Color.lerp(colors.border, colors.primaryDark, 0.16)!;
    final lineColor = Color.lerp(onSurface, colors.primary, 0.24)!;
    final edgeLabelBackground = Color.lerp(canvasColor, colors.surface, 0.78)!;
    return _MermaidPalette._(
      canvasColor: canvasColor,
      clusterFill: clusterFill,
      nodeFill: nodeFill,
      secondaryFill: secondaryFill,
      tertiaryFill: tertiaryFill,
      noteFill: noteFill,
      borderColor: borderColor,
      lineColor: lineColor,
      edgeLabelBackground: edgeLabelBackground,
    );
  }

  final Color canvasColor;
  final Color clusterFill;
  final Color nodeFill;
  final Color secondaryFill;
  final Color tertiaryFill;
  final Color noteFill;
  final Color borderColor;
  final Color lineColor;
  final Color edgeLabelBackground;
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0x00FFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
