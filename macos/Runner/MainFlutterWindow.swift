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
      result(currentMicrophoneStatusString())
    case "bundleIdentifier":
      result(Bundle.main.bundleIdentifier ?? "unknown")
    case "displayName":
      let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      result(displayName ?? bundleName ?? ProcessInfo.processInfo.processName)
    case "openSettings":
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
        result(NSWorkspace.shared.open(url))
      } else {
        result(false)
      }
    case "request":
      requestMicrophonePermission(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func currentMicrophoneStatusString() -> String {
    if #available(macOS 14.0, *) {
      return statusString(AVAudioApplication.shared.recordPermission)
    }
    return statusString(AVCaptureDevice.authorizationStatus(for: .audio))
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    if #available(macOS 14.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted:
        result(true)
      case .undetermined:
        Task {
          let granted = await AVAudioApplication.requestRecordPermission()
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case .denied:
        result(false)
      @unknown default:
        result(false)
      }
      return
    }

    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
      result(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }
    case .denied, .restricted:
      result(false)
    @unknown default:
      result(false)
    }
  }

  @available(macOS 14.0, *)
  private func statusString(_ status: AVAudioApplication.recordPermission) -> String {
    switch status {
    case .granted:
      return "authorized"
    case .denied:
      return "denied"
    case .undetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  private func statusString(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }
}
