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

  /// Last known CSS zoom per panel (= board scale at gesture-end).
  /// Read by [onPageFinished] to re-inject after navigation.
  /// Formula: zoom = boardScale → CSS layout width = panel.logicalWidth.
  static final Map<String, double> pendingCssZoom = {};

  /// Loading state per panel.  Set to true on page start, false on
  /// page finish.  The overlay shows a white cover during loading to
  /// hide the flash of unstyled content.
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
            loading.value = true;
          },
          onPageFinished: (_) {
            // Re-inject CSS zoom so page reflows at panel's logical width.
            // zoom = boardScale → CSS layout width = panel.logicalWidth.
            // Board injects the correct zoom on gesture-end; here we use
            // whatever was last stored (default 1.0 on first load).
            final panelId = widget.panel.id;
            final zoom = WebpagePlugin.pendingCssZoom[panelId] ?? 1.0;
            _controller!.runJavaScript('''
(function(){
  document.documentElement.style.zoom='${zoom.toStringAsFixed(4)}';
  window.dispatchEvent(new Event('resize'));
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
            Future.delayed(const Duration(milliseconds: 150), () {
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

  Future<void> _runExperiment(String id) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    debugPrint('[WebExp] ══════════════════════════════════════════');
    debugPrint('[WebExp] Running experiment: $id');

    switch (id) {
      // ── 📊 Info ────────────────────────────────────────────────────────
      case 'info':
        final info = await ctrl.runJavaScriptReturningResult('''
(function(){
  return JSON.stringify({
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    devicePixelRatio: window.devicePixelRatio,
    outerWidth: window.outerWidth,
    bodyClientWidth: document.body ? document.body.clientWidth : null,
    bodyScrollWidth: document.body ? document.body.scrollWidth : null,
    htmlZoom: document.documentElement.style.zoom || 'none',
    htmlTransform: document.documentElement.style.transform || 'none',
    userAgent: navigator.userAgent,
    viewport: (()=>{var vp=document.querySelector("meta[name=viewport]");return vp?vp.content:"none";})()
  });
})()
''');
        debugPrint('[WebExp] INFO: $info');

      // ── A: User Agent ──────────────────────────────────────────────────
      case 'ua_desktop':
        await ctrl.setUserAgent(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0.0.0 Safari/537.36',
        );
        await ctrl.reload();
        debugPrint('[WebExp] A: Set desktop Chrome UA, reloading...');

      case 'ua_reset':
        await ctrl.setUserAgent(null);
        await ctrl.reload();
        debugPrint('[WebExp] A: Reset UA to default, reloading...');

      // ── B: CSS zoom on <html> ──────────────────────────────────────────
      case 'zoom_0_5':
        await ctrl.runJavaScript(
          "document.documentElement.style.zoom='0.5';"
          "window.dispatchEvent(new Event('resize'));"
          "console.log('[WebExp] B: zoom=0.5, innerWidth='+window.innerWidth);",
        );
        debugPrint('[WebExp] B: Set html zoom=0.5');

      case 'zoom_0_75':
        await ctrl.runJavaScript(
          "document.documentElement.style.zoom='0.75';"
          "window.dispatchEvent(new Event('resize'));"
          "console.log('[WebExp] B: zoom=0.75, innerWidth='+window.innerWidth);",
        );
        debugPrint('[WebExp] B: Set html zoom=0.75');

      case 'zoom_1':
        await ctrl.runJavaScript(
          "document.documentElement.style.zoom='';"
          "window.dispatchEvent(new Event('resize'));"
          "console.log('[WebExp] B: zoom reset, innerWidth='+window.innerWidth);",
        );
        debugPrint('[WebExp] B: Reset html zoom');

      // ── C: CSS transform scale on <body> ───────────────────────────────
      case 'scale_body':
        await ctrl.runJavaScript('''
(function(){
  var b=document.body;
  b.style.transform='scale(0.5)';
  b.style.transformOrigin='top left';
  b.style.width='200%';
  window.dispatchEvent(new Event('resize'));
  console.log('[WebExp] C: body scale(0.5), bodyClientWidth='+b.clientWidth);
})();
''');
        debugPrint('[WebExp] C: body transform scale(0.5) + width=200%');

      case 'scale_reset':
        await ctrl.runJavaScript('''
(function(){
  var b=document.body;
  b.style.transform='';
  b.style.transformOrigin='';
  b.style.width='';
  window.dispatchEvent(new Event('resize'));
  console.log('[WebExp] C: body transform reset');
})();
''');
        debugPrint('[WebExp] C: body transform reset');

      // ── D: Force minWidth on body ──────────────────────────────────────
      case 'min_width':
        await ctrl.runJavaScript('''
(function(){
  document.body.style.minWidth='1280px';
  window.dispatchEvent(new Event('resize'));
  console.log('[WebExp] D: minWidth=1280px set, scrollWidth='+document.body.scrollWidth);
})();
''');
        debugPrint('[WebExp] D: Set body minWidth=1280px');

      case 'min_width_reset':
        await ctrl.runJavaScript('''
(function(){
  document.body.style.minWidth='';
  window.dispatchEvent(new Event('resize'));
  console.log('[WebExp] D: minWidth reset');
})();
''');
        debugPrint('[WebExp] D: Reset body minWidth');
    }

    // Log state after experiment
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await ctrl.runJavaScriptReturningResult(
      'JSON.stringify({innerWidth:window.innerWidth,zoom:document.documentElement.style.zoom||"none",bodyW:document.body?document.body.clientWidth:null})',
    );
    debugPrint('[WebExp] After state: $after');
    debugPrint('[WebExp] ══════════════════════════════════════════');
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
                      default:
                        return;
                    }
                    // Trigger a resize event so page reflows at new panel size.
                    final ctrl = _controller;
                    if (ctrl != null) {
                      Future.delayed(const Duration(milliseconds: 200), () {
                        ctrl.runJavaScript(
                          "window.dispatchEvent(new Event('resize'));",
                        );
                      });
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
                // ── 🔬 Viewport debug experiments ──────────────────────────
                if (_controller != null)
                  PopupMenuButton<String>(
                    tooltip: 'Viewport experiments (debug)',
                    padding: EdgeInsets.zero,
                    iconSize: 15,
                    icon: const Icon(Icons.science_outlined, size: 15, color: Color(0xFFE67E22)),
                    onSelected: (id) => _runExperiment(id),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'info',
                        child: Row(children: [Icon(Icons.info_outline, size: 16), SizedBox(width: 8), Text('📊 Log frame & UA info')]),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'ua_desktop',
                        child: Row(children: [Icon(Icons.laptop_mac, size: 16), SizedBox(width: 8), Text('A: UA → Desktop Chrome')]),
                      ),
                      PopupMenuItem(
                        value: 'ua_reset',
                        child: Row(children: [Icon(Icons.restore, size: 16), SizedBox(width: 8), Text('A: UA → reset (reload)')]),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'zoom_0_5',
                        child: Row(children: [Icon(Icons.zoom_out, size: 16), SizedBox(width: 8), Text('B: html zoom = 0.5')]),
                      ),
                      PopupMenuItem(
                        value: 'zoom_0_75',
                        child: Row(children: [Icon(Icons.zoom_out, size: 16), SizedBox(width: 8), Text('B: html zoom = 0.75')]),
                      ),
                      PopupMenuItem(
                        value: 'zoom_1',
                        child: Row(children: [Icon(Icons.zoom_in, size: 16), SizedBox(width: 8), Text('B: html zoom = 1.0 (reset)')]),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'scale_body',
                        child: Row(children: [Icon(Icons.transform, size: 16), SizedBox(width: 8), Text('C: body transform scale(0.5)')]),
                      ),
                      PopupMenuItem(
                        value: 'scale_reset',
                        child: Row(children: [Icon(Icons.transform, size: 16), SizedBox(width: 8), Text('C: body transform reset')]),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'min_width',
                        child: Row(children: [Icon(Icons.width_full, size: 16), SizedBox(width: 8), Text('D: body minWidth=1280px')]),
                      ),
                      PopupMenuItem(
                        value: 'min_width_reset',
                        child: Row(children: [Icon(Icons.width_normal, size: 16), SizedBox(width: 8), Text('D: body minWidth reset')]),
                      ),
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
