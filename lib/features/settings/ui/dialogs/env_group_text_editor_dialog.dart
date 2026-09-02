import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/languages/ini.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// Opens a full-screen editor that shows [group]'s variables as a `.env`
/// file with syntax highlighting.
///
/// Returns the parsed key/value map when the user taps Apply, or `null` when
/// the editor was dismissed with Cancel.
Future<Map<String, String>?> showEnvGroupTextEditor(
  BuildContext context, {
  required GlobalEnvGroup group,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EnvGroupTextEditorDialog(group: group),
  );
}

/// Full-screen `.env` text editor for a single env group.
///
/// Values are serialized with [GlobalEnvGroupsService.encodeEnvContent] and
/// parsed back with [GlobalEnvGroupsService.parseEnvContent] on Apply, so the
/// round trip stays consistent with `.env` file import (quoting, escapes and
/// duplicate-key handling behave the same).
class EnvGroupTextEditorDialog extends StatefulWidget {
  const EnvGroupTextEditorDialog({super.key, required this.group});

  final GlobalEnvGroup group;

  @override
  State<EnvGroupTextEditorDialog> createState() =>
      _EnvGroupTextEditorDialogState();
}

class _EnvGroupTextEditorDialogState extends State<EnvGroupTextEditorDialog> {
  final _service = GlobalEnvGroupsService.instance;
  late final CodeController _controller;
  late final String _initialText;
  late int _variableCount;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _initialText = _service.encodeEnvContent(widget.group.values);
    _variableCount = widget.group.values.length;
    // The `ini` mode gives .env-friendly highlighting: `#` comments, `KEY=`
    // names, quoted strings, numbers and true/false literals.
    _controller = CodeController(text: _initialText, language: ini);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final count = _service.parseEnvContent(text).length;
    final dirty = text != _initialText;
    if (count == _variableCount && dirty == _dirty) return;
    setState(() {
      _variableCount = count;
      _dirty = dirty;
    });
  }

  void _apply() {
    Navigator.of(context).pop(_service.parseEnvContent(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: Text('Edit as .env — ${widget.group.name}'),
          actions: [
            IconButton(
              onPressed: _dirty ? _reset : null,
              tooltip: 'Reset to saved values',
              icon: const Icon(Icons.restart_alt, size: 20),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 12),
              child: FilledButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Apply'),
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colors.surfaceElevated,
              child: Text(
                '$_variableCount variable(s) · One KEY=VALUE per line. '
                'Lines starting with # are comments and are not saved.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ),
            Expanded(
              child: CodeTheme(
                data: CodeThemeData(styles: atomOneDarkTheme),
                child: RepaintBoundary(
                  child: CodeField(
                    controller: _controller,
                    expands: true,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                    background: colors.background,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reset() {
    _controller.text = _initialText;
  }
}
