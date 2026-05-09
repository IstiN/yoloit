import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class WebpagePlugin extends BoardPanelPlugin {
  const WebpagePlugin();

  static const String kTypeId = 'board.webpage';

  /// Shared controller cache so the board view can render WebViews
  /// outside the InteractiveViewer transform to avoid coordinate offset.
  static final Map<String, WebViewController> controllers = {};

  /// Desired CSS zoom per panel.  Updated by the WebView overlay,
  /// read by [onPageFinished] to re-inject zoom after navigation.
  static final Map<String, double> pendingCssZoom = {};

  /// Loading state per panel.  Set to true on page start, false
  /// after CSS zoom is applied in onPageFinished.  The overlay
  /// shows a white cover during loading to hide the flash of
  /// unzoomed content between page load and CSS zoom injection.
  static final Map<String, ValueNotifier<bool>> pageLoading = {};

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
  late final FocusNode _urlFocus;
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _urlFocus = FocusNode();
    final savedUrl = widget.panel.state['url'] as String? ?? '';
    _urlCtrl = TextEditingController(text: savedUrl);
    if (savedUrl.isNotEmpty) {
      _initController(savedUrl);
    } else {
      // Auto-focus URL field when panel is new (no URL yet)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _urlFocus.requestFocus();
      });
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
    WebpagePlugin.controllers.remove(widget.panel.id);
    WebpagePlugin.pendingCssZoom.remove(widget.panel.id);
    WebpagePlugin.pageLoading.remove(widget.panel.id)?.dispose();
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _initController(String url) {
    final panelId = widget.panel.id;
    final loading = WebpagePlugin.pageLoading.putIfAbsent(
      panelId,
      () => ValueNotifier<bool>(false),
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            // Hide WebView content while the new page loads to prevent
            // the flash of unzoomed content.
            loading.value = true;
          },
          onPageFinished: (_) {
            // Re-inject CSS zoom after every page load.  Navigation
            // replaces the DOM so the previous zoom style is lost.
            final zoom = WebpagePlugin.pendingCssZoom[panelId];
            if (zoom != null) {
              _controller!.runJavaScript(
                "document.documentElement.style.zoom='${zoom.toStringAsFixed(4)}'",
              );
            }
            // Intercept target="_blank" links and window.open → route
            // to Flutter via YoloNewTab channel.
            _controller!.runJavaScript('''
(function(){
  if(window.__yoloNewTabSetup) return;
  window.__yoloNewTabSetup=true;
  window.open=function(u){if(u)YoloNewTab.postMessage(u);return null;};
  document.addEventListener('click',function(e){
    var a=e.target;while(a&&a.tagName!=='A')a=a.parentElement;
    if(a&&a.target==='_blank'&&a.href){
      e.preventDefault();e.stopPropagation();
      YoloNewTab.postMessage(a.href);
    }
  },true);
})();
''');
            // Brief delay for CSS zoom to take effect before revealing.
            Future.delayed(const Duration(milliseconds: 80), () {
              loading.value = false;
            });
          },
          onUrlChange: (change) {
            final newUrl = change.url ?? '';
            if (newUrl.isNotEmpty && newUrl != _urlCtrl.text) {
              if (mounted) setState(() => _urlCtrl.text = newUrl);
              widget.renderContext.onUpdateState({
                ...widget.panel.state,
                'url': newUrl,
                'title': _hostname(newUrl),
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    // Intercept target="_blank" links → create new panel with link.
    _controller!.addJavaScriptChannel(
      'YoloNewTab',
      onMessageReceived: (message) {
        final tabUrl = message.message;
        if (tabUrl.isEmpty) return;
        final createLinked = widget.renderContext.onCreateLinkedPanel;
        if (createLinked != null) {
          createLinked(
            WebpagePlugin.kTypeId,
            {'url': tabUrl, 'title': _hostname(tabUrl), 'favicon': ''},
            _hostname(tabUrl),
          );
        }
      },
    );

    // Expose controller so the board view can render the WebView
    // outside the InteractiveViewer transform.
    WebpagePlugin.controllers[widget.panel.id] = _controller!;
    if (mounted) setState(() {});
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
                    focusNode: _urlFocus,
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
                    onTap: () => _urlFocus.requestFocus(),
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
                // ── Viewport presets (via PopupMenu to save space) ──
                PopupMenuButton<String>(
                  tooltip: 'Resize panel',
                  padding: EdgeInsets.zero,
                  iconSize: 15,
                  icon: const Icon(Icons.aspect_ratio, size: 15, color: Color(0xFF64748B)),
                  onSelected: (value) {
                    final resize = widget.renderContext.onResize;
                    if (resize == null) return;
                    switch (value) {
                      case 'mobile':
                        resize(375, 667 + 81);
                      case 'tablet':
                        resize(768, 1024 + 81);
                      case 'desktop':
                        resize(1280, 800 + 81);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'mobile', child: Row(children: [
                      Icon(Icons.phone_iphone, size: 16), SizedBox(width: 8),
                      Text('Mobile  375 × 667'),
                    ])),
                    PopupMenuItem(value: 'tablet', child: Row(children: [
                      Icon(Icons.tablet_mac, size: 16), SizedBox(width: 8),
                      Text('Tablet  768 × 1024'),
                    ])),
                    PopupMenuItem(value: 'desktop', child: Row(children: [
                      Icon(Icons.laptop_mac, size: 16), SizedBox(width: 8),
                      Text('Desktop  1280 × 800'),
                    ])),
                  ],
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
        // Content area — always a background placeholder; the live
        // WebView is rendered by the board view as an overlay outside
        // the InteractiveViewer transform.
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
              : _controller == null
              ? const Center(child: CircularProgressIndicator())
              // WebView overlay covers this area; just show white bg.
              : Container(color: Colors.white),
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
