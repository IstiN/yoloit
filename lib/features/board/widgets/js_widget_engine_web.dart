import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/widgets/js_widget_bootstrap.dart';
import 'package:yoloit/features/board/widgets/js_widget_bridge.dart';
import 'package:yoloit/features/board/widgets/js_widget_engine_message.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

/// Web JS widget engine backed by a dedicated [web.Worker].
///
/// The worker is created from an inline Blob URL so it stays same-origin and
/// avoids the cross-origin iframe restrictions that broke widgets on GitHub
/// Pages. The Dart side and the worker communicate via prefixed
/// [JsWidgetMessage] strings over `postMessage`.
class JsWidgetEngine {
  JsWidgetEngine({
    required this.widgetId,
    required this.onRender,
    required this.onSetTitle,
    required this.onStorageUpdate,
    required Map<String, dynamic> initialStorage,
    Map<String, dynamic> initialTheme = const {},
    this.appDir,
  }) : _initialTheme = Map<String, dynamic>.from(initialTheme),
       _consoleLogs = [] {
    _bridge = JsWidgetBridge(
      widgetId: widgetId,
      onRender: onRender,
      onSetTitle: onSetTitle,
      onStorageUpdate: onStorageUpdate,
      onLog: (msg) => _handleLog(msg),
      isDisposed: () => _disposed,
      appDir: appDir,
      resolveCallback: (id, value) => _resolveCallback(id, value),
      fetchHandler: (id, url, method, headers) => _handleFetch(id, url, method, headers),
      secretsGetHandler: (id, key) => _handleSecretsGet(id, key),
      secretsSetHandler: (id, key, value) => _handleSecretsSet(id, key, value),
      loadAssetHandler: (id, path) => _handleLoadAsset(id, path),
      execHandler: (id, cmd) => _handleExec(id, cmd),
      intervalTickHandler: (id) => _postToWorker('__yoloit_interval_tick', id),
      rafTickHandler: (id, elapsedMs) => _postToWorker(
        '__yoloit_raf_tick',
        {'id': id, 'elapsed': elapsedMs},
      ),
      initialStorage: initialStorage,
    );
  }

  final String widgetId;
  final void Function(Map<String, dynamic> tree) onRender;
  final void Function(String title) onSetTitle;
  final void Function(Map<String, dynamic> storage) onStorageUpdate;

  /// Virtual base path used by `yoloit.loadAsset()`.
  final String? appDir;

  final Map<String, dynamic> _initialTheme;
  late final JsWidgetBridge _bridge;
  web.Worker? _worker;
  JSFunction? _messageHandler;
  Completer<void>? _readyCompleter;
  bool _disposed = false;
  final List<Map<String, dynamic>> _consoleLogs;
  static const int _maxLogs = 200;
  String? _blobUrl;

  /// Environment variables injected into exec calls (unused on web).
  Map<String, String> envVars = {};

  // ── Public API ──────────────────────────────────────────────────────────

  List<Map<String, dynamic>> flushLogs() {
    final logs = List<Map<String, dynamic>>.from(_consoleLogs);
    _consoleLogs.clear();
    return logs;
  }

  List<Map<String, dynamic>> peekLogs() =>
      List<Map<String, dynamic>>.from(_consoleLogs);

  Map<String, dynamic>? get exportedState => _bridge.exportedState;

