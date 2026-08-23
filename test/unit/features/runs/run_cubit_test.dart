import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/data/run_service.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';

/// Points run log files at a temp dir so tests never touch the real config.
class _TempDirs extends PlatformDirs {
  _TempDirs(this.root);

  final String root;

  @override
  String get configDir => root;

  @override
  String get dataDir => root;

  @override
  String? get userHome => null;

  @override
  String get logsDir => root;

  @override
  String get tempDir => root;

  @override
  String get skillsDir => '$root/skills';

  @override
  String get yoloitTempDir => '$root/tmp';
}

/// Prepends a temp bin dir (with a fake tmux shim) to the executable search
/// path so [RunService] never talks to a real tmux server.
class _ShimShell extends PlatformShell {
  _ShimShell(this.binDir);

  final String binDir;

  @override
  String get defaultShell => '/bin/bash';

  @override
  String get pathSeparator => ':';

  @override
  String enrichedPath(String existing) => '$binDir:$existing';
}

RunConfig _config(
  String id, {
  String name = 'Config',
  String command = 'echo hi',
  String group = 'default',
  String? workingDir,
}) => RunConfig(
  id: id,
  name: name,
  command: command,
  group: group,
  workingDir: workingDir,
);

RunSession _session(
  String id, {
  RunStatus status = RunStatus.stopped,
  List<RunOutputLine> output = const [],
  String workspacePath = '/ws',
}) => RunSession(
  id: id,
  config: _config('cfg-$id'),
  workspacePath: workspacePath,
  status: status,
  output: output,
  startedAt: DateTime.utc(2026),
);

/// Seeds SharedPreferences with persisted run configs/sessions for [wsPath].
void _seedPrefs(
  String wsPath, {
  List<RunConfig> configs = const [],
  List<RunSession> sessions = const [],
}) {
  SharedPreferences.setMockInitialValues({
    if (configs.isNotEmpty)
      'run_configs_$wsPath': jsonEncode(
        configs.map((c) => c.toJson()).toList(),
      ),
    if (sessions.isNotEmpty)
      'run_sessions_$wsPath': jsonEncode(
        sessions.map((s) => s.toJson()).toList(),
      ),
  });
}

Future<Map<String, Object?>> _prefs() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) key: prefs.get(key)};
}

