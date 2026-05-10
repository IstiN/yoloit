import 'package:flutter/services.dart';

/// Controls WKWebViews on macOS via a native MethodChannel.
class WebViewZoomService {
  static const _channel = MethodChannel('yoloit/webview_zoom');

  static double _lastZoom = -1;

  /// Sets pageZoom on ALL WKWebViews in the app. Legacy / unused by viewport
  /// fix; kept for compatibility.
  static Future<void> setPageZoom(double zoom) async {
    if ((zoom - _lastZoom).abs() < 0.001) return;
    _lastZoom = zoom;
    try {
      await _channel.invokeMethod<int>('setPageZoom', {'zoom': zoom});
    } catch (_) {}
  }

  /// Installs [script] as a WKUserScript at documentStart on ALL WKWebViews
  /// then reloads them so the script runs before the page's own JS.
  ///
  /// Used by the Viewport Lab to override window.innerWidth before YouTube's
  /// player JS measures it.
  static Future<int> installInitScript(String script, {bool reload = true}) async {
    try {
      final n = await _channel.invokeMethod<int>(
        'installInitScript',
        {'script': script, 'reload': reload},
      );
      return n ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Removes any user scripts installed by [installInitScript] from ALL
  /// WKWebViews. Optionally reloads.
  static Future<int> clearInitScripts({bool reload = true}) async {
    try {
      final n = await _channel.invokeMethod<int>(
        'clearInitScripts',
        {'reload': reload},
      );
      return n ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

