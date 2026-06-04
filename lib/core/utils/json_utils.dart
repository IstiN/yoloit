import 'dart:convert';

import 'package:yoloit/core/utils/string_utils.dart';

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

/// Compacts a tool-call result string for LLM prompts.
///
/// If [rawResult] is valid JSON containing `ok`, `command`, `error`, or
/// `stdout` with a panel summary, returns a JSON-encoded compact map
/// truncated to 800 chars.  Otherwise returns the raw string truncated.
String compactToolResultForPrompt(Object? rawResult) {
  if (rawResult is! String || rawResult.trim().isEmpty) return 'none';
  try {
    final decoded = jsonDecode(rawResult);
    if (decoded is Map) {
      final compact = <String, Object?>{
        if (decoded.containsKey('ok')) 'ok': decoded['ok'],
        if (decoded['command'] != null) 'command': decoded['command'],
        if (decoded['error'] != null) 'error': decoded['error'],
      };
      final stdout = decoded['stdout'];
      final panel = panelSummaryFromStdout(stdout);
      if (panel != null) compact['panel'] = panel;
      if (compact.isNotEmpty) return compactPromptJson(compact, 800);
    }
  } catch (_) {}
  return truncatePromptText(rawResult, 800);
}
