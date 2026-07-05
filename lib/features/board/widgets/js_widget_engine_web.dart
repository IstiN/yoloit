import 'dart:async';

import 'package:flutter/foundation.dart';

/// Web stub for [JsWidgetEngine].
///
/// The real engine depends on `flutter_js` and `dart:io`, which are not
/// available on web. This stub preserves the public API so callers (e.g.
/// [WidgetEngineManager]) compile on both targets.
class JsWidgetEngine {
  JsWidgetEngine({
    required this.widgetId,
    required this.onRender,
    required this.onSetTitle,
    required this.onStorageUpdate,
    required Map<String, dynamic> initialStorage,
    Map<String, dynamic> initialTheme = const {},
    this.appDir,
  }) : _initialTheme = Map<String, dynamic>.from(initialTheme);

  final String widgetId;
  final void Function(Map<String, dynamic> tree) onRender;
  final void Function(String title) onSetTitle;
  final void Function(Map<String, dynamic> storage) onStorageUpdate;
  final String? appDir;

  final Map<String, dynamic> _initialTheme;
  Map<String, dynamic>? _exportedState;

  /// Environment variables injected into exec calls.
  Map<String, String> envVars = {};

  /// Return and clear the accumulated console.log buffer.
  List<Map<String, dynamic>> flushLogs() => [];

  /// Return a copy of the console.log buffer without clearing it.
  List<Map<String, dynamic>> peekLogs() => [];

  /// Last structured state exported via `yoloit.exportState(...)`.
  Map<String, dynamic>? get exportedState =>
      _exportedState == null ? null : Map<String, dynamic>.from(_exportedState!);

  /// Push updated theme colors into the running JS widget.
  void updateTheme(Map<String, dynamic> colors) {}

  /// No-op on web: widget JS cannot be executed without a native JS engine.
  Future<void> run(String widgetJs) async {
    debugPrint('[JsWidgetEngine] run() is not supported on web');
  }

  /// No-op on web.
  Future<void> callEvent(String actionId, [Map<String, dynamic>? payload]) async {}

  /// No-op on web.
  Future<void> dispose() async {}
}
