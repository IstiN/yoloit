import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/settings/data/setup_check_service.dart';

class _RecordingLauncher extends PlatformLauncher {
  final List<String> openedTerminals = <String>[];

  @override
  Future<void> openUrl(String url) async {}

  @override
  Future<void> revealInFinder(String path) async {}

  @override
  Future<void> openTerminal(String workdir) async {
    openedTerminals.add(workdir);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SetupCheckService.mergePathForTest', () {
    test('prepends new candidates before existing paths', () {
      final result = SetupCheckService.mergePathForTest(
        '/usr/bin:/bin',
        ['/opt/homebrew/bin', '/usr/local/bin'],
        ':',
      );
      expect(
        result,
        '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
      );
    });

    test('does not duplicate existing paths', () {
      final result = SetupCheckService.mergePathForTest(
        '/usr/local/bin:/usr/bin:/bin',
        ['/usr/local/bin', '/opt/bin'],
        ':',
      );
      expect(
        result,
        '/opt/bin:/usr/local/bin:/usr/bin:/bin',
      );
    });

    test('handles empty current path', () {
      final result = SetupCheckService.mergePathForTest(
        '',
        ['/usr/bin', '/bin'],
        ':',
      );
      expect(result, '/usr/bin:/bin');
    });

    test('handles empty candidates', () {
      final result = SetupCheckService.mergePathForTest(
        '/usr/bin:/bin',
        <String>[],
        ':',
      );
      expect(result, '/usr/bin:/bin');
    });

    test('uses semicolon separator on Windows', () {
      final result = SetupCheckService.mergePathForTest(
        r'C:\Windows;C:\Program Files',
        [r'C:\Tools', r'C:\Windows'],
        ';',
      );
      expect(
        result,
        r'C:\Tools;C:\Windows;C:\Program Files',
      );
    });

    test('filters out empty segments', () {
      final result = SetupCheckService.mergePathForTest(
        ':/usr/bin::/bin:',
        ['/opt/bin'],
        ':',
      );
      expect(
        result,
        '/opt/bin:/usr/bin:/bin',
      );
    });
  });

  group('SetupCheckService.extractOutputForTest', () {
    test('returns output when exit code is 0 and output is non-empty', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '/usr/bin/git\n', ''),
      );
      expect(result, '/usr/bin/git');
    });

    test('returns null when exit code is non-zero', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 1, '/usr/bin/git\n', ''),
      );
      expect(result, isNull);
    });

    test('returns null when output is empty', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '', ''),
      );
      expect(result, isNull);
    });

    test('trims whitespace from output', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '  /usr/bin/git  \n', ''),
      );
      expect(result, '/usr/bin/git');
    });

    test('takes first line when multiple lines', () {
      final result = SetupCheckService.extractOutputForTest(
        ProcessResult(0, 0, '/first\n/second\n', ''),
      );
      expect(result, '/first');
    });
  });

  group('SetupCheckService.cleanVersionForTest', () {
    test('extracts semantic version from string', () {
      expect(
        SetupCheckService.cleanVersionForTest('git version 2.39.0'),
        '2.39.0',
      );
    });

    test('extracts version with patch', () {
      expect(
        SetupCheckService.cleanVersionForTest('node v18.17.1'),
        '18.17.1',
      );
    });

    test('extracts version with more segments', () {
      expect(
        SetupCheckService.cleanVersionForTest('tool 1.2.3.4'),
        '1.2.3.4',
      );
    });

    test('returns raw string when no version found', () {
      expect(
        SetupCheckService.cleanVersionForTest('some text without numbers'),
        'some text without numbers',
      );
    });

    test('truncates long raw strings to 40 chars', () {
      final longString = 'a' * 100;
      expect(
        SetupCheckService.cleanVersionForTest(longString),
        'a' * 40,
      );
    });

    test('does not truncate version match even if long', () {
      expect(
        SetupCheckService.cleanVersionForTest('version 1.2.3.4.5.6.7.8.9.10'),
        '1.2.3.4.5.6.7.8.9.10',
      );
    });

    test('extracts version from stderr-style output', () {
      expect(
        SetupCheckService.cleanVersionForTest('tmux 3.3a'),
        '3.3',
      );
    });

    test('handles version at start of string', () {
      expect(
        SetupCheckService.cleanVersionForTest('2.40.1 (Apple Git-143)'),
        '2.40.1',
      );
    });
  });

  group('SetupCheckService.checkToolForTest', () {
    test('reports available with a cleaned version for a real tool', () async {
      final status = await SetupCheckService.checkToolForTest(
        command: 'sh',
        versionArgs: ['-c', 'echo tool 1.2.3'],
      );

      expect(status.isAvailable, isTrue);
      expect(status.version, '1.2.3');
      expect(status.id, 'test-tool');
    });

    test('reports available with null version when the probe prints nothing',
        () async {
      final status = await SetupCheckService.checkToolForTest(
        command: 'sh',
        versionArgs: ['-c', 'exit 1'],
      );

      expect(status.isAvailable, isTrue);
      expect(status.version, isNull);
    });

    test('reports unavailable for a missing command', () async {
      final status = await SetupCheckService.checkToolForTest(
        command: 'yoloit-no-such-tool-xyz123',
        versionArgs: ['--version'],
      );

      expect(status.isAvailable, isFalse);
      expect(status.version, isNull);
    });

    test('uses the fallback command when the primary is missing', () async {
      final status = await SetupCheckService.checkToolForTest(
        command: 'yoloit-no-such-tool-xyz123',
        versionArgs: ['--version'],
        fallbackCommand: 'sh',
        fallbackVersionArgs: ['-c', 'echo fallback 9.9.9'],
      );

      expect(status.isAvailable, isTrue);
      expect(status.version, '9.9.9');
    });
  });

  group('SetupCheckService.checkOpencodeAgentForTest', () {
    test('uses npm install action when winget is requested', () async {
      final status = await SetupCheckService.checkOpencodeAgentForTest(
        winget: true,
      );

      expect(status.id, 'opencode');
      expect(status.installHint, contains('npm i -g opencode-ai'));
      expect(status.installAction?.executable, 'npm');
    });

    test('uses brew install action on macOS without winget', () async {
      final status = await SetupCheckService.checkOpencodeAgentForTest(
        winget: false,
      );

      expect(status.id, 'opencode');
      expect(
        status.installHint,
        Platform.isMacOS
            ? contains('brew install anomalyco/tap/opencode')
            : contains('opencode.ai/install'),
      );
    });
  });

  group('SetupCheckService.findPathWindowsForTest', () {
    test('returns null on hosts without powershell/where', () async {
      // On macOS/Linux both probes fail fast (missing executables are caught)
      // and the method falls through to null.
      final result = await SetupCheckService.findPathWindowsForTest('git');
      expect(result, isNull);
    });
  });

  group('SetupCheckService.install', () {
    late Directory home;
    late _RecordingLauncher launcher;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('setup-install-test-');
      PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
      launcher = _RecordingLauncher();
      PlatformLauncher.setInstance(launcher);
    });

    tearDown(() async {
      PlatformLauncher.setInstance(const MacosPlatformLauncher());
      PlatformDirs.reset();
      if (await home.exists()) {
        await home.delete(recursive: true);
      }
    });

    // NOTE: in the flutter_test environment the 'done' event of a child
    // process's stdout/stderr streams is never delivered (data events arrive
    // and exitCode completes, but the stream never closes), so install()'s
    // internal `sub.asFuture()` drain never finishes and the output stream is
    // never closed. These tests therefore listen to the stream and poll for
    // the expected lines instead of awaiting stream completion.
    Future<void> waitForLine(List<String> lines, String needle) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!lines.any((line) => line.contains(needle))) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for "$needle" in $lines');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('spawns the process and streams its stdout', () async {
      final lines = <String>[];
      final sub = SetupCheckService.install(
        const InstallAction(
          executable: 'sh',
          args: ['-c', 'echo install-ok'],
        ),
      ).listen(lines.add);
      addTearDown(sub.cancel);

      await waitForLine(lines, 'install-ok');
    });

    test('spawns the process and streams its stderr', () async {
      final lines = <String>[];
      final sub = SetupCheckService.install(
        const InstallAction(
          executable: 'sh',
          args: ['-c', 'echo bad-news >&2; exit 7'],
        ),
      ).listen(lines.add);
      addTearDown(sub.cancel);

      await waitForLine(lines, 'bad-news');
    });
    test('reports an error when the executable cannot be started', () async {
      final lines = await SetupCheckService.install(
        const InstallAction(
          executable: 'yoloit-no-such-tool-xyz123',
          args: <String>[],
        ),
      ).toList();

      expect(lines.single, startsWith('❌ Error:'));
    });

    test('opens an interactive terminal instead of running the process',
        () async {
      final lines = await SetupCheckService.install(
        const InstallAction(
          executable: 'brew',
          args: <String>[],
          requiresInteractiveTerminal: true,
          interactiveScript: 'echo interactive-script',
        ),
      ).toList();

      expect(launcher.openedTerminals, <String>['echo interactive-script']);
      expect(lines.join('\n'), contains('Opened Terminal'));
      expect(lines.join('\n'), contains('Re-check'));
    });

    test('runs the built-in global skills task for the sentinel executable',
        () async {
      final lines = await SetupCheckService.install(
        const InstallAction(
          executable: '__yoloit_global_skills__',
          args: <String>[],
        ),
      ).toList();

      final joined = lines.join('\n');
      expect(joined, contains('Ensuring built-in YoLoIT skill exists'));
      expect(joined, contains('Installation complete'));

      // The built-in skill was materialized under the temp skills dir.
      final skillFile = File(
        '${PlatformDirs.instance.skillsDir}/yoloit-app-development/SKILL.md',
      );
      expect(await skillFile.exists(), isTrue);
    });
  });
}
