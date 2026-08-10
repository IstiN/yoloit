import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'server_process_test_support.dart';

void main() {
  group('ServerProcessMixin.runSetupInstallTasks', () {
    late ProcessHost host;
    late Directory workDir;

    setUp(() async {
      host = ProcessHost();
      workDir = await Directory.systemTemp.createTemp('setup-tasks-test-');
    });

    tearDown(() async {
      host.killAllRunsAndTerminals();
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    });

    test('runs special tasks, skips an empty script and records exit 0',
        () async {
      host.activeTaskRuns.add('t1');

      await host.runSetupInstallTasks('t1', <String>['bogus-task'], '', workDir.path);

      final lines = host.runLogs['t1']!;
      expect(lines.first, contains('Unknown special install task: bogus-task'));
      expect(lines.last, '[exit 0]');
      expect(host.runExitCodes['t1'], 0);
      expect(host.activeTaskRuns, isNot(contains('t1')));
      expect(host.runs, isNot(contains('t1')));
    });

    test('runs the script, collects output and returns early', () async {
      await host.runSetupInstallTasks(
        't2',
        <String>[],
        'echo task-output',
        workDir.path,
      );

      final lines = host.runLogs['t2']!;
      expect(lines, contains('task-output'));
      expect(lines.last, '[exit 0]');
      expect(host.runExitCodes['t2'], 0);
      expect(host.runs, isNot(contains('t2')));
    });

    test('records an error when the working directory does not exist',
        () async {
      await host.runSetupInstallTasks(
        't3',
        <String>[],
        'echo never-runs',
        '${workDir.path}/no-such-subdir',
      );

      final lines = host.runLogs['t3']!;
      expect(lines.first, startsWith('[error]'));
      expect(lines.last, '[exit 1]');
      expect(host.runExitCodes['t3'], 1);
    });
  });

  group('ServerProcessMixin.handleSetupRequest', () {
    late ProcessHost host;

    setUp(() {
      host = ProcessHost();
    });

    Future<shelf.Response> call({
      required String method,
      required List<String> sub,
      shelf.Request? request,
      String Function()? nextId,
      Future<void> Function(String id, List<String> specialIds, String script)?
      startTasks,
    }) {
      return host.handleSetupRequest(
        request: request ?? shelfRequest(method, 'http://x/api/setup'),
        method: method,
        sub: sub,
        nextId: nextId ?? () => 'generated-id',
        startTasks: startTasks ?? (_, _, _) async {},
      );
    }

    test('GET log returns stored lines, running state and exit code', () async {
      host.runLogs['r1'] = <String>['l1', 'l2'];
      host.runExitCodes['r1'] = 3;

      final response = await call(method: 'GET', sub: <String>['r1', 'log']);

      expect(response.statusCode, 200);
      final body = await decodeShelfJson(response);
      expect(body['id'], 'r1');
      expect(body['lines'], <String>['l1', 'l2']);
      expect(body['running'], isFalse);
      expect(body['exitCode'], 3);
    });

    test('GET log reports a running task and omits the exit code', () async {
      host.activeTaskRuns.add('r2');

      final response = await call(method: 'GET', sub: <String>['r2', 'log']);

      final body = await decodeShelfJson(response);
      expect(body['lines'], isEmpty);
      expect(body['running'], isTrue);
      expect(body.containsKey('exitCode'), isFalse);
    });

    test('non-log routes delegate to the install handler', () async {
      final response = await call(
        method: 'POST',
        sub: <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{'packageIds': <String>[]},
        ),
      );

      expect(response.statusCode, 400);
      expect((await decodeShelfJson(response))['error'], 'packageIds required');
    });

    test('POST install seeds the run log and tracks the active task',
        () async {
      final tasks = <List<Object?>>[];

      final response = await call(
        method: 'POST',
        sub: <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{'packageIds': <String>['git']},
        ),
        startTasks: (id, specialIds, script) async {
          tasks.add(<Object?>[id, specialIds, script]);
        },
      );

      expect(response.statusCode, 200);
      final body = await decodeShelfJson(response);
      expect(body['ok'], isTrue);
      expect(body['id'], 'generated-id');

      // The onStarted hook seeded the run state.
      expect(host.runLogs['generated-id']!.single, startsWith(r'$ '));
      expect(host.runLogs['generated-id']!.single, contains('install'));
      expect(host.activeTaskRuns, contains('generated-id'));
      expect(host.runExitCodes.containsKey('generated-id'), isFalse);

      // The async kick-off happens via unawaited — let it run.
      await Future<void>.delayed(Duration.zero);
      expect(tasks, hasLength(1));
      expect(tasks.single[0], 'generated-id');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
