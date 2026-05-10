import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/services/webview_zoom_service.dart';
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
            // This makes sites like YouTube use desktop layout widths in CSS,
            // even when the WKWebView NSView frame is smaller due to board zoom.
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

      // ── E: Override window.innerWidth ─────────────────────────────────
      case 'override_inner_width':
        await ctrl.runJavaScript(r'''
(function(){
  const target = 1278;
  try {
    Object.defineProperty(window, 'innerWidth', {get: function(){ return target; }, configurable: true});
    Object.defineProperty(window, 'outerWidth', {get: function(){ return target; }, configurable: true});
    window.dispatchEvent(new Event('resize'));
    console.log('[WebExp] E: override innerWidth=' + window.innerWidth);
  } catch(e) {
    console.log('[WebExp] E: failed: ' + e);
  }
})();
''');
        debugPrint('[WebExp] E: override window.innerWidth=1278');

      case 'override_inner_width_zoom':
        await ctrl.runJavaScript(r'''
(function(){
  const target = 1278;
  try {
    Object.defineProperty(window, 'innerWidth', {get: function(){ return target; }, configurable: true});
    Object.defineProperty(window, 'outerWidth', {get: function(){ return target; }, configurable: true});
    document.documentElement.style.zoom = '0.5';
    window.dispatchEvent(new Event('resize'));
    console.log('[WebExp] E+B: innerWidth=' + window.innerWidth + ' zoom=0.5 bodyW=' + document.body.clientWidth);
  } catch(e) {
    console.log('[WebExp] E+B: failed: ' + e);
  }
})();
''');
        debugPrint('[WebExp] E+B: override innerWidth=1278 + zoom=0.5');

      case 'override_inner_width_reset':
        await ctrl.runJavaScript(r'''
(function(){
  try {
    Object.defineProperty(window, 'innerWidth', {get: undefined, configurable: true});
    Object.defineProperty(window, 'outerWidth', {get: undefined, configurable: true});
  } catch(e) {}
  document.documentElement.style.zoom = '';
  window.dispatchEvent(new Event('resize'));
  console.log('[WebExp] E: reset, innerWidth=' + window.innerWidth);
})();
''');
        debugPrint('[WebExp] E: reset innerWidth override');
    }

    // Log state after experiment
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await ctrl.runJavaScriptReturningResult(
      'JSON.stringify({innerWidth:window.innerWidth,zoom:document.documentElement.style.zoom||"none",bodyW:document.body?document.body.clientWidth:null})',
    );
    debugPrint('[WebExp] After state: $after');
    debugPrint('[WebExp] ══════════════════════════════════════════');
  }

  void _showViewportLab(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => _ViewportLabDialog(controller: ctrl),
    );
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
                // ── 🔬 Viewport Lab (interactive experiment panel) ─────────
                if (_controller != null)
                  Tooltip(
                    message: 'Viewport Lab',
                    child: InkWell(
                      onTap: () => _showViewportLab(context),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.science_outlined, size: 15, color: Color(0xFFE67E22)),
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// 🔬 Interactive Viewport Lab dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ViewportLabDialog extends StatefulWidget {
  const _ViewportLabDialog({required this.controller});
  final WebViewController controller;

  @override
  State<_ViewportLabDialog> createState() => _ViewportLabDialogState();
}

class _ViewportLabDialogState extends State<_ViewportLabDialog> {
  // ── A: User Agent ──────────────────────────────────────────────────────────
  bool _useDesktopUA = true;

  // ── B: CSS zoom on <html> ──────────────────────────────────────────────────
  bool _cssZoomEnabled = true;
  final TextEditingController _cssZoomCtrl = TextEditingController(text: '0.5');

  // ── C: body transform scale ───────────────────────────────────────────────
  bool _bodyScaleEnabled = false;
  final TextEditingController _bodyScaleCtrl = TextEditingController(text: '0.5');

  // ── D: body minWidth ──────────────────────────────────────────────────────
  bool _minWidthEnabled = false;
  final TextEditingController _minWidthCtrl = TextEditingController(text: '1280');

  // ── E: override window.innerWidth ─────────────────────────────────────────
  bool _overrideInnerWidthEnabled = false;
  final TextEditingController _innerWidthCtrl = TextEditingController(text: '1278');

