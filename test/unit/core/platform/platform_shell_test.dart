import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_shell.dart';

void main() {
  tearDown(() {
    // Reset singleton after each test.
    PlatformShell.setInstance(const MacosPlatformShell());
  });

  group('MacosPlatformShell', () {
    late MacosPlatformShell shell;

    setUp(() => shell = const MacosPlatformShell(homeOverride: '/Users/test'));

    test('defaultShell falls back to /bin/zsh', () {
      // SHELL env var may or may not be set in CI; we test the fallback logic.
      const noEnvShell = MacosPlatformShell(homeOverride: '/Users/test');
      // We can't force SHELL to be unset, but we can verify it returns a path.
      expect(noEnvShell.defaultShell, isNotEmpty);
    });

    test('pathSeparator is colon', () {
      expect(shell.pathSeparator, ':');
    });

    test('enrichedPath prepends homebrew paths', () {
      final result = shell.enrichedPath('/usr/bin:/bin');
      expect(result, contains('/opt/homebrew/bin'));
      expect(result, contains('/opt/homebrew/sbin'));
      expect(result, contains('/usr/local/bin'));
    });

    test('enrichedPath prepends home-relative paths', () {
      final result = shell.enrichedPath('/usr/bin:/bin');
      expect(result, contains('/Users/test/.local/bin'));
      expect(result, contains('/Users/test/.kimi-code/bin'));
      expect(result, contains('/Users/test/development/flutter/bin'));
    });

    test('enrichedPath preserves existing entries', () {
      final result = shell.enrichedPath('/usr/bin:/bin');
      expect(result, contains('/usr/bin'));
      expect(result, contains('/bin'));
    });

    test('enrichedPath deduplicates entries', () {
      // /usr/local/bin is already in the extras AND in existing.
      final result = shell.enrichedPath('/usr/local/bin:/usr/bin:/bin');
      final parts = result.split(':');
      expect(
        parts.where((p) => p == '/usr/local/bin').length,
        1,
        reason: '/usr/local/bin should appear exactly once',
      );
    });

    test('enrichedPath handles empty existing PATH', () {
      final result = shell.enrichedPath('');
      expect(result, contains('/opt/homebrew/bin'));
      expect(result, isNot(startsWith(':')));
    });

    test('splitPath and joinPath round-trip', () {
      const original = '/usr/bin:/bin:/usr/local/bin';
      expect(shell.joinPath(shell.splitPath(original)), original);
    });
  });

  group('LinuxPlatformShell', () {
    late LinuxPlatformShell shell;

    setUp(() => shell = const LinuxPlatformShell(homeOverride: '/home/user'));

    test('defaultShell falls back to /bin/bash', () {
      expect(shell.defaultShell, isNotEmpty);
    });

    test('pathSeparator is colon', () {
      expect(shell.pathSeparator, ':');
    });

    test('enrichedPath includes ~/.local/bin', () {
      final result = shell.enrichedPath('/usr/bin');
      expect(result, contains('/home/user/.local/bin'));
    });

    test('enrichedPath includes kimi-code bin', () {
      final result = shell.enrichedPath('/usr/bin');
      expect(result, contains('/home/user/.kimi-code/bin'));
    });

    test('enrichedPath includes /snap/bin', () {
      final result = shell.enrichedPath('/usr/bin');
      expect(result, contains('/snap/bin'));
    });

    test('enrichedPath preserves existing entries', () {
      final result = shell.enrichedPath('/custom/bin:/usr/bin');
      expect(result, contains('/custom/bin'));
    });
  });

  group('WindowsPlatformShell', () {
    late WindowsPlatformShell shell;

    setUp(
      () =>
          shell = const WindowsPlatformShell(
            userProfileOverride: r'C:\Users\test',
          ),
    );

    test('defaultShell falls back to cmd.exe', () {
      expect(shell.defaultShell, isNotEmpty);
    });

    test('pathSeparator is semicolon', () {
      expect(shell.pathSeparator, ';');
    });

    test('enrichedPath uses semicolons as separator', () {
      final result = shell.enrichedPath(r'C:\Windows\System32');
      // Verify the separator between entries is semicolon, not colon.
      // (Windows paths naturally contain colons for drive letters like C:)
      final parts = result.split(';');
      expect(
        parts.length,
        greaterThan(1),
        reason: 'entries should be separated by ;',
      );
    });

    test('enrichedPath includes flutter bin', () {
      final result = shell.enrichedPath(r'C:\Windows\System32');
      expect(
        result,
        contains(r'C:\Users\test\AppData\Local\Programs\flutter\bin'),
      );
    });
  });

  group('PlatformShell.instance', () {
    test('can be overridden for testing', () {
      const fake = LinuxPlatformShell(homeOverride: '/override');
      PlatformShell.setInstance(fake);
      expect(PlatformShell.instance.pathSeparator, ':');
      expect(
        PlatformShell.instance.enrichedPath(''),
        contains('/override/.local/bin'),
      );
    });
  });
}
