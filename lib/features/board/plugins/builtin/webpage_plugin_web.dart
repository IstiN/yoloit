// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin_base.dart';

class WebpagePlugin extends WebpagePluginBase {
  const WebpagePlugin();

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
  static final Set<String> _registeredViewTypes = {};
  static final Map<String, html.IFrameElement> _iframes = {};

  late final TextEditingController _urlCtrl;
  late final FocusNode _urlFocusNode;

  String get _viewType => 'webpage-panel-${widget.panel.id}';

  @override
  void initState() {
    super.initState();
    final savedUrl = widget.panel.state['url'] as String? ?? '';
    _urlCtrl = TextEditingController(text: savedUrl);
    _urlFocusNode = FocusNode();
    _urlFocusNode.addListener(_onUrlFocusChanged);
    if (!_registeredViewTypes.contains(_viewType)) {
      _registeredViewTypes.add(_viewType);
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%';
          final url = widget.panel.state['url'] as String? ?? '';
          if (url.isNotEmpty) {
            iframe.src = _normalizeUrl(url);
          }
          _iframes[_viewType] = iframe;
          return iframe;
        },
      );
    }
  }

  void _onUrlFocusChanged() {
    final iframe = _iframes[_viewType];
    if (iframe == null) return;
    // Disable pointer events on the iframe while the URL text field is focused
    // so that the platform view does not steal taps/keyboard from Flutter.
    iframe.style.pointerEvents = _urlFocusNode.hasFocus ? 'none' : 'auto';
  }

  @override
  void didUpdateWidget(covariant _WebpageWebContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final url = widget.panel.state['url'] as String? ?? '';
    final oldUrl = oldWidget.panel.state['url'] as String? ?? '';
    if (url != oldUrl && url.isNotEmpty) {
      final iframe = _iframes[_viewType];
      if (iframe != null) {
        iframe.src = _normalizeUrl(url);
      }
    }
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    _urlCtrl.dispose();
    _iframes.remove(_viewType);
    super.dispose();
  }

  void _openUrl(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    html.window.open(_normalizeUrl(normalized), '_blank');
  }

  void _saveUrl(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    _urlFocusNode.unfocus();
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'url': normalized,
    });
  }

  String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
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
                  focusNode: _urlFocusNode,
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
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _saveUrl(_urlCtrl.text),
                icon: Icon(Icons.check, color: colors.accentBlue),
                tooltip: 'Load URL',
              ),
              IconButton(
                onPressed: () => _openUrl(url),
                icon: Icon(Icons.open_in_new, color: colors.accentBlue),
                tooltip: 'Open in new tab',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (url.isNotEmpty)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: HtmlElementView(viewType: _viewType),
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
