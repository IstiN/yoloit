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

  /// Per-slot accent overrides (persisted to SharedPreferences).
  Map<String, Color> _accentOverrides = {};

  AppThemePreset get current => _current;
  Brightness get brightness => _brightness;
  bool get isDark => _brightness == Brightness.dark;
  List<CustomTheme> get customThemes => List.unmodifiable(_customThemes);
  String? get activeCustomThemeId => _activeCustomThemeId;
  Map<String, Color> get accentOverrides => Map.unmodifiable(_accentOverrides);

  ThemeData get theme {
    AppColorScheme scheme;
    Brightness bright;
    if (_activeCustomThemeId != null) {
      final custom = _customThemes
          .where((t) => t.id == _activeCustomThemeId)
          .firstOrNull;
      if (custom != null) {
        scheme = custom.scheme;
        bright = custom.brightness;
      } else {
        scheme = AppColorScheme.fromAccent(
          _current.color,
          bgSeed: _current.bgSeed,
          brightness: _current.defaultBrightness ?? _brightness,
        );
        bright = _current.defaultBrightness ?? _brightness;
      }
    } else {
      scheme = AppColorScheme.fromAccent(
        _current.color,
        bgSeed: _current.bgSeed,
        brightness: _current.defaultBrightness ?? _brightness,
      );
      bright = _current.defaultBrightness ?? _brightness;
    }
    if (_accentOverrides.isNotEmpty) {
      scheme = scheme.copyWith(
        accentGreen: _accentOverrides['accentGreen'],
        accentGreenDim: _accentOverrides['accentGreenDim'],
        accentGreenGlow: _accentOverrides['accentGreenGlow'],
        accentRed: _accentOverrides['accentRed'],
        accentRedDim: _accentOverrides['accentRedDim'],
        accentBlue: _accentOverrides['accentBlue'],
        accentOrange: _accentOverrides['accentOrange'],
      );
    }
    return AppTheme.buildThemeFromScheme(scheme, brightness: bright);
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
    _loadAccentOverrides(prefs);
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

  // ── Accent color overrides ──────────────────────────────────────────────────

  static const _accentSlots = [
    'accentGreen',
    'accentRed',
    'accentBlue',
    'accentOrange',
  ];

  /// Human-readable labels for accent override slots.
  static const accentSlotLabels = {
    'accentGreen': 'Green',
    'accentRed': 'Red',
    'accentBlue': 'Blue',
    'accentOrange': 'Orange',
  };

  /// Sets an accent color override for a specific slot.
  Future<void> setAccentOverride(String slot, Color color) async {
    _accentOverrides[slot] = color;
    // Also compute dim/glow variants for green and red
    if (slot == 'accentGreen') {
      _accentOverrides['accentGreenDim'] =
          Color.lerp(color, Colors.black, 0.2)!;
      _accentOverrides['accentGreenGlow'] = color.withAlpha(0x22);
    } else if (slot == 'accentRed') {
      _accentOverrides['accentRedDim'] =
          Color.lerp(color, Colors.black, 0.2)!;
    }
    notifyListeners();
    await _saveAccentOverrides();
  }

  /// Removes an accent color override, reverting to the theme default.
  Future<void> removeAccentOverride(String slot) async {
    _accentOverrides.remove(slot);
    if (slot == 'accentGreen') {
      _accentOverrides.remove('accentGreenDim');
      _accentOverrides.remove('accentGreenGlow');
    } else if (slot == 'accentRed') {
      _accentOverrides.remove('accentRedDim');
    }
    notifyListeners();
    await _saveAccentOverrides();
  }

  /// Clears all accent overrides.
  Future<void> clearAccentOverrides() async {
    _accentOverrides.clear();
    notifyListeners();
    await _saveAccentOverrides();
  }

  void _loadAccentOverrides(SharedPreferences prefs) {
    _accentOverrides = {};
    final json = prefs.getString('accent_overrides');
    if (json == null) return;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final hex = entry.value as String;
        final h = hex.replaceFirst('#', '');
        if (h.length == 6) {
          _accentOverrides[entry.key] =
              Color(int.parse('FF$h', radix: 16));
        } else if (h.length == 8) {
          _accentOverrides[entry.key] = Color(int.parse(h, radix: 16));
        }
      }
    } catch (_) {
      // Ignore malformed data.
    }
  }

  Future<void> _saveAccentOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accentOverrides.isEmpty) {
      await prefs.remove('accent_overrides');
      return;
    }
    final map = <String, String>{};
    for (final entry in _accentOverrides.entries) {
      map[entry.key] = entry.value.value.toRadixString(16).padLeft(8, '0');
    }
    await prefs.setString('accent_overrides', jsonEncode(map));
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
