import Cocoa
import FlutterMacOS
import AVFoundation

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register custom plugins
    WebViewZoomPlugin.register(
      with: flutterViewController.registrar(forPlugin: "WebViewZoomPlugin")
    )
    MicrophonePermissionPlugin.register(
      with: flutterViewController.registrar(forPlugin: "MicrophonePermissionPlugin")
    )

    super.awakeFromNib()
  }
}

class MicrophonePermissionPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "yoloit/microphone_permission",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(MicrophonePermissionPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(microphoneStatusString())
    case "request":
      requestMicrophonePermission(result: result)
    case "openSettings":
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
        result(NSWorkspace.shared.open(url))
      } else {
        result(false)
      }
    case "bundleIdentifier":
      result(Bundle.main.bundleIdentifier)
    case "displayName":
      let name = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        ?? "YoLoIT"
      result(name)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func microphoneStatusString() -> String {
    let s = AVCaptureDevice.authorizationStatus(for: .audio)
    switch s {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    let s = AVCaptureDevice.authorizationStatus(for: .audio)
    switch s {
    case .authorized:
      result(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { result(granted) }
      }
    case .denied, .restricted:
      result(false)
    @unknown default:
      result(false)
    }
  }
}
