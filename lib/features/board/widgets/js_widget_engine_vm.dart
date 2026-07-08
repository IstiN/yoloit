import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:yoloit/features/board/widgets/js_widget_bootstrap.dart';
import 'package:yoloit/features/board/widgets/js_widget_bridge.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

/// Headless JS widget engine.
///
/// Runs a widget's JS code using flutter_js (QuickJS / JavascriptCore).
/// The JS side communicates with Flutter via a declarative JSON UI tree
/// and a set of async bridge functions.
///
/// JS API exposed to widgets:
/// ```js
/// yoloit.render(tree)           // update the Flutter UI
/// yoloit.fetchJson(url, opts)   // HTTP fetch via Dart (no CORS)
/// yoloit.exec(cmd)              // run yoloit CLI command, returns {stdout, stderr, exitCode}
/// yoloit.storage.get(key)       // persistent per-panel storage (plain JSON)
/// yoloit.storage.set(key, val)
/// yoloit.secrets.get(key)       // per-widget secure storage (encrypted)
/// yoloit.secrets.set(key, val)
/// yoloit.panel.setTitle(title)
/// yoloit.showError(msg)
/// yoloit.loadAsset(path)
/// setInterval(fn, ms)           // Dart-backed timer
/// clearInterval(id)
/// setTimeout(fn, ms)
/// clearTimeout(id)
/// requestAnimationFrame(fn)     // vsync-driven (~60fps), fn receives elapsed ms
/// cancelAnimationFrame(id)
/// console.log(...)
/// ```
class JsWidgetEngine {
  JsWidgetEngine({
    required this.widgetId,
    required this.onRender,
    required this.onSetTitle,
    required this.onStorageUpdate,
    required Map<String, dynamic> initialStorage,
    Map<String, dynamic> initialTheme = const {},
    this.appDir,
  }) : _initialTheme = Map<String, dynamic>.from(initialTheme) {
    _bridge = JsWidgetBridge(
      widgetId: widgetId,
      onRender: onRender,
      onSetTitle: onSetTitle,
      onStorageUpdate: onStorageUpdate,
      onLog: (msg) => _handleLog(msg),
      isDisposed: () => _disposed,
      appDir: appDir,
      resolveCallback: (id, value) async {},
      fetchHandler: (id, url, method, headers) async {},
      secretsGetHandler: (id, key) async {},
      secretsSetHandler: (id, key, value) async {},
      loadAssetHandler: (id, path) async {},
      execHandler: (id, cmd) async {},
      intervalTickHandler: (id) {},
      rafTickHandler: (id, elapsedMs) {},
      initialStorage: initialStorage,
    );
  }

  /// Widget ID used to namespace secure storage keys.
  final String widgetId;
  final void Function(Map<String, dynamic> tree) onRender;
  final void Function(String title) onSetTitle;
  final void Function(Map<String, dynamic> storage) onStorageUpdate;

  /// Absolute path to the app's folder — used by loadAsset bridge.
  final String? appDir;

  final Map<String, dynamic> _initialTheme;
  late final JsWidgetBridge _bridge;
  JavascriptRuntime? _runtime;
  bool _disposed = false;
  final List<Map<String, dynamic>> _consoleLogs = [];
  static const int _maxLogs = 200;

  /// Environment variables injected into exec calls.
  Map<String, String> envVars = {};

  static const _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  // ── Public API ──────────────────────────────────────────────────────────

  /// Return and clear the accumulated console.log buffer.
  List<Map<String, dynamic>> flushLogs() {
    final logs = List<Map<String, dynamic>>.from(_consoleLogs);
    _consoleLogs.clear();
    return logs;
  }

  /// Return a copy of the console.log buffer without clearing it.
  List<Map<String, dynamic>> peekLogs() =>
      List<Map<String, dynamic>>.from(_consoleLogs);

  /// Last structured state exported via `yoloit.exportState(...)`.
  Map<String, dynamic>? get exportedState => _bridge.exportedState;

  /// Push updated theme colors into the running JS widget.
  void updateTheme(Map<String, dynamic> colors) {
    final rt = _runtime;
    if (rt == null || _disposed) return;
    try {
      rt.evaluate(JsWidgetBridge.updateThemeJs(colors));
      rt.executePendingJob();
    } catch (e) {
      debugPrint('[JsWidgetEngine] updateTheme error: $e');
    }
  }

