import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewManager {
  static final instance = WebViewManager._();
  WebViewManager._();

  factory WebViewManager.testInstance() => WebViewManager._();

  final Map<String, WebViewEntry> _entries = {};

  /// FIFO queue of pending script-channel mutations per panel.
  ///
  /// WKUserContentController throws an NSException (process-killing SIGABRT)
  /// when a script message handler is added while one with the same name is
  /// still registered. All add/remove operations on the YoloNewTab channel
  /// must therefore be serialized per panel so remove→add pairs can never
  /// interleave with another add.
  final Map<String, Future<void>> _channelQueues = {};

  static const String kNewTabChannel = 'YoloNewTab';

  Future<void> _enqueueChannelOp(
    String panelId,
    Future<void> Function() op,
  ) {
    final prev = _channelQueues[panelId] ?? Future<void>.value();
    final next = prev.then((_) => op()).catchError((Object _) {});
    _channelQueues[panelId] = next;
    // Drop the entry once drained so stale (completed) futures are never
    // chained upon later — a listener registered on a future that completed
    // in a defunct async zone may never fire.
    next.whenComplete(() {
      if (identical(_channelQueues[panelId], next)) {
        _channelQueues.remove(panelId);
      }
    });
    return next;
  }

  Future<void> _enqueueControllerChannelOp(
    String panelId,
    WebViewController? controller,
    Future<void> Function(WebViewController controller) op,
  ) {
    if (controller == null) return Future<void>.value();
    return _enqueueChannelOp(panelId, () => op(controller));
  }

  /// Register the YoloNewTab JS channel on the panel's controller.
  ///
  /// Serialized per panel and idempotent: any previously registered handler
  /// is removed first, so concurrent callers cannot trigger WebKit's
  /// duplicate-handler NSException.
  Future<void> ensureYoloNewTabChannel(
    String panelId,
    void Function(JavaScriptMessage message) onMessageReceived,
  ) {
    return _enqueueControllerChannelOp(
      panelId,
      _entries[panelId]?.controller,
      (controller) async {
        try {
          await controller.removeJavaScriptChannel(kNewTabChannel);
        } catch (_) {}
        await controller.addJavaScriptChannel(
          kNewTabChannel,
          onMessageReceived: onMessageReceived,
        );
      },
    );
  }

  /// Remove the YoloNewTab JS channel (serialized with other channel ops).
  Future<void> removeYoloNewTabChannel(String panelId) {
    return _enqueueControllerChannelOp(
      panelId,
      _entries[panelId]?.controller,
      (controller) async {
        try {
          await controller.removeJavaScriptChannel(kNewTabChannel);
        } catch (_) {}
      },
    );
  }

  /// Serialized channel removal for an entry already evicted from [_entries]
  /// (used by [remove] so the removal is still ordered after pending adds).
  Future<void> _removeYoloNewTabChannelFor(
    String panelId,
    WebViewController? controller,
  ) {
    return _enqueueControllerChannelOp(panelId, controller, (controller) async {
      try {
        await controller.removeJavaScriptChannel(kNewTabChannel);
      } catch (_) {}
    });
  }

  /// Get an existing controller or null.
  WebViewController? controller(String panelId) =>
      _entries[panelId]?.controller;

  /// Register a controller (called by widget when creating one).
  void register(String panelId, WebViewController controller) {
    final existing = _entries[panelId];
    if (identical(existing?.controller, controller)) {
      existing!.attached = true;
      return;
    }
    _entries[panelId] = WebViewEntry(controller: controller);
  }

  /// Detach UI — keep controller alive (called on widget dispose).
  void detach(String panelId) {
    final entry = _entries[panelId];
    if (entry == null) return;
    entry.attached = false;
    final controller = entry.controller;
    if (controller == null) return;
    unawaited(controller.setNavigationDelegate(NavigationDelegate()));
    unawaited(removeYoloNewTabChannel(panelId));
  }

  /// Check if a controller exists for this panel.
  bool has(String panelId) => _entries.containsKey(panelId);

  /// Execute JavaScript on a panel's WebView.
  /// Works even when the widget is not mounted (headless).
  Future<String?> runJavaScript(String panelId, String js) async {
    final entry = _entries[panelId];
    if (entry == null) return null;
    await entry.runJavaScript(js);
    return null;
  }

  /// Execute JavaScript and return the result.
  Future<Object?> runJavaScriptReturningResult(String panelId, String js) {
    final entry = _entries[panelId];
    if (entry == null) return Future<Object?>.value(null);
    return entry.runJavaScriptReturningResult(js);
  }

  /// Get the current URL of a panel's WebView.
  Future<String?> currentUrl(String panelId) {
    final entry = _entries[panelId];
    if (entry == null) return Future<String?>.value(null);
    return entry.currentUrl();
  }

  /// Get page title.
  Future<String?> pageTitle(String panelId) {
    final entry = _entries[panelId];
    if (entry == null) return Future<String?>.value(null);
    return entry.pageTitle();
  }

  /// Remove and forget controller (panel deleted).
  void remove(String panelId) {
    final entry = _entries.remove(panelId);
    final controller = entry?.controller;
    if (controller == null) return;
    unawaited(controller.setNavigationDelegate(NavigationDelegate()));
    unawaited(_removeYoloNewTabChannelFor(panelId, controller));
  }

  /// Dispose all.
  void disposeAll() {
    final panelIds = _entries.keys.toList(growable: false);
    for (final panelId in panelIds) {
      remove(panelId);
    }
  }

  @visibleForTesting
  void registerEntry(String panelId, WebViewEntry entry) {
    entry.attached = true;
    _entries[panelId] = entry;
  }

  @visibleForTesting
  bool isAttached(String panelId) => _entries[panelId]?.attached ?? false;

  @visibleForTesting
  List<String> get activePanelIds => _entries.keys.toList(growable: false);
}

class WebViewEntry {
  WebViewEntry({
    this.controller,
    Future<void> Function(String js)? runJavaScript,
    Future<Object?> Function(String js)? runJavaScriptReturningResult,
    Future<String?> Function()? currentUrl,
    Future<String?> Function()? pageTitle,
    this.attached = true,
  }) : _runJavaScript = runJavaScript,
       _runJavaScriptReturningResult = runJavaScriptReturningResult,
       _currentUrl = currentUrl,
       _pageTitle = pageTitle;

  final WebViewController? controller;
  final Future<void> Function(String js)? _runJavaScript;
  final Future<Object?> Function(String js)? _runJavaScriptReturningResult;
  final Future<String?> Function()? _currentUrl;
  final Future<String?> Function()? _pageTitle;
  bool attached;

  Future<void> runJavaScript(String js) async {
    final callback = _runJavaScript;
    if (callback != null) {
      await callback(js);
      return;
    }
    final controller = this.controller;
    if (controller != null) {
      await controller.runJavaScript(js);
    }
  }

  Future<Object?> runJavaScriptReturningResult(String js) async {
    final callback = _runJavaScriptReturningResult;
    if (callback != null) {
      return callback(js);
    }
    return controller?.runJavaScriptReturningResult(js);
  }

  Future<String?> currentUrl() async {
    final callback = _currentUrl;
    if (callback != null) {
      return callback();
    }
    return controller?.currentUrl();
  }

  Future<String?> pageTitle() async {
    final callback = _pageTitle;
    if (callback != null) {
      return callback();
    }
    return controller?.getTitle();
  }
}
