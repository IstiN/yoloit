import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/runs/data/run_service.dart';

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

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('run_service_test_');
    PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
  });

  tearDown(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    tmpDir.deleteSync(recursive: true);
  });

  group('RunService.tmuxName', () {
    test('preserves alphanumeric characters', () {
      expect(RunService.tmuxName('myConfig123'), 'yoloit_run_myConfig123');
    });

    test('replaces hyphens with underscores', () {
      expect(RunService.tmuxName('my-config'), 'yoloit_run_my_config');
    });

    test('replaces dots with underscores', () {
      expect(RunService.tmuxName('my.config'), 'yoloit_run_my_config');
    });

    test('replaces multiple special chars', () {
      expect(
        RunService.tmuxName('my-config.v1_test'),
        'yoloit_run_my_config_v1_test',
      );
    });

    test('handles empty string', () {
      expect(RunService.tmuxName(''), 'yoloit_run_');
    });
  });

  group('RunService.logPath', () {
    test('returns path under runs directory', () async {
      final path = await RunService.logPath('myConfig');
      expect(path, contains('runs'));
      expect(path, endsWith('yoloit_run_myConfig.log'));
    });

    test('creates runs directory if missing', () async {
      final runsDir = Directory('${tmpDir.path}/runs');
      expect(runsDir.existsSync(), isFalse);
      await RunService.logPath('any');
      expect(runsDir.existsSync(), isTrue);
    });

    test('sanitizes config id in filename', () async {
      final path = await RunService.logPath('my-config');
      expect(path, endsWith('yoloit_run_my_config.log'));
    });
  });
}
