import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';

void main() {
  tearDown(() {
    // Reset singleton after each test.
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  group('MacosPlatformDirs', () {
    late MacosPlatformDirs dirs;

    setUp(() => dirs = const MacosPlatformDirs(homeOverride: '/Users/test'));

    test('configDir returns ~/.config/yoloit', () {
      expect(dirs.configDir, '/Users/test/.config/yoloit');
    });

    test('logsDir returns ~/Library/Logs/yoloit', () {
      expect(dirs.logsDir, '/Users/test/Library/Logs/yoloit');
    });

    test('dataDir returns ~/Library/Application Support/yoloit', () {
      expect(dirs.dataDir, '/Users/test/Library/Application Support/yoloit');
    });

    test('tempDir is non-empty', () {
      expect(dirs.tempDir, isNotEmpty);
    });

    test('configDir uses /tmp when HOME is absent', () {
      const noHome = MacosPlatformDirs(homeOverride: '/tmp');
      expect(noHome.configDir, '/tmp/.config/yoloit');
    });

    test('paths are consistent with legacy hardcoded values', () {
      // Regression guard: macOS paths must match what was previously hardcoded.
      expect(dirs.configDir, endsWith('/.config/yoloit'));
      expect(dirs.logsDir, contains('Library/Logs/yoloit'));
    });
  });

  group('LinuxPlatformDirs', () {
    late LinuxPlatformDirs dirs;

    setUp(() => dirs = const LinuxPlatformDirs(homeOverride: '/home/user'));

    test('configDir returns ~/.config/yoloit', () {
      expect(dirs.configDir, '/home/user/.config/yoloit');
    });

    test('dataDir returns ~/.local/share/yoloit', () {
      expect(dirs.dataDir, '/home/user/.local/share/yoloit');
    });

    test('logsDir returns ~/.local/share/yoloit/logs', () {
      expect(dirs.logsDir, '/home/user/.local/share/yoloit/logs');
    });

    test('tempDir is non-empty', () {
      expect(dirs.tempDir, isNotEmpty);
    });
  });

  group('IosPlatformDirs', () {
    late IosPlatformDirs dirs;

    setUp(() => dirs = const IosPlatformDirs(homeOverride: '/ios/sandbox'));

    test('config and data dirs live inside app Documents', () {
      expect(dirs.configDir, '/ios/sandbox/Documents/yoloit');
      expect(dirs.dataDir, '/ios/sandbox/Documents/yoloit');
    });

    test('logs and skills dirs live under the sandbox root', () {
      expect(dirs.logsDir, '/ios/sandbox/Documents/yoloit/logs');
      expect(dirs.skillsDir, '/ios/sandbox/Documents/yoloit/skills');
    });
  });

  group('WindowsPlatformDirs', () {
    late WindowsPlatformDirs dirs;

    setUp(
      () =>
          dirs = const WindowsPlatformDirs(
            appDataOverride: r'C:\Users\test\AppData\Roaming',
          ),
    );

    test('configDir returns APPDATA\\yoloit', () {
      expect(dirs.configDir, r'C:\Users\test\AppData\Roaming\yoloit');
    });

    test('dataDir returns APPDATA\\yoloit', () {
      expect(dirs.dataDir, r'C:\Users\test\AppData\Roaming\yoloit');
    });

    test('logsDir returns APPDATA\\yoloit\\logs', () {
      expect(dirs.logsDir, r'C:\Users\test\AppData\Roaming\yoloit\logs');
    });
  });

  group('PlatformDirs.instance', () {
    test('can be overridden for testing', () {
      const fake = LinuxPlatformDirs(homeOverride: '/override');
      PlatformDirs.setInstance(fake);
      expect(PlatformDirs.instance.configDir, '/override/.config/yoloit');
    });

    test('yoloitTempDir ends with yoloit_tmp', () {
      const dirs = MacosPlatformDirs(homeOverride: '/Users/test');
      expect(dirs.yoloitTempDir, endsWith('yoloit_tmp'));
    });
  });
}
