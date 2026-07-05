// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

final _webpageDefaultColors = AppColorScheme.fromAccent(Colors.lightBlue);

class WebpagePluginWeb extends BoardPanelPlugin {
  const WebpagePluginWeb();

  static const String kTypeId = 'board.webpage';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Webpage';

  @override
  IconData get icon => Icons.language_outlined;

  @override
  Color get accentColor => _webpageDefaultColors.accentBlue;

  @override
  Size get defaultSize => const Size(700, 500);

  @override
  Map<String, dynamic> get initialState => {
    'url': '',
    'title': '',
    'favicon': '',
  };

  @override
  bool get hasEditor => false;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _WebpageWebContent(panel: panel, renderContext: renderContext);
  }
}

class _WebpageWebContent extends StatefulWidget {
  const _WebpageWebContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_WebpageWebContent> createState() => _WebpageWebContentState();
}

class _WebpageWebContentState extends State<_WebpageWebContent> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    final savedUrl = widget.panel.state['url'] as String? ?? '';
    _urlCtrl = TextEditingController(text: savedUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _openUrl(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    final href = normalized.startsWith('http') ? normalized : 'https://$normalized';
    html.window.open(href, '_blank');
  }

  void _saveUrl(String url) {
    widget.renderContext.onUpdateState?.call({
      ...widget.panel.state,
      'url': url.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final url = widget.panel.state['url'] as String? ?? '';
    return Container(
      color: colors.background,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'https://example.com',
                    hintStyle: TextStyle(color: colors.textMuted),
                    isDense: true,
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (value) {
                    _saveUrl(value);
                    _openUrl(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _openUrl(_urlCtrl.text),
                icon: Icon(Icons.open_in_new, color: colors.accentBlue),
                tooltip: 'Open in new tab',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (url.isNotEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 48, color: colors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      url,
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _openUrl(url),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open in new tab'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accentBlue,
                        foregroundColor: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Text(
                  'Enter a URL above',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
