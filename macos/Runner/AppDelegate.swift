import Cocoa
import FlutterMacOS
import WebKit

class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Swizzle WKWebView init so the HTML5 Fullscreen API is enabled for
    // every webview created in the app (including those from webview_flutter).
    WKWebViewFullscreen.install()
    super.applicationDidFinishLaunching(notification)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
