import 'dart:convert';

/// Collapses whitespace in [value] and trims the result.
String truncatePromptText(String value, int maxChars) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

/// JSON-encodes [value]; if that fails, stringifies it.
/// The result is then run through [truncatePromptText].
String compactPromptJson(Object? value, int maxChars) {
  try {
    return truncatePromptText(jsonEncode(value), maxChars);
  } catch (_) {
    return truncatePromptText('$value', maxChars);
  }
}
