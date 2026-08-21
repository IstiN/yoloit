import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/runs/data/run_service.dart';

class _TempPlatformDirs extends PlatformDirs {
  _TempPlatformDirs(this._tmpDir);
  final String _tmpDir;

  @override
  String get configDir => _tmpDir;

  @override
  String get dataDir => _tmpDir;

  @override
  String? get userHome => null;

  @override
  String get logsDir => _tmpDir;

  @override
  String get tempDir => _tmpDir;

  @override
  String get skillsDir => '$_tmpDir/skills';

  @override
  String get yoloitTempDir => '$_tmpDir/tmp';
}

/// Prepends a temp bin dir (with shim executables) ahead of every real PATH
/// entry so `_findExecutable` resolves the shims first.
class _TestPlatformShell extends PlatformShell {
  _TestPlatformShell(this._binDir);
  final String _binDir;
  final PlatformShell _delegate = const MacosPlatformShell();

  @override
  String get defaultShell => _delegate.defaultShell;

  @override
  String get pathSeparator => ':';

  @override
  String enrichedPath(String existing) =>
      '$_binDir:${_delegate.enrichedPath(existing)}';
}

/// Collects streamed output and the exit code from a run session.
class _RunCapture {
  final lines = <String>[];
  final errors = <String>[];
  final exitCompleter = Completer<int>();

  void onOutput(String line, bool isError) {
    (isError ? errors : lines).add(line);
  }

  void onExit(int code) {
    if (!exitCompleter.isCompleted) exitCompleter.complete(code);
  }

  Future<int> exitCode({Duration timeout = const Duration(seconds: 20)}) =>
      exitCompleter.future.timeout(timeout);
}

