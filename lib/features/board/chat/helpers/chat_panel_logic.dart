import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Pure, side-effect-free logic extracted from `ChatPanelWidget` so it can be
/// unit-tested directly: /yolo panel summaries, changed-file extraction from
/// tool results, and sub-agent log markdown rendering.

/// Matches /yolo panel mentions of the form `[panel:title|panelId]`.
final RegExp yoloMentionRe = RegExp(r'\[panel:([^|\]]+)\|([^|\]]+)\]');

/// Tool names whose results typically describe a file mutation.
const Set<String> fileMutationToolNames = {
  'create',
  'edit',
  'apply_patch',
  'write_file',
  'delete_file',
  'move_file',
  'rename',
};

/// Argument keys whose string values may hold a file path.
const Set<String> _pathArgumentKeys = {
  'path',
  'file',
  'filepath',
  'target',
  'destination',
  'newpath',
  'oldpath',
  'from',
  'to',
};

final RegExp _changedFilePathRe = RegExp(r'(/\S+)');

// ── /yolo panel summaries ───────────────────────────────────────────────────

/// Builds a concise textual summary of a panel to inject into the user
/// message when /yolo mentions are used.
String summarizePanelForYolo(BoardPanelInstance panel) {
  final buffer = StringBuffer();
  buffer.writeln('- ${panel.title} [${panel.type}] (id: ${panel.id})');
  switch (panel.type) {
    case 'board.note.markdown':
      _appendMarkdownSummary(buffer, panel.state);
    case 'board.kanban':
      _appendKanbanSummary(buffer, panel.state);
    case 'board.file.preview':
      _appendFilePreviewSummary(buffer, panel.state);
    case 'board.chat':
      buffer.writeln('  AI chat panel');
    default:
      _appendGenericStateKeys(buffer, panel.state);
  }
  return buffer.toString().trimRight();
}

void _appendMarkdownSummary(StringBuffer buffer, Map<String, dynamic> state) {
  final markdown = (state['markdown'] as String? ?? '').trim();
  if (markdown.isEmpty) return;
  final preview =
      markdown.length > 500 ? '${markdown.substring(0, 500)}…' : markdown;
  buffer.writeln('  Markdown preview:\n$preview');
}

void _appendKanbanSummary(StringBuffer buffer, Map<String, dynamic> state) {
  final columns = (state['columns'] as List?)?.cast<String>() ?? [];
  final cards = (state['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  for (var i = 0; i < columns.length; i++) {
    final colCards =
        cards.where((c) => (c['columnIndex'] as int? ?? 0) == i).toList();
    if (colCards.isEmpty) continue;
    buffer.writeln('  ${columns[i]}:');
    for (final card in colCards) {
      final title = card['title'] as String? ?? '';
      if (title.isNotEmpty) buffer.writeln('    - $title');
    }
  }
}

void _appendFilePreviewSummary(
  StringBuffer buffer,
  Map<String, dynamic> state,
) {
  final path = state['path'] as String? ?? '';
  if (path.isNotEmpty) buffer.writeln('  File: $path');
}

void _appendGenericStateKeys(StringBuffer buffer, Map<String, dynamic> state) {
  final keys =
      state.keys
          .where((k) => k != 'config' && k != 'messages' && k != 'lastUsage')
          .toList();
  if (keys.isNotEmpty) {
    buffer.writeln('  State keys: ${keys.join(', ')}');
  }
}

/// Parses /yolo panel mentions, appends their summaries to [text], and
/// returns the enriched prompt. Also strips the bare `/yolo` trigger.
String injectYoloPanelContext(String text, BoardDocument? board) {
  final matches = yoloMentionRe.allMatches(text).toList();
  if (matches.isEmpty) return text;
  if (board == null) return text;

  final summaryBuffer = StringBuffer('\n\nReferenced board panels:\n');
  for (final match in matches) {
    final panelId = match.group(2)!;
    BoardPanelInstance? panel;
    for (final p in board.panels) {
      if (p.id == panelId) {
        panel = p;
        break;
      }
    }
    if (panel != null) {
      summaryBuffer.writeln(summarizePanelForYolo(panel));
    }
  }

  var userText = text.replaceAll(yoloMentionRe, '').trim();
  if (userText.startsWith('/yolo')) {
    userText = userText.substring(5).trim();
  } else if (userText.startsWith('.yolo')) {
    userText = userText.substring(5).trim();
  }
  if (userText.isEmpty) {
    return 'See the referenced board panels:${summaryBuffer.toString()}';
  }
  return '$userText${summaryBuffer.toString()}';
}

// ── Changed-file extraction ─────────────────────────────────────────────────

/// Extracts file paths mutated by a tool call, from both the free-text
/// [resultContent] and the structured [arguments].
List<String> extractChangedFiles({
  required String toolName,
  required String resultContent,
  Map<String, dynamic> arguments = const {},
}) {
  final loweredName = toolName.trim().toLowerCase();
  final loweredContent = resultContent.toLowerCase();
  final likelyMutation =
      fileMutationToolNames.contains(loweredName) ||
      loweredContent.contains('created file ') ||
      loweredContent.contains('updated with changes') ||
      loweredContent.contains('updated file') ||
      loweredContent.contains('deleted file');
  if (!likelyMutation) return const [];

  final found = <String>{};
  for (final match in _changedFilePathRe.allMatches(resultContent)) {
    final cleaned = normalizePathToken(match.group(1) ?? '');
    if (cleaned.isNotEmpty) found.add(cleaned);
  }

  _collectPathsFromDynamic(arguments, found);
  return found.toList()..sort();
}

void _collectPathsFromDynamic(
  dynamic value,
  Set<String> found, {
  String? key,
}) {
  if (value is String) {
    _collectPathString(value, found, key: key);
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) continue;
      _collectPathsFromDynamic(entry.value, found, key: entry.key as String);
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _collectPathsFromDynamic(item, found);
    }
  }
}

