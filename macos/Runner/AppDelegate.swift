import Cocoa
import FlutterMacOS
import WebKit

class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    WKWebViewFullscreen.install()
    super.applicationDidFinishLaunching(notification)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Don't quit when a popped-out board window is the last one — keep the
    // app alive so board windows can be re-opened from the main window.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