void main() {
  late Directory tempDir;
  late RunCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('run_cubit_test');
    cubit = RunCubit();
    addTearDown(cubit.close);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void writePubspec({bool flutter = true}) {
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
      flutter
          ? 'name: sample\nflutter:\n  uses-material-design: true\n'
          : 'name: sample\n',
    );
  }

  group('loadForWorkspace', () {
    test('seeds flutter presets for a flutter project and saves them', () async {
      writePubspec();

      await cubit.loadForWorkspace(tempDir.path);

      expect(cubit.state.workspacePath, tempDir.path);
      expect(cubit.state.configs, hasLength(5));
      expect(
        cubit.state.configs.map((c) => c.id),
        containsAll([
          'preset_flutter_run_macos',
          'preset_flutter_run_web',
          'preset_flutter_test',
          'preset_flutter_build_macos',
          'preset_flutter_build_web',
        ]),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('run_configs_${tempDir.path}'), isNotNull);
    });

    test('does not seed presets without a pubspec', () async {
      await cubit.loadForWorkspace(tempDir.path);
      expect(cubit.state.configs, isEmpty);
    });

    test('does not seed presets for a non-flutter pubspec', () async {
      writePubspec(flutter: false);
      await cubit.loadForWorkspace(tempDir.path);
      expect(cubit.state.configs, isEmpty);
    });

    test('dedupes persisted configs by signature and saves the result', () async {
      final wsPath = tempDir.path;
      final dupeA = _config('a', workingDir: wsPath);
      final dupeB = _config('b', workingDir: wsPath); // same signature as a
      final other = _config('c', name: 'Other');
      _seedPrefs(wsPath, configs: [dupeA, dupeB, other]);

      await cubit.loadForWorkspace(wsPath);

      expect(cubit.state.configs, hasLength(2));
      expect(cubit.state.configs.first.id, 'a');
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString('run_configs_$wsPath')!) as List<dynamic>;
      expect(saved, hasLength(2));
    });

    test('restores saved sessions and activates the last one', () async {
      final wsPath = tempDir.path;
      _seedPrefs(
        wsPath,
        sessions: [
          _session('s1', workspacePath: wsPath),
          _session('s2', workspacePath: wsPath),
        ],
      );

      await cubit.loadForWorkspace(wsPath);

      expect(cubit.state.sessions.map((s) => s.id), ['s1', 's2']);
      expect(cubit.state.activeSessionId, 's2');
    });
  });

  group('config management', () {
    test('addConfig stores a new config and returns it', () async {
      await cubit.loadForWorkspace(tempDir.path);
      final added = await cubit.addConfig(_config('x'));

      expect(added.id, 'x');
      expect(cubit.state.configs.single.id, 'x');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('run_configs_${tempDir.path}'), isNotNull);
    });

    test('addConfig returns the equivalent existing config', () async {
      await cubit.loadForWorkspace(tempDir.path);
      final first = await cubit.addConfig(
        _config('x', name: ' Build ', command: ' make '),
      );
      final second = await cubit.addConfig(
        _config('y', name: 'build', command: 'make'),
      );

      expect(second.id, first.id);
      expect(cubit.state.configs, hasLength(1));
    });

    test('updateConfig replaces the config with the same id', () async {
      await cubit.loadForWorkspace(tempDir.path);
      await cubit.addConfig(_config('x'));

      await cubit.updateConfig(_config('x', name: 'Renamed'));

      expect(cubit.state.configs.single.name, 'Renamed');
    });

    test('removeConfig drops the config by id', () async {
      await cubit.loadForWorkspace(tempDir.path);
      await cubit.addConfig(_config('x'));
      await cubit.addConfig(_config('y', name: 'Other'));

      await cubit.removeConfig('x');

      expect(cubit.state.configs.single.id, 'y');
    });
  });

  group('ensureGroupInitialized', () {
    test('ignores blank groups', () async {
      await cubit.ensureGroupInitialized('   ');
      expect(cubit.state.configs, isEmpty);
    });

    test('ignores groups that already exist', () async {
      await cubit.loadForWorkspace(tempDir.path);
      await cubit.addConfig(_config('x', group: 'g1'));

      await cubit.ensureGroupInitialized('g1');

      expect(cubit.state.configs, hasLength(1));
    });

    test('ignores calls without a workspace', () async {
      await cubit.ensureGroupInitialized('g1');
      expect(cubit.state.configs, isEmpty);
    });

    test('ignores non-flutter workspaces', () async {
      await cubit.loadForWorkspace(tempDir.path);
      await cubit.ensureGroupInitialized('g1');
      expect(cubit.state.configs, isEmpty);
    });

    test('seeds group presets for a flutter workspace', () async {
      writePubspec();
      await cubit.loadForWorkspace(tempDir.path);
      final baseline = cubit.state.configs.length;

      await cubit.ensureGroupInitialized('My Group');

      final groupConfigs =
          cubit.state.configs.where((c) => c.group == 'My Group').toList();
      expect(cubit.state.configs.length, baseline + 5);
      expect(groupConfigs, hasLength(5));
      expect(
        groupConfigs.map((c) => c.id),
        everyElement(endsWith('_My_Group')),
      );

      // A second call for the same group is a no-op.
      await cubit.ensureGroupInitialized('My Group');
      expect(cubit.state.configs.length, baseline + 5);
    });

    test('sanitizes symbol-only groups into an underscore suffix', () async {
      writePubspec();
      await cubit.loadForWorkspace(tempDir.path);

      await cubit.ensureGroupInitialized('!!!');

      final groupConfigs =
          cubit.state.configs.where((c) => c.group == '!!!').toList();
      expect(groupConfigs, hasLength(5));
      expect(groupConfigs.map((c) => c.id), everyElement(endsWith('__')));
    });
  });

  group('session controls', () {
    Future<void> loadWithSessions(List<RunSession> sessions) async {
      _seedPrefs(tempDir.path, sessions: sessions);
      await cubit.loadForWorkspace(tempDir.path);
    }

    test('startRun without a workspace returns null', () async {
      expect(await cubit.startRun(_config('x')), isNull);
    });

    test('restartSession with an unknown id returns null', () async {
      await loadWithSessions([_session('s1', workspacePath: tempDir.path)]);
      expect(await cubit.restartSession('nope'), isNull);
    });

    test('stopRun marks the session stopped', () async {
      await loadWithSessions([_session('s1', workspacePath: tempDir.path)]);

      cubit.stopRun('s1');

      expect(cubit.state.sessions.single.status, RunStatus.stopped);
    });

    test('hot reload/restart and input guards do not throw', () async {
      await loadWithSessions([_session('s1', workspacePath: tempDir.path)]);

      cubit.sendHotReload('s1');
      cubit.sendHotRestart('s1');
      cubit.sendInput('s1', ''); // empty input is ignored
      cubit.sendInput('s1', 'hello');
      cubit.triggerQuickAction(
        's1',
        const RunQuickAction(id: 'q', label: 'Q', icon: 'i', command: '  '),
      );
      cubit.triggerQuickAction(
        's1',
        const RunQuickAction(
          id: 'q',
          label: 'Q',
          icon: 'i',
          command: 'r',
          appendNewline: true,
        ),
      );
    });

    test('clearOutput empties the session output', () async {
      await loadWithSessions([
        _session(
          's1',
          workspacePath: tempDir.path,
          output: [
            RunOutputLine(
              text: 'line',
              isError: false,
              timestamp: DateTime.utc(2026),
            ),
          ],
        ),
      ]);
      expect(cubit.state.sessions.single.output, isNotEmpty);

      cubit.clearOutput('s1');

      expect(cubit.state.sessions.single.output, isEmpty);
    });

    test('setActiveSession and attach/detach manage the active id', () async {
      await loadWithSessions([
        _session('s1', workspacePath: tempDir.path),
        _session('s2', workspacePath: tempDir.path),
      ]);
      expect(cubit.state.activeSessionId, 's2');

      cubit.setActiveSession('s1');
      expect(cubit.state.activeSessionId, 's1');

      // attachSession ignores unknown ids but accepts known ones.
      cubit.attachSession('nope');
      expect(cubit.state.activeSessionId, 's1');
      cubit.attachSession('s2');
      expect(cubit.state.activeSessionId, 's2');

      // detachSession only clears when the id is active.
      cubit.detachSession('s1');
      expect(cubit.state.activeSessionId, 's2');
      cubit.detachSession('s2');
      expect(cubit.state.activeSessionId, isNull);
    });

    test('removeSession reassigns the active id to the last remaining', () async {
      await loadWithSessions([
        _session('s1', workspacePath: tempDir.path),
        _session('s2', workspacePath: tempDir.path),
      ]);
      expect(cubit.state.activeSessionId, 's2');

      cubit.removeSession('s2');
      expect(cubit.state.sessions.map((s) => s.id), ['s1']);
      expect(cubit.state.activeSessionId, 's1');

      cubit.removeSession('s1');
      expect(cubit.state.sessions, isEmpty);
      expect(cubit.state.activeSessionId, isNull);
    });

    test('removeSession keeps the active id when removing another', () async {
      await loadWithSessions([
        _session('s1', workspacePath: tempDir.path),
        _session('s2', workspacePath: tempDir.path),
      ]);

      cubit.removeSession('s1');

      expect(cubit.state.activeSessionId, 's2');
    });
  });

  group('restartSession (real runner)', () {
    late Directory binDir;

    setUp(() async {
      binDir = Directory('${tempDir.path}/bin')..createSync();
      PlatformDirs.setInstance(_TempDirs(tempDir.path));
      PlatformShell.setInstance(_ShimShell(binDir.path));

      // Fake tmux: runs the new-session command detached in a plain bash so
      // the log file (including the __YOLOIT_EXIT_ marker) is still written,
      // and answers every other subcommand without a real tmux server.
      final shim = File('${binDir.path}/tmux');
      shim.writeAsStringSync(
        '#!/bin/bash\n'
        'if [ "\$1" = "new-session" ]; then\n'
        '  for last in "\$@"; do :; done\n'
        '  nohup /bin/bash -c "\$last" >/dev/null 2>&1 &\n'
        '  exit 0\n'
        'fi\n'
        'if [ "\$1" = "has-session" ]; then exit 1; fi\n'
        'exit 0\n',
      );
      final chmod = await Process.run('chmod', ['+x', shim.path]);
      expect(chmod.exitCode, 0, reason: 'chmod +x ${shim.path} failed');
      RunService.instance.resetTmuxPathForTesting();
    });

    tearDown(() {
      RunService.instance.stop('s1');
      PlatformShell.setInstance(const MacosPlatformShell());
      PlatformDirs.setInstance(const MacosPlatformDirs());
    });

    test('clears output, marks running and re-runs the command', () async {
      final session = RunSession(
        id: 's1',
        config: _config('cfg-s1', command: 'echo restarted-marker'),
        workspacePath: tempDir.path,
        status: RunStatus.stopped,
        output: [
          RunOutputLine(
            text: 'stale line',
            isError: false,
            timestamp: DateTime.utc(2026),
          ),
        ],
        startedAt: DateTime.utc(2026),
      );
      _seedPrefs(tempDir.path, sessions: [session]);
      await cubit.loadForWorkspace(tempDir.path);

      final restarted = await cubit.restartSession('s1');

      expect(restarted, isNotNull);
      expect(restarted!.id, 's1');
      expect(restarted.status, RunStatus.running);
      expect(restarted.output, isEmpty);
      expect(restarted.exitCode, isNull);
      expect(restarted.workspacePath, tempDir.path);
      expect(cubit.state.activeSessionId, 's1');

      // Wait for the detached command to finish and the log poller to
      // deliver the exit marker before tearDown removes the temp dir.
      final sw = Stopwatch()..start();
      while (cubit.state.sessions.single.status == RunStatus.running) {
        if (sw.elapsed > const Duration(seconds: 15)) {
          fail('restarted run did not finish in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final done = cubit.state.sessions.single;
      expect(done.status, RunStatus.stopped);
      expect(done.exitCode, 0);
      expect(done.output.map((line) => line.text), contains('restarted-marker'));
      expect(
        done.output.map((line) => line.text),
        isNot(contains('stale line')),
      );
    });
  });

  group('output batching', () {
    Future<void> loadWithSession() async {
      _seedPrefs(
        tempDir.path,
        sessions: [_session('s1', workspacePath: tempDir.path)],
      );
      await cubit.loadForWorkspace(tempDir.path);
    }

    test('ignores output for unknown sessions', () async {
      await loadWithSession();
      final before = cubit.state.sessions.single.output.length;

      cubit.debugAppendOutput('ghost', 'line', false);

      expect(cubit.state.sessions.single.output.length, before);
    });

    test('flushes immediately once the pending threshold is reached', () async {
      await loadWithSession();

      for (var i = 0; i < 5000; i++) {
        cubit.debugAppendOutput('s1', 'line $i', i.isOdd);
      }

      final output = cubit.state.sessions.single.output;
      expect(output, hasLength(5000));
      expect(output.first.text, 'line 0');
      expect(output.first.isError, isFalse);
      expect(output[1].isError, isTrue);
    });

    test('exit flushes pending output and marks the session stopped', () async {
      await loadWithSession();

      cubit.debugAppendOutput('s1', 'pending', false);
      cubit.debugOnExit('s1', 0);

      final session = cubit.state.sessions.single;
      expect(session.status, RunStatus.stopped);
      expect(session.exitCode, 0);
      expect(session.output, hasLength(2));
      expect(session.output.last.text, contains('exited with code 0'));
      expect(session.output.last.isError, isFalse);
    });

    test('non-zero exit marks the session failed with an error line', () async {
      await loadWithSession();

      cubit.debugOnExit('s1', 3);

      final session = cubit.state.sessions.single;
      expect(session.status, RunStatus.failed);
      expect(session.exitCode, 3);
      expect(session.output.single.isError, isTrue);
    });

    test('exit for an unknown session is ignored', () async {
      await loadWithSession();

      cubit.debugOnExit('ghost', 1);

      expect(cubit.state.sessions.single.status, RunStatus.stopped);
      expect(cubit.state.sessions.single.output, isEmpty);
    });

    test('trims output beyond the maximum line count', () async {
      await loadWithSession();

      // First 5000 lines flush immediately via the pending threshold.
      for (var i = 0; i < 5000; i++) {
        cubit.debugAppendOutput('s1', 'line $i', false);
      }
      // 3000 more wait for the debounce timer; combined they exceed the
      // 5000-line cap, so the oldest 3000 are dropped.
      for (var i = 5000; i < 8000; i++) {
        cubit.debugAppendOutput('s1', 'line $i', false);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final output = cubit.state.sessions.single.output;
      expect(output, hasLength(5000));
      expect(output.first.text, 'line 3000');
      expect(output.last.text, 'line 7999');
    });

    test('flushes pending output via the debounce timer', () async {
      await loadWithSession();

      cubit.debugAppendOutput('s1', 'later', false);
      expect(cubit.state.sessions.single.output, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(cubit.state.sessions.single.output.single.text, 'later');
    });

    test('close cancels pending flush timers', () async {
      await loadWithSession();
      cubit.debugAppendOutput('s1', 'never flushed', false);

      await cubit.close();

      expect(cubit.isClosed, isTrue);
    });
  });

  test('prefs stay untouched until a workspace is loaded', () async {
    cubit.stopRun('s1'); // persists only when a workspace is set
    final keys = await _prefs();
    expect(keys, isEmpty);
  });
}
