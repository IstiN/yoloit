import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('env_groups_test_');
    PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
  });

  tearDown(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    tmpDir.deleteSync(recursive: true);
  });

  group('GlobalEnvGroupsService', () {
    test('loadAll returns empty list when file does not exist', () async {
      final groups = await GlobalEnvGroupsService.instance.loadAll();
      expect(groups, isEmpty);
    });

    test('saveAll and loadAll round-trip', () async {
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
      expect(loaded[1].id, 'g2');
      expect(loaded[1].name, 'staging');
    });

    test('saved JSON file is pretty-printed', () async {
      final data = [
        const GlobalEnvGroup(
          id: 'g1',
          name: 'test',
          values: {'A': '1'},
        ),
      ];

      await GlobalEnvGroupsService.instance.saveAll(data);

      final file = File('${tmpDir.path}/env_groups.json');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      // Pretty-printed JSON has newlines
      expect(content, contains('\n'));
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
