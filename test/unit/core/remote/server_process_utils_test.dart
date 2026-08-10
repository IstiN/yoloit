import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/remote/server_process_utils.dart';

import 'server_process_test_support.dart';

void main() {
  group('response helpers', () {
    test('readJsonBody parses maps and tolerates empty or non-map bodies',
        () async {
      expect(await readJsonBody(shelfRequest('POST', 'http://x/')), isEmpty);
      expect(
        await readJsonBody(shelfRequest('POST', 'http://x/', body: '  ')),
        isEmpty,
      );
      expect(
        await readJsonBody(shelfRequest('POST', 'http://x/', body: <String, int>{'a': 1})),
        <String, dynamic>{'a': 1},
      );
      // A JSON list is not a map and yields an empty body.
      final listRequest = shelf.Request(
        'POST',
        Uri.parse('http://x/'),
        body: '[1,2]',
      );
      expect(await readJsonBody(listRequest), isEmpty);
    });

    test('jsonResponse encodes body with status and content type', () async {
      final response = jsonResponse(<String, Object?>{'ok': true}, 201);
      expect(response.statusCode, 201);
      expect(response.headers['content-type'], contains('application/json'));
      expect(await response.readAsString(), '{"ok":true}');
    });

    test('htmlResponse serves html content type', () async {
      final response = htmlResponse('<p>hi</p>');
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/html'));
      expect(await response.readAsString(), '<p>hi</p>');
    });
  });

  group('file-system helpers', () {
    test('homePath returns trimmed HOME or null when unset', () {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
      if (home == null || home.trim().isEmpty) {
        expect(homePath(), isNull);
      } else {
        expect(homePath(), home.trim());
      }
    });

    test('validDirectoryName rejects empty, dot and separator names', () {
      expect(validDirectoryName(''), isFalse);
      expect(validDirectoryName('.'), isFalse);
      expect(validDirectoryName('..'), isFalse);
      expect(validDirectoryName('a/b'), isFalse);
      expect(validDirectoryName('a\\b'), isFalse);
      expect(validDirectoryName('a\x00b'), isFalse);
      expect(validDirectoryName('plain dir'), isTrue);
    });

    test('shellQuote escapes single quotes', () {
      expect(shellQuote('plain'), "'plain'");
      expect(shellQuote("it's"), "'it'\\''s'");
    });
  });

  group('process helpers', () {
    test('findExecutable resolves known tools and misses bogus ones', () async {
      expect(await findExecutable('sh'), isNotNull);
      expect(
        await findExecutable('yoloit-no-such-binary-xyz'),
        isNull,
      );
    });

    test('terminalLauncher prefers the script wrapper with the shell',
        () async {
      final launcher = await terminalLauncher('/bin/sh');
      expect(launcher.executable, isNotEmpty);
      expect(launcher.arguments, contains('/bin/sh'));
    });
  });

  group('authorization', () {
    test('isAuthorized allows empty token and matches bearer or query', () {
      expect(isAuthorized(shelfRequest('GET', 'http://x/'), null), isTrue);
      expect(isAuthorized(shelfRequest('GET', 'http://x/'), '  '), isTrue);
      expect(
        isAuthorized(
          shelfRequest(
            'GET',
            'http://x/',
            headers: const <String, String>{'authorization': 'Bearer tok'},
          ),
          'tok',
        ),
        isTrue,
      );
      expect(
        isAuthorized(shelfRequest('GET', 'http://x/?token=tok'), 'tok'),
        isTrue,
      );
      expect(isAuthorized(shelfRequest('GET', 'http://x/'), 'tok'), isFalse);
    });
  });

  group('ServerProcessMixin', () {
    test('collectRun captures output lines, exit code and cleanup', () async {
      final host = ProcessHost();
      final process = await Process.start(
        'sh',
        <String>['-c', 'echo hello; echo oops 1>&2; exit 3'],
      );
      host.runs['r1'] = process;
      await host.collectRun('r1', process);

      expect(host.runLogs['r1'], contains('hello'));
      expect(host.runLogs['r1'], contains('oops'));
      expect(host.runLogs['r1']!.last, '[exit 3]');
      expect(host.runs, isNot(contains('r1')));
      expect(host.runExitCodes['r1'], 3);
    });

    test('collectTerminal captures raw chunks, exit code and cleanup',
        () async {
      final host = ProcessHost();
      final process = await Process.start(
        'sh',
        <String>['-c', 'printf out; printf err 1>&2; exit 5'],
      );
      host.terminals['t1'] = process;
      await host.collectTerminal('t1', process);

      final combined = host.terminalChunks['t1']!.join();
      expect(combined, contains('out'));
      expect(combined, contains('err'));
      expect(combined, contains('[exit 5]'));
      expect(host.terminals, isNot(contains('t1')));
      expect(host.terminalExitCodes['t1'], 5);
    });

    test('killAllRunsAndTerminals kills processes and clears state', () async {
      final host = ProcessHost();
      final runProcess = await Process.start('sleep', <String>['30']);
      final termProcess = await Process.start('sleep', <String>['30']);
      host.runs['r'] = runProcess;
      host.terminals['t'] = termProcess;
      host.activeTaskRuns.add('r');

      host.killAllRunsAndTerminals();

      expect(host.runs, isEmpty);
      expect(host.terminals, isEmpty);
      expect(host.activeTaskRuns, isEmpty);
      expect(await runProcess.exitCode, isNot(0));
      expect(await termProcess.exitCode, isNot(0));
    });
  });

  group('terminalLogResponse', () {
    test('slices chunks from since and reports running state', () async {
      final response = terminalLogResponse(
        id: 't1',
        since: 1,
        chunks: <String>['a', 'b', 'c'],
        running: true,
        exitCode: null,
      );
      final body = await decodeShelfJson(response);
      expect(body['id'], 't1');
      expect(body['next'], 3);
      expect(body['chunks'], <String>['b', 'c']);
      expect(body['running'], isTrue);
      expect(body.containsKey('exitCode'), isFalse);
    });

    test('clamps since into range and includes exit code', () async {
      final response = terminalLogResponse(
        id: 't1',
        since: 99,
        chunks: <String>['a'],
        running: false,
        exitCode: 7,
      );
      final body = await decodeShelfJson(response);
      expect(body['chunks'], isEmpty);
      expect(body['exitCode'], 7);
    });
  });

  group('handleTerminalsRequest', () {
    final terminals = <String, Process>{};
    final terminalChunks = <String, List<String>>{};
    final terminalExitCodes = <String, int>{};

    tearDown(() {
      for (final process in terminals.values) {
        process.kill();
      }
      terminals.clear();
      terminalChunks.clear();
      terminalExitCodes.clear();
    });

    Future<shelf.Response> call({
      required String method,
      required List<String> sub,
      shelf.Request? request,
    }) {
      return handleTerminalsRequest(
        request: request ?? shelfRequest(method, 'http://x/api/terminals'),
        method: method,
        sub: sub,
        defaultCwd: Directory.systemTemp.path,
        nextId: () => 'generated',
        killExisting: (id) {},
        onProcessStarted: (id, process) {},
        terminals: terminals,
        terminalChunks: terminalChunks,
        terminalExitCodes: terminalExitCodes,
      );
    }

    test('returns 404 for malformed or unknown routes', () async {
      for (final sub in <List<String>>[
        <String>['t1'],
        <String>['t1', 'bogus'],
        <String>['t1', 'log', 'extra'],
      ]) {
        final response = await call(method: 'GET', sub: sub);
        expect(response.statusCode, 404, reason: 'sub=$sub');
      }
      // Wrong method for a known route.
      final response = await call(method: 'POST', sub: <String>['t1', 'log']);
      expect(response.statusCode, 404);
    });

    test('log returns stored chunks honoring since and exit code', () async {
      terminalChunks['t1'] = <String>['a', 'b'];
      terminalExitCodes['t1'] = 2;
      final response = await call(
        method: 'GET',
        sub: <String>['t1', 'log'],
        request: shelfRequest('GET', 'http://x/api/terminals/t1/log?since=1'),
      );
      final body = await decodeShelfJson(response);
      expect(response.statusCode, 200);
      expect(body['chunks'], <String>['b']);
      expect(body['running'], isFalse);
      expect(body['exitCode'], 2);

      // Invalid since falls back to 0.
      final invalid = await call(
        method: 'GET',
        sub: <String>['t1', 'log'],
        request: shelfRequest('GET', 'http://x/api/terminals/t1/log?since=abc'),
      );
      final invalidBody = await decodeShelfJson(invalid);
      expect(invalidBody['chunks'], <String>['a', 'b']);
    });

    test('input returns 404 for unknown terminal', () async {
      final response = await call(
        method: 'POST',
        sub: <String>['nope', 'input'],
        request: shelfRequest(
          'POST',
          'http://x/api/terminals/nope/input',
          body: <String, String>{'data': 'ls\n'},
        ),
      );
      expect(response.statusCode, 404);
      expect((await decodeShelfJson(response))['error'], 'terminal not found');
    });

    test('input writes data to the terminal stdin', () async {
      final process = await Process.start('cat', <String>[]);
      terminals['t1'] = process;
      final response = await call(
        method: 'POST',
        sub: <String>['t1', 'input'],
        request: shelfRequest(
          'POST',
          'http://x/api/terminals/t1/input',
          body: <String, String>{'data': 'ping\n'},
        ),
      );
      expect((await decodeShelfJson(response))['ok'], isTrue);
      await process.stdin.close();
      final echoed = await utf8.decoder.bind(process.stdout).join();
      expect(echoed, contains('ping'));
    });

    test('resize returns 404 for unknown terminal and stty for known',
        () async {
      final missing = await call(
        method: 'POST',
        sub: <String>['nope', 'resize'],
        request: shelfRequest(
          'POST',
          'http://x/api/terminals/nope/resize',
          body: <String, int>{'rows': 40, 'cols': 120},
        ),
      );
      expect(missing.statusCode, 404);

      final process = await Process.start('cat', <String>[]);
      terminals['t1'] = process;
      final response = await call(
        method: 'POST',
        sub: <String>['t1', 'resize'],
        request: shelfRequest(
          'POST',
          'http://x/api/terminals/t1/resize',
          body: <String, int>{'rows': 40, 'cols': 120},
        ),
      );
      expect((await decodeShelfJson(response))['ok'], isTrue);
      await process.stdin.close();
      final echoed = await utf8.decoder.bind(process.stdout).join();
      expect(echoed, contains('stty rows 40 cols 120'));
    });

    test('stop kills the terminal and reports false for unknown id',
        () async {
      final missing = await call(method: 'POST', sub: <String>['nope', 'stop']);
      expect((await decodeShelfJson(missing))['ok'], isFalse);

      final process = await Process.start('sleep', <String>['30']);
      terminals['t1'] = process;
      final response = await call(method: 'POST', sub: <String>['t1', 'stop']);
      expect((await decodeShelfJson(response))['ok'], isTrue);
      expect(terminals, isNot(contains('t1')));
      expect(await process.exitCode, isNot(0));
    });
  });

  group('handleTerminalCreate', () {
    final started = <Process>[];

    tearDown(() {
      for (final process in started) {
        process.kill();
      }
      started.clear();
    });

    Future<shelf.Response> create({
      required Map<String, Object?> body,
      String defaultCwd = '',
      void Function(String id)? killExisting,
    }) {
      final killed = <String>[];
      return handleTerminalCreate(
        request: shelfRequest('POST', 'http://x/api/terminals', body: body),
        defaultCwd: defaultCwd.isEmpty ? Directory.systemTemp.path : defaultCwd,
        nextId: () => '',
        killExisting: killExisting ?? killed.add,
        onProcessStarted: (id, process) => started.add(process),
      );
    }

    test('rejects an empty id', () async {
      final response = await create(body: <String, Object?>{'id': '  '});
      expect(response.statusCode, 400);
      expect((await decodeShelfJson(response))['error'], 'id required');
    });

    test('rejects a missing working directory', () async {
      final response = await create(
        body: <String, Object?>{
          'id': 't1',
          'cwd': '/yoloit/no/such/dir-xyz',
        },
      );
      expect(response.statusCode, 404);
      expect((await decodeShelfJson(response))['error'], 'working directory not found');
    });

    test('starts a terminal process with env and reports pid', () async {
      final tempDir = await Directory.systemTemp.createTemp('yoloit_term_');
      addTearDown(() => tempDir.delete(recursive: true));
      final killed = <String>[];
      final response = await create(
        body: <String, Object?>{
          'id': 't1',
          'cwd': tempDir.path,
          'env': <String, String>{'YOLOIT_TEST_ENV': '1'},
        },
        killExisting: killed.add,
      );
      final body = await decodeShelfJson(response);
      expect(body['ok'], isTrue);
      expect(body['id'], 't1');
      expect(body['pid'], isA<int>());
      expect(killed, <String>['t1']);
      expect(started, hasLength(1));
    });
  });

  group('handleFilesRequest and handleCreateDirectory', () {
    test('GET lists files and rejects unsupported routes', () async {
      final listed = <String?>[];
      Future<shelf.Response> listFiles(String? path) async {
        listed.add(path);
        return jsonResponse(<String, Object?>{'listed': path});
      }

      final response = await handleFilesRequest(
        request: shelfRequest('GET', 'http://x/api/files?path=%2Ftmp'),
        method: 'GET',
        sub: const <String>[],
        defaultRoot: () => Directory.systemTemp.path,
        listFiles: listFiles,
      );
      expect(listed, <String?>['/tmp']);
      expect((await decodeShelfJson(response))['listed'], '/tmp');

      final rejected = await handleFilesRequest(
        request: shelfRequest('DELETE', 'http://x/api/files/x'),
        method: 'DELETE',
        sub: const <String>['x'],
        defaultRoot: () => Directory.systemTemp.path,
        listFiles: listFiles,
      );
      expect(rejected.statusCode, 405);
    });

    test('POST directories validates the name and parent', () async {
      Future<shelf.Response> listFiles(String? path) async =>
          jsonResponse(<String, Object?>{'listed': path});

      Future<shelf.Response> create(Map<String, Object?> body) {
        return handleFilesRequest(
          request:
              shelfRequest('POST', 'http://x/api/files/directories', body: body),
          method: 'POST',
          sub: const <String>['directories'],
          defaultRoot: () => Directory.systemTemp.path,
          listFiles: listFiles,
        );
      }

      final badName = await create(<String, Object?>{'name': 'a/b'});
      expect(badName.statusCode, 400);
      expect((await decodeShelfJson(badName))['error'], 'invalid directory name');

      final badParent = await create(<String, Object?>{
        'parentPath': '/yoloit/no/such/dir-xyz',
        'name': 'child',
      });
      expect(badParent.statusCode, 404);
      expect((await decodeShelfJson(badParent))['error'], 'parent directory not found');

      final tempDir = await Directory.systemTemp.createTemp('yoloit_mkdir_');
      addTearDown(() => tempDir.delete(recursive: true));
      final created = await create(<String, Object?>{
        'parentPath': tempDir.path,
        'name': 'child',
      });
      expect((await decodeShelfJson(created))['listed'], tempDir.path);
      expect(
        Directory('${tempDir.path}${Platform.pathSeparator}child').existsSync(),
        isTrue,
      );
    });

    test('buildFileListingResponse reports missing and existing dirs',
        () async {
      final missing = await buildFileListingResponse(
        directory: Directory('/yoloit/no/such/dir-xyz'),
        entries: const <Map<String, Object?>>[],
        roots: const <Map<String, Object?>>[],
      );
      expect(missing.statusCode, 404);
      expect((await decodeShelfJson(missing))['error'], 'directory not found');

      final root = await buildFileListingResponse(
        directory: Directory(Platform.isWindows ? 'C:\\' : '/'),
        entries: const <Map<String, Object?>>[
          <String, Object?>{'name': 'a'},
        ],
        roots: const <Map<String, Object?>>[
          <String, Object?>{'name': 'root'},
        ],
      );
      final body = await decodeShelfJson(root);
      expect(body['ok'], isTrue);
      expect(body['parent'], isNull);
      expect((body['entries'] as List).length, 1);
      expect((body['roots'] as List).length, 1);
    });
  });

  group('handleSetupInstall', () {
    Future<shelf.Response> call({
      required String method,
      required List<String> sub,
      shelf.Request? request,
      String Function()? nextId,
      void Function(String id, String displayScript)? onStarted,
      Future<void> Function(String id, List<String> specialIds, String script)?
      startTasks,
    }) {
      return handleSetupInstall(
        request: request ?? shelfRequest(method, 'http://x/api/setup'),
        method: method,
        sub: sub,
        nextId: nextId ?? () => 'generated-id',
        onStarted: onStarted ?? (_, _) {},
        startTasks: startTasks ?? (_, _, _) async {},
      );
    }

    test('GET returns the setup snapshot', () async {
      final response = await call(method: 'GET', sub: const <String>[]);
      expect(response.statusCode, 200);
      final body = await decodeShelfJson(response);
      expect(body['runtime'], isA<Map<String, dynamic>>());
      expect(body['packages'], isA<List<dynamic>>());
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('POST install rejects missing packageIds', () async {
      final response = await call(
        method: 'POST',
        sub: const <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{'packageIds': <String>[]},
        ),
      );
      expect(response.statusCode, 400);
      expect((await decodeShelfJson(response))['error'], 'packageIds required');
    });

    test('POST install rejects packages without an install command', () async {
      final response = await call(
        method: 'POST',
        sub: const <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{'packageIds': <String>['no-such-package-xyz']},
        ),
      );
      expect(response.statusCode, 400);
      expect(
        (await decodeShelfJson(response))['error'],
        'no install command for selected packages on this OS',
      );
    });

    test('POST install dryRun returns the script without starting tasks',
        () async {
      var started = 0;
      final response = await call(
        method: 'POST',
        sub: const <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{
            'packageIds': <String>['git'],
            'dryRun': true,
          },
        ),
        onStarted: (_, _) => started++,
      );
      expect(response.statusCode, 200);
      final body = await decodeShelfJson(response);
      expect(body['ok'], isTrue);
      expect(body['script'] as String, contains('install'));
      expect(body.containsKey('id'), isFalse);
      expect(started, 0);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('POST install with a special task labels the display script',
        () async {
      final response = await call(
        method: 'POST',
        sub: const <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{
            'packageIds': <String>['yoloit-skills'],
            'dryRun': true,
          },
        ),
      );
      expect(response.statusCode, 200);
      final body = await decodeShelfJson(response);
      expect(body['ok'], isTrue);
      expect(body['script'] as String, contains('YoLoIT built-in task'));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('POST install starts tasks and reports the generated id', () async {
      final started = <String>[];
      final tasks = <List<Object?>>[];
      final response = await call(
        method: 'POST',
        sub: const <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{'packageIds': <String>['git']},
        ),
        onStarted: (id, displayScript) => started.add('$id|$displayScript'),
        startTasks: (id, specialIds, script) async {
          tasks.add(<Object?>[id, specialIds, script]);
        },
      );
      expect(response.statusCode, 200);
      final body = await decodeShelfJson(response);
      expect(body['ok'], isTrue);
      expect(body['id'], 'generated-id');
      expect(started, hasLength(1));
      expect(started.single, startsWith('generated-id|'));
      // The async kick-off happens via unawaited — let it run.
      await Future<void>.delayed(Duration.zero);
      expect(tasks, hasLength(1));
      expect(tasks.single[0], 'generated-id');
      expect(tasks.single[1], isEmpty);
      expect(tasks.single[2] as String, contains('install'));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('POST install honors a caller-provided run id', () async {
      final response = await call(
        method: 'POST',
        sub: const <String>['install'],
        request: shelfRequest(
          'POST',
          'http://x/api/setup/install',
          body: <String, Object?>{
            'packageIds': <String>['git'],
            'id': 'custom-run',
          },
        ),
      );
      expect((await decodeShelfJson(response))['id'], 'custom-run');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('returns 404 for unknown routes', () async {
      final wrongMethod = await call(method: 'GET', sub: const <String>['install']);
      expect(wrongMethod.statusCode, 404);
      final wrongSub = await call(method: 'POST', sub: const <String>['bogus']);
      expect(wrongSub.statusCode, 404);
    });
  });
}
