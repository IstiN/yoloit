import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin_base.dart';

class WebViewManager {
  static final instance = WebViewManager._();
  WebViewManager._({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  factory WebViewManager.testInstance({DateTime Function()? clock}) =>
      WebViewManager._(clock: clock);

  DateTime Function() _clock;

  /// Test hook to override the clock used for retention bookkeeping
  /// (flutter_test advances timers but not `DateTime.now()`).
  @visibleForTesting
  set debugClock(DateTime Function() clock) => _clock = clock;

  /// Grace period a detached (hidden) controller is kept alive so board
  /// switches can re-attach instantly. After this TTL the controller is
  /// disposed and forgotten; a later re-attach recreates it from the panel's
  /// persisted URL/state exactly like a fresh panel.
  static const Duration kDetachedRetentionTTL = Duration(minutes: 4);

  /// Single shared timer driving eviction of detached controllers
  /// (never one timer per panel).
  Timer? _evictionTimer;

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
  /// Re-registering a detached controller cancels its pending eviction.
  void register(String panelId, WebViewController controller) {
    final existing = _entries[panelId];
    if (identical(existing?.controller, controller)) {
      existing!
        ..attached = true
        ..detachedAt = null;
      _scheduleEviction();
      return;
    }
    _entries[panelId] = WebViewEntry(controller: controller);
    _scheduleEviction();
  }

  /// Detach UI — keep controller alive for [kDetachedRetentionTTL] so a
  /// board switch can re-attach instantly, then dispose it via the shared
  /// eviction timer (called on widget dispose).
  void detach(String panelId) {
    final entry = _entries[panelId];
    if (entry == null) return;
    entry.attached = false;
    entry.detachedAt ??= _clock();
    final controller = entry.controller;
    if (controller != null) {
      unawaited(controller.setNavigationDelegate(NavigationDelegate()));
      unawaited(removeYoloNewTabChannel(panelId));
    }
    _scheduleEviction();
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

  /// Remove and forget controller immediately (panel deleted).
  ///
  /// Unlike [detach] there is no grace period: the controller is disposed
  /// right away and the shared overlay reference in
  /// [WebpagePluginBase.controllers] is dropped so the native view is
  /// released.
  void remove(String panelId) {
    final entry = _entries.remove(panelId);
    WebpagePluginBase.controllers.remove(panelId);
    final controller = entry?.controller;
    if (controller == null) {
      _scheduleEviction();
      return;
    }
    unawaited(controller.setNavigationDelegate(NavigationDelegate()));
    unawaited(_removeYoloNewTabChannelFor(panelId, controller));
    _scheduleEviction();
  }

  /// Dispose all.
  void disposeAll() {
    _evictionTimer?.cancel();
    _evictionTimer = null;
    final panelIds = _entries.keys.toList(growable: false);
    for (final panelId in panelIds) {
      remove(panelId);
    }
  }

  /// Schedule the single shared eviction timer for the earliest expiring
  /// detached entry; cancels the timer when nothing is pending eviction.
  void _scheduleEviction() {
    _evictionTimer?.cancel();
    _evictionTimer = null;
    final now = _clock();
    var earliest = Duration.zero;
    var found = false;
    for (final entry in _entries.values) {
      if (entry.attached) continue;
      final detachedAt = entry.detachedAt;
      if (detachedAt == null) continue;
      final remaining = kDetachedRetentionTTL - now.difference(detachedAt);
      final delay = remaining.isNegative ? Duration.zero : remaining;
      if (!found || delay < earliest) {
        earliest = delay;
        found = true;
      }
    }
    if (!found) return;
    _evictionTimer = Timer(earliest, _evictExpired);
  }

  void _evictExpired() {
    _evictionTimer = null;
    final now = _clock();
    final expired =
        _entries.entries
            .where(
              (e) =>
                  !e.value.attached &&
                  e.value.detachedAt != null &&
                  now.difference(e.value.detachedAt!) >= kDetachedRetentionTTL,
            )
            .map((e) => e.key)
            .toList(growable: false);
    for (final panelId in expired) {
      _evict(panelId);
    }
    _scheduleEviction();
  }

  /// Dispose a controller evicted from [_entries]: clear its navigation
  /// delegate and JS channel so timers/media/network stop, and drop the
  /// shared overlay reference in [WebpagePluginBase.controllers].
  void _evict(String panelId) {
    final entry = _entries.remove(panelId);
    WebpagePluginBase.controllers.remove(panelId);
    final controller = entry?.controller;
    if (controller == null) return;
    unawaited(controller.setNavigationDelegate(NavigationDelegate()));
    unawaited(_removeYoloNewTabChannelFor(panelId, controller));
  }

  /// Manually run the detached-retention eviction pass (honors
  /// [kDetachedRetentionTTL] against the manager clock).
  @visibleForTesting
  void evictExpiredDetachedNow() => _evictExpired();

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

  /// When the widget was last detached; null while attached. Set by
  /// [WebViewManager.detach], cleared by [WebViewManager.register].
  DateTime? detachedAt;

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
