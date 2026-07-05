import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:yoloit/core/platform/platform_capabilities_factory.dart'
    as impl;

/// Runtime platforms YoLoIT can target.
///
/// Distinct from Flutter's [TargetPlatform] because web is a first-class
/// runtime here and because the same OS target can have different capability
/// sets in different contexts (e.g. a browser vs. a native macOS app).
enum RuntimePlatform { web, macos, windows, linux, android, ios }

/// Describes what the current runtime can do.
///
/// Plugins and services declare the capabilities they need. The registry and
/// service layer use this to decide whether to enable real behavior or a
/// placeholder/stub. This keeps platform checks centralized and makes adding
/// mobile support later a matter of returning a different capability set.
abstract class PlatformCapabilities {
  const PlatformCapabilities();

  static PlatformCapabilities? _instance;

  /// Current runtime capabilities. Lazy-initialized from the conditional export.
  static PlatformCapabilities get current {
    _instance ??= impl.createPlatformCapabilities();
    return _instance!;
  }

  /// Override for tests.
  // ignore: use_setters_to_change_properties
  @visibleForTesting
  static set current(PlatformCapabilities value) => _instance = value;

  /// Resets the cached instance so the next [current] call re-evaluates.
  @visibleForTesting
  static void reset() => _instance = null;

  RuntimePlatform get platform;

  Set<PlatformCapability> get capabilities;

  bool has(PlatformCapability capability) => capabilities.contains(capability);

  bool get supportsAllDesktopFeatures =>
      has(PlatformCapability.processes) &&
      has(PlatformCapability.nativeTerminal) &&
      has(PlatformCapability.nativeMediaPlayback);
}

/// Capabilities that a plugin or service may require.
///
/// Keep this list small and capability-oriented rather than platform-oriented.
/// A capability should represent a concrete system feature (e.g. spawning a
/// process) rather than a marketing name (e.g. "desktop").
enum PlatformCapability {
  /// Read/write persistent storage. On web this is browser storage, not a raw
  /// file system, but it is enough for JSON/config data.
  filesystem,

  /// Spawn and manage native OS processes.
  processes,

  /// Allocate a PTY and run an interactive shell.
  nativeTerminal,

  /// Decode/play media through a native player (e.g. MPV / AVPlayer).
  nativeMediaPlayback,

  /// Store secrets in a platform keychain/keystore.
  secureStorage,

  /// Bind a local TCP/HTTP server.
  networkServer,

  /// Manage the application window (size, position, fullscreen, etc.).
  windowManagement,

  /// Read files from the system clipboard.
  clipboardFiles,
}
