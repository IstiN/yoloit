import 'dart:convert';

import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Max characters of panel content to include in the assistant context.
const _maxContentChars = 2000;

/// Builds a Markdown summary of a panel for injection into the assistant
/// system prompt.
///
/// Uses the plugin registry for metadata and the matching [PanelCliHandler]
/// for content and supported actions, when available.
String buildFocusPanelSummary(
  BoardPanelInstance panel, {
  String? typeName,
}) {
  final handler = CliServer.instance.handlerFor(panel.type);
  final resolvedTypeName = typeName ?? panel.type;
  final content = handler?.getContent(panel);
  final contentJson = _safeJsonEncode(content);
  final actions = handler?.supportedActions ?? const <String>[];
  final actionHelp = handler?.actionHelp ?? const {};

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
    ..writeln(contentJson.isEmpty ? '(no content available)' : contentJson);

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
        actionHelp.entries.map((e) => '- `${e.key}`: ${e.value.description}').join('\n'),
      );
  }

  return buffer.toString().trim();
}

String _safeJsonEncode(Object? value) {
  if (value == null) return '';
  try {
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    if (encoded.length <= _maxContentChars) return '```json\n$encoded\n```';
    final truncated = '${encoded.substring(0, _maxContentChars)}…';
    return '```json\n$truncated\n```\n*(content truncated to $_maxContentChars chars)*';
  } catch (_) {
    return '```\n$value\n```';
  }
}
