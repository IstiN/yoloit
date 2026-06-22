import 'dart:convert';

import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Max characters of panel content to include in the assistant context.
const _maxContentChars = 2000;

/// Max rows from a table/kanban to include in the context.
const _maxRows = 10;

/// Max terminal output lines to include in the context.
const _terminalOutputLimit = 30;

/// Builds a Markdown summary of a panel for injection into the assistant
/// system prompt.
///
/// Uses the matching [PanelCliHandler] for content and supported actions,
/// and fetches extra live data (e.g. terminal output) when available.
Future<String> buildFocusPanelSummary(
  BoardPanelInstance panel, {
  String? typeName,
}) async {
  final handler = CliServer.instance.handlerFor(panel.type);
  final resolvedTypeName = typeName ?? panel.type;
  final content = handler?.getContent(panel);
  final actions = handler?.supportedActions ?? const <String>[];
  final actionHelp = handler?.actionHelp ?? const {};

  final actionOutput = await _fetchActionOutput(handler, panel);
  final formattedContent = _formatContent(
    panel.type,
    content,
    actionOutput,
  );
  final guidance = _typeGuidance(panel.type);

  final buffer = StringBuffer()
    ..writeln('### Focus panel')
    ..writeln()
    ..writeln('- id: `${panel.id}`')
    ..writeln('- title: ${panel.title}')
    ..writeln('- type: ${panel.type}')
    ..writeln('- typeName: $resolvedTypeName')
    ..writeln('- bounds: x=${panel.bounds.x}, y=${panel.bounds.y}, ')
    ..writeln('  width=${panel.bounds.width}, height=${panel.bounds.height}')
    ..writeln('- zIndex: ${panel.zIndex}')
    ..writeln('- locked: ${panel.locked}')
    ..writeln('- pinned: ${panel.pinned}')
    ..writeln('- hidden: ${panel.hidden}')
    ..writeln()
    ..writeln('#### Content / state')
    ..writeln(formattedContent);

  if (actions.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('#### Supported actions')
      ..writeln(actions.map((a) => '- `$a`').join('\n'));
  }

  if (actionHelp.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('#### Action help')
      ..writeln(
        actionHelp.entries
            .map((e) => '- `${e.key}`: ${e.value.description}')
            .join('\n'),
      );
  }

  if (guidance.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('#### How to work with this panel')
      ..writeln(guidance);
  }

  return buffer.toString().trim();
}

/// Fetches live, expensive output for panels that expose an `output` action
/// (e.g. terminals). Returns `null` when not applicable or unavailable.
Future<Map<String, dynamic>?> _fetchActionOutput(
  PanelCliHandler? handler,
  BoardPanelInstance panel,
) async {
  if (handler == null) return null;
  if (!handler.supportedActions.contains('output')) return null;
  try {
    final result = await handler.handleAction(
      'output',
      {'limit': _terminalOutputLimit},
      panel,
    );
    if (!result.ok || result.data == null) return null;
    return result.data;
  } catch (_) {
    return null;
  }
}

/// Formats panel content in a type-friendly way.
String _formatContent(
  String typeId,
  Map<String, dynamic>? content,
  Map<String, dynamic>? actionOutput,
) {
  if (content == null || content.isEmpty) {
    return '(no content available)';
  }

  switch (typeId) {
    case 'board.note.markdown':
      return _formatNoteContent(content);
    case 'board.terminal':
      return _formatTerminalContent(content, actionOutput);
    case 'board.table':
      return _formatTableContent(content);
    case 'board.kanban':
      return _formatKanbanContent(content);
    case 'board.run_configs':
    case 'board.run':
      return _formatRunConfigsContent(content);
    default:
      return _safeJsonEncode(content);
  }
}

String _formatNoteContent(Map<String, dynamic> content) {
  final markdown = content['markdown'] as String? ?? '';
  if (markdown.isEmpty) return '(empty note)';
  return '```markdown\n${_truncate(markdown)}\n```';
}

String _formatTerminalContent(
  Map<String, dynamic> content,
  Map<String, dynamic>? actionOutput,
) {
  final config = content['config'] as Map<String, dynamic>? ?? {};
  final buffer = StringBuffer()
    ..writeln('**Configuration:**')
    ..writeln('```json')
    ..writeln(_safeJsonEncode(config, maxChars: 600))
    ..writeln('```');
  final lines = actionOutput?['lines'] as List<dynamic>?;
  if (lines != null && lines.isNotEmpty) {
    final text = lines.map((l) => '$l').join('\n');
    buffer
      ..writeln()
      ..writeln('**Recent output (${lines.length} lines):**')
      ..writeln('```')
      ..writeln(_truncate(text, maxChars: 1200))
      ..writeln('```');
  }
  return buffer.toString().trim();
}

