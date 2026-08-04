import 'dart:convert';
import 'dart:typed_data';

import 'package:local_models_flutter/runtime/embedded_gemma_tool_calls.dart';
import 'package:yoloit/core/utils/json_utils.dart';
import 'package:yoloit/core/utils/string_utils.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_tool_errors.dart';
import 'package:yoloit/features/board/model/board_models.dart';

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

// ── Send/voice phase helpers (extracted verbatim from the widget state) ──────

/// Picks the text stored in the LLM history and the text shown in the chat
/// bubble for an outgoing message.
({String text, String displayContent}) resolveOutgoingMessageContent({
  required String rawText,
  required bool hasAudioContent,
  required bool mirrorToOverlay,
}) {
  // When sending audio directly to LLM: no voice-prefix, show mic icon in chat.
  // For transcribed voice: prepend ASR context for the LLM.
  final String text;
  final String displayContent;
  if (hasAudioContent) {
    // Audio sent directly — display mic icon, no prefix for LLM history
    // (audio IS the content).
    displayContent = '🎤 Voice message';
    text = displayContent; // stored in history for display only
  } else if (mirrorToOverlay) {
    text =
        '[Voice message — transcribed via speech recognition, '
        'may contain recognition errors]\n$rawText';
    displayContent = text;
  } else {
    text = rawText;
    displayContent = text;
  }
  return (text: text, displayContent: displayContent);
}

/// Replaces the last matching `⏳ running:` overlay tool log entry in place
/// with [doneEntry] (so the overlay shows ✅/❌ in-place rather than showing
/// both states at once), or appends it when no running entry exists.
void upsertOverlayToolLogEntry(List<String> overlayToolLogs, String doneEntry) {
  final runningIdx = overlayToolLogs.lastIndexWhere(
    (e) => e.startsWith('⏳ running:'),
  );
  if (runningIdx >= 0) {
    overlayToolLogs[runningIdx] = doneEntry;
  } else {
    overlayToolLogs.add(doneEntry);
  }
}

/// Records the tool start timestamp under the function name, the toolCallId,
/// AND the CLI command so the lookup in onToolCompleted (keyed by CLI
/// command) succeeds.
void recordPendingToolStarts(
  Map<String, String> pendingToolStarts, {
  required String toolName,
  required String toolCallId,
  required String? cliCommand,
}) {
  final now = DateTime.now().toIso8601String();
  pendingToolStarts[toolName] = now;
  pendingToolStarts[toolCallId] = now;
  if (cliCommand != null) pendingToolStarts[cliCommand] = now;
}

/// Debug-session model info entries for a cloud provider config.
Map<String, String> cloudModelDebugInfo({
  required String model,
  required String providerName,
  required String baseUrl,
}) => {'modelId': model, 'modelProvider': providerName, 'modelBaseUrl': baseUrl};

/// Computes the overlay assistant status from the recording/transcribing/
/// generating flags when no status was forced.
String computeAssistantOverlayStatus({
  String? forcedStatus,
  required bool isRecordingMic,
  required bool isTranscribingMic,
  required bool isGeneratingReply,
  required bool receivedAssistantToken,
  required String draft,
}) =>
    forcedStatus ??
    (isRecordingMic
        ? 'listening'
        : isTranscribingMic
        ? 'processing'
        : isGeneratingReply
        ? (receivedAssistantToken ? 'responding' : 'thinking')
        : draft.isNotEmpty
        ? 'ready'
        : 'idle');

/// Strips the voice prefix from a user message for display (the prefix is
/// kept in the LLM context but hidden in the UI).
String assistantDisplayContent({required bool isUser, required String content}) =>
    isUser && content.startsWith('[Voice message')
        ? content.substring(content.indexOf('\n') + 1).trim()
        : content;

/// Derives a short session name from the first user message.
String deriveAssistantSessionName(List<Map<String, dynamic>> messages) {
  final firstUserMsg = messages.firstWhere(
    (m) => m['role'] == 'user',
    orElse: () => <String, dynamic>{},
  );
  final firstText = (firstUserMsg['content'] as String? ?? '').trim();
  final rawName =
      firstText.length > 60 ? firstText.substring(0, 60) : firstText;
  return rawName.isEmpty ? 'Yolo session' : rawName.replaceAll('\n', ' ');
}

/// One line per board, marking the current one — for the LLM context.
String availableBoardsSummary(
  List<BoardDocument> boards,
  String? currentBoardId,
) => boards
    .map((board) {
      final marker = board.id == currentBoardId ? ' (current)' : '';
      return '- ${board.name} [${board.id}]$marker';
    })
    .join('\n');

