import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// A PlatformDirs that points configDir to a temp directory.
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

void _cleanupScopedFiles() {
  try {
    final configDir = PlatformDirs.instance.configDir;
    final meta = File(p.join(configDir, 'env_groups.json'));
    if (meta.existsSync()) meta.deleteSync();
    final valuesDir = Directory(p.join(configDir, 'env_groups_values'));
    if (valuesDir.existsSync()) valuesDir.deleteSync(recursive: true);
    final credentialsDir = Directory(p.join(configDir, 'credentials'));
    if (credentialsDir.existsSync()) credentialsDir.deleteSync(recursive: true);
    // Also remove any legacy relative-path leftovers from older test runs.
    final legacyMeta = File('env_groups.json');
    if (legacyMeta.existsSync()) legacyMeta.deleteSync();
    final legacyValuesDir = Directory('env_groups_values');
    if (legacyValuesDir.existsSync()) legacyValuesDir.deleteSync(recursive: true);
  } catch (_) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('env_groups_test_');
    PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
    // The service now uses scoped paths via [FileStorageAdapter]; remove any
    // leftovers from earlier test runs.
    _cleanupScopedFiles();
  });

  tearDown(() {
    _cleanupScopedFiles();
    GlobalEnvGroupsService.instance.resetForTesting();
    PlatformDirs.setInstance(const MacosPlatformDirs());
    tmpDir.deleteSync(recursive: true);
  });

  group('GlobalEnvGroupsService', () {
    test('loadAll returns empty list when file does not exist', () async {
      final groups = await GlobalEnvGroupsService.instance.loadAll();
      expect(groups, isEmpty);
    });

    test('loadAll returns mutable copies that can be edited', () async {
      await GlobalEnvGroupsService.instance.saveAll([
        const GlobalEnvGroup(
          id: 'g1',
          name: 'test',
          values: {'TOKEN': 'my_token'},
        ),
      ]);

      final loaded = await GlobalEnvGroupsService.instance.loadAll();
      expect(() => loaded.add(
        const GlobalEnvGroup(id: 'g2', name: 'new', values: {}),
      ), returnsNormally);
      expect(() => loaded[0] = loaded[0].copyWith(name: 'renamed'), returnsNormally);
    });

    test('loadAll round-trip after save uses cache without breaking edits', () async {
      final data = [
        const GlobalEnvGroup(
          id: 'g1',
          name: 'production',
          values: {'API_KEY': 'abc123', 'DB_HOST': 'localhost'},
        ),
        const GlobalEnvGroup(
          id: 'g2',
          name: 'staging',
          values: {'API_KEY': 'xyz789'},
        ),
      ];

      await GlobalEnvGroupsService.instance.saveAll(data);

      final loaded = await GlobalEnvGroupsService.instance.loadAll();
      expect(loaded.length, 2);
      expect(loaded[0].id, 'g1');
      expect(loaded[0].name, 'production');
      expect(loaded[0].values['API_KEY'], 'abc123');
      expect(loaded[0].values['DB_HOST'], 'localhost');
      expect(loaded[1].id, 'g2');
      expect(loaded[1].name, 'staging');
      expect(loaded[1].values['API_KEY'], 'xyz789');
    });

    test('JSON file contains only metadata, not secret values', () async {
      final data = [
        const GlobalEnvGroup(
          id: 'g1',
          name: 'test',
          values: {'SECRET': 'super_secret_value'},
        ),
      ];

      await GlobalEnvGroupsService.instance.saveAll(data);

      final file = File(p.join(tmpDir.path, 'env_groups.json'));
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      // JSON must NOT contain the secret value.
      expect(content, isNot(contains('super_secret_value')));
      // JSON must contain keys list, not a values map.
      expect(content, contains('"keys"'));
      expect(content, contains('SECRET'));
    });

    test('values are stored in FlutterSecureStorage', () async {
      final data = [
        const GlobalEnvGroup(
          id: 'g1',
          name: 'test',
          values: {'TOKEN': 'my_token'},
        ),
      ];

      await GlobalEnvGroupsService.instance.saveAll(data);

      // Read directly from mock secure storage.
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: 'env_group_g1');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map;
      expect(decoded['TOKEN'], 'my_token');
    });

    test(
      'saveAll preserves existing secret values when incoming values are empty',
      () async {
        await GlobalEnvGroupsService.instance.saveAll([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'test',
            values: {'TOKEN': 'my_token', 'EMPTY': ''},
          ),
        ]);

        await GlobalEnvGroupsService.instance.saveAll([
          const GlobalEnvGroup(
            id: 'g1',
            name: 'test',
            values: {'TOKEN': '', 'EMPTY': ''},
          ),
        ]);

        const storage = FlutterSecureStorage();
        final raw = await storage.read(key: 'env_group_g1');
        final decoded = jsonDecode(raw!) as Map;
        expect(decoded['TOKEN'], 'my_token');
        expect(decoded['EMPTY'], '');
      },
    );

    test(
      'prefixed group ids do not produce double-prefixed secure keys',
      () async {
        final data = [
          const GlobalEnvGroup(
            id: 'env_group_123',
            name: 'test',
            values: {'TOKEN': 'my_token'},
          ),
        ];

        await GlobalEnvGroupsService.instance.saveAll(data);

        const storage = FlutterSecureStorage();
        expect(await storage.read(key: 'env_group_123'), isNotNull);
        expect(await storage.read(key: 'env_group_env_group_123'), isNull);
      },
    );

    test('migrates old JSON format with embedded values', () async {
      // Write old-format JSON with values embedded.
      final oldJson = jsonEncode([
        {
          'id': 'g1',
          'name': 'legacy',
          'values': {'OLD_KEY': 'old_value'},
        },
      ]);
      final file = File(p.join(tmpDir.path, 'env_groups.json'));
      file.writeAsStringSync(oldJson);

      // Load should migrate automatically.
      final loaded = await GlobalEnvGroupsService.instance.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].values['OLD_KEY'], 'old_value');

      // After migration, JSON should no longer contain the value.
      final updatedContent = file.readAsStringSync();
      expect(updatedContent, isNot(contains('old_value')));
      expect(updatedContent, contains('"keys"'));

      // Value should now be in secure storage.
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: 'env_group_g1');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map;
      expect(decoded['OLD_KEY'], 'old_value');
    });

    test('migrates legacy relative-path env_groups.json into configDir', () async {
      // Simulate an old build that wrote env_groups.json next to the executable.
      final legacy = File('env_groups.json');
      legacy.writeAsStringSync(
        jsonEncode([
          {
            'id': 'g1',
            'name': 'relative',
            'keys': ['TOKEN'],
          },
        ]),
      );
      FlutterSecureStorage.setMockInitialValues({
        'env_group_g1': jsonEncode({'TOKEN': 'relative_token'}),
      });

      final loaded = await GlobalEnvGroupsService.instance.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.name, 'relative');
      expect(loaded.first.values['TOKEN'], 'relative_token');

      // The file should now exist under configDir.
      expect(File(p.join(tmpDir.path, 'env_groups.json')).existsSync(), isTrue);
    });

    test('deleteGroupSecrets removes from secure storage', () async {
      final data = [
        const GlobalEnvGroup(id: 'g1', name: 'test', values: {'KEY': 'val'}),
      ];

      await GlobalEnvGroupsService.instance.saveAll(data);

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'env_group_g1'), isNotNull);

      await GlobalEnvGroupsService.instance.deleteGroupSecrets('g1');
      expect(await storage.read(key: 'env_group_g1'), isNull);
    });

    test('loadAll migrates legacy double-prefixed secure key', () async {
      final encoded = jsonEncode({'TOKEN': 'legacy_token'});
      FlutterSecureStorage.setMockInitialValues({
        'env_group_env_group_legacy': encoded,
      });

      final file = File(p.join(tmpDir.path, 'env_groups.json'));
      file.writeAsStringSync(
        jsonEncode([
          {
            'id': 'env_group_legacy',
            'name': 'legacy',
            'keys': ['TOKEN'],
          },
        ]),
      );

      final loaded = await GlobalEnvGroupsService.instance.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.values['TOKEN'], 'legacy_token');

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'env_group_legacy'), isNotNull);
      expect(await storage.read(key: 'env_group_env_group_legacy'), isNull);
    });
  });

  group('GlobalEnvGroupsService.parseEnvContent', () {
    test('parses plain key/value pairs and export-prefixed lines', () {
      final result = GlobalEnvGroupsService.instance.parseEnvContent(
        'FOO=bar\nexport BAZ=qux\n',
      );
      expect(result, {'FOO': 'bar', 'BAZ': 'qux'});
    });

    test('skips comments, blank lines, and lines without a key', () {
      final result = GlobalEnvGroupsService.instance.parseEnvContent(
        '# comment\n\n   \n=nokey\nKEY_WITHOUT_EQUALS\nVALID=1',
      );
      expect(result, {'VALID': '1'});
    });

    test('preserves empty values', () {
      expect(
        GlobalEnvGroupsService.instance.parseEnvContent('EMPTY='),
        {'EMPTY': ''},
      );
    });

    test('strips surrounding double and single quotes', () {
      final result = GlobalEnvGroupsService.instance.parseEnvContent(
        'A="double quoted"\nB=\'single quoted\'\nC=""',
      );
      expect(result, {'A': 'double quoted', 'B': 'single quoted', 'C': ''});
    });

    test('keeps # inside quoted values', () {
      expect(
        GlobalEnvGroupsService.instance.parseEnvContent('HASH="a # b"'),
        {'HASH': 'a # b'},
      );
    });

    test('strips trailing comment from unquoted values', () {
      expect(
        GlobalEnvGroupsService.instance.parseEnvContent(
          'VAL=value # trailing comment',
        ),
        {'VAL': 'value'},
      );
    });

    test(r'unescapes \n \r \t sequences in values', () {
      expect(
        GlobalEnvGroupsService.instance.parseEnvContent(
          r'MULTI=line1\nline2\ttab\rcr',
        ),
        {'MULTI': 'line1\nline2\ttab\rcr'},
      );
    });

    test('trims whitespace around key and value', () {
      expect(
        GlobalEnvGroupsService.instance.parseEnvContent(
          '  SPACED  =  some value  ',
        ),
        {'SPACED': 'some value'},
      );
    });

    test('last occurrence wins for duplicate keys', () {
      expect(
        GlobalEnvGroupsService.instance.parseEnvContent('K=first\nK=second'),
        {'K': 'second'},
      );
    });

    test('handles CRLF line endings', () {
      expect(
        GlobalEnvGroupsService.instance.parseEnvContent('A=1\r\nB=2\r\n'),
        {'A': '1', 'B': '2'},
      );
    });
  });

  group('GlobalEnvGroupsService.encodeEnvContent', () {
    Map<String, String> roundTrip(Map<String, String> values) {
      final encoded = GlobalEnvGroupsService.instance.encodeEnvContent(values);
      return GlobalEnvGroupsService.instance.parseEnvContent(encoded);
    }

    test('encodes plain key/value pairs, preserving order', () {
      final encoded = GlobalEnvGroupsService.instance.encodeEnvContent({
        'FIRST': '1',
        'SECOND': 'two words',
      });
      expect(encoded, 'FIRST=1\nSECOND=two words\n');
    });

    test('round-trips simple values through parseEnvContent', () {
      expect(
        roundTrip({'API_KEY': 'abc', 'EMPTY': '', 'URL': 'https://x.dev'}),
        {'API_KEY': 'abc', 'EMPTY': '', 'URL': 'https://x.dev'},
      );
    });

    test('quotes multiline values so they survive the round trip', () {
      const multiline = 'line1\nline2';
      expect(
        roundTrip({'CERT': multiline}),
        {'CERT': multiline},
      );
      final encoded = GlobalEnvGroupsService.instance.encodeEnvContent({
        'CERT': multiline,
      });
      expect(encoded, 'CERT="line1\\nline2"\n');
    });

    test('round-trips tabs, carriage returns and padded values', () {
      expect(
        roundTrip({
          'TABBED': 'a\tb',
          'CR': 'a\rb',
          'PADDED': '  spaced  ',
        }),
        {'TABBED': 'a\tb', 'CR': 'a\rb', 'PADDED': '  spaced  '},
      );
    });

    test('quotes values containing " #" so comments survive', () {
      expect(
        roundTrip({'HASH': 'a # b'}),
        {'HASH': 'a # b'},
      );
    });

    test('quotes values with outer quotes so they survive', () {
      expect(
        roundTrip({'QUOTED': '"double"', 'SINGLE': "'single'"}),
        {'QUOTED': '"double"', 'SINGLE': "'single'"},
      );
    });

    test('skips draft keys and blank keys', () {
      final encoded = GlobalEnvGroupsService.instance.encodeEnvContent({
        '__draft_123': '',
        '  ': 'blank key',
        'REAL': 'value',
      });
      expect(encoded, 'REAL=value\n');
    });

    test('never emits comment lines', () {
      final encoded = GlobalEnvGroupsService.instance.encodeEnvContent({
        'A': '1',
        'B': 'two # words',
        'C': '\n# looks like a comment',
      });
      for (final line in encoded.split('\n')) {
        if (line.isEmpty) continue;
        expect(line.startsWith('#'), isFalse, reason: 'line: $line');
      }
    });
  });

  group('GlobalEnvGroup.fromJson', () {
    test('parses valid JSON', () {
      final group = GlobalEnvGroup.fromJson({
        'id': 'g1',
        'name': 'test',
        'values': {'KEY': 'value'},
      });
      expect(group.id, 'g1');
      expect(group.name, 'test');
      expect(group.values, {'KEY': 'value'});
    });

    test('handles missing fields with defaults', () {
      final group = GlobalEnvGroup.fromJson({});
      expect(group.id, '');
      expect(group.name, '');
      expect(group.values, isEmpty);
    });

    test('copyWith works', () {
      const original = GlobalEnvGroup(
        id: 'g1',
        name: 'orig',
        values: {'A': '1'},
      );
      final copy = original.copyWith(name: 'updated');
      expect(copy.id, 'g1');
      expect(copy.name, 'updated');
      expect(copy.values, {'A': '1'});
    });
  });
}
