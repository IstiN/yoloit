import 'dart:convert';

String? extractYoloAssistantToolError(Map<dynamic, dynamic> decoded) {
  return _nonEmptyTrimmed(decoded['error']) ??
      _nonEmptyTrimmed(decoded['stderr']) ??
      _nonEmptyTrimmed(decoded['message']) ??
      _errorFromStdout(decoded['stdout']);
}

String? _nonEmptyTrimmed(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  return text;
}

String? _errorFromStdout(Object? stdout) {
  if (stdout is! String || stdout.trim().isEmpty) return null;
  try {
    final inner = jsonDecode(stdout);
    if (inner is Map) {
      return extractYoloAssistantToolError(inner);
    }
  } catch (_) {
    if (stdout.length <= 240) return stdout.trim();
  }
  return null;
}
