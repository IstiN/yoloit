import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/data/backup_migration_service.dart';
import 'package:yoloit/features/settings/ui/backup_migration_section.dart';

Map<String, Object?> _manifest() => <String, Object?>{
  'schemaVersion': 1,
  'createdAt': '2026-01-02T03:04:05.000Z',
  'sourceAppVersion': '1.0.0',
  'sourceHostname': 'source-host',
  'sourceHome': '/Users/source',
  'sourceUsername': 'source',
  'contents': <String>['prefs', 'config'],
  'flags': <String, bool>{},
  'pathIndex': <Map<String, Object?>>[],
};

Map<String, Object?> _report({required bool dryRun}) => <String, Object?>{
  'manifest': _manifest(),
  'dryRun': dryRun,
  'changes': <Map<String, Object?>>[
    <String, Object?>{
      'root': 'config',
      'action': 'overwrite',
      'path': 'state.json',
    },
    <String, Object?>{
      'root': 'data',
      'action': 'add',
      'path': 'boards_history/new.json',
    },
  ],
  'missing': <Map<String, Object?>>[
    <String, Object?>{
      'entry': <String, Object?>{
        'kind': 'workspace.path',
        'old': '/old/project',
      },
      'rewritten': '/new/project',
    },
  ],
  'conflicts': <Map<String, Object?>>[
    <String, Object?>{
      'boardId': 'board-1',
      'incomingName': 'Incoming',
      'existingName': 'Existing',
    },
  ],
};

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('yoloit_import_section_');
    final config = Directory(p.join(scratch.path, '.config', 'yoloit'))
      ..createSync(recursive: true);
    File(p.join(config.path, 'cli.port')).writeAsStringSync('54321');
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  BackupMigrationService service(
    List<http.Request> requests, {
    bool fail = false,
  }) {
    return BackupMigrationService(
      client: MockClient((request) async {
        requests.add(request);
        if (fail) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'ok': false,
              'message': 'broken archive',
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'report': _report(dryRun: body['dryRun'] as bool),
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
      dirs: MacosPlatformDirs(homeOverride: scratch.path),
    );
  }

  Future<void> pumpSection(
    WidgetTester tester,
    BackupMigrationService backupService, {
    ArchivePathPicker? picker,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackupMigrationSection(
              service: backupService,
              pickArchivePath: picker ?? () async => '/tmp/source.tar',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('cancelling archive selection does not call the service', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await pumpSection(
      tester,
      service(requests),
      picker: () async => null,
    );

    await tester.tap(find.text('Import…'));
    await tester.pumpAndSettle();

    expect(requests, isEmpty);
    expect(find.text('Restore preview'), findsNothing);
  });

  testWidgets('cancelling the restore preview stops before applying', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await pumpSection(tester, service(requests));

    await tester.tap(find.text('Import…'));
    await tester.pumpAndSettle();
    expect(find.text('Restore preview'), findsOneWidget);
    expect(find.textContaining('Files: 2'), findsOneWidget);
    expect(find.textContaining('Board conflicts: 1'), findsOneWidget);
    expect(find.textContaining('Missing paths: 1'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['dryRun'], isTrue);
    expect(find.textContaining('Last import:'), findsNothing);
  });

  testWidgets('apply performs dry run then restore and shows the report', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await pumpSection(tester, service(requests));
    await tester.enterText(find.byType(TextField), 'secret');

    await tester.tap(find.text('Import…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Source: source-host', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('1 overwrite, 1 add'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    final preview = jsonDecode(requests[0].body) as Map<String, dynamic>;
    final applied = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(preview['dryRun'], isTrue);
    expect(applied['dryRun'], isFalse);
    expect(preview['passphrase'], 'secret');
    expect(applied['passphrase'], 'secret');
    expect(applied['onConflict'], 'keep');
    expect(find.textContaining('Last import: 2 files'), findsOneWidget);
    expect(find.textContaining('Restored 2 files'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('restore errors are shown inline', (tester) async {
    final requests = <http.Request>[];
    await pumpSection(tester, service(requests, fail: true));

    await tester.tap(find.text('Import…'));
    await tester.pumpAndSettle();

    expect(find.textContaining('broken archive'), findsOneWidget);
    expect(requests, hasLength(1));
  });

  testWidgets('an unavailable CLI service is shown inline', (tester) async {
    final requests = <http.Request>[];
    final backupService = service(requests);
    File(p.join(scratch.path, '.config', 'yoloit', 'cli.port')).deleteSync();
    await pumpSection(tester, backupService);

    await tester.tap(find.text('Import…'));
    await tester.pumpAndSettle();

    expect(find.textContaining('CLI server is not running'), findsOneWidget);
    expect(requests, isEmpty);
  });
}
