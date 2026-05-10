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
///   - setFixedViewportWidth: force WKWebView bounds.width to a fixed value
///     so that `window.innerWidth` and `document.documentElement.clientWidth`
///     always equal that value regardless of board zoom level. macOS natively
///     scales the rendering and coordinates through the bounds transform.
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

  // MARK: - Fixed viewport state
  private var fixedViewportWidth: CGFloat = 0
  /// Set of WKWebViews we've already added a frame-change observer to.
  private var observedWebViews: Set<ObjectIdentifier> = []

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

    case "setFixedViewportWidth":
      let width = (call.arguments as? Double) ?? 0
      let count = applyFixedViewport(width: CGFloat(width))
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

  // MARK: - Fixed viewport width (native bounds manipulation)

  /// Set WKWebView.bounds.width to `width` (0 = disable / reset to frame).
  /// macOS automatically scales rendering from the bounds coordinate space
  /// to the frame, and converts mouse/scroll coordinates through the same
  /// transform. This means:
  ///   • window.innerWidth = bounds.width (= `width`)
  ///   • document.documentElement.clientWidth = bounds.width (= `width`)
  ///   • Click/scroll coordinates are correctly mapped to the CSS layout
  /// No CSS zoom injection needed — the native scaling handles everything.
  @discardableResult
  private func applyFixedViewport(width: CGFloat) -> Int {
    fixedViewportWidth = width
    var count = 0
    for window in NSApplication.shared.windows {
      count += applyFixedViewport(width: width, inView: window.contentView)
    }
    return count
  }

  private func applyFixedViewport(width: CGFloat, inView view: NSView?) -> Int {
    guard let view = view else { return 0 }
    var count = 0
    if let webView = view as? WKWebView {
      applyBounds(to: webView, viewportWidth: width)
      // Enable HTML5 Fullscreen API (required for YouTube fullscreen button).
      if #available(macOS 12.3, *) {
        webView.configuration.preferences.isElementFullscreenEnabled = true
      }
      let oid = ObjectIdentifier(webView)
      if !observedWebViews.contains(oid) {
        observedWebViews.insert(oid)
        webView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
          forName: NSView.frameDidChangeNotification,
          object: webView,
          queue: .main
        ) { [weak self, weak webView] _ in
          guard let self = self, let webView = webView else { return }
          self.applyBounds(to: webView, viewportWidth: self.fixedViewportWidth)
        }
      }
      count += 1
    }
    for subview in view.subviews {
      count += applyFixedViewport(width: width, inView: subview)
    }
    return count
  }

  /// Set WKWebView.pageZoom so the JS viewport width equals viewportWidth.
  ///
  /// pageZoom = frame.width / viewportWidth → window.innerWidth = viewportWidth,
  /// document.documentElement.clientWidth = viewportWidth. WebKit handles all
  /// coordinate mapping (mouse, scroll) through the same transform.
  /// When viewportWidth <= 0, reset pageZoom to 1.0.
  private func applyBounds(to webView: WKWebView, viewportWidth: CGFloat) {
    let frame = webView.frame
    guard frame.width > 0 else { return }
    if viewportWidth <= 0 {
      webView.pageZoom = 1.0
      return
    }
    webView.pageZoom = frame.width / viewportWidth
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

