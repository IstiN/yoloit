import 'dart:convert';

import 'package:local_models_flutter/runtime/embedded_gemma_tool_calls.dart';
import 'package:yoloit/core/utils/json_utils.dart';
import 'package:yoloit/core/utils/string_utils.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_tool_errors.dart';

/// Pure message/log helpers extracted from `_YoloAssistantWidgetState` so the
/// text-processing logic can be unit-tested without pumping the widget.

/// Normalizes a raw overlay tool log entry into a single compact line with a
/// status icon (`⚙️` running, `✅` done, `❌` failed).
String normalizeOverlayToolLogEntry(String entry) {
  // Strip leading emoji/status prefixes, keep just the tool name.
  final clean =
      entry
          .replaceAll(RegExp(r'^[⏳✅❌]\s*running:\s*'), '')
          .replaceAll(RegExp(r'^[⏳✅❌]\s*'), '')
          .trim();
  final isDone = entry.startsWith('✅') || entry.startsWith('❌');
  final icon =
      entry.startsWith('❌')
          ? '❌'
          : isDone
          ? '✅'
          : '⚙️';
  return '$icon $clean';
}

/// Composes the voice overlay response: up to 5 recent tool calls as compact
/// lines followed by the assistant text (when non-empty).
String composeAssistantOverlayResponse(
  String assistantContent,
  List<String> toolLogs,
) {
  final text = assistantContent.trim();
  if (toolLogs.isEmpty) return text;
  final recent =
      toolLogs.length > 5 ? toolLogs.sublist(toolLogs.length - 5) : toolLogs;
  final toolText = recent.map(normalizeOverlayToolLogEntry).join('\n');
  if (text.isEmpty) return toolText;
  return '$toolText\n\n$text';
}

/// Computes the overlay assistant status shown while streaming a reply.
String assistantOverlayStatus({
  required bool isGenerating,
  required String content,
  required List<String> overlayToolLogs,
}) {
  if (isGenerating && content.trim().isEmpty && overlayToolLogs.isEmpty) {
    return 'processing';
  }
  return isGenerating ? 'responding' : 'output';
}

/// Replaces the `content` of the message with [messageId] in place.
/// Returns false when no message with that id exists.
bool replaceMessageContentInPlace(
  List<Map<String, dynamic>> messages,
  String messageId,
  String content,
) {
  final idx = messages.indexWhere((m) => m['id'] == messageId);
  if (idx == -1) return false;
  messages[idx] = {...messages[idx], 'content': content};
  return true;
}

/// Strips local-model tool-call echo blocks from assistant output. When the
/// cleaned content is empty but tools were called, returns a fallback summary.
String cleanAssistantToolEchoes(String content, List<String> calledTools) {
  var cleaned = stripEmbeddedGemmaToolCallBlocks(content).trim();
  if (cleaned.startsWith(RegExp(r'\[yoloit_[^\]]+\]')) &&
      (cleaned.contains('"ok"') || cleaned.contains('"command"'))) {
    cleaned = '';
  }
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*\[yoloit_[^\]]+\]\s*\{[\s\S]*?\}\s*$', multiLine: true),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*\[yoloit_[^\]]+\].*$', multiLine: true),
    '',
  );
  cleaned = cleaned.trim();
  if (cleaned.isNotEmpty) return cleaned;
  if (calledTools.isEmpty) return '';
  final unique = <String>[];
  for (final tool in calledTools) {
    if (!unique.contains(tool)) unique.add(tool);
  }
  return 'Готово — выполнил через ${unique.join(', ')}.';
}

/// Builds the one-line tool result shown in the chat: the CLI command on
/// success, or a compact failure description.
String compactAssistantToolResult(String toolName, String result, bool success) {
  String? command;
  String? error;
  try {
    final decoded = jsonDecode(result);
    if (decoded is Map) {
      command = decoded['command'] as String?;
      error = extractYoloAssistantToolError(decoded);
    }
  } catch (_) {}
  if (!success) {
    return error == null || error.isEmpty
        ? 'Tool failed: $toolName'
        : 'Tool failed: $error';
  }
  return command == null || command.isEmpty ? 'Done: $toolName' : command;
}

/// Whether the raw tool result JSON reports `{ok: false}`.
bool toolResultReportedFailure(String result) {
  try {
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded['ok'] == false) return true;
  } catch (_) {}
  return false;
}

/// State patch that retargets the assistant to a note panel created via the
/// `panel:create` tool. Empty when the tool did not create a markdown note.
Map<String, dynamic> panelCreateTargetPatch({
  required Map<String, Object?> arguments,
  required String result,
}) {
  final type = '${arguments['type'] ?? ''}'.trim();
  if (type != 'board.note.markdown') return const {};
  try {
    final decoded = jsonDecode(result);
    if (decoded is! Map) return const {};
    final stdout = decoded['stdout'];
    final payload = stdout is String ? jsonDecode(stdout) : decoded;
    if (payload is! Map) return const {};
    final panel = payload['panel'];
    if (panel is! Map) return const {};
    final id = '${panel['id'] ?? ''}'.trim();
    final title = '${panel['title'] ?? id}'.trim();
    if (id.isEmpty) return const {};
    return {
      'lastTargetNotePanelId': id,
      'lastTargetNotePanelTitle': title.isEmpty ? id : title,
    };
  } catch (_) {
    return const {};
  }
}

