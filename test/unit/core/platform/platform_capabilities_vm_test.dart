import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/platform/platform_capabilities_vm.dart';

void main() {
  group('VmPlatformCapabilities.platform — all OS branches', () {
    test('returns macos when isMacOS', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.platform, RuntimePlatform.macos);
    });

    test('returns windows when isWindows', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: true,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.platform, RuntimePlatform.windows);
    });

    test('returns linux when isLinux', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.platform, RuntimePlatform.linux);
    });

    test('returns android when isAndroid', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        isAndroid: true,
        isIOS: false,
      );
      expect(caps.platform, RuntimePlatform.android);
    });

    test('returns ios when isIOS', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        isAndroid: false,
        isIOS: true,
      );
      expect(caps.platform, RuntimePlatform.ios);
    });

    test('falls back to linux for unknown target', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.platform, RuntimePlatform.linux);
    });
  });

  group('VmPlatformCapabilities.capabilities — desktop vs mobile', () {
    test('returns full set on macOS', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.capabilities, PlatformCapability.values.toSet());
      expect(caps.supportsAllDesktopFeatures, isTrue);
    });

    test('returns full set on Windows', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: true,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.capabilities, PlatformCapability.values.toSet());
    });

    test('returns full set on Linux', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.capabilities, PlatformCapability.values.toSet());
    });

    test('returns restricted set on Android', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        isAndroid: true,
        isIOS: false,
      );
      expect(
        caps.capabilities,
        const {
          PlatformCapability.filesystem,
          PlatformCapability.secureStorage,
          PlatformCapability.clipboardFiles,
        },
      );
      expect(caps.supportsAllDesktopFeatures, isFalse);
    });

    test('returns restricted set on iOS', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        isAndroid: false,
        isIOS: true,
      );
      expect(
        caps.capabilities,
        const {
          PlatformCapability.filesystem,
          PlatformCapability.secureStorage,
          PlatformCapability.clipboardFiles,
        },
      );
    });

    test('returns restricted set for unknown target', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      expect(caps.capabilities.length, 3);
      expect(caps.has(PlatformCapability.processes), isFalse);
    });
  });

  group('VmPlatformCapabilities.has()', () {
    test('returns true for capabilities in the set', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      for (final cap in PlatformCapability.values) {
        expect(caps.has(cap), isTrue);
      }
    });

    test('returns false for desktop-only capabilities on mobile', () {
      const caps = VmPlatformCapabilities.forTest(
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        isAndroid: true,
        isIOS: false,
      );
      expect(caps.has(PlatformCapability.processes), isFalse);
      expect(caps.has(PlatformCapability.nativeTerminal), isFalse);
      expect(caps.has(PlatformCapability.filesystem), isTrue);
    });
  });

  test('createPlatformCapabilities returns instance with correct platform', () {
    final caps = createPlatformCapabilities();
    expect(caps, isA<VmPlatformCapabilities>());
    // On the CI runner one branch is taken; verify it's a known platform.
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
}
