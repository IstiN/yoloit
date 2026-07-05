import 'dart:io';

import 'package:yoloit/core/platform/platform_capabilities.dart';

PlatformCapabilities createPlatformCapabilities() =>
    const VmPlatformCapabilities();

class VmPlatformCapabilities extends PlatformCapabilities {
  const VmPlatformCapabilities();

  @override
  RuntimePlatform get platform {
    if (Platform.isMacOS) return RuntimePlatform.macos;
    if (Platform.isWindows) return RuntimePlatform.windows;
    if (Platform.isLinux) return RuntimePlatform.linux;
    if (Platform.isAndroid) return RuntimePlatform.android;
    if (Platform.isIOS) return RuntimePlatform.ios;
    // Unknown VM target — fall back to Linux semantics.
    return RuntimePlatform.linux;
  }

  @override
  Set<PlatformCapability> get capabilities {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
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