/// One line per panel of [board], sorted by descending z-index — for the
/// LLM context. Empty string when there is no active board.
String boardPanelsSummary(BoardDocument? board) {
  if (board == null) return '';
  final panels = [...board.panels]
    ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
  return panels
      .map((panel) => '- ${panel.title} [${panel.type}] (${panel.id})')
      .join('\n');
}

/// Rough token estimate: ~4 characters per token.
int estimateTokenCount(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) return 0;
  return (normalized.length / 4).ceil();
}

/// Formats an exception thrown during send for display in the chat bubble.
String formatAssistantError(Object error) {
  final raw = error.toString();
  if (raw.contains('flm_dispatch_json')) {
    return 'Local model runtime mismatch: missing symbol "flm_dispatch_json". '
        'Please update/reinstall the selected local model runtime in Settings → AI Models, then restart YoLoIT.';
  }
  return 'Error: $raw';
}

/// Computes the ASR mode from the voice settings flags.
String resolveAsrMode({
  required bool useCloudAsr,
  required bool useChatModelForCloudAsr,
}) =>
    !useCloudAsr
        ? 'local'
        : useChatModelForCloudAsr
        ? 'direct_audio'
        : 'cloud';

/// Merges a fresh transcript into the current input field text.
String mergeTranscriptIntoInput(String currentText, String transcript) {
  final current = currentText.trim();
  return current.isEmpty ? transcript : '$current ${transcript.trim()}';
}

/// Builds the `_pendingAsrDebug` map recorded after a transcription run.
Map<String, dynamic> buildAsrDebugInfo({
  required String mode,
  required String status,
  required String startedAt,
  required String completedAt,
  required int durationMs,
  required int transcriptChars,
  String? resolvedModel,
  String? providerName,
  String? error,
}) => {
  'mode': mode,
  'status': status,
  'startedAt': startedAt,
  'completedAt': completedAt,
  'durationMs': durationMs,
  'transcriptChars': transcriptChars,
  if (resolvedModel != null) 'model': resolvedModel,
  if (providerName != null) 'provider': providerName,
  if (error != null) 'error': error,
};

/// Builds the companion metadata JSON persisted next to a saved ASR sample —
/// useful for replay benchmarks.
Map<String, dynamic> buildAsrSampleMetadata({
  required String recordedAt,
  required String completedAt,
  required int durationMs,
  required String asrMode,
  required String asrStatus,
  required String transcript,
  required int transcriptChars,
  String? resolvedModel,
  String? providerName,
  String? error,
}) => {
  'recordedAt': recordedAt,
  'completedAt': completedAt,
  'durationMs': durationMs,
  'asrMode': asrMode,
  'asrStatus': asrStatus,
  if (resolvedModel != null) 'asrModel': resolvedModel,
  if (providerName != null) 'asrProvider': providerName,
  'transcript': transcript,
  'transcriptChars': transcriptChars,
  if (error != null) 'error': error,
};

/// Builds a standard WAV file from raw PCM-16bit mono 16kHz bytes.
Uint8List buildWavFromPcm(Uint8List pcm) {
  const sampleRate = 16000;
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  const blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = pcm.length;
  final fileSize = 36 + dataSize; // RIFF chunk size

  final header = ByteData(44);
  // RIFF chunk
  header.setUint8(0, 0x52); // R
  header.setUint8(1, 0x49); // I
  header.setUint8(2, 0x46); // F
  header.setUint8(3, 0x46); // F
  header.setUint32(4, fileSize, Endian.little);
  header.setUint8(8, 0x57); // W
  header.setUint8(9, 0x41); // A
  header.setUint8(10, 0x56); // V
  header.setUint8(11, 0x45); // E
  // fmt chunk
  header.setUint8(12, 0x66); // f
  header.setUint8(13, 0x6D); // m
  header.setUint8(14, 0x74); // t
  header.setUint8(15, 0x20); // (space)
  header.setUint32(16, 16, Endian.little); // chunk size = 16 for PCM
  header.setUint16(20, 1, Endian.little); // PCM = 1
  header.setUint16(22, numChannels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  // data chunk
  header.setUint8(36, 0x64); // d
  header.setUint8(37, 0x61); // a
  header.setUint8(38, 0x74); // t
  header.setUint8(39, 0x61); // a
  header.setUint32(40, dataSize, Endian.little);

  final wav = Uint8List(44 + dataSize);
  wav.setRange(0, 44, header.buffer.asUint8List());
  wav.setRange(44, 44 + dataSize, pcm);
  return wav;
}