void main() {
  late Directory tmpDir;
  late Directory binDir;
  late String failFlag;

  final usedConfigIds = <String>[];
  final usedSessionIds = <String>[];

  Future<void> waitUntil(bool Function() condition, String reason) async {
    final sw = Stopwatch()..start();
    while (!condition()) {
      if (sw.elapsed > const Duration(seconds: 15)) {
        fail('Timed out waiting for $reason');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> writeExecutable(String path, String content) async {
    await File(path).writeAsString(content);
    final chmod = await Process.run('chmod', ['+x', path]);
    expect(chmod.exitCode, 0, reason: 'chmod +x $path failed');
  }

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('run_service_test_');
    binDir = Directory('${tmpDir.path}/bin')..createSync();
    failFlag = '${binDir.path}/fail_new_session';
    PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
    PlatformShell.setInstance(_TestPlatformShell(binDir.path));

    // Resolve the real tmux so the shim can delegate to it.
    final which = await Process.run('/usr/bin/which', ['tmux']);
    final realTmux =
        which.exitCode == 0 ? (which.stdout as String).trim() : 'tmux';

    // Fake tmux: fails new-session only when the fail-flag file exists,
    // otherwise delegates everything to the real tmux binary.
    await writeExecutable(
      '${binDir.path}/tmux',
      '#!/bin/bash\n'
      'if [ "\$1" = "new-session" ] && [ -f "$failFlag" ]; then\n'
      "  echo 'fake tmux: forced new-session failure' >&2\n"
      '  exit 1\n'
      'fi\n'
      'exec "$realTmux" "\$@"\n',
    );

    // The singleton caches the resolved tmux path — re-resolve against the
    // fresh shim for every test.
    RunService.instance.resetTmuxPathForTesting();

    // Fake flutter: prints a marker line, then idles so pipe-pane has time
    // to attach before the exit marker is appended to the log. Exits 3 when
    // asked to via a flag, to exercise non-zero exit propagation.
    await writeExecutable(
      '${binDir.path}/flutter',
      '#!/bin/bash\n'
      'echo fake-flutter-output\n'
      'sleep 1\n'
      'for a in "\$@"; do\n'
      '  if [ "\$a" = "--yoloit-exit3" ]; then exit 3; fi\n'
      'done\n'
      'exit 0\n',
    );
  });

  tearDown(() async {
    for (final sessionId in usedSessionIds) {
      RunService.instance.stop(sessionId);
    }
    usedSessionIds.clear();
    for (final configId in usedConfigIds) {
      await Process.run(
        'tmux',
        ['kill-session', '-t', RunService.tmuxName(configId)],
      );
    }
    usedConfigIds.clear();
    PlatformShell.setInstance(const MacosPlatformShell());
    PlatformDirs.setInstance(const MacosPlatformDirs());
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('RunService.tmuxName', () {
    test('preserves alphanumeric characters', () {
      expect(RunService.tmuxName('myConfig123'), 'yoloit_run_myConfig123');
    });

    test('replaces hyphens with underscores', () {
      expect(RunService.tmuxName('my-config'), 'yoloit_run_my_config');
    });

    test('replaces dots with underscores', () {
      expect(RunService.tmuxName('my.config'), 'yoloit_run_my_config');
    });

    test('replaces multiple special chars', () {
      expect(
        RunService.tmuxName('my-config.v1_test'),
        'yoloit_run_my_config_v1_test',
      );
    });

    test('handles empty string', () {
      expect(RunService.tmuxName(''), 'yoloit_run_');
    });
  });

  group('RunService.logPath', () {
    test('returns path under runs directory', () async {
      final path = await RunService.logPath('myConfig');
      expect(path, contains('runs'));
      expect(path, endsWith('yoloit_run_myConfig.log'));
    });

    test('creates runs directory if missing', () async {
      final runsDir = Directory('${tmpDir.path}/runs');
      expect(runsDir.existsSync(), isFalse);
      await RunService.logPath('any');
      expect(runsDir.existsSync(), isTrue);
    });

    test('sanitizes config id in filename', () async {
      final path = await RunService.logPath('my-config');
      expect(path, endsWith('yoloit_run_my_config.log'));
    });
  });

  group('RunService.start', () {
    test('streams output lines and reports zero exit code', () async {
      final capture = _RunCapture();
      usedConfigIds.add('basicEcho');
      usedSessionIds.add('s-basic');

      await RunService.instance.start(
        sessionId: 's-basic',
        configId: 'basicEcho',
        command: 'echo hello-yolo-run',
        workingDir: tmpDir.path,
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );

      expect(await capture.exitCode(), 0);
      await waitUntil(
        () => capture.lines.contains('hello-yolo-run'),
        'echo output line',
      );
    });

    test('reports non-zero exit code from the command', () async {
      final capture = _RunCapture();
      usedConfigIds.add('nonZero');
      usedSessionIds.add('s-nonzero');

      // The piped (tee) branch reports tee's status, so non-zero exit
      // propagation is exercised through the direct flutter-run branch.
      await RunService.instance.start(
        sessionId: 's-nonzero',
        configId: 'nonZero',
        command: 'flutter run --yoloit-exit3',
        workingDir: tmpDir.path,
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );

      expect(await capture.exitCode(timeout: const Duration(seconds: 30)), 3);
    });

    test('exports provided environment variables into the run', () async {
      final capture = _RunCapture();
      usedConfigIds.add('envVars');
      usedSessionIds.add('s-env');

      await RunService.instance.start(
        sessionId: 's-env',
        configId: 'envVars',
        command: 'echo var-is-\$YOLOIT_TEST_VAR',
        workingDir: tmpDir.path,
        env: const {'YOLOIT_TEST_VAR': 'forty-two'},
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );

      expect(await capture.exitCode(), 0);
      await waitUntil(
        () => capture.lines.contains('var-is-forty-two'),
        'exported env var output',
      );
    });

    test('reports an error when the tmux session cannot be created', () async {
      File(failFlag).writeAsStringSync('fail');
      final capture = _RunCapture();
      usedConfigIds.add('tmuxFail');
      usedSessionIds.add('s-fail');

      await RunService.instance.start(
        sessionId: 's-fail',
        configId: 'tmuxFail',
        command: 'echo never-runs',
        workingDir: tmpDir.path,
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );

      expect(await capture.exitCode(), 1);
      expect(
        capture.errors,
        anyElement(contains('Failed to start tmux session')),
      );
      expect(
        capture.errors,
        anyElement(contains('forced new-session failure')),
      );
    });

    test('mirrors flutter run output to the log via pipe-pane', () async {
      final capture = _RunCapture();
      usedConfigIds.add('flutterRun');
      usedSessionIds.add('s-flutter');

      await RunService.instance.start(
        sessionId: 's-flutter',
        configId: 'flutterRun',
        command: 'flutter run',
        workingDir: tmpDir.path,
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );

      expect(await capture.exitCode(timeout: const Duration(seconds: 30)), 0);
      await waitUntil(
        () => capture.lines.any((l) => l.contains('fake-flutter-output')),
        'fake flutter output mirrored via pipe-pane',
      );
    });
  });

  group('RunService.tailLog', () {
    test('reports an error and exits when the log file never appears',
        () async {
      final capture = _RunCapture();

      await RunService.instance.tailLogForTesting(
        sessionId: 's-missing',
        log: '${tmpDir.path}/does-not-exist.log',
        fromStart: true,
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );

      expect(await capture.exitCode(), 1);
      expect(capture.errors, anyElement(contains('log file not found')));
      expect(RunService.instance.isRunning('s-missing'), isFalse);
    });

    test('with fromStart=false only streams lines appended after start',
        () async {
      final capture = _RunCapture();
      usedSessionIds.add('s-from-end');
      final logFile = File('${tmpDir.path}/from-end.log')
        ..writeAsStringSync('old-line\n');

      await RunService.instance.tailLogForTesting(
        sessionId: 's-from-end',
        log: logFile.path,
        fromStart: false,
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );
      expect(RunService.instance.isRunning('s-from-end'), isTrue);

      // Give the poller a couple of ticks to settle at the file end.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await logFile.writeAsString('new-line\n', mode: FileMode.append);
      await waitUntil(
        () => capture.lines.contains('new-line'),
        'appended line',
      );
      expect(capture.lines, isNot(contains('old-line')));

      await logFile.writeAsString('__YOLOIT_EXIT_3\n', mode: FileMode.append);
      expect(await capture.exitCode(), 3);
      expect(RunService.instance.isRunning('s-from-end'), isFalse);
    });

    test('reassembles partial lines and strips carriage returns', () async {
      final capture = _RunCapture();
      usedSessionIds.add('s-partial');
      final logFile = File('${tmpDir.path}/partial.log')
        ..writeAsStringSync('');

      await RunService.instance.tailLogForTesting(
        sessionId: 's-partial',
        log: logFile.path,
        fromStart: true,
        onOutput: capture.onOutput,
        onExit: capture.onExit,
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await logFile.writeAsString('part', mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // Incomplete line must stay buffered — nothing emitted yet.
      expect(capture.lines, isEmpty);

      await logFile.writeAsString('ial\r\n', mode: FileMode.append);
      await waitUntil(
        () => capture.lines.contains('partial'),
        'reassembled line',
      );

      await logFile.writeAsString('__YOLOIT_EXIT_0\n', mode: FileMode.append);
      expect(await capture.exitCode(), 0);
    });

    test('re-tailing a session replaces the previous poller', () async {
      final captureA = _RunCapture();
      final captureB = _RunCapture();
      usedSessionIds.add('s-retail');
      final logA = File('${tmpDir.path}/retail-a.log')..writeAsStringSync('');
      final logB = File('${tmpDir.path}/retail-b.log')..writeAsStringSync('');

      await RunService.instance.tailLogForTesting(
        sessionId: 's-retail',
        log: logA.path,
        fromStart: true,
        onOutput: captureA.onOutput,
        onExit: captureA.onExit,
      );
      await RunService.instance.tailLogForTesting(
        sessionId: 's-retail',
        log: logB.path,
        fromStart: true,
        onOutput: captureB.onOutput,
        onExit: captureB.onExit,
      );
      expect(RunService.instance.isRunning('s-retail'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await logA.writeAsString('from-a\n', mode: FileMode.append);
      await logB.writeAsString('from-b\n', mode: FileMode.append);
      await waitUntil(
        () => captureB.lines.contains('from-b'),
        'line from the active log',
      );
      // The first poller was cancelled — nothing from log A is delivered.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(captureA.lines, isEmpty);
    });
  });
}
