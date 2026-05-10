import Cocoa
import FlutterMacOS
import WebKit

/// MethodChannel plugin that sets WKWebView.pageZoom on all WKWebViews
/// in the Flutter view hierarchy. Called by Flutter when board scale changes
/// so that window.innerWidth reflects the panel's logical width, not the
/// scaled NSView frame width.
///
/// Channel: "yoloit/webview_zoom"
/// Method: "setPageZoom" — args: {"zoom": Double}
class WebViewZoomPlugin: NSObject, FlutterPlugin {

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "yoloit/webview_zoom",
      binaryMessenger: registrar.messenger
    )
    let instance = WebViewZoomPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setPageZoom":
      guard
        let args = call.arguments as? [String: Any],
        let zoom = args["zoom"] as? Double
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "zoom required", details: nil))
        return
      }
      let count = setPageZoom(zoom)
      result(count)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Traverses all NSViews in the application and sets pageZoom on every
  /// WKWebView found.  Returns the number of WKWebViews updated.
  @discardableResult
  private func setPageZoom(_ zoom: Double) -> Int {
    var count = 0
    for window in NSApplication.shared.windows {
      count += setPageZoom(zoom, inView: window.contentView)
    }
    return count
  }

  private func setPageZoom(_ zoom: Double, inView view: NSView?) -> Int {
    guard let view = view else { return 0 }
    var count = 0
    if let webView = view as? WKWebView {
      webView.pageZoom = zoom
      count += 1
    }
    for subview in view.subviews {
      count += setPageZoom(zoom, inView: subview)
    }
    return count
  }
}
