import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yoloit/features/board/widgets/js_widget_bootstrap.dart';
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
  }) : _storage = Map<String, dynamic>.from(initialStorage),
       _initialTheme = Map<String, dynamic>.from(initialTheme);

  /// Widget ID used to namespace secure storage keys.
  final String widgetId;
  final void Function(Map<String, dynamic> tree) onRender;
  final void Function(String title) onSetTitle;
  final void Function(Map<String, dynamic> storage) onStorageUpdate;

  /// Absolute path to the app's folder — used by loadAsset bridge.
  final String? appDir;

  final Map<String, dynamic> _storage;
  final Map<String, dynamic> _initialTheme;
  Map<String, dynamic>? _exportedState;
  JavascriptRuntime? _runtime;
  Completer<void>? _eventCompleter;
  bool _disposed = false;
  final Map<String, Timer> _intervals = {};
  final List<Map<String, dynamic>> _consoleLogs = [];
  static const int _maxLogs = 200;
  Ticker? _rafTicker;
  final Map<String, bool> _rafCallbacks = {};

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
  Map<String, dynamic>? get exportedState =>
      _exportedState == null ? null : Map<String, dynamic>.from(_exportedState!);

  /// Push updated theme colors into the running JS widget.
  void updateTheme(Map<String, dynamic> colors) {
    final rt = _runtime;
    if (rt == null || _disposed) return;
    try {
      rt.evaluate(
        'yoloit.theme=${jsonEncode(colors)};'
        'if(yoloit._onThemeChange){try{yoloit._onThemeChange(yoloit.theme);}catch(e){}}',
      );
      rt.executePendingJob();
    } catch (e) {
      debugPrint('[JsWidgetEngine] updateTheme error: $e');
    }
  }

  Future<void> run(String widgetJs) async {
    await dispose();
    _disposed = false;
    _consoleLogs.clear();
    _exportedState = null;

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
    final completer = Completer<void>();
    _eventCompleter?.complete();
    _eventCompleter = completer;
    try {
      final encodedAction = jsonEncode(actionId);
      final encodedPayload = jsonEncode(payload ?? {});
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
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[JsWidgetEngine] callEvent timeout for $actionId');
        },
      );
      rt.executePendingJob();
    } catch (e) {
      debugPrint('[JsWidgetEngine] callEvent error: $e');
      if (!completer.isCompleted) completer.complete();
    } finally {
      if (identical(_eventCompleter, completer)) {
        _eventCompleter = null;
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final t in _intervals.values) {
      t.cancel();
    }
    _intervals.clear();
    _rafTicker?.dispose();
    _rafTicker = null;
    _rafCallbacks.clear();
    _runtime?.dispose();
    _runtime = null;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _parseArgs(dynamic args) => (args is Map)
      ? Map<String, dynamic>.from(args)
      : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;

  void _setupBridges(JavascriptRuntime rt) {
    // flutter_js bridges are invoked from JS via: sendMessage(channelName, jsonString)
    // The Dart callback receives args = jsonDecode(jsonString) — already decoded.

    // yoloit.render(jsonTree)
    rt.setupBridge('__yoloit_render', (args) {
      if (_disposed) return;
      try {
        debugPrint('[JsWidgetEngine] render bridge called, args type: ${args.runtimeType}');
        final tree = (args is Map)
            ? Map<String, dynamic>.from(args)
            : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;
        debugPrint('[JsWidgetEngine] render tree type: ${tree['type']}');
        onRender(tree);
      } catch (e) {
        debugPrint('[JsWidgetEngine] render bridge error: $e args=$args (${args.runtimeType})');
      }
    });

    // yoloit.fetchJson(url, opts) — goes through Dart, no CORS
    rt.setupBridge('__yoloit_fetch', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      if (!WidgetPermissionsService.instance.isAllowed('fetch')) {
        _resolveCallback(rt, id, {'__error': 'fetchJson is disabled in Settings → Apps & Widgets'});
        return;
      }
      final url = req['url'] as String;
      final method = (req['method'] as String? ?? 'GET').toUpperCase();
      final headers = (req['headers'] as Map?)?.cast<String, String>() ?? {};

      Future(() async {
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
      });
    });

    // yoloit.storage.get(key)
    rt.setupBridge('__yoloit_storage_get', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      if (!WidgetPermissionsService.instance.isAllowed('storage')) {
        _resolveCallback(rt, id, {'__error': 'storage is disabled in Settings → Apps & Widgets'});
        return;
      }
      final key = req['key'] as String;
      _resolveCallback(rt, id, _storage[key]);
    });

    // yoloit.storage.set(key, value)
    // Flow: JS → sendMessage → Dart _storage[key]=value → onStorageUpdate(shallow copy)
    // → plugin onUpdateState({..., '_storage': newStorage}) → cubit _persist() → SharedPreferences.
    // jsonEncode handles List<dynamic> correctly, so array storage is safe across hot restarts.
    rt.setupBridge('__yoloit_storage_set', (args) {
      if (_disposed) return;
      if (!WidgetPermissionsService.instance.isAllowed('storage')) return;
      final req = _parseArgs(args);
      _storage[req['key'] as String] = req['value'];
      onStorageUpdate(Map<String, dynamic>.from(_storage));
    });

    // yoloit.panel.setTitle(title)
    rt.setupBridge('__yoloit_set_title', (title) {
      if (_disposed) return;
      onSetTitle(title?.toString() ?? '');
    });

    // Async widget event completion (see callEvent).
    rt.setupBridge('__yoloit_event_done', (args) {
      if (_disposed) return;
      try {
        if (args is Map && args['error'] != null) {
          debugPrint(
            '[JsWidgetEngine] event error: ${args['error']}',
          );
        }
      } catch (_) {}
      final pending = _eventCompleter;
      if (pending != null && !pending.isCompleted) {
        pending.complete();
      }
    });

    // yoloit.exportState(obj) — structured data for app:state CLI
    rt.setupBridge('__yoloit_export_state', (args) {
      if (_disposed) return;
      try {
        _exportedState =
            args is Map
                ? Map<String, dynamic>.from(args)
                : Map<String, dynamic>.from(_parseArgs(args));
      } catch (_) {
        _exportedState = null;
      }
    });

    // console.log
    rt.setupBridge('__yoloit_log', (args) {
      final msg = args?.toString() ?? '';
      debugPrint('[JsWidget:$widgetId] $msg');
      _consoleLogs.add({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'msg': msg,
      });
      if (_consoleLogs.length > _maxLogs) _consoleLogs.removeAt(0);
    });

    // setInterval — Dart-backed
    rt.setupBridge('__yoloit_set_interval', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      final ms = (req['ms'] as num?)?.toInt() ?? 1000;
      _intervals[id]?.cancel();
      _intervals[id] = Timer.periodic(Duration(milliseconds: ms), (_) {
        if (_disposed) return;
        try {
          rt.evaluate('if(__iv_cbs["$id"])__iv_cbs["$id"]()');
          rt.executePendingJob();
        } catch (_) {}
      });
    });

    // clearInterval
    rt.setupBridge('__yoloit_clear_interval', (id) {
      final idStr = id?.toString() ?? '';
      _intervals[idStr]?.cancel();
      _intervals.remove(idStr);
    });

    // yoloit.secrets.get(key) — encrypted secure storage, per-widget namespace
    rt.setupBridge('__yoloit_secrets_get', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      if (!WidgetPermissionsService.instance.isAllowed('secrets')) {
        _resolveCallback(rt, id, {'__error': 'secrets is disabled in Settings → Apps & Widgets'});
        return;
      }
      final key = '_widget_${widgetId}_${req['key'] as String}';
      Future(() async {
        try {
          final val = await _secureStorage.read(key: key);
          if (!_disposed) _resolveCallback(rt, id, val);
        } catch (e) {
          if (!_disposed) _resolveCallback(rt, id, null);
        }
      });
    });

    // yoloit.secrets.set(key, value)
    rt.setupBridge('__yoloit_secrets_set', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      if (!WidgetPermissionsService.instance.isAllowed('secrets')) {
        _resolveCallback(rt, id, false);
        return;
      }
      final key = '_widget_${widgetId}_${req['key'] as String}';
      final value = req['value'];
      Future(() async {
        try {
          if (value == null) {
            await _secureStorage.delete(key: key);
          } else {
            await _secureStorage.write(key: key, value: value.toString());
          }
          if (!_disposed) _resolveCallback(rt, id, true);
        } catch (e) {
          if (!_disposed) _resolveCallback(rt, id, false);
        }
      });
    });

    // yoloit.loadAsset(path) — read a file from the app's folder
    rt.setupBridge('__yoloit_load_asset', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      final assetPath = req['path'] as String? ?? '';
      Future(() async {
        try {
          final dir = appDir;
          if (dir == null || dir.isEmpty) {
            if (!_disposed) _resolveCallback(rt, id, null);
            return;
          }
          final file = File('$dir${Platform.pathSeparator}${assetPath.replaceAll('/', Platform.pathSeparator)}');
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
      });
    });

    // yoloit.exec(cmd) — run a yoloit CLI command, returns stdout
    rt.setupBridge('__yoloit_exec', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      final cmd = req['cmd'] as String? ?? '';
      // Permission check
      if (!WidgetPermissionsService.instance.isAllowed('exec')) {
        _resolveCallback(rt, id, {'__error': 'exec is disabled in Settings → Apps & Widgets'});
        return;
      }
      // Security: only allow yoloit commands
      if (!cmd.startsWith('yoloit ') && cmd != 'yoloit') {
        _resolveCallback(rt, id, {'__error': 'Only yoloit commands are allowed'});
        return;
      }
      Future(() async {
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
      });
    });

    // requestAnimationFrame — vsync-driven frame callback
    rt.setupBridge('__yoloit_raf', (args) {
      if (_disposed) return;
      final req = _parseArgs(args);
      final id = req['id'] as String;
      _rafCallbacks[id] = true;
      _ensureRafTicker(rt);
    });

    // cancelAnimationFrame
    rt.setupBridge('__yoloit_caf', (id) {
      _rafCallbacks.remove(id?.toString() ?? '');
      if (_rafCallbacks.isEmpty) {
        _rafTicker?.stop();
      }
    });
  }

  void _resolveCallback(JavascriptRuntime rt, String id, dynamic value) {
    if (_disposed) return;
    try {
      rt.evaluate('if(__cbs["$id"]){__cbs["$id"](${jsonEncode(value)});delete __cbs["$id"];}');
      rt.executePendingJob();
    } catch (e) {
      debugPrint('[JsWidgetEngine] resolve callback error: $e');
    }
  }

  void _ensureRafTicker(JavascriptRuntime rt) {
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
      // Copy keys to avoid concurrent modification
      final ids = List<String>.from(_rafCallbacks.keys);
      _rafCallbacks.clear();
      try {
        for (final id in ids) {
          rt.evaluate('if(__raf_cbs["$id"]){__raf_cbs["$id"]($ms);delete __raf_cbs["$id"];}');
        }
        rt.executePendingJob();
      } catch (e) {
        debugPrint('[JsWidgetEngine] RAF tick error: $e');
      }
    });
    _rafTicker!.start();
  }
}