String _formatTableContent(Map<String, dynamic> content) {
  final columns = _asMapList(content['columns']);
  final rows = _asMapList(content['rows']);
  if (columns.isEmpty) return '(empty table)';

  final headers = columns.map((c) {
    final title = c['title'] as String?;
    final id = c['id'] as String?;
    return title ?? id ?? '?';
  }).toList();
  final buffer = StringBuffer()
    ..writeln('| ${headers.join(' | ')} |')
    ..writeln('| ${headers.map((_) => '---').join(' | ')} |');

  for (var i = 0; i < rows.length && i < _maxRows; i++) {
    final row = rows[i];
    final cells = columns
        .map((c) {
          final id = c['id'] as String?;
          final title = c['title'] as String?;
          final key = id ?? title ?? '';
          return row[key] as String? ?? '';
        })
        .toList();
    buffer.writeln('| ${cells.join(' | ')} |');
  }
  if (rows.length > _maxRows) {
    buffer.writeln('*(+${rows.length - _maxRows} rows omitted)*');
  }
  return buffer.toString().trim();
}

String _formatKanbanContent(Map<String, dynamic> content) {
  final columns = _asMapList(content['columns']);
  if (columns.isEmpty) return '(empty kanban)';

  final buffer = StringBuffer();
  for (final column in columns) {
    final title = column['title'] as String? ?? 'Untitled';
    final cards = _asMapList(column['cards']);
    buffer.writeln('- **$title** (${cards.length})');
    for (final card in cards) {
      final text =
          card['text'] as String? ??
          card['title'] as String? ??
          card['id'] as String? ??
          'card';
      buffer.writeln('  - $text');
    }
  }
  return buffer.toString().trim();
}

String _formatRunConfigsContent(Map<String, dynamic> content) {
  final configs = _asMapList(content['configurations']);
  final sessions = _asMapList(content['sessions']);
  final buffer = StringBuffer()
    ..writeln('**Group:** ${content['group'] ?? 'default'}')
    ..writeln('**Workspace:** ${content['workspacePath'] ?? ''}')
    ..writeln('**Configurations:**');
  for (final config in configs) {
    final name = config['name'] as String? ?? 'unnamed';
    final command = config['command'] as String? ?? '';
    buffer.writeln('- `$name`: $command');
  }
  if (sessions.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('**Sessions:**');
    for (final session in sessions) {
      final sessionConfig = session['config'] as Map<String, dynamic>?;
      final sessionName = sessionConfig?['name'] as String? ?? 'unnamed';
      final status = session['status'] as String? ?? 'unknown';
      buffer.writeln('- `$sessionName` ($status)');
    }
  }
  return buffer.toString().trim();
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList();
}

String _truncate(String text, {int maxChars = _maxContentChars}) {
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

String _safeJsonEncode(
  Object? value, {
  int maxChars = _maxContentChars,
}) {
  if (value == null) return '';
  try {
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    if (encoded.length <= maxChars) return encoded;
    return '${encoded.substring(0, maxChars)}…';
  } catch (_) {
    return '$value';
  }
}

/// Type-specific instructions for the assistant.
String _typeGuidance(String typeId) {
  switch (typeId) {
    case 'board.note.markdown':
      return '''
- Use `yoloit_do <board> <panel> set '{"text":"..."}'` to replace the note content.
- Use `yoloit_do <board> <panel> append '{"text":"..."}'` to append text.
- When the user says "добавь", "append", "write into it", target this panel.'''.trim();
    case 'board.terminal':
      return '''
- Read recent output with `yoloit_do <board> <panel> output '{"limit": 30}'`.
- Send input with `yoloit_do <board> <panel> input '{"text":"..."}'` if supported.
- Change working directory with `yoloit_do <board> <panel> set-dir '{"dir":"/path"}'`.'''.trim();
    case 'board.table':
      return '''
- Add rows with `yoloit_do <board> <panel> add-row '{"row":{...}}'`.
- Update rows with `yoloit_do <board> <panel> update-row '{"rowId":"...","row":{...}}'`.
- Column ids are shown in the content above.'''.trim();
    case 'board.kanban':
      return '''
- Add cards with `yoloit_do <board> <panel> add-card '{"column":"Column title","text":"..."}'`.
- Move cards with `yoloit_do <board> <panel> move-card '{"cardId":"...","column":"..."}'`.
- Use exact column titles from the content above.'''.trim();
    case 'board.run_configs':
    case 'board.run':
      return '''
- Run a config with `yoloit_do <board> <panel> run '{"name":"..."}'`.
- Read output with `yoloit_do <board> <panel> output '{"name":"...","limit":30}'`.
- Stop with `yoloit_do <board> <panel> stop '{"name":"..."}'`.'''.trim();
    default:
      return '''
- Discover available actions with `yoloit_panel_help <board> <panel>`.
- Execute an action with `yoloit_do <board> <panel> <action> '{...}'`.'''.trim();
  }
}
