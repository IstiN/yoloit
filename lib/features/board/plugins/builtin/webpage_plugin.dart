import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class WebpagePlugin extends BoardPanelPlugin {
  const WebpagePlugin();

  static const String kTypeId = 'board.webpage';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Webpage';

  @override
  IconData get icon => Icons.language_outlined;

  @override
  Color get accentColor => const Color(0xFF0EA5E9);

  @override
  Size get defaultSize => const Size(700, 500);

  @override
  Map<String, dynamic> get initialState => {'url': '', 'title': '', 'favicon': ''};

  @override
  bool get hasEditor => false;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _WebpageContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _WebpageContent extends StatefulWidget {
  const _WebpageContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_WebpageContent> createState() => _WebpageContentState();
}

class _WebpageContentState extends State<_WebpageContent> {
  static const Color _accent = Color(0xFF0EA5E9);

  late final TextEditingController _urlCtrl;
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final savedUrl = widget.panel.state['url'] as String? ?? '';
    _urlCtrl = TextEditingController(text: savedUrl);
    if (savedUrl.isNotEmpty) {
      _initController(savedUrl);
    }
  }

  @override
  void didUpdateWidget(_WebpageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newUrl = widget.panel.state['url'] as String? ?? '';
    final oldUrl = oldWidget.panel.state['url'] as String? ?? '';
    if (newUrl != oldUrl && newUrl.isNotEmpty) {
      _urlCtrl.text = newUrl;
      if (_controller == null) {
        _initController(newUrl);
      } else {
        _controller!.loadRequest(Uri.parse(newUrl));
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _initController(String url) {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
    setState(() {});
  }

  String get _currentUrl => widget.panel.state['url'] as String? ?? '';

  String _hostname(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isEmpty ? url : uri.host;
    } catch (_) {
      return url;
    }
  }

  String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  void _commit() {
    final url = _normalizeUrl(_urlCtrl.text);
    _urlCtrl.text = url;
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'url': url,
      'title': url.isEmpty ? '' : _hostname(url),
    });
    if (url.isNotEmpty) {
      if (_controller == null) {
        _initController(url);
      } else {
        _controller!.loadRequest(Uri.parse(url));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _currentUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact URL bar (~32-36px height)
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              children: [
                const Icon(Icons.link, size: 14, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'https://example.com',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(
                          color: Color(0xFF0EA5E9),
                          width: 1.5,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                const SizedBox(width: 4),
                if (_controller != null) ...[
                  _NavBtn(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onPressed: () => _controller?.goBack(),
                  ),
                  _NavBtn(
                    icon: Icons.arrow_forward,
                    tooltip: 'Forward',
                    onPressed: () => _controller?.goForward(),
                  ),
                  _NavBtn(
                    icon: Icons.refresh,
                    tooltip: 'Reload',
                    onPressed: () => _controller?.reload(),
                  ),
                ],
                if (url.isNotEmpty)
                  _NavBtn(
                    icon: Icons.open_in_browser,
                    tooltip: 'Open in Browser',
                    onPressed: () => PlatformLauncher.instance.openUrl(url),
                  ),
                SizedBox(
                  height: 28,
                  child: FilledButton(
                    onPressed: _commit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 28),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Go'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // Content area
        Expanded(
          child: url.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.language,
                        size: 40,
                        color: _accent.withOpacity(0.4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter a URL above',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : _controller != null
              // MouseRegion releases Flutter keyboard focus so WKWebView
              // can receive native keyboard input (macOS KVO/firstResponder).
              ? MouseRegion(
                  onEnter: (_) => FocusScope.of(context).unfocus(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: WebViewWidget(controller: _controller!),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: const Color(0xFF94A3B8)),
        ),
      ),
    );
  }
}
