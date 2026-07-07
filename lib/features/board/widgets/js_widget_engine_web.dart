import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/widgets/js_widget_bootstrap.dart';
import 'package:yoloit/features/board/widgets/js_widget_engine_message.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

/// Web JS widget engine backed by a hidden iframe and `postMessage`.
///
/// The iframe loads a self-contained HTML document that defines the same
/// `yoloit` API as the VM engine, then runs the widget's JS code. All
/// communication between Dart and the iframe uses `postMessage` prefixed with
/// `__yoloit__`.
class JsWidgetEngine {
  JsWidgetEngine({
    required this.widgetId,
    required this.onRender,
    required this.onSetTitle,
    required this.onStorageUpdate,
    required Map<String, dynamic> initialStorage,
    Map<String, dynamic> initialTheme = const {},
    this.appDir,
  }) : _storage = Map<String, dynamic>.from(initialStorage),
       _initialTheme = Map<String, dynamic>.from(initialTheme);

  final String widgetId;
  final void Function(Map<String, dynamic> tree) onRender;
  final void Function(String title) onSetTitle;
  final void Function(Map<String, dynamic> storage) onStorageUpdate;

  /// Virtual base path used by `yoloit.loadAsset()`.
  final String? appDir;

  final Map<String, dynamic> _storage;
  final Map<String, dynamic> _initialTheme;
  Map<String, dynamic>? _exportedState;
  web.HTMLIFrameElement? _iframe;
  JSFunction? _messageHandler;
  Completer<void>? _eventCompleter;
  Completer<void>? _readyCompleter;
  bool _disposed = false;
  final Map<String, Timer> _intervals = {};
  final List<Map<String, dynamic>> _consoleLogs = [];
  static const int _maxLogs = 200;
  Ticker? _rafTicker;
  final Map<String, bool> _rafCallbacks = {};

  /// Environment variables injected into exec calls.
  Map<String, String> envVars = {};

  // ── Public API ──────────────────────────────────────────────────────────

  List<Map<String, dynamic>> flushLogs() {
    final logs = List<Map<String, dynamic>>.from(_consoleLogs);
    _consoleLogs.clear();
    return logs;
  }

  List<Map<String, dynamic>> peekLogs() =>
      List<Map<String, dynamic>>.from(_consoleLogs);

  Map<String, dynamic>? get exportedState =>
      _exportedState == null ? null : Map<String, dynamic>.from(_exportedState!);

  Future<void> run(String widgetJs) async {
    await dispose();
    _disposed = false;
    _consoleLogs.clear();
    _exportedState = null;
    _readyCompleter = Completer<void>();

    await WidgetPermissionsService.instance.load();

    final iframe = web.HTMLIFrameElement()
      ..setAttribute('sandbox', 'allow-scripts')
      ..setAttribute('style', 'display:none;position:fixed;width:0;height:0;')
      ..srcdoc = _buildSrcdoc(widgetJs, _initialTheme).toJS;
    _iframe = iframe;

    _messageHandler = _onMessage.toJS;
    web.window.addEventListener('message', _messageHandler);

    web.document.body?.appendChild(iframe);
  }

