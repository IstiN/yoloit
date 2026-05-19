import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewManager {
  static final instance = WebViewManager._();
  WebViewManager._();

  factory WebViewManager.testInstance() => WebViewManager._();

  final Map<String, WebViewEntry> _entries = {};

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
    unawaited(
      controller.removeJavaScriptChannel('YoloNewTab').catchError((_) {}),
    );
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
    unawaited(
      controller.removeJavaScriptChannel('YoloNewTab').catchError((_) {}),
    );
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