  // ── Result state ──────────────────────────────────────────────────────────
  String? _result;
  bool _applying = false;

  @override
  void dispose() {
    _cssZoomCtrl.dispose();
    _bodyScaleCtrl.dispose();
    _minWidthCtrl.dispose();
    _innerWidthCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() { _applying = true; _result = null; });
    final ctrl = widget.controller;
    try {
      // A: User Agent
      if (_useDesktopUA) {
        await ctrl.setUserAgent(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0.0.0 Safari/537.36',
        );
      } else {
        await ctrl.setUserAgent(null);
      }

      // Build JS that applies all enabled options at once, then reads state
      final cssZoom = _cssZoomCtrl.text.trim();
      final bodyScale = _bodyScaleCtrl.text.trim();
      final minWidth = _minWidthCtrl.text.trim();
      final innerWidth = _innerWidthCtrl.text.trim();

      final sb = StringBuffer('(function(){\n');

      // B: CSS zoom
      if (_cssZoomEnabled && cssZoom.isNotEmpty) {
        sb.writeln("  document.documentElement.style.zoom='$cssZoom';");
      } else {
        sb.writeln("  document.documentElement.style.zoom='';");
      }

      // C: body transform scale
      if (_bodyScaleEnabled && bodyScale.isNotEmpty) {
        sb.writeln("  var b=document.body;");
        sb.writeln("  b.style.transform='scale($bodyScale)';");
        sb.writeln("  b.style.transformOrigin='top left';");
        sb.writeln("  b.style.width=(100/parseFloat('$bodyScale'))+'%';");
        // Compensate height so video players / fixed-height containers render correctly
        sb.writeln("  b.style.minHeight=(100/parseFloat('$bodyScale'))+'vh';");
      } else {
        sb.writeln("  document.body.style.transform='';");
        sb.writeln("  document.body.style.transformOrigin='';");
        sb.writeln("  document.body.style.width='';");
        sb.writeln("  document.body.style.minHeight='';");
      }

      // D: minWidth
      if (_minWidthEnabled && minWidth.isNotEmpty) {
        sb.writeln("  document.body.style.minWidth='${minWidth}px';");
      } else {
        sb.writeln("  document.body.style.minWidth='';");
      }

      // E: override innerWidth
      if (_overrideInnerWidthEnabled && innerWidth.isNotEmpty) {
        sb.writeln("  var iw=parseInt('$innerWidth');");
        sb.writeln("  try{Object.defineProperty(window,'innerWidth',{get:function(){return iw;},configurable:true});}catch(e){}");
        sb.writeln("  try{Object.defineProperty(window,'outerWidth',{get:function(){return iw;},configurable:true});}catch(e){}");
      } else {
        sb.writeln("  try{Object.defineProperty(window,'innerWidth',{get:undefined,configurable:true});}catch(e){}");
        sb.writeln("  try{Object.defineProperty(window,'outerWidth',{get:undefined,configurable:true});}catch(e){}");
      }

      sb.writeln("  window.dispatchEvent(new Event('resize'));");
      // After CSS applied, force video players to recalculate their size
      // using the new CSS layout width (not window.innerWidth)
      sb.writeln(r"""
  (function(){
    // YouTube: force player to use the container's CSS width
    var ytPlayer = document.getElementById('movie_player');
    if (ytPlayer) {
      var pw = ytPlayer.parentElement ? ytPlayer.parentElement.clientWidth : ytPlayer.clientWidth;
      var ph = Math.round(pw * 9 / 16);
      ytPlayer.style.width = pw + 'px';
      ytPlayer.style.height = ph + 'px';
    }
    // Also dispatch resize on the player element so YouTube's JS picks it up
    var players = document.querySelectorAll('#movie_player, [data-player-slot], ytd-player');
    players.forEach(function(p){ p.dispatchEvent(new Event('resize', {bubbles:true})); });
    // Generic: fix video elements whose height looks wrong
    document.querySelectorAll('iframe[allowfullscreen]').forEach(function(f){
      if(f.width && !f.style.height){
        f.style.height = Math.round(f.clientWidth * 9/16) + 'px';
      }
    });
  })();
""");
      sb.writeln("  return JSON.stringify({");
      sb.writeln("    innerWidth: window.innerWidth,");
      sb.writeln("    innerHeight: window.innerHeight,");
      sb.writeln("    zoom: document.documentElement.style.zoom||'none',");
      sb.writeln("    bodyClientW: document.body?document.body.clientWidth:null,");
      sb.writeln("    bodyClientH: document.body?document.body.clientHeight:null,");
      sb.writeln("    bodyScrollW: document.body?document.body.scrollWidth:null,");
      // YouTube player info
      sb.writeln("    ytW: (function(){var p=document.getElementById('movie_player');return p?p.clientWidth:null;})(),");
      sb.writeln("    ytH: (function(){var p=document.getElementById('movie_player');return p?p.clientHeight:null;})(),");
      sb.writeln("    transform: document.body?document.body.style.transform:'none',");
      sb.writeln("    minHeight: document.body?document.body.style.minHeight:'none',");
      sb.writeln("  });");
      sb.writeln('})()');

      await Future<void>.delayed(const Duration(milliseconds: 400));

      final raw = await ctrl.runJavaScriptReturningResult(sb.toString());
      final pretty = raw.toString()
          .replaceAll('{', '{\n  ')
          .replaceAll(',', ',\n  ')
          .replaceAll('}', '\n}');
      setState(() { _result = pretty; });
      debugPrint('[ViewportLab] Result: $raw');
    } catch (e) {
      setState(() { _result = 'Error: $e'; });
    } finally {
      setState(() { _applying = false; });
    }
  }

  Future<void> _resetAll() async {
    setState(() { _applying = true; _result = null; });
    try {
      await widget.controller.setUserAgent(null);
      // Also clear native WKUserScripts and reload.
      await WebViewZoomService.clearInitScripts(reload: true);
      await widget.controller.runJavaScript('''
(function(){
  document.documentElement.style.zoom='';
  document.body.style.transform='';
  document.body.style.transformOrigin='';
  document.body.style.width='';
  document.body.style.minWidth='';
  document.body.style.minHeight='';
  try{Object.defineProperty(window,'innerWidth',{get:undefined,configurable:true});}catch(e){}
  try{Object.defineProperty(window,'outerWidth',{get:undefined,configurable:true});}catch(e){}
  window.dispatchEvent(new Event('resize'));
})();
''');
      setState(() { _result = 'All CSS overrides reset.'; });
    } finally {
      setState(() { _applying = false; });
    }
  }

  /// Install JS at documentStart via WKUserScript and reload page.
  /// This is the ONLY way to override window.innerWidth BEFORE YouTube's
  /// player JS measures it during initialization.
  Future<void> _applyAndReload() async {
    setState(() { _applying = true; _result = null; });
    try {
      // Set UA first (takes effect on next reload)
      if (_useDesktopUA) {
        await widget.controller.setUserAgent(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0.0.0 Safari/537.36',
        );
      } else {
        await widget.controller.setUserAgent(null);
      }

      final cssZoom = _cssZoomCtrl.text.trim();
      final innerWidth = _innerWidthCtrl.text.trim();
      final useZoom = _cssZoomEnabled && cssZoom.isNotEmpty;
      final useInner = _overrideInnerWidthEnabled && innerWidth.isNotEmpty;

      // Build documentStart script. This runs BEFORE any page JS.
      final sb = StringBuffer('(function(){\n');
      if (useInner) {
        sb.writeln("  var iw = $innerWidth;");
        sb.writeln("  var ih = Math.round(iw * 9 / 16);");
        sb.writeln("  try{Object.defineProperty(window,'innerWidth',{get:function(){return iw;},configurable:true});}catch(e){}");
        sb.writeln("  try{Object.defineProperty(window,'outerWidth',{get:function(){return iw;},configurable:true});}catch(e){}");
        // Optionally also override innerHeight so video player picks correct aspect.
        sb.writeln("  // Don't override innerHeight - let real viewport drive it");
      }
      // Apply CSS zoom on every DOMContentLoaded so reflow happens before JS.
      if (useZoom) {
        sb.writeln("  var applyZoom = function(){ if(document.documentElement) document.documentElement.style.zoom='$cssZoom'; };");
        sb.writeln("  applyZoom();");
        sb.writeln("  document.addEventListener('DOMContentLoaded', applyZoom);");
      }
      sb.writeln('})();');

      final installed = await WebViewZoomService.installInitScript(sb.toString(), reload: true);

      // Wait for reload to finish, then sample state.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      String afterRaw = '';
      try {
        final r = await widget.controller.runJavaScriptReturningResult('''
JSON.stringify({
  innerWidth: window.innerWidth,
  innerHeight: window.innerHeight,
  bodyClientW: document.body?document.body.clientWidth:null,
  bodyClientH: document.body?document.body.clientHeight:null,
  ytW: (function(){var p=document.getElementById('movie_player');return p?p.clientWidth:null;})(),
  ytH: (function(){var p=document.getElementById('movie_player');return p?p.clientHeight:null;})(),
  zoom: document.documentElement.style.zoom||'none',
  ua: navigator.userAgent.substring(0,60)
})
''');
        afterRaw = r.toString();
      } catch (_) {}

      final pretty = '✓ Installed on $installed WKWebView(s).\n\n'
          + afterRaw
              .replaceAll('{', '{\n  ')
              .replaceAll(',', ',\n  ')
              .replaceAll('}', '\n}');
      setState(() { _result = pretty; });
      debugPrint('[ViewportLab] After reload: $afterRaw');
    } catch (e) {
      setState(() { _result = 'Error: $e'; });
    } finally {
      setState(() { _applying = false; });
    }
  }

  Widget _row({
    required bool enabled,
    required String label,
    required ValueChanged<bool?> onToggle,
    required TextEditingController ctrl,
    required String suffix,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(value: enabled, onChanged: onToggle, visualDensity: VisualDensity.compact),
          const SizedBox(width: 4),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: 90,
            child: TextField(
              controller: ctrl,
              enabled: enabled,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: const OutlineInputBorder(),
                hintText: hint,
                suffixText: suffix,
                suffixStyle: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.science_outlined, color: Color(0xFFE67E22), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Viewport Lab',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // A: User Agent
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: _useDesktopUA,
                      onChanged: (v) => setState(() => _useDesktopUA = v ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'A: Desktop Chrome User Agent',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              // B: CSS zoom
              _row(
                enabled: _cssZoomEnabled,
                label: 'B: html CSS zoom',
                onToggle: (v) => setState(() => _cssZoomEnabled = v ?? false),
                ctrl: _cssZoomCtrl,
                suffix: '×',
                hint: '0.5',
              ),

              // C: body transform scale
              _row(
                enabled: _bodyScaleEnabled,
                label: 'C: body transform scale',
                onToggle: (v) => setState(() => _bodyScaleEnabled = v ?? false),
                ctrl: _bodyScaleCtrl,
                suffix: '×',
                hint: '0.5',
              ),

              // D: body minWidth
              _row(
                enabled: _minWidthEnabled,
                label: 'D: body minWidth',
                onToggle: (v) => setState(() => _minWidthEnabled = v ?? false),
                ctrl: _minWidthCtrl,
                suffix: 'px',
                hint: '1280',
              ),

              // E: override window.innerWidth
              _row(
                enabled: _overrideInnerWidthEnabled,
                label: 'E: override innerWidth/outerWidth',
                onToggle: (v) => setState(() => _overrideInnerWidthEnabled = v ?? false),
                ctrl: _innerWidthCtrl,
                suffix: 'px',
                hint: '1278',
              ),

              const SizedBox(height: 8),
              // Info note
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE67E22).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE67E22).withOpacity(0.3)),
                ),
                child: const Text(
                  '⚡ Apply: runtime CSS only (after page load).\n'
                  '🔄 Apply (Reload): inject E + B as WKUserScript at\n'
                  '   documentStart, then reload — fixes YouTube video\n'
                  '   aspect ratio (player measures innerWidth on init).',
                  style: TextStyle(fontSize: 11, height: 1.5),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Result area
              if (_result != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _result!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              if (_result != null) const SizedBox(height: 12),

              // Buttons
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _applying ? null : _resetAll,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _applying ? null : _apply,
                    icon: const Icon(Icons.play_arrow, size: 14),
                    label: const Text('Apply'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _applying ? null : _applyAndReload,
                    icon: _applying
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 14),
                    label: const Text('Apply (Reload)'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE67E22),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
