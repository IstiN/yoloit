import WebKit
import ObjectiveC

/// Swizzles WKWebView.init(frame:configuration:) to enable the HTML5
/// Fullscreen API on every WKWebView created in the app. Must be called
/// once during application startup via `WKWebViewFullscreen.install()`.
///
/// Background: WKWebView.configuration returns a copy after creation, so
/// modifying it post-init has no effect. The only reliable way to enable
/// fullscreen is to modify the configuration *before* the webview is created.
enum WKWebViewFullscreen {
  static func install() {
    let origSel = NSSelectorFromString("initWithFrame:configuration:")
    let swizSel = #selector(WKWebView.yoloit_initWithFrame(_:configuration:))
    guard
      let origMethod = class_getInstanceMethod(WKWebView.self, origSel),
      let swizMethod = class_getInstanceMethod(WKWebView.self, swizSel)
    else {
      print("[WKWebViewFullscreen] swizzle failed: method not found")
      return
    }
    method_exchangeImplementations(origMethod, swizMethod)
  }
}

extension WKWebView {
  /// Replacement for `initWithFrame:configuration:`.
  /// Enables the Fullscreen API before calling the original init so the
  /// setting is baked into the webview from the start.
  @objc func yoloit_initWithFrame(_ frame: CGRect, configuration: WKWebViewConfiguration) -> WKWebView {
    // Patch the configuration's preferences before the real init runs.
    if #available(macOS 12.3, *) {
      configuration.preferences.isElementFullscreenEnabled = true
    } else {
      // Private KVC key for older macOS
      configuration.preferences.setValue(true, forKey: "fullScreenEnabled")
    }
    // After swizzle, this call routes to the *original* initWithFrame:configuration:
    return yoloit_initWithFrame(frame, configuration: configuration)
  }
}