  Future<void> run(String widgetJs) async {
    await dispose();
    _disposed = false;
    _consoleLogs.clear();
    _readyCompleter = Completer<void>();

    await WidgetPermissionsService.instance.load();

    final script = _buildWorkerScript(widgetJs, _initialTheme);
    final blob = web.Blob(
      [script.toJS].toJS,
      web.BlobPropertyBag(type: 'application/javascript'),
    );
    final blobUrl = web.URL.createObjectURL(blob);
    _blobUrl = blobUrl;

    final worker = web.Worker(blobUrl.toJS);
    _worker = worker;

    _messageHandler = _onMessage.toJS;
    worker.onmessage = _messageHandler;

    await _readyCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('[JsWidgetEngineWeb] worker ready timeout');
      },
    );
  }

  Future<void> callEvent(String actionId, [Map<String, dynamic>? payload]) async {
    if (_disposed || _worker == null) return;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      await ready.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    if (_disposed || _worker == null) return;
    await _bridge.callEvent(() {
      _postToWorker(
        '__yoloit_call_event',
        {'actionId': actionId, 'payload': payload ?? {}},
      );
    });
  }

  void updateTheme(Map<String, dynamic> colors) => _postToWorker('__yoloit_updateTheme', colors);

  Future<void> dispose() async {
    _disposed = true;
    _bridge.dispose();
    final worker = _worker;
    _worker = null;
    worker?.terminate();
    final blobUrl = _blobUrl;
    _blobUrl = null;
    if (blobUrl != null) {
      web.URL.revokeObjectURL(blobUrl);
    }
    _readyCompleter?.complete();
    _readyCompleter = null;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _onMessage(web.MessageEvent event) {
    final data = event.data;
    if (data == null || !data.isA<JSString>()) return;
    final raw = (data as JSString).toDart;
    final message = JsWidgetMessage.tryParse(raw);
    if (message == null) return;
    if (message.channel == '__yoloit_ready') {
      _readyCompleter?.complete();
      return;
    }
    unawaited(_bridge.dispatch(message.channel, message.payload));
  }

  void _handleLog(String msg) {
    debugPrint('[JsWidget:$widgetId] $msg');
    _consoleLogs.add({'ts': DateTime.now().millisecondsSinceEpoch, 'msg': msg});
    if (_consoleLogs.length > _maxLogs) _consoleLogs.removeAt(0);
  }

  Future<void> _handleFetch(
    String id,
    String url,
    String method,
    Map<String, String> headers,
  ) async {
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

  Future<void> _handleSecretsGet(String id, String key) async {
    final fullKey = '_widget_${widgetId}_$key';
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(fullKey);
      if (!_disposed) _resolveCallback(id, value);
    } catch (e) {
      if (!_disposed) _resolveCallback(id, null);
    }
  }

  Future<void> _handleSecretsSet(String id, String key, dynamic value) async {
    final fullKey = '_widget_${widgetId}_$key';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(fullKey);
      } else {
        await prefs.setString(fullKey, value.toString());
      }
      if (!_disposed) _resolveCallback(id, true);
    } catch (e) {
      if (!_disposed) _resolveCallback(id, false);
    }
  }

  Future<void> _handleLoadAsset(String id, String assetPath) async {
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

  Future<void> _handleExec(String id, String cmd) async {
    if (!_disposed) _resolveCallback(id, {'__error': 'exec is not available on web'});
  }

  void _resolveCallback(String id, dynamic value) {
    if (_disposed) return;
    _postToWorker('__yoloit_resolve', {'id': id, 'value': value});
  }

  void _postToWorker(String channel, dynamic payload) {
    final worker = _worker;
    if (worker == null) return;
    final message = JsWidgetMessage.encode(channel: channel, payload: payload);
    worker.postMessage(message.toJS);
  }

  String _buildWorkerScript(String widgetJs, Map<String, dynamic> initialTheme) {
    final escapedJs = widgetJs.replaceAll('</script>', '<\\/script>');
    final themeJson = jsonEncode(initialTheme);
    return '''
function sendMessage(channel, jsonString) {
  self.postMessage('__yoloit__' + JSON.stringify({channel: channel, payload: jsonString}));
}
self.onmessage = function(e){
  var data = e.data;
  if (typeof data !== 'string' || !data.startsWith('__yoloit__')) return;
  var msg = JSON.parse(data.slice('__yoloit__'.length));
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
};
$kJsWidgetBootstrap
yoloit.theme = $themeJson;
try {
  $escapedJs
} catch(e) {
  yoloit.showError('Widget error: ' + (e.message || String(e)));
}
sendMessage('__yoloit_ready', '{}');
''';
  }
}
