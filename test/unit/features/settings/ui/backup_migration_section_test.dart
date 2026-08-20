import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/settings/data/backup_migration_service.dart';
import 'package:yoloit/features/settings/ui/backup_migration_section.dart';

/// HTTP mock that captures every export/import request and returns a
/// scripted JSON response.
class _CapturingMock {
  _CapturingMock({required this.exportBody, required this.importBody});

  final Map<String, dynamic> exportBody;
  final Map<String, dynamic> importBody;
  final List<http.Request> requests = [];

  http.Client client() {
    return MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/export')) {
        return http.Response(jsonEncode(exportBody), 200,
            headers: {'content-type': 'application/json'});
      }
      if (request.url.path.endsWith('/import')) {
        return http.Response(jsonEncode(importBody), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
  }
}

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('yoloit_bm_section_test_');
    // Provide a port file so the service can resolve the URL.
    Directory(p.join(scratch.path, '.config', 'yoloit')).createSync(
      recursive: true,
    );
    File(p.join(scratch.path, '.config', 'yoloit', 'cli.port'))
        .writeAsStringSync('54321');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: scratch.path));
  });

  tearDown(() {
    PlatformDirs.reset();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BackupMigrationSection())),
      ),
    );
  }

  testWidgets('renders section with passphrase field and toggle switches',
      (tester) async {
    await pumpSection(tester);

    expect(find.text('Export…'), findsOneWidget);
    expect(find.text('Import…'), findsOneWidget);
    expect(find.text('Archive passphrase'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Secrets'), findsOneWidget);
  });

  testWidgets('tapping Export with mocked picker calls service with flags',
      (tester) async {
    final mock = _CapturingMock(
      exportBody: {
        'ok': true,
        'path': '/tmp/out.tar',
        'encrypted': true,
        'manifest': {
          'schemaVersion': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'sourceAppVersion': '1.0.56',
          'sourceHostname': 'host',
          'sourceHome': '/Users/tester',
          'sourceUsername': 'tester',
          'contents': <String>['prefs', 'config'],
          'flags': <String, bool>{'secrets': false},
          'pathIndex': <Map<String, dynamic>>[],
        },
      },
      importBody: <String, dynamic>{'ok': true, 'report': <String, dynamic>{}},
    );

    final service = BackupMigrationService(client: mock.client());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackupMigrationSection(
              service: service,
              pickSavePath: (name) async => '/tmp/$name',
            ),
          ),
        ),
      ),
    );

    // Toggle the "Secrets" switch on. The 5 switches in the section are
// (in order): History, Chat sessions, Calendar, CLI bookmarks, Secrets.
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(5));
    await tester.tap(switches.at(4));
    await tester.pumpAndSettle();

    // Trigger export.
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    expect(mock.requests, hasLength(1));
    final body = mock.requests.single.body;
    expect(body, contains('"path":"/tmp/yoloit-'));
    expect(body, contains('"includeSecrets":true'));
  });

  testWidgets('export error surfaces in UI', (tester) async {
    final mock = _CapturingMock(
      exportBody: <String, dynamic>{'ok': false, 'message': 'CLI server is down'},
      importBody: <String, dynamic>{'ok': true, 'report': <String, dynamic>{}},
    );
    final service = BackupMigrationService(client: mock.client());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackupMigrationSection(
              service: service,
              pickSavePath: (name) async => '/tmp/out.tar',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    expect(find.textContaining('CLI server is down'), findsOneWidget);
  });

  testWidgets('last export path displays after success', (tester) async {
    final mock = _CapturingMock(
      exportBody: {
        'ok': true,
        'path': '/Users/me/Desktop/yoloit.tar',
        'encrypted': false,
        'manifest': {
          'schemaVersion': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'sourceAppVersion': '1.0.56',
          'sourceHostname': 'host',
          'sourceHome': '/Users/me',
          'sourceUsername': 'me',
          'contents': <String>['prefs'],
          'flags': <String, bool>{},
          'pathIndex': <Map<String, dynamic>>[],
        },
      },
      importBody: <String, dynamic>{'ok': true, 'report': <String, dynamic>{}},
    );
    final service = BackupMigrationService(client: mock.client());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackupMigrationSection(
              service: service,
              pickSavePath: (name) async => '/Users/me/Desktop/yoloit.tar',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Last export: /Users/me/Desktop/yoloit.tar'),
      findsOneWidget,
    );
  });
}