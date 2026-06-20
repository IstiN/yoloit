import 'package:flutter/material.dart';

/// Parses a color string into a [Color].
///
/// Supports:
/// - `'clear'` or empty/blank → `null`
/// - `'#RRGGBB'` or `'#AARRGGBB'` hex strings
/// - raw 32-bit integer strings (e.g. `'0xFF123456'`)
Color? parseColor(String? text) {
  if (text == null) return null;
  final normalized = text.trim();
  if (normalized.isEmpty || normalized == 'clear') return null;
  if (normalized.startsWith('#')) {
    final hex = normalized.substring(1);
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) {
      return hex.length == 6 ? Color(0xFF000000 | parsed) : Color(parsed);
    }
  }
  final parsed = int.tryParse(normalized);
  if (parsed != null) return Color(parsed);
  return null;
}

/// Alias for backwards compatibility with existing call sites.
Color? parseHexColor(String? text) => parseColor(text);

/// Default blue used for panel-to-panel links when no color is specified.
const Color kDefaultLinkColor = Color(0xFF60A5FA);
