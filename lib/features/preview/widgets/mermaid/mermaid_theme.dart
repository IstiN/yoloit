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
  final canvasColor =
      isDark
          ? Color.lerp(colors.background, colors.surface, 0.55)!
          : Color.lerp(colors.surface, colors.background, 0.45)!;
  final clusterFill =
      isDark
          ? Color.lerp(colors.surfaceElevated, colors.primary, 0.18)!
          : Color.lerp(colors.surfaceElevated, colors.primary, 0.10)!;
  final nodeFill =
      isDark
          ? Color.lerp(clusterFill, colors.textPrimary, 0.07)!
          : Color.lerp(colors.surface, colors.primary, 0.08)!;
  final secondaryFill =
      isDark
          ? Color.lerp(nodeFill, colors.primaryLight, 0.10)!
          : Color.lerp(nodeFill, colors.primary, 0.06)!;
  final tertiaryFill =
      isDark
          ? Color.lerp(clusterFill, colors.surfaceHighlight, 0.45)!
          : Color.lerp(colors.surfaceHighlight, colors.surface, 0.18)!;
  final noteFill =
      isDark
          ? Color.lerp(nodeFill, colors.primary, 0.12)!
          : Color.lerp(colors.surface, colors.primary, 0.14)!;
  final borderColor =
      isDark
          ? Color.lerp(colors.border, colors.primaryLight, 0.42)!
          : Color.lerp(colors.border, colors.primaryDark, 0.16)!;
  final lineColor =
      Color.lerp(onSurface, colors.primary, isDark ? 0.48 : 0.24)!;
  final edgeLabelBackground =
      isDark
          ? Color.lerp(canvasColor, colors.background, 0.16)!
          : Color.lerp(canvasColor, colors.surface, 0.78)!;
  final backgroundHex = _hexColor(canvasColor);
  final textHex = _hexColor(onSurface);
  final borderHex = _hexColor(borderColor);
  final lineHex = _hexColor(lineColor);
  final renderOptions = MermaidRenderOptions(
    backgroundColor: backgroundHex,
    config: <String, Object?>{
      'theme': 'base',
      'darkMode': isDark,
      'themeVariables': <String, Object?>{
        'background': backgroundHex,
        'textColor': textHex,
        'lineColor': lineHex,
        'mainBkg': _hexColor(nodeFill),
        'secondBkg': _hexColor(clusterFill),
        'tertiaryBkg': _hexColor(tertiaryFill),
        'primaryColor': _hexColor(nodeFill),
        'primaryBorderColor': borderHex,
        'primaryTextColor': textHex,
        'secondaryColor': _hexColor(secondaryFill),
        'secondaryBorderColor': borderHex,
        'secondaryTextColor': textHex,
        'tertiaryColor': _hexColor(tertiaryFill),
        'tertiaryBorderColor': borderHex,
        'tertiaryTextColor': textHex,
        'clusterBkg': _hexColor(clusterFill),
        'clusterBorder': borderHex,
        'nodeBorder': borderHex,
        'edgeLabelBackground': _hexColor(edgeLabelBackground),
        'labelBoxBkgColor': _hexColor(edgeLabelBackground),
        'labelTextColor': textHex,
        'actorBkg': _hexColor(nodeFill),
        'actorBorder': borderHex,
        'actorTextColor': textHex,
        'activationBorderColor': _hexColor(colors.primary),
        'activationBkgColor': _hexColor(secondaryFill),
        'sequenceNumberColor': textHex,
        'signalColor': lineHex,
        'signalTextColor': textHex,
        'noteBkgColor': _hexColor(noteFill),
        'noteBorderColor': borderHex,
        'noteTextColor': textHex,
      },
    },
  );
  return MermaidThemeOptions(
    renderOptions: renderOptions,
    cacheToken:
        '${isDark ? 'dark' : 'light'}:${_hexColor(colors.primary)}:$backgroundHex:$textHex',
    canvasColor: canvasColor,
    scrimColor: canvasColor.withValues(alpha: isDark ? 0.62 : 0.52),
  );
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0x00FFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
