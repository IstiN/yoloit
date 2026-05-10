import 'package:flutter/services.dart';

/// Controls WKWebView.pageZoom on macOS via a native MethodChannel.
///
/// Setting pageZoom = boardScale makes window.innerWidth = panelLogicalWidth
/// regardless of how small the WKWebView native frame is (due to board zoom).
/// This ensures sites like YouTube see the correct desktop viewport dimensions.
class WebViewZoomService {
  static const _channel = MethodChannel('yoloit/webview_zoom');

  static double _lastZoom = -1;

  /// Sets pageZoom on ALL WKWebViews in the app.
  /// No-op if [zoom] hasn't changed since last call.
  static Future<void> setPageZoom(double zoom) async {
    if ((zoom - _lastZoom).abs() < 0.001) return;
    _lastZoom = zoom;
    try {
      await _channel.invokeMethod<int>('setPageZoom', {'zoom': zoom});
    } catch (_) {
      // Non-fatal: pageZoom is a macOS-only enhancement.
    }
  }
}