  Future<void> callEvent(String actionId, [Map<String, dynamic>? payload]) async {
    if (_disposed || _iframe == null) return;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      await ready.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    if (_disposed || _iframe == null) return;
    final completer = Completer<void>();
    _eventCompleter?.complete();
    _eventCompleter = completer;
    _postToIframe(
      '__yoloit_call_event',
      {'actionId': actionId, 'payload': payload ?? {}},
    );
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('[JsWidgetEngineWeb] callEvent timeout for $actionId');
      },
    );
    if (identical(_eventCompleter, completer)) {
      _eventCompleter = null;
    }
  }

  void updateTheme(Map<String, dynamic> colors) => _postToIframe('__yoloit_updateTheme', colors);

  Future<void> dispose() async {
    _disposed = true;
    for (final t in _intervals.values) {
      t.cancel();
    }
    _intervals.clear();
    _rafTicker?.dispose();
    _rafTicker = null;
    _rafCallbacks.clear();
    final handler = _messageHandler;
    if (handler != null) {
      web.window.removeEventListener('message', handler);
      _messageHandler = null;
    }
    _iframe?.remove();
    _iframe = null;
    _readyCompleter?.complete();
    _readyCompleter = null;
    _eventCompleter?.complete();
    _eventCompleter = null;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _onMessage(web.MessageEvent event) {
    final iframe = _iframe;
    if (iframe == null) return;
    final source = event.source;
    if (source == null || source != iframe.contentWindow) return;
    final data = event.data;
    if (data == null || !data.isA<JSString>()) return;
    final raw = (data as JSString).toDart;
    final message = JsWidgetMessage.tryParse(raw);
    if (message == null) return;
    _dispatch(message.channel, message.payload);
  }

  void _dispatch(String channel, dynamic payload) {
    switch (channel) {
      case '__yoloit_ready':
        _readyCompleter?.complete();
        break;
      case '__yoloit_render':
        _handleRender(payload);
        break;
      case '__yoloit_fetch':
        _handleFetch(payload);
        break;
      case '__yoloit_storage_get':
        _handleStorageGet(payload);
        break;
      case '__yoloit_storage_set':
        _handleStorageSet(payload);
        break;
      case '__yoloit_set_title':
        _handleSetTitle(payload);
        break;
      case '__yoloit_event_done':
        _handleEventDone(payload);
        break;
      case '__yoloit_export_state':
        _handleExportState(payload);
        break;
      case '__yoloit_log':
        _handleLog(payload);
        break;
      case '__yoloit_set_interval':
        _handleSetInterval(payload);
        break;
      case '__yoloit_clear_interval':
        _handleClearInterval(payload);
        break;
      case '__yoloit_raf':
        _handleRaf(payload);
        break;
      case '__yoloit_caf':
        _handleCaf(payload);
        break;
      case '__yoloit_secrets_get':
        _handleSecretsGet(payload);
        break;
      case '__yoloit_secrets_set':
        _handleSecretsSet(payload);
        break;
      case '__yoloit_load_asset':
        _handleLoadAsset(payload);
        break;
      case '__yoloit_exec':
        _handleExec(payload);
        break;
    }
  }

  void _handleRender(dynamic args) {
    if (_disposed) return;
    try {
      final tree = _parseArgs(args);
      onRender(tree);
    } catch (e) {
      debugPrint('[JsWidgetEngineWeb] render error: $e');
    }
  }

  Future<void> _handleFetch(dynamic args) async {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('fetch')) {
      _resolveCallback(id, {'__error': 'fetchJson is disabled in Settings → Apps & Widgets'});
      return;
    }
    final url = req['url'] as String;
    final method = (req['method'] as String? ?? 'GET').toUpperCase();
    final headers = (req['headers'] as Map?)?.cast<String, String>() ?? {};
    try {
      final headersMap = <String, String>{
        'Accept': 'application/json',
        ...headers,
      };
      final init = web.RequestInit(
        method: method,
        headers: headersMap.jsify() as JSObject,
      );
      final response = await web.window.fetch(url.toJS, init).toDart;
      final text = await response.text().toDart;
      final decoded = jsonDecode(text.toDart) as dynamic;
      if (!_disposed) _resolveCallback(id, decoded);
    } catch (e) {
      if (!_disposed) _resolveCallback(id, {'__error': e.toString()});
    }
  }

  void _handleStorageGet(dynamic args) {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('storage')) {
      _resolveCallback(id, {'__error': 'storage is disabled in Settings → Apps & Widgets'});
      return;
    }
    final key = req['key'] as String;
    _resolveCallback(id, _storage[key]);
  }

  void _handleStorageSet(dynamic args) {
    if (_disposed) return;
    if (!WidgetPermissionsService.instance.isAllowed('storage')) return;
    final req = _parseArgs(args);
    _storage[req['key'] as String] = req['value'];
    onStorageUpdate(Map<String, dynamic>.from(_storage));
  }

  void _handleSetTitle(dynamic title) {
    if (_disposed) return;
    String decoded;
    try {
      decoded = jsonDecode(title?.toString() ?? '')?.toString() ?? '';
    } catch (_) {
      decoded = title?.toString() ?? '';
    }
    onSetTitle(decoded);
  }

  void _handleEventDone(dynamic args) {
    if (_disposed) return;
    try {
      final decoded = _parseArgs(args);
      if (decoded['error'] != null) {
        debugPrint('[JsWidgetEngineWeb] event error: ${decoded['error']}');
      }
    } catch (_) {}
    final pending = _eventCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  void _handleExportState(dynamic args) {
    if (_disposed) return;
    try {
      _exportedState =
          args is Map
              ? Map<String, dynamic>.from(args)
              : Map<String, dynamic>.from(_parseArgs(args));
    } catch (_) {
      _exportedState = null;
    }
  }

  void _handleLog(dynamic args) {
    String msg;
    try {
      msg = jsonDecode(args?.toString() ?? '')?.toString() ?? '';
    } catch (_) {
      msg = args?.toString() ?? '';
    }
    debugPrint('[JsWidget:$widgetId] $msg');
    _consoleLogs.add({'ts': DateTime.now().millisecondsSinceEpoch, 'msg': msg});
    if (_consoleLogs.length > _maxLogs) _consoleLogs.removeAt(0);
  }

  void _handleSetInterval(dynamic args) {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    final ms = (req['ms'] as num?)?.toInt() ?? 1000;
    _intervals[id]?.cancel();
    _intervals[id] = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (_disposed) return;
      _postToIframe('__yoloit_interval_tick', id);
    });
  }

  void _handleClearInterval(dynamic id) {
    String idStr;
    try {
      idStr = jsonDecode(id?.toString() ?? '')?.toString() ?? '';
    } catch (_) {
      idStr = id?.toString() ?? '';
    }
    _intervals[idStr]?.cancel();
    _intervals.remove(idStr);
  }

  void _handleRaf(dynamic args) {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    _rafCallbacks[id] = true;
    _ensureRafTicker();
  }

  void _handleCaf(dynamic id) {
    String idStr;
    try {
      idStr = jsonDecode(id?.toString() ?? '')?.toString() ?? '';
    } catch (_) {
      idStr = id?.toString() ?? '';
    }
    _rafCallbacks.remove(idStr);
    if (_rafCallbacks.isEmpty) {
      _rafTicker?.stop();
    }
  }

  Future<void> _handleSecretsGet(dynamic args) async {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('secrets')) {
      _resolveCallback(id, {'__error': 'secrets is disabled in Settings → Apps & Widgets'});
      return;
    }
    final key = '_widget_${widgetId}_${req['key'] as String}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(key);
      if (!_disposed) _resolveCallback(id, value);
    } catch (e) {
      if (!_disposed) _resolveCallback(id, null);
    }
  }

  Future<void> _handleSecretsSet(dynamic args) async {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('secrets')) {
      _resolveCallback(id, false);
      return;
    }
    final key = '_widget_${widgetId}_${req['key'] as String}';
    final value = req['value'];
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value.toString());
      }
      if (!_disposed) _resolveCallback(id, true);
    } catch (e) {
      if (!_disposed) _resolveCallback(id, false);
    }
  }

  Future<void> _handleLoadAsset(dynamic args) async {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    final assetPath = req['path'] as String? ?? '';
    try {
      final dir = appDir;
      if (dir == null || dir.isEmpty) {
        if (!_disposed) _resolveCallback(id, null);
        return;
      }
      final content = await FileStorageAdapter.instance.readString('$dir/$assetPath');
      if (!_disposed) _resolveCallback(id, content);
    } catch (e) {
      debugPrint('[JsWidgetEngineWeb] loadAsset error: $e');
      if (!_disposed) _resolveCallback(id, null);
    }
  }

  void _handleExec(dynamic args) {
    if (_disposed) return;
    final req = _parseArgs(args);
    final id = req['id'] as String;
    _resolveCallback(id, {'__error': 'exec is not available on web'});
  }

  void _resolveCallback(String id, dynamic value) {
    if (_disposed) return;
    _postToIframe('__yoloit_resolve', {'id': id, 'value': value});
  }

  void _postToIframe(String channel, dynamic payload) {
    final iframe = _iframe;
    if (iframe == null) return;
    final message = JsWidgetMessage.encode(channel: channel, payload: payload);
    iframe.contentWindow?.postMessage(message.toJS, '*'.toJS);
  }

  void _ensureRafTicker() {
    if (_rafTicker != null) {
      if (!_rafTicker!.isTicking) _rafTicker!.start();
      return;
    }
    _rafTicker = Ticker((elapsed) {
      if (_disposed || _rafCallbacks.isEmpty) {
        _rafTicker?.stop();
        return;
      }
      final ms = elapsed.inMilliseconds;
      final ids = List<String>.from(_rafCallbacks.keys);
      _rafCallbacks.clear();
      for (final id in ids) {
        _postToIframe('__yoloit_raf_tick', {'id': id, 'elapsed': ms});
      }
    });
    _rafTicker!.start();
  }

  Map<String, dynamic> _parseArgs(dynamic args) =>
      (args is Map)
          ? Map<String, dynamic>.from(args)
          : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;

  String _buildSrcdoc(String widgetJs, Map<String, dynamic> initialTheme) {
    final escapedJs = widgetJs.replaceAll('</script>', '<\\/script>');
    final themeJson = jsonEncode(initialTheme);
    return '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
(function(){
  function sendMessage(channel, jsonString) {
    window.parent.postMessage('__yoloit__' + JSON.stringify({channel: channel, payload: jsonString}), '*');
  }
  window.addEventListener('message', function(e){
    if (typeof e.data !== 'string' || !e.data.startsWith('__yoloit__')) return;
    var msg = JSON.parse(e.data.slice('__yoloit__'.length));
    if (msg.channel === '__yoloit_call_event') {
      var actionId = msg.payload.actionId;
      var payload = msg.payload.payload;
      var __h = yoloit._handler || (typeof handleEvent === 'function' ? handleEvent : null);
      if (!__h) { sendMessage('__yoloit_event_done', '{}'); return; }
      try {
        var __r = __h(actionId, payload);
        if (__r && typeof __r.then === 'function') {
          __r.then(function(){ sendMessage('__yoloit_event_done', '{}'); },
                   function(e){ sendMessage('__yoloit_event_done', JSON.stringify({error: e.message || String(e)})); });
        } else {
          sendMessage('__yoloit_event_done', '{}');
        }
      } catch(e) {
        sendMessage('__yoloit_event_done', JSON.stringify({error: e.message || String(e)}));
      }
    } else if (msg.channel === '__yoloit_updateTheme') {
      yoloit.theme = msg.payload;
      if (yoloit._onThemeChange) { try { yoloit._onThemeChange(yoloit.theme); } catch(e) {} }
    } else if (msg.channel === '__yoloit_interval_tick') {
      if (__iv_cbs[msg.payload]) __iv_cbs[msg.payload]();
    } else if (msg.channel === '__yoloit_raf_tick') {
      if (__raf_cbs[msg.payload.id]) __raf_cbs[msg.payload.id](msg.payload.elapsed);
    } else if (msg.channel === '__yoloit_resolve') {
      if (__cbs[msg.payload.id]) { __cbs[msg.payload.id](msg.payload.value); delete __cbs[msg.payload.id]; }
    }
  });
  $kJsWidgetBootstrap
  yoloit.theme = $themeJson;
  try {
    $escapedJs
  } catch(e) {
    yoloit.showError('Widget error: ' + (e.message || String(e)));
  }
  sendMessage('__yoloit_ready', '{}');
})();
</script>
</body>
</html>
''';
  }
}
