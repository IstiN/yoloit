import 'dart:convert';

String? extractYoloAssistantToolError(Map<dynamic, dynamic> decoded) {
  final error = decoded['error'];
  if (error != null && '$error'.trim().isNotEmpty) {
    return '$error'.trim();
  }
  final stderr = decoded['stderr'];
  if (stderr != null && '$stderr'.trim().isNotEmpty) {
    return '$stderr'.trim();
  }
  final message = decoded['message'];
  if (message != null && '$message'.trim().isNotEmpty) {
    return '$message'.trim();
  }
  final stdout = decoded['stdout'];
  if (stdout is String && stdout.trim().isNotEmpty) {
    try {
      final inner = jsonDecode(stdout);
      if (inner is Map) {
        return extractYoloAssistantToolError(inner);
      }
    } catch (_) {
      if (stdout.length <= 240) return stdout.trim();
    }
  }
  return null;
}
