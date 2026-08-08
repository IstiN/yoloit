import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory configDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    configDir = Directory.systemTemp.createTempSync('theme_manager_test_');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: configDir.path));
  });

  tearDown(() {
    PlatformDirs.reset();
    if (configDir.existsSync()) configDir.deleteSync(recursive: true);
  });

  String themesDir() => p.join(
    PlatformDirs.instance.configDir,
    'themes',
  );

  group('ThemeManager custom theme loading', () {
    test('loads no custom themes when the themes dir is missing', () async {
      await ThemeManager.instance.load();

      expect(ThemeManager.instance.customThemes, isEmpty);
    });

    test('loads valid JSON themes and skips non-JSON files', () async {
      Directory(themesDir()).createSync(recursive: true);
      File(p.join(themesDir(), 'my_theme.json')).writeAsStringSync(
        '{"id":"my_theme","name":"My Theme","brightness":"light",'
        '"colors":{"primary":"#FF0000"}}',
      );
      // Notes file that must be ignored.
      File(p.join(themesDir(), 'README.txt')).writeAsStringSync('not a theme');

      await ThemeManager.instance.load();

      final themes = ThemeManager.instance.customThemes;
      expect(themes.length, 1);
      expect(themes.single.id, 'my_theme');
      expect(themes.single.name, 'My Theme');
      expect(themes.single.brightness, Brightness.light);
      expect(themes.single.scheme.primary, const Color(0xFFFF0000));
    });

    test('falls back to the file basename when id is missing and defaults '
        'brightness to dark', () async {
      Directory(themesDir()).createSync(recursive: true);
      File(p.join(themesDir(), 'fallback_name.json')).writeAsStringSync(
        '{"colors":{"primary":"#00FF00"}}',
      );

      await ThemeManager.instance.load();

      final themes = ThemeManager.instance.customThemes;
      expect(themes.length, 1);
      expect(themes.single.id, 'fallback_name');
      expect(themes.single.name, 'fallback_name');
      expect(themes.single.brightness, Brightness.dark);
    });

    test('skips malformed, empty and non-map theme files', () async {
      Directory(themesDir()).createSync(recursive: true);
      File(p.join(themesDir(), 'broken.json')).writeAsStringSync('{not json');
      File(p.join(themesDir(), 'empty.json')).writeAsStringSync('   ');
      File(p.join(themesDir(), 'list.json')).writeAsStringSync('[1,2,3]');
      File(p.join(themesDir(), 'good.json')).writeAsStringSync(
        '{"id":"good","name":"Good","colors":{}}',
      );

      await ThemeManager.instance.load();

      final themes = ThemeManager.instance.customThemes;
      expect(themes.length, 1);
      expect(themes.single.id, 'good');
    });

    test('an empty themes dir yields an empty custom theme list', () async {
      Directory(themesDir()).createSync(recursive: true);

      await ThemeManager.instance.load();

      expect(ThemeManager.instance.customThemes, isEmpty);
    });
  });
}
