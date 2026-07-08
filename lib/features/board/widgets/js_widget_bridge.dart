import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

/// Callback used by the bridge to return async values to the JS runtime.
typedef JsResolveCallback = void Function(String id, dynamic value);

/// Callback for an HTTP request initiated by `yoloit.fetchJson`.
typedef JsFetchHandler = Future<void> Function(
  String id,
  String url,
  String method,
  Map<String, String> headers,
);

/// Callback for `yoloit.secrets.get(key)`.
typedef JsSecretsReadHandler = Future<void> Function(String id, String key);

/// Callback for `yoloit.secrets.set(key, value)`.
typedef JsSecretsWriteHandler = Future<void> Function(
  String id,
  String key,
  dynamic value,
);

/// Callback for `yoloit.loadAsset(path)`.
typedef JsLoadAssetHandler = Future<void> Function(String id, String path);

/// Callback for `yoloit.exec(cmd)`.
typedef JsExecHandler = Future<void> Function(String id, String cmd);

/// Callback invoked when a Dart-backed interval fires.
typedef JsIntervalTickHandler = void Function(String id);

/// Callback invoked when a Dart-backed animation frame fires.
typedef JsRafTickHandler = void Function(String id, int elapsedMs);

/// Shared bridge logic for the JS widget engine.
///
/// Both the VM ([flutter_js]) and web (Worker/iframe) engines use this class
/// to handle the `yoloit.*` API surface: render, storage, timers, secrets,
/// fetch, exec, exportState and event completion. Platform-specific I/O
/// (network, secure storage, file system, process execution) is injected via
/// callbacks so the bridge stays testable on any platform.
class JsWidgetBridge {
  JsWidgetBridge({
    required this.widgetId,
    required this.onRender,
    required this.onSetTitle,
    required this.onStorageUpdate,
    required this.onLog,
    required this.isDisposed,
    this.appDir,
    required this.resolveCallback,
    required this.fetchHandler,
    required this.secretsGetHandler,
    required this.secretsSetHandler,
    required this.loadAssetHandler,
    required this.execHandler,
    required this.intervalTickHandler,
    required this.rafTickHandler,
    required Map<String, dynamic> initialStorage,
  }) : _storage = Map<String, dynamic>.from(initialStorage);

  final String widgetId;
  final void Function(Map<String, dynamic> tree) onRender;
  final void Function(String title) onSetTitle;
  final void Function(Map<String, dynamic> storage) onStorageUpdate;
  final void Function(String log) onLog;
  final bool Function() isDisposed;
  final String? appDir;
  JsResolveCallback resolveCallback;
  JsFetchHandler fetchHandler;
  JsSecretsReadHandler secretsGetHandler;
  JsSecretsWriteHandler secretsSetHandler;
  JsLoadAssetHandler loadAssetHandler;
  JsExecHandler execHandler;
  JsIntervalTickHandler intervalTickHandler;
  JsRafTickHandler rafTickHandler;

  final Map<String, dynamic> _storage;
  Map<String, dynamic>? _exportedState;
  final Map<String, Timer> _intervals = {};
  Ticker? _rafTicker;
  final Map<String, bool> _rafCallbacks = {};
  Completer<void>? _eventCompleter;

  /// Last structured state exported via `yoloit.exportState(...)`.
  Map<String, dynamic>? get exportedState =>
      _exportedState == null ? null : Map<String, dynamic>.from(_exportedState!);

  /// Returns the JS snippet used to update the widget theme.
  static String updateThemeJs(Map<String, dynamic> colors) {
    return 'yoloit.theme=${jsonEncode(colors)};'
        'if(yoloit._onThemeChange){try{yoloit._onThemeChange(yoloit.theme);}catch(e){}}';
  }

  /// Dispatches a message coming from the JS runtime.
  Future<void> dispatch(String channel, dynamic payload) async {
    if (isDisposed()) return;
    switch (channel) {
      case '__yoloit_render':
        _handleRender(payload);
      case '__yoloit_fetch':
        await _handleFetch(payload);
      case '__yoloit_storage_get':
        _handleStorageGet(payload);
      case '__yoloit_storage_set':
        _handleStorageSet(payload);
      case '__yoloit_set_title':
        _handleSetTitle(payload);
      case '__yoloit_event_done':
        _handleEventDone(payload);
      case '__yoloit_export_state':
        _handleExportState(payload);
      case '__yoloit_log':
        _handleLog(payload);
      case '__yoloit_set_interval':
        _handleSetInterval(payload);
      case '__yoloit_clear_interval':
        _handleClearInterval(payload);
      case '__yoloit_raf':
        _handleRaf(payload);
      case '__yoloit_caf':
        _handleCaf(payload);
      case '__yoloit_secrets_get':
        await _handleSecretsGet(payload);
      case '__yoloit_secrets_set':
        await _handleSecretsSet(payload);
      case '__yoloit_load_asset':
        await _handleLoadAsset(payload);
      case '__yoloit_exec':
        await _handleExec(payload);
    }
  }