  Future<void> run(String widgetJs) async {
    await dispose();
    _disposed = false;
    _consoleLogs.clear();

    // Ensure permissions are loaded before checking them in bridges
    await WidgetPermissionsService.instance.load();

    try {
      // Always use QuickJsRuntime2 — JavascriptCoreRuntime has a static
      // _sendMessageDartFunc field that gets overwritten by each new instance,
      // breaking multi-widget setups on macOS/iOS.
      // NOTE: flutter_js pub cache is patched (jscore_runtime.dart) to use an
      // instance map keyed by context pointer instead of the static field.
      final runtime = getJavascriptRuntime();
      runtime.enableHandlePromises();
      _runtime = runtime;
      debugPrint('[JsWidgetEngine] starting ${runtime.runtimeType}');
      _setupBridges(runtime);

      final bootstrapResult = runtime.evaluate(kJsWidgetBootstrap);
      if (bootstrapResult.isError) {
        debugPrint('[JsWidgetEngine] bootstrap error: ${bootstrapResult.stringResult}');
      }
      updateTheme(_initialTheme);

      final code = '''
(function() {
  try {
    $widgetJs
  } catch(e) {
    yoloit.showError('Widget error: ' + (e.message || String(e)));
  }
})();
''';
      debugPrint('[JsWidgetEngine] evaluating widget code...');
      final result = runtime.evaluate(code);
      if (result.isError) {
        debugPrint('[JsWidgetEngine] widget eval error: ${result.stringResult}');
      }
      runtime.executePendingJob();
      debugPrint('[JsWidgetEngine] widget code done, uiTree set: $_disposed');
    } catch (e) {
      debugPrint('[JsWidgetEngine] startup error: $e');
      rethrow;
    }
  }

