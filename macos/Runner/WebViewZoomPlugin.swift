import Cocoa
import FlutterMacOS
import WebKit

/// MethodChannel plugin for controlling WKWebViews from Flutter.
/// Provides:
///   - setPageZoom: legacy visual zoom (not used)
///   - installInitScript: inject a WKUserScript at documentStart so JS like
///     `Object.defineProperty(window,'innerWidth',{get:()=>X})` runs BEFORE
///     YouTube/site JS loads. Also reloads each web view so the script takes
///     effect on the current page.
///   - clearInitScripts: remove our injected user scripts.
///
/// Channel: "yoloit/webview_zoom"
class WebViewZoomPlugin: NSObject, FlutterPlugin {

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "yoloit/webview_zoom",
      binaryMessenger: registrar.messenger
    )
    let instance = WebViewZoomPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  /// Marker so we can identify and remove our previously-installed scripts.
  private static let scriptMarker = "/*YOLOIT_INIT_SCRIPT*/"

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

    case "installInitScript":
      guard
        let args = call.arguments as? [String: Any],
        let script = args["script"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "script required", details: nil))
        return
      }
      let reload = (args["reload"] as? Bool) ?? true
      let count = installInitScript(script, reload: reload)
      result(count)

    case "clearInitScripts":
      let reload = (call.arguments as? [String: Any])?["reload"] as? Bool ?? true
      let count = clearInitScripts(reload: reload)
      result(count)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Page zoom (legacy, kept for compatibility)

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

  // MARK: - WKUserScript install

  @discardableResult
  private func installInitScript(_ script: String, reload: Bool) -> Int {
    let webViews = collectWebViews()
    let wrapped = WebViewZoomPlugin.scriptMarker + "\n" + script
    for webView in webViews {
      let controller = webView.configuration.userContentController
      // Remove existing yoloit scripts so each call replaces the previous.
      let kept = controller.userScripts.filter { !$0.source.hasPrefix(WebViewZoomPlugin.scriptMarker) }
      controller.removeAllUserScripts()
      for s in kept { controller.addUserScript(s) }
      let userScript = WKUserScript(
        source: wrapped,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
      )
      controller.addUserScript(userScript)
      if reload {
        webView.reload()
      }
    }
    return webViews.count
  }

  @discardableResult
  private func clearInitScripts(reload: Bool) -> Int {
    let webViews = collectWebViews()
    for webView in webViews {
      let controller = webView.configuration.userContentController
      let kept = controller.userScripts.filter { !$0.source.hasPrefix(WebViewZoomPlugin.scriptMarker) }
      controller.removeAllUserScripts()
      for s in kept { controller.addUserScript(s) }
      if reload {
        webView.reload()
      }
    }
    return webViews.count
  }

  private func collectWebViews() -> [WKWebView] {
    var result: [WKWebView] = []
    for window in NSApplication.shared.windows {
      collect(into: &result, view: window.contentView)
    }
    return result
  }

  private func collect(into result: inout [WKWebView], view: NSView?) {
    guard let view = view else { return }
    if let webView = view as? WKWebView {
      result.append(webView)
    }
    for subview in view.subviews {
      collect(into: &result, view: subview)
    }
  }
}

