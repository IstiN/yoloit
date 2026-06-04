import 'package:flutter/material.dart';

/// Parse a hex color string (e.g. `'#FF5733'` or `'FF5733'` or `'#80FF5733'`)
/// into a [Color].
///
/// Returns `null` if [raw] is null, empty, or not a valid hex color.
Color? parseHexColor(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final cleaned = raw.trim().replaceFirst('#', '');
  if (cleaned.isEmpty) return null;
  final value = int.tryParse(
    cleaned.length <= 6 ? 'FF${cleaned.padLeft(6, '0')}' : cleaned,
    radix: 16,
  );
  if (value == null) return null;
  return Color(value);
}
