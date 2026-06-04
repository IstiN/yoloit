import 'dart:convert';

/// Extract a minimal panel summary (`{id, title, type}`) from a JSON string
/// that may contain a `panel` key in its root object.  Used when parsing
/// tool-call stdout to compress panel-related output for LLM prompts.
///
/// Returns `null` if [stdout] is not a valid JSON string or has no panel.
Map<String, Object?>? panelSummaryFromStdout(Object? stdout) {
  if (stdout is! String || stdout.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(stdout);
    if (decoded is! Map) return null;
    final panel = decoded['panel'];
    if (panel is! Map) return null;
    return <String, Object?>{
      if (panel['id'] != null) 'id': panel['id'],
      if (panel['title'] != null) 'title': panel['title'],
      if (panel['type'] != null) 'type': panel['type'],
    };
  } catch (_) {
    return null;
  }
}
