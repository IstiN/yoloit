import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

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
/// yoloit.storage.get(key)       // persistent per-panel storage
/// yoloit.storage.set(key, val)
/// yoloit.panel.setTitle(title)
/// yoloit.showError(msg)
/// setInterval(fn, ms)           // Dart-backed timer
/// clearInterval(id)
/// console.log(...)
/// ```
class JsWidgetEngine {
  JsWidgetEngine({
    required this.onRender,
    required this.onSetTitle,
    required this.onStorageUpdate,
    required Map<String, dynamic> initialStorage,
  }) : _storage = Map<String, dynamic>.from(initialStorage);

  final void Function(Map<String, dynamic> tree) onRender;
  final void Function(String title) onSetTitle;
  final void Function(Map<String, dynamic> storage) onStorageUpdate;

  Map<String, dynamic> _storage;
  JavascriptRuntime? _runtime;
  bool _disposed = false;
  final Map<String, Timer> _intervals = {};

  // ── Public API ──────────────────────────────────────────────────────────

  Future<void> run(String widgetJs) async {
    await dispose();
    _disposed = false;

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

      final bootstrapResult = runtime.evaluate(_bootstrap);
      if (bootstrapResult.isError) {
        debugPrint('[JsWidgetEngine] bootstrap error: ${bootstrapResult.stringResult}');
      }

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
      debugPrint('[JsWidgetEngine] widget code done, uiTree set: ${_disposed}');
    } catch (e) {
      debugPrint('[JsWidgetEngine] startup error: $e');
      rethrow;
    }
  }

  /// Call the JS `handleEvent(actionId, payload)` function.
  void callEvent(String actionId, [Map<String, dynamic>? payload]) {
    final rt = _runtime;
    if (rt == null || _disposed) return;
    try {
      final p = jsonEncode(payload ?? {});
      // Support both yoloit.onEvent(fn) registration and global handleEvent
      rt.evaluate(
        'var __h=yoloit._handler||(typeof handleEvent==="function"?handleEvent:null);'
        'if(__h){try{__h(${jsonEncode(actionId)},$p);}catch(e){yoloit.showError(e.message||String(e));}}'
      );
      rt.executePendingJob();
    } catch (e) {
      debugPrint('[JsWidgetEngine] callEvent error: $e');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final t in _intervals.values) {
      t.cancel();
    }
    _intervals.clear();
    _runtime?.dispose();
    _runtime = null;
  }

  // ── Private ──────────────────────────────────────────────────────────────

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
      final req = (args is Map)
          ? Map<String, dynamic>.from(args)
          : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;
      final id = req['id'] as String;
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
      final req = (args is Map)
          ? Map<String, dynamic>.from(args)
          : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;
      final id = req['id'] as String;
      final key = req['key'] as String;
      _resolveCallback(rt, id, _storage[key]);
    });

    // yoloit.storage.set(key, value)
    rt.setupBridge('__yoloit_storage_set', (args) {
      if (_disposed) return;
      final req = (args is Map)
          ? Map<String, dynamic>.from(args)
          : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;
      _storage[req['key'] as String] = req['value'];
      onStorageUpdate(Map<String, dynamic>.from(_storage));
    });

    // yoloit.panel.setTitle(title)
    rt.setupBridge('__yoloit_set_title', (title) {
      if (_disposed) return;
      onSetTitle(title?.toString() ?? '');
    });

    // console.log
    rt.setupBridge('__yoloit_log', (msg) {
      debugPrint('[JsWidget] ${msg?.toString() ?? ''}');
    });

    // setInterval — Dart-backed
    rt.setupBridge('__yoloit_set_interval', (args) {
      if (_disposed) return;
      final req = (args is Map)
          ? Map<String, dynamic>.from(args)
          : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;
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

  // ── Bootstrap JS injected before widget code ────────────────────────────

  // NOTE: flutter_js bridges are called from JS via the native `sendMessage(channelName, jsonString)`
  // function that flutter_js injects globally. Do NOT call channel names as functions directly.
  static const _bootstrap = r'''
var __cbs = {};
var __iv_cbs = {};
var __nid = function(){return Math.random().toString(36).slice(2)+Date.now().toString(36);};

var console = {
  log:   function(){sendMessage('__yoloit_log',JSON.stringify(Array.prototype.slice.call(arguments).join(' ')));},
  warn:  function(){sendMessage('__yoloit_log',JSON.stringify('[W] '+Array.prototype.slice.call(arguments).join(' ')));},
  error: function(){sendMessage('__yoloit_log',JSON.stringify('[E] '+Array.prototype.slice.call(arguments).join(' ')));}
};

var setTimeout = function(fn,ms){ var id=__nid(); __iv_cbs[id]=function(){fn();clearInterval(id);}; sendMessage('__yoloit_set_interval',JSON.stringify({id:id,ms:ms||0})); return id; };
var clearTimeout = function(id){ sendMessage('__yoloit_clear_interval',JSON.stringify(String(id))); };
var setInterval = function(fn,ms){ var id=__nid(); __iv_cbs[id]=fn; sendMessage('__yoloit_set_interval',JSON.stringify({id:id,ms:ms||1000})); return id; };
var clearInterval = function(id){ sendMessage('__yoloit_clear_interval',JSON.stringify(String(id))); delete __iv_cbs[String(id)]; };

var yoloit = {
  render: function(tree){ sendMessage('__yoloit_render', JSON.stringify(tree)); },

  fetchJson: function(url,opts){
    return new Promise(function(resolve,reject){
      var id=__nid();
      __cbs[id]=function(r){if(r&&r.__error)reject(new Error(r.__error));else resolve(r);};
      sendMessage('__yoloit_fetch', JSON.stringify({id:id,url:url,method:(opts&&opts.method)||'GET',headers:(opts&&opts.headers)||{}}));
    });
  },

  storage:{
    _c:{},
    get:function(key){
      if(key in this._c)return Promise.resolve(this._c[key]);
      var self=this;
      return new Promise(function(resolve){
        var id=__nid();
        __cbs[id]=function(v){self._c[key]=v;resolve(v);};
        sendMessage('__yoloit_storage_get', JSON.stringify({id:id,key:key}));
      });
    },
    set:function(key,val){
      this._c[key]=val;
      sendMessage('__yoloit_storage_set', JSON.stringify({key:key,value:val}));
      return Promise.resolve();
    }
  },

  panel:{setTitle:function(t){sendMessage('__yoloit_set_title', JSON.stringify(t));}},

  // Event handler registration — called from IIFE widgets:
  //   yoloit.onEvent(function handleEvent(actionId, payload) { ... });
  _handler: null,
  onEvent: function(fn){ yoloit._handler = fn; },

  showError:function(msg){
    yoloit.render({type:'center',child:{type:'padding',padding:[16,16,16,16],child:{
      type:'column',mainAxisSize:'min',children:[
        {type:'text',data:'\u26a0\ufe0f',style:{fontSize:28}},
        {type:'sizedBox',height:8},
        {type:'text',data:String(msg),style:{color:'#ef4444',fontSize:13,textAlign:'center'}}
      ]
    }}});
  }
};
''';
}
