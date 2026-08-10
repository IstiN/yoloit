import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';

PlatformCapabilities createPlatformCapabilities() => _createPlatformCapabilities(
  isMacOS: Platform.isMacOS,
  isWindows: Platform.isWindows,
  isLinux: Platform.isLinux,
  isAndroid: Platform.isAndroid,
  isIOS: Platform.isIOS,
);

@visibleForTesting
PlatformCapabilities _createPlatformCapabilities({
  required bool isMacOS,
  required bool isWindows,
  required bool isLinux,
  required bool isAndroid,
  required bool isIOS,
}) {
  if (isMacOS) {
    return const VmPlatformCapabilities.forTest(
      isMacOS: true,
      isWindows: false,
      isLinux: false,
      isAndroid: false,
      isIOS: false,
    );
  }
  if (Platform.isWindows) {
    return const VmPlatformCapabilities.forTest(
      isMacOS: false,
      isWindows: true,
      isLinux: false,
      isAndroid: false,
      isIOS: false,
    );
  }
  if (Platform.isLinux) {
    return const VmPlatformCapabilities.forTest(
      isMacOS: false,
      isWindows: false,
      isLinux: true,
      isAndroid: false,
      isIOS: false,
    );
  }
  if (Platform.isAndroid) {
    return const VmPlatformCapabilities.forTest(
      isMacOS: false,
      isWindows: false,
      isLinux: false,
      isAndroid: true,
      isIOS: false,
    );
  }
  if (Platform.isIOS) {
    return const VmPlatformCapabilities.forTest(
      isMacOS: false,
      isWindows: false,
      isLinux: false,
      isAndroid: false,
      isIOS: true,
    );
  }
  return const VmPlatformCapabilities._defaults();
}

class VmPlatformCapabilities extends PlatformCapabilities {
  const VmPlatformCapabilities() : this._defaults();

  /// Test-only constructor that overrides the platform detection flags.
  @visibleForTesting
  const VmPlatformCapabilities.forTest({
    required this.isMacOS,
    required this.isWindows,
    required this.isLinux,
    required this.isAndroid,
    required this.isIOS,
  });

  final bool isMacOS;
  final bool isWindows;
  final bool isLinux;
  final bool isAndroid;
  final bool isIOS;

  const VmPlatformCapabilities._defaults()
    : isMacOS = false,
      isWindows = false,
      isLinux = false,
      isAndroid = false,
      isIOS = false;

  @override
  RuntimePlatform get platform {
    if (isMacOS) return RuntimePlatform.macos;
    if (isWindows) return RuntimePlatform.windows;
    if (isLinux) return RuntimePlatform.linux;
    if (isAndroid) return RuntimePlatform.android;
    if (isIOS) return RuntimePlatform.ios;
    // Unknown VM target — fall back to Linux semantics.
    return RuntimePlatform.linux;
  }

  @override
  Set<PlatformCapability> get capabilities {
    if (isMacOS || isWindows || isLinux) {
      return PlatformCapability.values.toSet();
    }
    // Mobile: file system and secure storage are available, but not raw
    // processes, PTY, native media players, local servers, or window mgmt.
    return const {
      PlatformCapability.filesystem,
      PlatformCapability.secureStorage,
      PlatformCapability.clipboardFiles,
    };
  }
}
