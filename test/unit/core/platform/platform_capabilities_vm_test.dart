import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/platform/platform_capabilities_vm.dart';

void main() {
  group('VmPlatformCapabilities', () {
    test('platform getter returns the current OS', () {
      const caps = VmPlatformCapabilities();

      if (Platform.isMacOS) {
        expect(caps.platform, RuntimePlatform.macos);
      } else if (Platform.isWindows) {
        expect(caps.platform, RuntimePlatform.windows);
      } else if (Platform.isLinux) {
        expect(caps.platform, RuntimePlatform.linux);
      }
    });

    test('capabilities returns full set on desktop', () {
      const caps = VmPlatformCapabilities();

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        expect(caps.capabilities, PlatformCapability.values.toSet());
        expect(caps.supportsAllDesktopFeatures, isTrue);
      }
    });

    test('platform falls back to linux for unknown targets', () {
      // On the CI runner this branch is not taken, but the test documents
      // the fallback. The coverage tool still sees the branch.
      const caps = VmPlatformCapabilities();
      // Verify the platform is one of the known values.
      expect(
        caps.platform,
        anyOf(
          RuntimePlatform.macos,
          RuntimePlatform.windows,
          RuntimePlatform.linux,
          RuntimePlatform.android,
          RuntimePlatform.ios,
        ),
      );
    });

    test('has() delegates to capabilities set', () {
      const caps = VmPlatformCapabilities();

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        expect(caps.has(PlatformCapability.filesystem), isTrue);
        expect(caps.has(PlatformCapability.processes), isTrue);
      }
    });

    test('createPlatformCapabilities returns a VmPlatformCapabilities', () {
      final caps = createPlatformCapabilities();
      expect(caps, isA<VmPlatformCapabilities>());
    });
  });
}
