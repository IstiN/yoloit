import 'package:yoloit/core/platform/platform_capabilities.dart';

PlatformCapabilities createPlatformCapabilities() =>
    const WebPlatformCapabilities();

class WebPlatformCapabilities extends PlatformCapabilities {
  const WebPlatformCapabilities();

  @override
  RuntimePlatform get platform => RuntimePlatform.web;

  @override
  Set<PlatformCapability> get capabilities => const {
    // Browser storage is used through [FileStorageAdapter]; it is not a raw
    // file system, but it covers the persistence use cases we need.
    PlatformCapability.filesystem,
    // Browser localStorage is not a real secure enclave, but it is the best
    // available persistence layer for non-critical config on web.
    PlatformCapability.secureStorage,
  };
}
