import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';
import 'package:yoloit/features/board/plugins/builtin/setup_guide_plugin.dart';

import 'setup_guide_test_harness.dart';

// Remote install flow tests. A real loopback HttpServer stands in for the
// remote yoloitd; tester.runAsync gives the panel's periodic poll timer and
// the client's dart:io HTTP futures a real event loop.

Future<HttpServer> _bindServer() async {
  Object? lastError;
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      return await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('could not bind test server: $lastError');
}

void _respondJson(HttpRequest request, Object body, {int status = 200}) {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  unawaited(request.response.close());
}

RemoteBoardInfo _remoteFor(HttpServer server) => (
  url: 'http://127.0.0.1:${server.port}',
  token: 'tok',
  boardId: 'b1',
  revision: null,
);

/// Waits (real clock) until [condition] holds, pumping frames in between.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
    if (condition()) return;
  }
  fail('condition not met within 15s');
}

void main() {
  // flutter_test installs a mock HttpOverrides that answers every request
  // with HTTP 400; disable it so the panel's client can reach the real
  // loopback test server, and restore it afterwards for other test files
  // sharing this process.
  HttpOverrides? previousOverrides;
  setUp(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = previousOverrides);

  testWidgets('remote install streams the run log and refreshes on completion', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final server = await _bindServer();
      try {
        SetupGuidePanel.debugRemotePollInterval = const Duration(
          milliseconds: 40,
        );
        addTearDown(() => SetupGuidePanel.debugRemotePollInterval = null);

        var logRequests = 0;
        var setupChecks = 0;
        final refreshed = setupSnapshotFor(
          <SetupPackageStatus>[
            setupPkg(
              id: 'codex',
              name: 'Codex CLI',
              category: SetupPackageCategory.agents,
              available: true,
              version: 'codex 1.0',
            ),
          ],
          versionLabel: '42.0',
        );
        server.listen((request) {
          final path = request.uri.path;
          if (request.method == 'POST' && path == '/api/setup/install') {
            _respondJson(request, <String, dynamic>{
              'id': 'run-1',
              'script': 'echo remote',
            });
          } else if (request.method == 'GET' &&
              path == '/api/setup/run-1/log') {
            logRequests++;
            if (logRequests == 1) {
              _respondJson(request, <String, dynamic>{
                'id': 'run-1',
                'lines': <String>['remote line 1'],
                'running': true,
              });
            } else {
              _respondJson(request, <String, dynamic>{
                'id': 'run-1',
                'lines': <String>['remote line 1', 'remote line 2'],
                'running': false,
                'exitCode': 0,
              });
            }
          } else if (request.method == 'GET' && path == '/api/setup') {
            setupChecks++;
            _respondJson(request, refreshed.toJson());
          } else {
            _respondJson(request, <String, dynamic>{
              'error': 'not found',
            }, status: 404);
          }
        });

        await tester.pumpWidget(
          setupGuideHarness(
            panel: setupPanelFor(<String>['codex']),
            snapshot: setupSnapshotFor(<SetupPackageStatus>[
              setupPkg(
                id: 'codex',
                name: 'Codex CLI',
                category: SetupPackageCategory.agents,
                installCommand: 'install codex',
              ),
            ]),
            remoteInfo: _remoteFor(server),
          ),
        );
        await tester.pump();

        // The header reflects the remote target.
        expect(find.text('Remote machine setup'), findsOneWidget);

        await tester.tap(find.textContaining('Install selected'));

        // Only new log lines are appended across polls: the second response
        // repeats 'remote line 1' but the panel must not duplicate it.
        await _pumpUntil(
          tester,
          () =>
              tester.any(find.text('remote line 2')) &&
              tester.any(find.text('42.0')),
        );

        expect(find.text('remote line 1'), findsOneWidget);
        expect(find.text('remote line 2'), findsOneWidget);
        expect(find.text('\$ echo remote'), findsOneWidget);
        expect(find.text('Run: run-1'), findsOneWidget);
        // Completing the run triggered a setup re-check...
        expect(setupChecks, greaterThan(0));
        expect(logRequests, greaterThan(1));
        // ...which replaced the snapshot and cleared the installing state.
        expect(find.text('42.0'), findsOneWidget);
        expect(find.textContaining('Install selected'), findsOneWidget);
        expect(find.text('Installing...'), findsNothing);
      } finally {
        await server.close(force: true);
      }
    });
  });

  testWidgets('remote install surfaces an error when the log poll fails', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final server = await _bindServer();
      try {
        SetupGuidePanel.debugRemotePollInterval = const Duration(
          milliseconds: 40,
        );
        addTearDown(() => SetupGuidePanel.debugRemotePollInterval = null);

        server.listen((request) {
          final path = request.uri.path;
          if (request.method == 'POST' && path == '/api/setup/install') {
            _respondJson(request, <String, dynamic>{
              'id': 'run-9',
              'script': 'echo boom',
            });
          } else if (request.method == 'GET' &&
              path == '/api/setup/run-9/log') {
            _respondJson(request, <String, dynamic>{
              'error': 'log gone',
            }, status: 500);
          } else {
            _respondJson(request, <String, dynamic>{
              'error': 'not found',
            }, status: 404);
          }
        });

        await tester.pumpWidget(
          setupGuideHarness(
            panel: setupPanelFor(<String>['codex']),
            snapshot: setupSnapshotFor(<SetupPackageStatus>[
              setupPkg(
                id: 'codex',
                name: 'Codex CLI',
                category: SetupPackageCategory.agents,
                installCommand: 'install codex',
              ),
            ]),
            remoteInfo: _remoteFor(server),
          ),
        );
        await tester.pump();

        await tester.tap(find.textContaining('Install selected'));

        await _pumpUntil(tester, () => tester.any(find.textContaining('HTTP 500')));

        expect(find.textContaining('HTTP 500'), findsOneWidget);
        // The poll timer was cancelled and the installing state cleared.
        expect(find.textContaining('Install selected'), findsOneWidget);
        expect(find.text('Installing...'), findsNothing);
      } finally {
        await server.close(force: true);
      }
    });
  });
}
