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

    test('values are stored in scoped file', () async {
      final data = [
        const GlobalEnvGroup(
          id: 'g1',
          name: 'test',
          values: {'TOKEN': 'my_token'},
        ),
      ];

      await GlobalEnvGroupsService.instance.saveAll(data);

      final file = File(p.join(tmpDir.path, 'env_groups_values', 'g1.json'));
      expect(file.existsSync(), isTrue);
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map;
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

        final file = File(p.join(tmpDir.path, 'env_groups_values', 'g1.json'));
        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw) as Map;
        expect(decoded['TOKEN'], 'my_token');
        expect(decoded['EMPTY'], '');
      },
    );

    test(
      'prefixed group ids do not produce double-prefixed file names',
      () async {
        final data = [
          const GlobalEnvGroup(
            id: 'env_group_123',
            name: 'test',
            values: {'TOKEN': 'my_token'},
          ),
        ];

        await GlobalEnvGroupsService.instance.saveAll(data);

        final file = File(p.join(tmpDir.path, 'env_groups_values', '123.json'));
        expect(file.existsSync(), isTrue);
        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw) as Map;
        expect(decoded['TOKEN'], 'my_token');
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

      // Value should now be in the scoped values file.
      final valuesFile = File(
        p.join(tmpDir.path, 'env_groups_values', 'g1.json'),
      );
      expect(valuesFile.existsSync(), isTrue);
      final raw = valuesFile.readAsStringSync();
      final decoded = jsonDecode(raw) as Map;
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

    test('deleteGroupSecrets removes values file', () async {
      final data = [
        const GlobalEnvGroup(id: 'g1', name: 'test', values: {'KEY': 'val'}),
      ];

      await GlobalEnvGroupsService.instance.saveAll(data);

      final file = File(p.join(tmpDir.path, 'env_groups_values', 'g1.json'));
      expect(file.existsSync(), isTrue);

      await GlobalEnvGroupsService.instance.deleteGroupSecrets('g1');
      expect(file.existsSync(), isFalse);
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

      // Values should now live in the scoped values file.
      final valuesFile = File(
        p.join(tmpDir.path, 'env_groups_values', 'legacy.json'),
      );
      expect(valuesFile.existsSync(), isTrue);
      final raw = valuesFile.readAsStringSync();
      final decoded = jsonDecode(raw) as Map;
      expect(decoded['TOKEN'], 'legacy_token');
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