/// State patch that updates the assistant's target note panel after a tool
/// call, when the tool call implies a new target. Empty patch otherwise.
Map<String, dynamic> toolTargetPatchIfNeeded({
  required String? toolCommand,
  required Map<String, Object?> arguments,
  required String result,
  required String selfPanelId,
}) {
  if (toolResultReportedFailure(result)) return const {};
  if (toolCommand == 'panel:create') {
    return panelCreateTargetPatch(arguments: arguments, result: result);
  }
  if (toolCommand == 'note' || toolCommand?.startsWith('note:') == true) {
    final panel = '${arguments['panel'] ?? ''}'.trim();
    if (panel.isEmpty || panel == selfPanelId) return const {};
    return {'lastTargetNotePanelId': panel, 'lastTargetNotePanelTitle': panel};
  }
  return const {};
}

/// Formats a stored tool message for inclusion in the LLM prompt.
String formatToolMessageForPrompt(Map<String, dynamic> message) {
  final toolName = (message['toolName'] as String? ?? 'tool').trim();
  final success = message['success'] as bool? ?? true;
  final arguments = compactPromptJson(message['arguments'], 600);
  final result = compactToolResultForPrompt(message['rawResult']);
  return '\nTool $toolName ${success ? 'succeeded' : 'failed'}'
      '\nTool arguments: $arguments'
      '\nTool result: $result';
}

/// Converts stored chat messages into the `{role, content}` list sent to the
/// model: non-empty user/assistant messages plus formatted tool messages.
List<Map<String, String>> conversationMessagesForRequest(
  List<Map<String, dynamic>> chatMessages,
) {
  final result = <Map<String, String>>[];
  for (final m in chatMessages) {
    final role = (m['role'] as String? ?? '').toLowerCase();
    final content = (m['content'] as String? ?? '').trim();
    if (role == 'user') {
      if (content.isEmpty) continue;
      result.add({'role': 'user', 'content': content});
    } else if (role == 'assistant') {
      if (content.isEmpty) continue;
      result.add({'role': 'assistant', 'content': content});
    } else if (role == 'tool') {
      result.add({'role': 'tool', 'content': formatToolMessageForPrompt(m)});
    }
  }
  return result;
}

/// Renders a single chat message (plus its tool calls) for the full chat log.
String formatChatMessageLogEntry(Map<String, dynamic> msg) {
  final buf = StringBuffer();
  final role = msg['role'] ?? 'unknown';
  final content = msg['content'] as String? ?? '';
  buf.writeln('--- [$role] ---');
  buf.writeln(content);
  final toolCalls = msg['toolCalls'] as List<dynamic>?;
  if (toolCalls != null && toolCalls.isNotEmpty) {
    for (final tc in toolCalls) {
      if (tc is Map) {
        buf.writeln('  [tool] ${tc['toolName']}(${tc['arguments']})');
        if (tc['result'] != null) buf.writeln('  [result] ${tc['result']}');
      }
    }
  }
  return buf.toString();
}

/// Renders a single raw LLM debug session for the full chat log.
String formatDebugSessionLogEntry(Map<String, dynamic> dbg) {
  final buf = StringBuffer();
  buf.writeln('User: ${dbg['userMessage'] ?? ''}');
  if (dbg['error'] != null) buf.writeln('ERROR: ${dbg['error']}');
  final resp = dbg['response'] as String? ?? '';
  if (resp.isNotEmpty) {
    buf.writeln('Response: ${resp.substring(0, resp.length.clamp(0, 500))}');
  }
  return buf.toString();
}

/// Builds the full text copied by "Copy chat log": all chat messages plus any
/// in-memory LLM debug sessions.
String buildFullChatLogsText({
  required List<Map<String, dynamic>> messages,
  required List<Map<String, dynamic>> debugSessions,
}) {
  final buf = StringBuffer();
  buf.writeln('=== YoLoIT Chat Logs ===');
  buf.writeln('Messages: ${messages.length}');
  buf.writeln('');
  for (final msg in messages) {
    buf.write(formatChatMessageLogEntry(msg));
    buf.writeln('');
  }
  if (debugSessions.isNotEmpty) {
    buf.writeln('=== LLM Debug Sessions ===');
    for (final dbg in debugSessions) {
      buf.write(formatDebugSessionLogEntry(dbg));
      buf.writeln('');
    }
  }
  return buf.toString();
}

/// Terminal command that resets the saved macOS microphone decision for the
/// given bundle identifier.
String microphonePermissionResetCommand(String bundleId) =>
    'tccutil reset Microphone $bundleId';

/// Body text of the microphone permission hint dialog.
String buildMicrophonePermissionHintText({
  required String appName,
  required String bundleId,
  required String status,
}) {
  final resetCommand = microphonePermissionResetCommand(bundleId);
  return 'YoLoIT needs microphone access to record audio for local ASR.\n\n'
      'App shown to macOS: $appName\n'
      'Bundle id: $bundleId\n'
      'macOS status: $status\n\n'
      'If the system prompt does not appear, macOS has already saved a decision for this exact debug bundle. '
      'Open Privacy & Security → Microphone and enable $appName. If it is missing from the list, reset the saved decision and press Request again:\n\n'
      '$resetCommand';
}
