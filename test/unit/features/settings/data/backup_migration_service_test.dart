import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/services/user_data_archive.dart';
import 'package:yoloit/features/settings/data/backup_migration_service.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('yoloit_bm_svc_test_');
    Directory(p.join(scratch.path, '.config', 'yoloit')).createSync(
      recursive: true,
    );
    File(p.join(scratch.path, '.config', 'yoloit', 'cli.port'))
        .writeAsStringSync('12345');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: scratch.path));
  });

  tearDown(() {
    PlatformDirs.reset();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('throws BackupMigrationUnavailableError when port file missing',
      () async {
    File(p.join(scratch.path, '.config', 'yoloit', 'cli.port'))
        .deleteSync();
    final svc = BackupMigrationService(client: MockClient((_) async => http.Response('{}', 200)));
    expect(
      () => svc.export(destinationPath: '/tmp/x.tar', passphrase: 'pw'),
      throwsA(isA<BackupMigrationUnavailableError>()),
    );
  });

  test('export() POSTs to /api/settings/export with expected body', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'ok': true,
          'path': '/tmp/x.tar',
          'encrypted': true,
          'manifest': _emptyManifest(),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final svc = BackupMigrationService(client: mock);

    final result = await svc.export(
      destinationPath: '/tmp/x.tar',
      passphrase: 'secret',
      includeSecrets: true,
      includeHistory: false,
      includeChatSessions: true,
      includeCalendar: true,
      includeStateJson: true,
    );

    expect(captured!.url.toString(),
        'http://127.0.0.1:12345/api/settings/export');
    expect(captured!.method, 'POST');
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['path'], '/tmp/x.tar');
    expect(body['passphrase'], 'secret');
    expect(body['includeSecrets'], isTrue);
    expect(body['includeHistory'], isFalse);
    expect(body['requirePassphrase'], isTrue);

    expect(result.path, '/tmp/x.tar');
    expect(result.encrypted, isTrue);
  });

  test('export() with empty passphrase sets requirePassphrase=false',
      () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'ok': true,
          'path': '/tmp/x.tar',
          'encrypted': false,
          'manifest': _emptyManifest(),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final svc = BackupMigrationService(client: mock);
    await svc.export(destinationPath: '/tmp/x.tar', passphrase: '');
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['requirePassphrase'], isFalse);
  });

  test('restore() POSTs to /api/settings/import with overrides and conflict',
      () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'ok': true,
          'report': {
            'manifest': _emptyManifest(),
            'dryRun': true,
            'changes': <Map<String, dynamic>>[
              {'root': 'config', 'action': 'add', 'path': 'foo.json'},
            ],
            'missing': <Map<String, dynamic>>[],
            'conflicts': <Map<String, dynamic>>[],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final svc = BackupMigrationService(client: mock);

    final result = await svc.restore(
      archivePath: '/tmp/old.tar',
      passphrase: 'pw',
      dryRun: true,
      mode: ImportMode.replace,
      pathRewrite: PathRewriteStrategy.keep,
      overrides: const ImportOverrides(
        prefs: false,
        config: true,
        data: true,
        workspaces: false,
      ),
      onConflict: BoardConflictChoice.overwrite,
    );

    expect(captured!.url.toString(),
        'http://127.0.0.1:12345/api/settings/import');
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['dryRun'], isTrue);
    expect(body['mode'], 'replace');
    expect(body['pathRewrite'], 'keep');
    expect(body['onConflict'], 'overwrite');
    final overrides = body['overrides'] as Map<String, dynamic>;
    expect(overrides['prefs'], isFalse);
    expect(overrides['config'], isTrue);
    expect(overrides['workspaces'], isFalse);

    expect(result.report.dryRun, isTrue);
    expect(result.report.changes, hasLength(1));
  });

  test('restore() surfaces server error as StateError', () async {
    final mock = MockClient((_) async => http.Response(
          jsonEncode({'ok': false, 'message': 'archive corrupted'}),
          200,
          headers: {'content-type': 'application/json'},
        ));
    final svc = BackupMigrationService(client: mock);
    expect(
      () => svc.restore(archivePath: '/tmp/x.tar'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('archive corrupted'),
        ),
      ),
    );
  });

  test('restore() propagates network errors', () async {
    final mock = MockClient((_) async => http.Response('nope', 500));
    final svc = BackupMigrationService(client: mock);
    expect(
      () => svc.restore(archivePath: '/tmp/x.tar'),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, dynamic> _emptyManifest() => {
  'schemaVersion': 1,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'sourceAppVersion': '1.0.56',
  'sourceHostname': 'host',
  'sourceHome': '/Users/tester',
  'sourceUsername': 'tester',
  'contents': <String>['prefs'],
  'flags': <String, bool>{},
  'pathIndex': <Map<String, dynamic>>[],
};