import 'dart:convert';

/// Collapse whitespace and truncate [value] to [maxChars], appending `…`
/// when truncation occurs.
String truncatePromptText(String value, int maxChars) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

/// Try to JSON-encode [value]; if that fails, stringify it.
/// The result is then run through [truncatePromptText] with [maxChars].
String compactPromptJson(Object? value, int maxChars) {
  try {
    return truncatePromptText(jsonEncode(value), maxChars);
  } catch (_) {
    return truncatePromptText('$value', maxChars);
  }
}
