import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class CodeSnippetPlugin extends BoardPanelPlugin {
  const CodeSnippetPlugin();

  static const String kTypeId = 'board.code.snippet';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Code Snippet';

  @override
  IconData get icon => Icons.code_outlined;

  @override
  Color get accentColor => const Color(0xFF10B981);

  @override
  Size get defaultSize => const Size(480, 300);

  @override
  Map<String, dynamic> get initialState => {'code': '', 'language': 'dart'};

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _CodeSnippetPanelContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

const _kLanguages = [
  'dart', 'python', 'javascript', 'typescript',
  'bash', 'json', 'yaml', 'sql', 'kotlin', 'swift',
];

Mode _modeFor(String lang) => switch (lang) {
  'dart'       => dart,
  'python'     => python,
  'javascript' => javascript,
  'typescript' => typescript,
  'bash'       => bash,
  'json'       => json,
  'yaml'       => yaml,
  'sql'        => sql,
  'kotlin'     => kotlin,
  'swift'      => swift,
  _            => dart,
} as Mode;

class _CodeSnippetPanelContent extends StatefulWidget {
  const _CodeSnippetPanelContent({
    required this.panel,
    required this.renderContext,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_CodeSnippetPanelContent> createState() =>
      _CodeSnippetPanelContentState();
}

class _CodeSnippetPanelContentState extends State<_CodeSnippetPanelContent> {
  static const Color _accent = Color(0xFF10B981);

  late CodeController _controller;
  late String _language;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _language = widget.panel.state['language'] as String? ?? 'dart';
    _controller = CodeController(
      text: widget.panel.state['code'] as String? ?? '',
      language: _modeFor(_language),
    );
  }

  @override
  void didUpdateWidget(_CodeSnippetPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCode = widget.panel.state['code'] as String? ?? '';
    final newLang = widget.panel.state['language'] as String? ?? 'dart';
    if (newCode != _controller.text) {
      _controller.text = newCode;
    }
    if (newLang != _language) {
      setState(() {
        _language = newLang;
        _controller.language = _modeFor(_language);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveCode(String code) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'code': code,
      'language': _language,
    });
  }

  void _setLanguage(String lang) {
    setState(() {
      _language = lang;
      _controller.language = _modeFor(lang);
    });
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'code': _controller.text,
      'language': lang,
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.08),
            border: Border(
              bottom: BorderSide(color: _accent.withOpacity(0.15)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.code, size: 14, color: Color(0xFF10B981)),
              const SizedBox(width: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _language,
                  isDense: true,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                  items: _kLanguages
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => v != null ? _setLanguage(v) : null,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _copied ? Icons.check : Icons.copy,
                  size: 14,
                  color: _copied ? Colors.greenAccent : const Color(0xFF94A3B8),
                ),
                tooltip: _copied ? 'Copied!' : 'Copy code',
                onPressed: _copy,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        // Editor
        Expanded(
          child: CodeTheme(
            data: CodeThemeData(styles: atomOneDarkTheme),
            child: SingleChildScrollView(
              child: CodeField(
                controller: _controller,
                textStyle: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                onChanged: _saveCode,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