  /// Runs [send] and waits until the JS event handler signals completion.
  Future<void> callEvent(void Function() send) async {
    final completer = Completer<void>();
    _eventCompleter?.complete();
    _eventCompleter = completer;
    send();
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('[JsWidgetBridge] callEvent timeout');
      },
    );
    if (identical(_eventCompleter, completer)) {
      _eventCompleter = null;
    }
  }

  /// Releases all timers and tickers owned by the bridge.
  void dispose() {
    for (final t in _intervals.values) {
      t.cancel();
    }
    _intervals.clear();
    _rafTicker?.dispose();
    _rafTicker = null;
    _rafCallbacks.clear();
    _eventCompleter?.complete();
    _eventCompleter = null;
  }

  Map<String, dynamic> _parseArgs(dynamic args) => (args is Map)
      ? Map<String, dynamic>.from(args)
      : jsonDecode(args?.toString() ?? '{}') as Map<String, dynamic>;

  void _handleRender(dynamic args) {
    try {
      final tree = _parseArgs(args);
      onRender(tree);
    } catch (e) {
      debugPrint('[JsWidgetBridge] render error: $e');
    }
  }

  Future<void> _handleFetch(dynamic args) async {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('fetch')) {
      resolveCallback(id, {
        '__error': 'fetchJson is disabled in Settings → Apps & Widgets',
      });
      return;
    }
    final url = req['url'] as String;
    final method = (req['method'] as String? ?? 'GET').toUpperCase();
    final headers = (req['headers'] as Map?)?.cast<String, String>() ?? {};
    await fetchHandler(id, url, method, headers);
  }

  void _handleStorageGet(dynamic args) {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('storage')) {
      resolveCallback(id, {
        '__error': 'storage is disabled in Settings → Apps & Widgets',
      });
      return;
    }
    final key = req['key'] as String;
    resolveCallback(id, _storage[key]);
  }

  void _handleStorageSet(dynamic args) {
    if (!WidgetPermissionsService.instance.isAllowed('storage')) return;
    final req = _parseArgs(args);
    _storage[req['key'] as String] = req['value'];
    onStorageUpdate(Map<String, dynamic>.from(_storage));
  }

  void _handleSetTitle(dynamic title) {
    onSetTitle(title?.toString() ?? '');
  }

  void _handleEventDone(dynamic args) {
    try {
      final decoded = _parseArgs(args);
      if (decoded['error'] != null) {
        debugPrint('[JsWidgetBridge] event error: ${decoded['error']}');
      }
    } catch (_) {}
    final pending = _eventCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  void _handleExportState(dynamic args) {
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
    onLog(args?.toString() ?? '');
  }

  void _handleSetInterval(dynamic args) {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    final ms = (req['ms'] as num?)?.toInt() ?? 1000;
    _intervals[id]?.cancel();
    _intervals[id] = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (isDisposed()) return;
      intervalTickHandler(id);
    });
  }

  void _handleClearInterval(dynamic id) {
    final idStr = id?.toString() ?? '';
    _intervals[idStr]?.cancel();
    _intervals.remove(idStr);
  }

  void _handleRaf(dynamic args) {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    _rafCallbacks[id] = true;
    _ensureRafTicker();
  }

  void _handleCaf(dynamic id) {
    final idStr = id?.toString() ?? '';
    _rafCallbacks.remove(idStr);
    if (_rafCallbacks.isEmpty) {
      _rafTicker?.stop();
    }
  }

  Future<void> _handleSecretsGet(dynamic args) async {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('secrets')) {
      resolveCallback(id, {
        '__error': 'secrets is disabled in Settings → Apps & Widgets',
      });
      return;
    }
    await secretsGetHandler(id, req['key'] as String);
  }

  Future<void> _handleSecretsSet(dynamic args) async {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    if (!WidgetPermissionsService.instance.isAllowed('secrets')) {
      resolveCallback(id, false);
      return;
    }
    await secretsSetHandler(id, req['key'] as String, req['value']);
  }

  Future<void> _handleLoadAsset(dynamic args) async {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    final assetPath = req['path'] as String? ?? '';
    await loadAssetHandler(id, assetPath);
  }

  Future<void> _handleExec(dynamic args) async {
    final req = _parseArgs(args);
    final id = req['id'] as String;
    final cmd = req['cmd'] as String? ?? '';
    await execHandler(id, cmd);
  }

  void _ensureRafTicker() {
    if (_rafTicker != null) {
      if (!_rafTicker!.isTicking) _rafTicker!.start();
      return;
    }
    _rafTicker = Ticker((elapsed) {
      if (isDisposed() || _rafCallbacks.isEmpty) {
        _rafTicker?.stop();
        return;
      }
      final ms = elapsed.inMilliseconds;
      final ids = List<String>.from(_rafCallbacks.keys);
      _rafCallbacks.clear();
      for (final id in ids) {
        rafTickHandler(id, ms);
      }
    });
    _rafTicker!.start();
  }
}
