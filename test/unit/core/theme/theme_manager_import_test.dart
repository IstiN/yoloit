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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configDir = Directory.systemTemp.createTempSync('theme_manager_import_');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: configDir.path));
    // Reset the singleton to a clean, empty state before each test.
    await ThemeManager.instance.load();
  });

  tearDown(() {
    PlatformDirs.reset();
    if (configDir.existsSync()) configDir.deleteSync(recursive: true);
  });

  String writeSource(String name, String content) {
    final file = File(p.join(configDir.path, name));
    file.writeAsStringSync(content);
    return file.path;
  }

  group('ThemeManager.importThemeFile', () {
    test('imports a JSON theme and persists it to the themes dir', () async {
      final path = writeSource(
        'imported.json',
        '{"name":"Imported","brightness":"light",'
        '"colors":{"primary":"#112233"}}',
      );

      final id = await ThemeManager.instance.importThemeFile(path);

      expect(id, startsWith('custom_'));
      final themes = ThemeManager.instance.customThemes;
      expect(themes.length, 1);
      expect(themes.single.id, id);
      expect(themes.single.name, 'Imported');
      expect(themes.single.brightness, Brightness.light);
      expect(themes.single.scheme.primary, const Color(0xFF112233));

      final persisted = File(
        p.join(PlatformDirs.instance.configDir, 'themes', '$id.json'),
      );
      expect(persisted.existsSync(), isTrue);
      expect(persisted.readAsStringSync(), contains('"name": "Imported"'));
    });

    test('defaults name to the file basename and brightness to dark', () async {
      final path = writeSource('bare_theme.json', '{"colors":{}}');

      await ThemeManager.instance.importThemeFile(path);

      final theme = ThemeManager.instance.customThemes.single;
      expect(theme.name, 'bare_theme');
      expect(theme.brightness, Brightness.dark);
    });

    test('imports an ICLS theme with brightness from the background', () async {
      const icls = '''
<scheme name="YoLo Test" parent_scheme="Darcula">
  <colors>
    <option name="CONSOLE_BACKGROUND_KEY" value="2b2b2b"/>
  </colors>
  <attributes>
    <option name="TEXT">
      <value>
        <option name="FOREGROUND" value="bbbbbb"/>
        <option name="BACKGROUND" value="2b2b2b"/>
      </value>
    </option>
  </attributes>
</scheme>
''';
      final path = writeSource('scheme.icls', icls);

      await ThemeManager.instance.importThemeFile(path);

      final theme = ThemeManager.instance.customThemes.single;
      expect(theme.name, 'YoLo Test');
      expect(theme.brightness, Brightness.dark);
      expect(theme.scheme.background, const Color(0xFF2B2B2B));
    });

    test('treats .xml files as ICLS and detects light brightness', () async {
      const xml = '''
<scheme name="Light Xml" parent_scheme="Default">
  <colors>
    <option name="CONSOLE_BACKGROUND_KEY" value="ffffff"/>
  </colors>
</scheme>
''';
      final path = writeSource('scheme.xml', xml);

      await ThemeManager.instance.importThemeFile(path);

      final theme = ThemeManager.instance.customThemes.single;
      expect(theme.name, 'Light Xml');
      expect(theme.brightness, Brightness.light);
    });

    test('throws StateError for a missing file', () {
      expect(
        () => ThemeManager.instance.importThemeFile(
          p.join(configDir.path, 'does_not_exist.json'),
        ),
        throwsStateError,
      );
    });

    test('throws StateError for an empty file', () {
      final path = writeSource('empty.json', '');
      expect(
        () => ThemeManager.instance.importThemeFile(path),
        throwsStateError,
      );
    });
  });

  group('ThemeManager color override loading', () {
    test('parses 6- and 8-digit hex overrides and skips bad entries', () async {
      SharedPreferences.setMockInitialValues({
        'color_overrides':
            '{"primary":"ff112233","accentGreen":"#22ff44","border":"12345"}',
      });

      await ThemeManager.instance.load();

      final overrides = ThemeManager.instance.colorOverrides;
      expect(overrides['primary'], const Color(0xFF112233));
      expect(overrides['accentGreen'], const Color(0xFF22FF44));
      expect(overrides.containsKey('border'), isFalse);
      expect(ThemeManager.instance.hasOverrides, isTrue);
    });

    test('falls back to the legacy accent_overrides key', () async {
      SharedPreferences.setMockInitialValues({
        'accent_overrides': '{"primary":"#aabbcc"}',
      });

      await ThemeManager.instance.load();

      expect(
        ThemeManager.instance.colorOverrides['primary'],
        const Color(0xFFAABBCC),
      );
    });

    test('ignores malformed override payloads', () async {
      SharedPreferences.setMockInitialValues({'color_overrides': '{not json'});

      await ThemeManager.instance.load();

      expect(ThemeManager.instance.colorOverrides, isEmpty);
      expect(ThemeManager.instance.hasOverrides, isFalse);
    });
  });
}
