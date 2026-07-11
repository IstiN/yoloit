import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import CoreMedia
import AVFoundation

/// Captures macOS system (loopback) audio via ScreenCaptureKit and streams raw
/// interleaved 16-bit little-endian PCM (48 kHz / stereo) to Dart over an
/// EventChannel. System audio capture requires macOS 13.0+.
class SystemAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "yoloit/system_audio"
  private static let eventChannelName = "yoloit/system_audio_pcm"

  private var eventSink: FlutterEventSink?
  private var capture: SystemAudioCapture?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemAudioPlugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger
    )
    eventChannel.setStreamHandler(instance)
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - FlutterPlugin

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(CGPreflightScreenCaptureAccess() ? "authorized" : "denied")
    case "request":
      DispatchQueue.global(qos: .userInitiated).async {
        let granted = CGRequestScreenCaptureAccess()
        DispatchQueue.main.async { result(granted) }
      }
    case "openSettings":
      let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
      result(url.map { NSWorkspace.shared.open($0) } ?? false)
    case "start":
      let args = call.arguments as? [String: Any]
      let sampleRate = (args?["sampleRate"] as? NSNumber)?.doubleValue ?? 48000
      startCapture(sampleRate: sampleRate, result: result)
    case "stop":
      stopCapture(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startCapture(sampleRate: Double, result: @escaping FlutterResult) {
    if #available(macOS 13.0, *) {
      let capture = SystemAudioCapture(sampleRate: sampleRate) { [weak self] data in
        guard let sink = self?.eventSink else { return }
        DispatchQueue.main.async {
          sink(FlutterStandardTypedData(bytes: data))
        }
      } onError: { [weak self] message in
        guard let sink = self?.eventSink else { return }
        DispatchQueue.main.async {
          sink(FlutterError(code: "capture_error", message: message, details: nil))
        }
      }
      self.capture = capture
      capture.start { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      }
    } else {
      result(FlutterError(code: "unsupported", message: "System audio capture requires macOS 13.0+.", details: nil))
    }
  }

  private func stopCapture(result: @escaping FlutterResult) {
    guard let capture = capture else {
      result(nil)
      return
    }
    capture.stop { [weak self] in
      self?.capture = nil
      DispatchQueue.main.async { result(nil) }
    }
  }
}

// MARK: - ScreenCaptureKit capture

@available(macOS 13.0, *)
private final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
  private let targetSampleRate: Double
  private let onAudio: (Data) -> Void
  private let onError: (String) -> Void
  private var stream: SCStream?
  private let queue = DispatchQueue(label: "yoloit.system_audio.capture")

  init(sampleRate: Double, onAudio: @escaping (Data) -> Void, onError: @escaping (String) -> Void) {
    self.targetSampleRate = sampleRate
    self.onAudio = onAudio
    self.onError = onError
  }

  func start(completion: @escaping (Error?) -> Void) {
    Task {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
          completion(CaptureError.noDisplay)
          return
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2
        config.height = 2
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
        completion(nil)
      } catch {
        completion(error)
      }
    }
  }

  func stop(completion: @escaping () -> Void) {
    guard let stream = stream else {
      completion()
      return
    }
    Task {
      try? await stream.stopCapture()
      self.stream = nil
      completion()
    }
  }

  // MARK: SCStreamOutput

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .audio else { return }
    guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
    if let data = Self.convertToInt16Interleaved(sampleBuffer: sampleBuffer, targetSampleRate: targetSampleRate) {
      onAudio(data)
    }
  }

  // MARK: SCStreamDelegate

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    onError(error.localizedDescription)
  }

  // MARK: Conversion

  /// Converts an arbitrary PCM sample buffer to interleaved signed 16-bit PCM
  /// at [targetSampleRate] / 2 channels, returning the raw bytes.
  private static func convertToInt16Interleaved(sampleBuffer: CMSampleBuffer, targetSampleRate: Double) -> Data? {
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
      return nil
    }
    let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frameCount > 0 else { return nil }

    guard let srcFormat = AVAudioFormat(streamDescription: asbdPtr),
          let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
      return nil
    }
    srcBuffer.frameLength = AVAudioFrameCount(frameCount)
    let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer,
      at: 0,
      frameCount: Int32(frameCount),
      into: srcBuffer.mutableAudioBufferList
    )
    guard copyStatus == noErr else { return nil }

    guard let dstFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: targetSampleRate,
      channels: 2,
      interleaved: true
    ) else { return nil }

    let ratio = targetSampleRate / srcFormat.sampleRate
    let dstCapacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 16
    guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstCapacity),
          let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
      return nil
    }

    var consumed = false
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      if consumed {
        outStatus.pointee = .endOfStream
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return srcBuffer
    }

    var error: NSError?
    converter.convert(to: dstBuffer, error: &error, withInputFrom: inputBlock)
    if error != nil { return nil }

    let frames = Int(dstBuffer.frameLength)
    guard frames > 0, let channelData = dstBuffer.int16ChannelData else { return nil }
    let byteCount = frames * 2 * MemoryLayout<Int16>.size
    return Data(bytes: channelData[0], count: byteCount)
  }
}

private enum CaptureError: LocalizedError {
  case noDisplay
  var errorDescription: String? { "No display available for system audio capture." }
}
