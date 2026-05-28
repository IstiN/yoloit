import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/icls_theme_adapter.dart';

class ThemeManager extends ChangeNotifier {
  ThemeManager._();

  static final ThemeManager instance = ThemeManager._();

  AppThemePreset _current = AppThemePreset.neonPurple;
  Brightness _brightness = Brightness.dark;

  /// Custom (user-imported) themes loaded from `~/.config/yoloit/themes/`.
  List<CustomTheme> _customThemes = [];

  /// When non-null, a custom theme is active instead of a preset.
  String? _activeCustomThemeId;

  AppThemePreset get current => _current;
  Brightness get brightness => _brightness;
  bool get isDark => _brightness == Brightness.dark;
  List<CustomTheme> get customThemes => List.unmodifiable(_customThemes);
  String? get activeCustomThemeId => _activeCustomThemeId;

  ThemeData get theme {
    if (_activeCustomThemeId != null) {
      final custom = _customThemes
          .where((t) => t.id == _activeCustomThemeId)
          .firstOrNull;
      if (custom != null) {
        return AppTheme.buildThemeFromScheme(
          custom.scheme,
          brightness: custom.brightness,
        );
      }
    }
    return _current.themeForBrightness(_brightness);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('theme_preset') ?? AppThemePreset.neonPurple.name;
    _current = AppThemePreset.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AppThemePreset.neonPurple,
    );
    final bright = prefs.getString('theme_brightness') ?? 'dark';
    _brightness = bright == 'light' ? Brightness.light : Brightness.dark;
    _activeCustomThemeId = prefs.getString('custom_theme_id');
    AppColors.setAccent(_current.color);
    await _loadCustomThemes();
    notifyListeners();
  }

  Future<void> setTheme(AppThemePreset preset) async {
    _current = preset;
    _activeCustomThemeId = null;
    if (preset.defaultBrightness != null) {
      _brightness = preset.defaultBrightness!;
    }
    AppColors.setAccent(preset.color);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preset', preset.name);
    await prefs.remove('custom_theme_id');
    if (preset.defaultBrightness != null) {
      await prefs.setString(
        'theme_brightness',
        _brightness == Brightness.light ? 'light' : 'dark',
      );
    }
  }

  /// Activates a custom (user-imported) theme by its [id].
  Future<void> setCustomTheme(String id) async {
    final custom = _customThemes.where((t) => t.id == id).firstOrNull;
    if (custom == null) return;
    _activeCustomThemeId = id;
    _brightness = custom.brightness;
    AppColors.setAccent(custom.scheme.primary);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_theme_id', id);
    await prefs.setString(
      'theme_brightness',
      _brightness == Brightness.light ? 'light' : 'dark',
    );
  }

  Future<void> setBrightness(Brightness brightness) async {
    _brightness = brightness;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_brightness',
      brightness == Brightness.light ? 'light' : 'dark',
    );
  }

  Future<void> toggleBrightness() async {
    await setBrightness(isDark ? Brightness.light : Brightness.dark);
  }

  // ── Custom theme management ──────────────────────────────────────────────────

  Directory get _themesDir =>
      Directory(p.join(PlatformDirs.instance.configDir, 'themes'));

  /// Imports a theme file (`.json` or `.icls`/`.xml`) and persists it.
  /// Returns the imported theme's id.
  Future<String> importThemeFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final ext = p.extension(filePath).toLowerCase();

    late CustomTheme custom;
    if (ext == '.icls' || ext == '.xml') {
      final result = IclsThemeAdapter.parse(content);
      custom = CustomTheme(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: result.name,
        scheme: result.scheme,
        brightness: result.scheme.background.computeLuminance() > 0.5
            ? Brightness.light
            : Brightness.dark,
      );
    } else {
      // JSON format
      final json = jsonDecode(content) as Map<String, dynamic>;
      final name = json['name'] as String? ?? p.basenameWithoutExtension(filePath);
      final brightStr = json['brightness'] as String? ?? 'dark';
      final brightness = brightStr == 'light' ? Brightness.light : Brightness.dark;
      final colorsJson = json['colors'] as Map<String, dynamic>? ?? json;
      custom = CustomTheme(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        scheme: AppColorScheme.fromJson(colorsJson, brightness: brightness),
        brightness: brightness,
      );
    }

    // Persist to disk
    await _saveCustomTheme(custom);
    _customThemes.add(custom);
    notifyListeners();
    return custom.id;
  }

  /// Deletes a custom theme by id.
  Future<void> deleteCustomTheme(String id) async {
    _customThemes.removeWhere((t) => t.id == id);
    if (_activeCustomThemeId == id) {
      _activeCustomThemeId = null;
      await setTheme(AppThemePreset.neonPurple);
    }
    final file = File(p.join(_themesDir.path, '$id.json'));
    if (await file.exists()) await file.delete();
    notifyListeners();
  }

  /// Exports a built-in preset theme as JSON string for the user.
  String exportPresetAsJson(AppThemePreset preset) {
    final scheme = AppColorScheme.fromAccent(
      preset.color,
      bgSeed: preset.bgSeed,
      brightness: preset.defaultBrightness ?? Brightness.dark,
    );
    final json = {
      'name': preset.label,
      'brightness': (preset.defaultBrightness ?? Brightness.dark) == Brightness.light
          ? 'light'
          : 'dark',
      'colors': scheme.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  Future<void> _loadCustomThemes() async {
    _customThemes = [];
    final dir = _themesDir;
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final id = json['id'] as String? ??
            p.basenameWithoutExtension(file.path);
        final name = json['name'] as String? ?? id;
        final brightStr = json['brightness'] as String? ?? 'dark';
        final brightness =
            brightStr == 'light' ? Brightness.light : Brightness.dark;
        final colorsJson = json['colors'] as Map<String, dynamic>? ?? {};
        _customThemes.add(CustomTheme(
          id: id,
          name: name,
          scheme: AppColorScheme.fromJson(colorsJson, brightness: brightness),
          brightness: brightness,
        ));
      } catch (_) {
        // Skip malformed theme files.
      }
    }
  }

  Future<void> _saveCustomTheme(CustomTheme theme) async {
    final dir = _themesDir;
    if (!dir.existsSync()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${theme.id}.json'));
    final json = {
      'id': theme.id,
      'name': theme.name,
      'brightness': theme.brightness == Brightness.light ? 'light' : 'dark',
      'colors': theme.scheme.toJson(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
  }
}

/// A user-imported custom theme stored on disk.
class CustomTheme {
  const CustomTheme({
    required this.id,
    required this.name,
    required this.scheme,
    required this.brightness,
  });

  final String id;
  final String name;
  final AppColorScheme scheme;
  final Brightness brightness;
}
