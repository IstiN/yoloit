import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/widgets/widget_manifest.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

class CustomWidgetPlugin extends BoardPanelPlugin {
  const CustomWidgetPlugin();

  static const String kTypeId = 'board.widget.custom';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Custom Widget';

  @override
  IconData get icon => Icons.widgets_outlined;

  @override
  Color get accentColor => const Color(0xFF7C3AED);

  @override
  Size get defaultSize => const Size(360, 420);

  @override
  Map<String, dynamic> get initialState => {
    'widgetId': '',
    'config': <String, dynamic>{},
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _CustomWidgetContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CustomWidgetContent extends StatefulWidget {
  const _CustomWidgetContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_CustomWidgetContent> createState() => _CustomWidgetContentState();
}

class _CustomWidgetContentState extends State<_CustomWidgetContent> {
  WidgetManifest? _manifest;
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  // Pending JS callbacks: requestId → completer
  final Map<String, Completer<dynamic>> _pending = {};

  String get _widgetId =>
      widget.panel.state['widgetId'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CustomWidgetContent old) {
    super.didUpdateWidget(old);
    final oldId = old.panel.state['widgetId'] as String? ?? '';
    if (_widgetId != oldId) _load();
  }

  Future<void> _load() async {
    if (_widgetId.isEmpty) {
      setState(() { _loading = false; _error = 'No widget selected'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    final manifest = await WidgetRegistryService.instance.find(_widgetId);
    if (manifest == null) {
      if (mounted) setState(() { _loading = false; _error = 'Widget "$_widgetId" not found'; });
      return;
    }
    final js = await manifest.readJs();
    if (js == null) {
      if (mounted) setState(() { _loading = false; _error = 'widget.js missing for "$_widgetId"'; });
      return;
    }
    final html = _buildHtml(manifest, js);
    final ctrl = _buildController(manifest, html);
    if (mounted) setState(() { _manifest = manifest; _controller = ctrl; _loading = false; });
  }

  WebViewController _buildController(WidgetManifest manifest, String html) {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'YoloitBridge',
        onMessageReceived: (msg) => _handleBridgeMessage(manifest, msg.message),
      )
      ..loadHtmlString(html);
    return ctrl;
  }

  /// Handle messages from the JS bridge:
  /// {type: 'cli', id: '...', command: '...', args: [...]}
  /// {type: 'storage.get', id: '...', key: '...'}
  /// {type: 'storage.set', id: '...', key: '...', value: ...}
  /// {type: 'panel.setTitle', title: '...'}
  Future<void> _handleBridgeMessage(WidgetManifest manifest, String raw) async {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? '';
      final id = msg['id'] as String? ?? '';

      switch (type) {
        case 'cli':
          final command = msg['command'] as String? ?? '';
          final args = List<String>.from(msg['args'] as List? ?? []);
          final result = await _runCliCommand(manifest, command, args);
          _respond(id, result);

        case 'storage.get':
          final key = msg['key'] as String? ?? '';
          final store = widget.panel.state['_storage'] as Map? ?? {};
          _respond(id, store[key]);

        case 'storage.set':
          final key = msg['key'] as String? ?? '';
          final value = msg['value'];
          final store = Map<String, dynamic>.from(
            widget.panel.state['_storage'] as Map? ?? {},
          )..[key] = value;
          widget.renderContext.onUpdateState({'_storage': store});
          _respond(id, true);

        case 'panel.setTitle':
          final title = msg['title'] as String? ?? '';
          widget.renderContext.onUpdateState({'_title': title});
      }
    } catch (e) {
      debugPrint('[CustomWidgetPlugin] bridge error: $e');
    }
  }

  Future<dynamic> _runCliCommand(
    WidgetManifest manifest,
    String command,
    List<String> args,
  ) async {
    // Permission check
    final allowed = manifest.allowedCommands;
    final permitted =
        allowed.contains('*') || allowed.contains(command);
    if (!permitted) {
      return {'error': 'Command "$command" not permitted by widget manifest'};
    }

    // Forward to CLI server via HTTP
    final port = CliServer.instance.port;
    if (port == null) return {'error': 'CLI server not running'};

    try {
      // Map simple commands to REST calls
      final result = await _dispatchCliToRest(port, command, args);
      return result;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<dynamic> _dispatchCliToRest(
    int port,
    String command,
    List<String> args,
  ) async {
    // For MVP: execute via the CLI server's /api/exec endpoint
    // (we'll add this endpoint, or map known commands to REST)
    final uri = Uri.parse('http://localhost:$port/api/exec');
    final http = HttpClientHelper();
    return http.post(uri, {'command': command, 'args': args});
  }

  void _respond(String id, dynamic value) {
    if (_controller == null || id.isEmpty) return;
    final encoded = jsonEncode(value);
    _controller!.runJavaScript('window.__yoloit_respond("$id", $encoded)');
  }

  String _buildHtml(WidgetManifest manifest, String widgetJs) {
    final port = CliServer.instance.port ?? 0;
    final config = jsonEncode(
      widget.panel.state['config'] as Map? ?? {},
    );
    final storage = jsonEncode(
      widget.panel.state['_storage'] as Map? ?? {},
    );
    final allowedCmds = jsonEncode(manifest.allowedCommands);

    return '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta charset="utf-8">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 14px;
    background: transparent;
    color: #e2e8f0;
    height: 100vh;
    overflow: hidden;
  }
  #app { width: 100%; height: 100vh; overflow: auto; padding: 12px; }
</style>
</head>
<body>
<div id="app"></div>
<script>
// ── Pending callbacks ───────────────────────────────────────────────────────
window._yoloit_pending = {};
window.__yoloit_respond = function(id, value) {
  var cb = window._yoloit_pending[id];
  if (cb) { delete window._yoloit_pending[id]; cb(value); }
};

function _bridge(msg) {
  return new Promise(function(resolve) {
    var id = Math.random().toString(36).slice(2);
    window._yoloit_pending[id] = resolve;
    msg.id = id;
    YoloitBridge.postMessage(JSON.stringify(msg));
  });
}

// ── yoloit API ──────────────────────────────────────────────────────────────
window.yoloit = {
  /** Widget id */
  widgetId: ${jsonEncode(manifest.id)},

  /** Allowed CLI commands for this widget */
  allowedCommands: $allowedCmds,

  /** CLI server port */
  port: $port,

  /** Per-widget config passed from panel state */
  config: $config,

  /** Execute a permitted yoloit CLI command. Returns parsed JSON result. */
  cli: function(command) {
    var args = Array.prototype.slice.call(arguments, 1);
    return _bridge({type: 'cli', command: command, args: args});
  },

  /** Fetch JSON from a URL (convenience wrapper). */
  fetchJson: async function(url, options) {
    var r = await fetch(url, options || {});
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  },

  /** Widget-local persistent storage. */
  storage: {
    _cache: $storage,
    get: function(key) {
      if (key in this._cache) return Promise.resolve(this._cache[key]);
      return _bridge({type: 'storage.get', key: key}).then(function(v) {
        window.yoloit.storage._cache[key] = v;
        return v;
      });
    },
    set: function(key, value) {
      this._cache[key] = value;
      return _bridge({type: 'storage.set', key: key, value: value});
    },
  },

  /** Panel controls. */
  panel: {
    setTitle: function(title) {
      YoloitBridge.postMessage(JSON.stringify({type: 'panel.setTitle', title: title}));
    },
  },

  /** Show a simple error in the widget area. */
  showError: function(msg) {
    document.getElementById('app').innerHTML =
      '<div style="color:#f87171;padding:16px;font-size:13px">⚠️ ' + msg + '</div>';
  },
};

// ── Widget JS ───────────────────────────────────────────────────────────────
try {
$widgetJs
} catch(e) {
  yoloit.showError('Widget error: ' + e.message);
}
</script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_controller == null) {
      return _PickerView(panel: widget.panel, renderContext: widget.renderContext);
    }
    return WebViewWidget(controller: _controller!);
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 32),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ─── Widget picker (no widget selected yet) ───────────────────────────────────

class _PickerView extends StatefulWidget {
  const _PickerView({required this.panel, required this.renderContext});
  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_PickerView> createState() => _PickerViewState();
}

class _PickerViewState extends State<_PickerView> {
  List<WidgetManifest>? _widgets;

  @override
  void initState() {
    super.initState();
    WidgetRegistryService.instance.loadAll().then((list) {
      if (mounted) setState(() => _widgets = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final widgets = _widgets;
    if (widgets == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (widgets.isEmpty) {
      return Center(
        child: Text(
          'No widgets installed.\nRun: yoloit widget:list',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: widgets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = widgets[i];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            widget.renderContext.onUpdateState({'widgetId': m.id});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Text(m.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (m.description.isNotEmpty)
                        Text(
                          m.description,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Minimal HTTP helper (avoids adding http package dependency) ──────────────

class HttpClientHelper {
  Future<dynamic> post(Uri uri, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final raw = await res.transform(const Utf8Decoder()).join();
      return jsonDecode(raw);
    } finally {
      client.close();
    }
  }
}

/// CLI handler for custom widget panels.
/// Supports `setState` (set widgetId), `info` (get current widget), and `reload`.
class CustomWidgetCliHandler extends PanelCliHandler {
  const CustomWidgetCliHandler();

  @override
  String get typeId => CustomWidgetPlugin.kTypeId;

  @override
  List<String> get supportedActions => const ['setState', 'info', 'reload'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'widgetId': panel.state['widgetId'] ?? '',
    'config': panel.state['config'] ?? {},
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'setState':
        final state = args['state'] as Map?;
        if (state == null) {
          return const CliActionResult(ok: false, message: 'Missing "state" field');
        }
        return CliActionResult(
          ok: true,
          message: 'State updated',
          stateUpdate: Map<String, dynamic>.from(state),
        );

      case 'info':
        final wid = panel.state['widgetId'] as String? ?? '';
        final manifest = wid.isNotEmpty
            ? await WidgetRegistryService.instance.find(wid)
            : null;
        return CliActionResult(
          ok: true,
          data: {
            'widgetId': wid,
            'manifest': manifest?.toJson(),
          },
        );

      case 'reload':
        // Toggling a dummy key forces the widget to reinit.
        return CliActionResult(
          ok: true,
          message: 'Widget reloaded',
          stateUpdate: {'_reload': DateTime.now().millisecondsSinceEpoch},
        );
    }
    return CliActionResult(ok: false, message: 'Unknown action: $action');
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'setState': CliActionHelp(
      description: 'Set panel state (e.g. widgetId)',
      params: {'state': 'JSON map of state keys to merge'},
      example: '{"action":"setState","state":{"widgetId":"weather"}}',
    ),
    'info': const CliActionHelp(
      description: 'Get current widget info',
    ),
    'reload': const CliActionHelp(
      description: 'Force widget JS to reload',
    ),
  };
}
