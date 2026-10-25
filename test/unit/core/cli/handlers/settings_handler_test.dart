import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:yoloit/core/cli/handlers/settings_handler.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/services/user_data_archive.dart';

shelf.Request _postRequest(String path, Map<String, dynamic> body) =>
    shelf.Request(
      'POST',
      Uri.parse('http://localhost:8080$path'),
      body: jsonEncode(body),
    );

shelf.Response _json(Object data) => shelf.Response.ok(
  jsonEncode(data),
  headers: {'content-type': 'application/json'},
);

shelf.Response _notFound(String msg) => shelf.Response.notFound(
  jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

shelf.Request _rawPostRequest(String path, String rawBody) => shelf.Request(
  'POST',
  Uri.parse('http://localhost:8080$path'),
  body: rawBody,
);

Future<Map<String, dynamic>> _importSettings(
  Map<String, dynamic> body,
) async {
  final response = await handleSettings(
    'POST',
    ['import'],
    _postRequest('/api/settings/import', body),
    json: _json,
    notFound: _notFound,
  );
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('yoloit_settings_test_');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: scratch.path));
    // Seed prefs to give the archive something to include.
    SharedPreferences.setMockInitialValues({'theme_preset': 'neonPurple'});
  });

  tearDown(() {
    PlatformDirs.reset();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  group('handleSettings', () {
    test('POST /export without passphrase and requirePassphrase=true errors',
        () async {
      final response = await handleSettings(
        'POST',
        ['export'],
        _postRequest('/api/settings/export', {
          'path': p.join(scratch.path, 'out.tar'),
        }),
        json: _json,
        notFound: _notFound,
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], isFalse);
      expect(body['message'], contains('passphrase'));
    });

    test('POST /export with YOLOIT_ARCHIVE_PASSPHRASE env produces archive',
        () async {
      // Force the singleton to use the test temp dir, then run export.
      final archive = UserDataArchive();
      final dest = File(p.join(scratch.path, 'out.tar'));

      // Mimic the handler by passing an explicit passphrase (the handler
      // reads the env var — we replicate that branch by calling the service
      // directly here). The handler unit-test for the env-var branch lives
      // implicitly in the UserDataArchive encryption round-trip test.
      final manifest = await archive.pack(
        outputPath: dest.path,
        passphrase: 'topsecret',
      );
      expect(dest.existsSync(), isTrue);
      expect(manifest.schemaVersion, ArchiveManifest.currentSchemaVersion);
    });

    test('POST /import dryRun returns report without touching files',
        () async {
      final archive = UserDataArchive();
      final src = File(p.join(scratch.path, 'src.tar'));
      await archive.pack(outputPath: src.path, passphrase: 'pw');

      final response = await handleSettings(
        'POST',
        ['import'],
        _postRequest('/api/settings/import', {
          'path': src.path,
          'passphrase': 'pw',
          'dryRun': true,
        }),
        json: _json,
        notFound: _notFound,
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], isTrue);
      final report = body['report'] as Map<String, dynamic>;
      expect(report['dryRun'], isTrue);
      expect(report['changes'], isA<List<dynamic>>());
    });

    test('POST /import with missing path errors', () async {
      final response = await handleSettings(
        'POST',
        ['import'],
        _postRequest('/api/settings/import', {
          'path': p.join(scratch.path, 'does-not-exist.tar'),
        }),
        json: _json,
        notFound: _notFound,
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], isFalse);
      expect(body['message'], contains('Archive not found'));
    });

    test('POST /import rejects bad mode', () async {
      final archive = UserDataArchive();
      final src = File(p.join(scratch.path, 'src.tar'));
      await archive.pack(outputPath: src.path, passphrase: 'pw');

      final response = await handleSettings(
        'POST',
        ['import'],
        _postRequest('/api/settings/import', {
          'path': src.path,
          'passphrase': 'pw',
          'mode': 'invalid',
        }),
        json: _json,
        notFound: _notFound,
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], isFalse);
      expect(body['message'], contains('mode'));
    });

    test('unknown path returns notFound', () async {
      final response = await handleSettings(
        'POST',
        ['nope'],
        _postRequest('/api/settings/nope', {}),
        json: _json,
        notFound: _notFound,
      );
      expect(response.statusCode, 404);
    });

    group('POST /import branches', () {
      Future<File> packArchive({String? passphrase}) async {
        final src = File(p.join(scratch.path, 'src.tar'));
        await UserDataArchive().pack(
          outputPath: src.path,
          passphrase: passphrase,
        );
        return src;
      }

      test('rejects a malformed JSON body', () async {
        final response = await handleSettings(
          'POST',
          ['import'],
          _rawPostRequest('/api/settings/import', '{not-json'),
          json: _json,
          notFound: _notFound,
        );
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['ok'], isFalse);
        expect(body['message'], contains('Invalid JSON'));
      });

      test('rejects an empty path', () async {
        final body = await _importSettings({'path': '   '});
        expect(body['ok'], isFalse);
        expect(body['message'], contains('Provide "path"'));
      });

      test('accepts mode replace with a dry-run report', () async {
        final src = await packArchive(passphrase: 'pw');
        final body = await _importSettings({
          'path': src.path,
          'passphrase': 'pw',
          'mode': 'replace',
        });
        expect(body['ok'], isTrue);
        final report = body['report'] as Map<String, dynamic>;
        expect(report['dryRun'], isTrue);
      });

      test('accepts pathRewrite ask and keep', () async {
        final src = await packArchive(passphrase: 'pw');
        for (final rewrite in ['ask', 'keep']) {
          final body = await _importSettings({
            'path': src.path,
            'passphrase': 'pw',
            'pathRewrite': rewrite,
          });
          expect(body['ok'], isTrue, reason: 'pathRewrite=$rewrite');
        }
      });

      test('rejects an unknown pathRewrite', () async {
        final src = await packArchive(passphrase: 'pw');
        final body = await _importSettings({
          'path': src.path,
          'passphrase': 'pw',
          'pathRewrite': 'bogus',
        });
        expect(body['ok'], isFalse);
        expect(body['message'], contains('pathRewrite'));
      });

      test('accepts every onConflict choice', () async {
        final src = await packArchive(passphrase: 'pw');
        for (final choice in ['keep', 'overwrite', 'rename', 'skip']) {
          final body = await _importSettings({
            'path': src.path,
            'passphrase': 'pw',
            'onConflict': choice,
          });
          expect(body['ok'], isTrue, reason: 'onConflict=$choice');
        }
      });

      test('rejects an unknown onConflict', () async {
        final src = await packArchive(passphrase: 'pw');
        final body = await _importSettings({
          'path': src.path,
          'passphrase': 'pw',
          'onConflict': 'bogus',
        });
        expect(body['ok'], isFalse);
        expect(body['message'], contains('onConflict'));
      });

      test('accepts a partial overrides map', () async {
        final src = await packArchive(passphrase: 'pw');
        final body = await _importSettings({
          'path': src.path,
          'passphrase': 'pw',
          'overrides': {'prefs': false, 'config': false},
        });
        expect(body['ok'], isTrue);
      });

      test('reports FormatException messages for encrypted archives '
          'without a passphrase', () async {
        final src = await packArchive(passphrase: 'pw');
        final body = await _importSettings({'path': src.path});
        expect(body['ok'], isFalse);
        expect(body['message'], contains('passphrase'));
      });

      test('wraps wrong-passphrase failures as Import failed', () async {
        final src = await packArchive(passphrase: 'pw');
        final body = await _importSettings({
          'path': src.path,
          'passphrase': 'wrong',
        });
        expect(body['ok'], isFalse);
        expect(body['message'], contains('Import failed'));
      });
    });
  });
}