  /// Call the JS `handleEvent(actionId, payload)` function.
  ///
  /// Waits until the handler finishes, including async handlers that return
  /// a Promise (e.g. weather city changes that await fetch + render).
  Future<void> callEvent(
    String actionId, [
    Map<String, dynamic>? payload,
  ]) async {
    final rt = _runtime;
    if (rt == null || _disposed) return;
    final encodedAction = jsonEncode(actionId);
    final encodedPayload = jsonEncode(payload ?? {});
    await _bridge.callEvent(() {
      rt.evaluate(
        '(function(){'
        'var __h=yoloit._handler||(typeof handleEvent==="function"?handleEvent:null);'
        'if(!__h){sendMessage("__yoloit_event_done","{}");return;}'
        'try{'
        'var __r=__h($encodedAction,$encodedPayload);'
        'if(__r&&typeof __r.then==="function"){'
        '__r.then(function(){sendMessage("__yoloit_event_done","{}");},'
        'function(e){sendMessage("__yoloit_event_done",JSON.stringify({error:e.message||String(e)}));});'
        '}else{sendMessage("__yoloit_event_done","{}");}'
        '}catch(e){sendMessage("__yoloit_event_done",JSON.stringify({error:e.message||String(e)}));}'
        '})();',
      );
      rt.executePendingJob();
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _bridge.dispose();
    _runtime?.dispose();
    _runtime = null;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _setupBridges(JavascriptRuntime rt) {
    // flutter_js bridges are invoked from JS via: sendMessage(channelName, jsonString)
    // The Dart callback receives args = jsonDecode(jsonString) — already decoded.

    // Bind bridge resolve callback to the current runtime.
    _bridge.resolveCallback = (id, value) => _resolveCallback(rt, id, value);
    _bridge.fetchHandler = (id, url, method, headers) => _handleFetch(rt, id, url, method, headers);
    _bridge.secretsGetHandler = (id, key) => _handleSecretsGet(rt, id, key);
    _bridge.secretsSetHandler = (id, key, value) => _handleSecretsSet(rt, id, key, value);
    _bridge.loadAssetHandler = (id, path) => _handleLoadAsset(rt, id, path);
    _bridge.execHandler = (id, cmd) => _handleExec(rt, id, cmd);
    _bridge.intervalTickHandler = (id) => _handleIntervalTick(rt, id);
    _bridge.rafTickHandler = (id, elapsedMs) => _handleRafTick(rt, id, elapsedMs);

    // Register all channels with flutter_js. The callback receives the already
    // decoded payload; we re-wrap it so the shared bridge can normalise it.
    for (final channel in _bridgeChannels) {
      rt.setupBridge(channel, (args) {
        if (_disposed) return;
        final payload = _payloadForChannel(channel, args);
        unawaited(_bridge.dispatch(channel, payload));
      });
    }
  }

  static const List<String> _bridgeChannels = [
    '__yoloit_render',
    '__yoloit_fetch',
    '__yoloit_storage_get',
    '__yoloit_storage_set',
    '__yoloit_set_title',
    '__yoloit_event_done',
    '__yoloit_export_state',
    '__yoloit_log',
    '__yoloit_set_interval',
    '__yoloit_clear_interval',
    '__yoloit_raf',
    '__yoloit_caf',
    '__yoloit_secrets_get',
    '__yoloit_secrets_set',
    '__yoloit_load_asset',
    '__yoloit_exec',
  ];

  dynamic _payloadForChannel(String channel, dynamic args) {
    // flutter_js decodes the JSON string for us, so most channels already get
    // a Map. A few channels send a bare string/value, so keep them as-is.
    return args;
  }

  void _handleLog(String msg) {
    debugPrint('[JsWidget:$widgetId] $msg');
    _consoleLogs.add({'ts': DateTime.now().millisecondsSinceEpoch, 'msg': msg});
    if (_consoleLogs.length > _maxLogs) _consoleLogs.removeAt(0);
  }

  Future<void> _handleFetch(
    JavascriptRuntime rt,
    String id,
    String url,
    String method,
    Map<String, String> headers,
  ) async {
    try {
      final client = HttpClient();
      final dartReq = await client.openUrl(method, Uri.parse(url));
      dartReq.headers.set('User-Agent', 'YoLoIT-Widget/1.0');
      dartReq.headers.set('Accept', 'application/json');
      headers.forEach((k, v) => dartReq.headers.set(k, v));
      final res = await dartReq.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(const Utf8Decoder()).join();
      client.close();
      if (_disposed) return;
      final result = jsonDecode(body);
      _resolveCallback(rt, id, result);
    } catch (e) {
      if (!_disposed) {
        _resolveCallback(rt, id, {'__error': e.toString()});
      }
    }
  }

  Future<void> _handleSecretsGet(
    JavascriptRuntime rt,
    String id,
    String key,
  ) async {
    final fullKey = '_widget_${widgetId}_$key';
    try {
      final val = await _secureStorage.read(key: fullKey);
      if (!_disposed) _resolveCallback(rt, id, val);
    } catch (e) {
      if (!_disposed) _resolveCallback(rt, id, null);
    }
  }

  Future<void> _handleSecretsSet(
    JavascriptRuntime rt,
    String id,
    String key,
    dynamic value,
  ) async {
    final fullKey = '_widget_${widgetId}_$key';
    try {
      if (value == null) {
        await _secureStorage.delete(key: fullKey);
      } else {
        await _secureStorage.write(key: fullKey, value: value.toString());
      }
      if (!_disposed) _resolveCallback(rt, id, true);
    } catch (e) {
      if (!_disposed) _resolveCallback(rt, id, false);
    }
  }

  Future<void> _handleLoadAsset(
    JavascriptRuntime rt,
    String id,
    String assetPath,
  ) async {
    try {
      final dir = appDir;
      if (dir == null || dir.isEmpty) {
        if (!_disposed) _resolveCallback(rt, id, null);
        return;
      }
      final file = File(
        '$dir${Platform.pathSeparator}${assetPath.replaceAll('/', Platform.pathSeparator)}',
      );
      if (await file.exists()) {
        final content = await file.readAsString();
        if (!_disposed) _resolveCallback(rt, id, content);
      } else {
        if (!_disposed) _resolveCallback(rt, id, null);
      }
    } catch (e) {
      debugPrint('[JsWidgetEngine] loadAsset error: $e');
      if (!_disposed) _resolveCallback(rt, id, null);
    }
  }

  Future<void> _handleExec(
    JavascriptRuntime rt,
    String id,
    String cmd,
  ) async {
    if (!WidgetPermissionsService.instance.isAllowed('exec')) {
      _resolveCallback(rt, id, {
        '__error': 'exec is disabled in Settings → Apps & Widgets',
      });
      return;
    }
    if (!cmd.startsWith('yoloit ') && cmd != 'yoloit') {
      _resolveCallback(rt, id, {'__error': 'Only yoloit commands are allowed'});
      return;
    }
    try {
      final yoloitBin = '${Platform.environment['HOME']}/.config/yoloit/yoloit';
      final cmdArgs = cmd.substring('yoloit'.length).trim().split(RegExp(r'\s+'));
      final env = Map<String, String>.from(Platform.environment)..addAll(envVars);
      final result = await Process.run(
        yoloitBin,
        cmdArgs.where((s) => s.isNotEmpty).toList(),
        environment: env,
      ).timeout(const Duration(seconds: 30));
      if (_disposed) return;
      _resolveCallback(rt, id, {
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
        'exitCode': result.exitCode,
      });
    } catch (e) {
      if (!_disposed) _resolveCallback(rt, id, {'__error': e.toString()});
    }
  }

  void _handleIntervalTick(JavascriptRuntime rt, String id) {
    try {
      rt.evaluate('if(__iv_cbs["$id"])__iv_cbs["$id"]()');
      rt.executePendingJob();
    } catch (_) {}
  }

  void _handleRafTick(JavascriptRuntime rt, String id, int elapsedMs) {
    try {
      rt.evaluate('if(__raf_cbs["$id"]){__raf_cbs["$id"]($elapsedMs);delete __raf_cbs["$id"];}');
      rt.executePendingJob();
    } catch (e) {
      debugPrint('[JsWidgetEngine] RAF tick error: $e');
    }
  }

  void _resolveCallback(JavascriptRuntime rt, String id, dynamic value) {
    if (_disposed) return;
    try {
      rt.evaluate(
        'if(__cbs["$id"]){__cbs["$id"](${jsonEncode(value)});delete __cbs["$id"];}',
      );
      rt.executePendingJob();
    } catch (e) {
      debugPrint('[JsWidgetEngine] resolve callback error: $e');
    }
  }
}