void _collectPathString(String value, Set<String> found, {String? key}) {
  final candidate = normalizePathToken(value);
  if (!candidate.startsWith('/')) return;
  if (key != null && !_pathArgumentKeys.contains(key.toLowerCase())) return;
  found.add(candidate);
}

/// Cleans a raw path token: strips surrounding quotes/backticks and trailing
/// punctuation. Returns an empty string when [raw] is not an absolute path.
String normalizePathToken(String raw) {
  var value = raw.trim();
  if (value.isEmpty || !value.startsWith('/')) return '';
  value = value.replaceAll(RegExp("^[`\"']+|[`\"']+\$"), '');
  value = value.replaceAll(RegExp(r'[),.;:!?]+$'), '');
  return value;
}

// ── Sub-agent log markdown ──────────────────────────────────────────────────

/// Renders the markdown content of a sub-agent log note panel.
String buildAgentMarkdown(SubAgentRunState? state) {
  if (state == null) return '';
  final buf = StringBuffer();
  buf.writeln('# 🤖 ${state.agentName}');
  if (state.agentDescription.isNotEmpty) {
    buf.writeln();
    buf.writeln('> ${state.agentDescription}');
  }
  buf.writeln();
  buf.writeln('---');
  buf.writeln();
  buf.writeln('```');
  for (final ev in state.events) {
    buf.writeln(_formatAgentEventLine(ev));
  }
  if (state.isRunning) {
    buf.writeln('...');
  }
  buf.writeln('```');
  buf.writeln();
  buf.writeln(state.isRunning ? '*Running…*' : '*Completed.*');
  return buf.toString();
}

String _formatAgentEventLine(SubAgentEvent ev) {
  final time =
      '${ev.timestamp.hour.toString().padLeft(2, '0')}:'
      '${ev.timestamp.minute.toString().padLeft(2, '0')}:'
      '${ev.timestamp.second.toString().padLeft(2, '0')}';
  switch (ev.type) {
    case 'tool_start':
      return '$time  ▶ ${ev.toolName}';
    case 'tool_complete':
      final preview =
          ev.content?.isNotEmpty == true ? '  → ${ev.content}' : '';
      return '$time  ✓ ${ev.toolName}$preview';
    case 'tool_error':
      return '$time  ✗ ${ev.toolName}';
    default: // message
      return '$time  » ${ev.content ?? ''}';
  }
}
