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

  /// Per-slot color overrides (persisted to SharedPreferences).
  /// Any key matching an [AppColorScheme] field name can be overridden.
  Map<String, Color> _colorOverrides = {};

  AppThemePreset get current => _current;
  Brightness get brightness => _brightness;
  bool get isDark => _brightness == Brightness.dark;
  List<CustomTheme> get customThemes => List.unmodifiable(_customThemes);
  String? get activeCustomThemeId => _activeCustomThemeId;
  Map<String, Color> get colorOverrides => Map.unmodifiable(_colorOverrides);
  bool get hasOverrides => _colorOverrides.isNotEmpty;

  /// Returns the base scheme (before overrides) for previewing defaults.
  AppColorScheme get baseScheme {
    if (_activeCustomThemeId != null) {
      final custom = _customThemes
          .where((t) => t.id == _activeCustomThemeId)
          .firstOrNull;
      if (custom != null) return custom.scheme;
    }
    return AppColorScheme.fromAccent(
      _current.color,
      bgSeed: _current.bgSeed,
      brightness: _current.defaultBrightness ?? _brightness,
    );
  }

  ThemeData get theme {
    var scheme = baseScheme;
    final bright = _activeCustomThemeId != null
        ? (_customThemes
                .where((t) => t.id == _activeCustomThemeId)
                .firstOrNull
                ?.brightness ??
            _current.defaultBrightness ??
            _brightness)
        : (_current.defaultBrightness ?? _brightness);
    if (_colorOverrides.isNotEmpty) {
      scheme = _applyOverrides(scheme);
    }
    return AppTheme.buildThemeFromScheme(scheme, brightness: bright);
  }

  AppColorScheme _applyOverrides(AppColorScheme scheme) {
    return scheme.copyWith(
      primary: _colorOverrides['primary'],
      primaryLight: _colorOverrides['primaryLight'],
      primaryDark: _colorOverrides['primaryDark'],
      primaryGlow: _colorOverrides['primaryGlow'],
      background: _colorOverrides['background'],
      surface: _colorOverrides['surface'],
      surfaceElevated: _colorOverrides['surfaceElevated'],
      surfaceHighlight: _colorOverrides['surfaceHighlight'],
      border: _colorOverrides['border'],
      divider: _colorOverrides['divider'],
      terminalBackground: _colorOverrides['terminalBackground'],
      sidebar: _colorOverrides['sidebar'],
      sidebarGlow: _colorOverrides['sidebarGlow'],
      terminalPrompt: _colorOverrides['terminalPrompt'],
      tabBorder: _colorOverrides['tabBorder'],
      tabActiveBg: _colorOverrides['tabActiveBg'],
      tabInactiveBg: _colorOverrides['tabInactiveBg'],
      textPrimary: _colorOverrides['textPrimary'],
      textSecondary: _colorOverrides['textSecondary'],
      textMuted: _colorOverrides['textMuted'],
      textHighlight: _colorOverrides['textHighlight'],
      terminalText: _colorOverrides['terminalText'],
      accentGreen: _colorOverrides['accentGreen'],
      accentGreenDim: _colorOverrides['accentGreenDim'],
      accentGreenGlow: _colorOverrides['accentGreenGlow'],
      accentRed: _colorOverrides['accentRed'],
      accentRedDim: _colorOverrides['accentRedDim'],
      accentBlue: _colorOverrides['accentBlue'],
      accentOrange: _colorOverrides['accentOrange'],
      diffAddBg: _colorOverrides['diffAddBg'],
      diffAddText: _colorOverrides['diffAddText'],
      diffRemoveBg: _colorOverrides['diffRemoveBg'],
      diffRemoveText: _colorOverrides['diffRemoveText'],
      diffContextBg: _colorOverrides['diffContextBg'],
      statusActive: _colorOverrides['statusActive'],
      statusIdle: _colorOverrides['statusIdle'],
      statusError: _colorOverrides['statusError'],
      statusWarning: _colorOverrides['statusWarning'],
      orbCyan: _colorOverrides['orbCyan'],
      orbPurple: _colorOverrides['orbPurple'],
      orbPink: _colorOverrides['orbPink'],
    );
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
    _loadColorOverrides(prefs);
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

  /// Whether the active preset has a fixed brightness (e.g. Islands Light).
  bool get hasFixedBrightness {
    if (_activeCustomThemeId != null) return false;
    return _current.defaultBrightness != null;
  }

  // ── Color overrides ─────────────────────────────────────────────────────────

  /// Color slot categories for the settings UI.
  static const colorCategories = <String, List<({String key, String label})>>{
    'Accent': [
      (key: 'primary', label: 'Primary'),
      (key: 'accentGreen', label: 'Green'),
      (key: 'accentRed', label: 'Red'),
      (key: 'accentBlue', label: 'Blue'),
      (key: 'accentOrange', label: 'Orange'),
    ],
    'Text': [
      (key: 'textPrimary', label: 'Primary'),
      (key: 'textSecondary', label: 'Secondary'),
      (key: 'textMuted', label: 'Muted'),
      (key: 'textHighlight', label: 'Highlight'),
      (key: 'terminalText', label: 'Terminal'),
    ],
    'Background': [
      (key: 'background', label: 'Base'),
      (key: 'surface', label: 'Surface'),
      (key: 'surfaceElevated', label: 'Elevated'),
      (key: 'border', label: 'Border'),
      (key: 'terminalBackground', label: 'Terminal'),
    ],
    'Status': [
      (key: 'statusActive', label: 'Active'),
      (key: 'statusIdle', label: 'Idle'),
      (key: 'statusError', label: 'Error'),
      (key: 'statusWarning', label: 'Warning'),
    ],
    'Diff': [
      (key: 'diffAddBg', label: 'Add Bg'),
      (key: 'diffAddText', label: 'Add Text'),
      (key: 'diffRemoveBg', label: 'Remove Bg'),
      (key: 'diffRemoveText', label: 'Remove Text'),
    ],
  };

  /// Auto-derived companion slots (dim/glow variants).
  static const _derivedSlots = {
    'accentGreen': ['accentGreenDim', 'accentGreenGlow'],
    'accentRed': ['accentRedDim'],
  };

  /// Sets a color override for any slot. Auto-derives companion variants.
  Future<void> setColorOverride(String slot, Color color) async {
    _colorOverrides[slot] = color;
    final derived = _derivedSlots[slot];
    if (derived != null) {
      for (final d in derived) {
        if (d.endsWith('Dim')) {
          _colorOverrides[d] = Color.lerp(color, Colors.black, 0.2)!;
        } else if (d.endsWith('Glow')) {
          _colorOverrides[d] = color.withAlpha(0x22);
        }
      }
    }
    notifyListeners();
    await _saveColorOverrides();
  }

  /// Removes a color override, reverting to the theme default.
  Future<void> removeColorOverride(String slot) async {
    _colorOverrides.remove(slot);
    final derived = _derivedSlots[slot];
    if (derived != null) {
      for (final d in derived) {
        _colorOverrides.remove(d);
      }
    }
    notifyListeners();
    await _saveColorOverrides();
  }

  /// Clears all color overrides, reverting to the base preset/custom theme.
  Future<void> clearColorOverrides() async {
    _colorOverrides.clear();
    notifyListeners();
    await _saveColorOverrides();
  }

  /// Returns the current effective color for a slot (override or base).
  Color colorForSlot(String slot) {
    final override = _colorOverrides[slot];
    if (override != null) return override;
    return _slotFromScheme(baseScheme, slot);
  }

  static Color _slotFromScheme(AppColorScheme s, String slot) {
    return switch (slot) {
      'primary' => s.primary,
      'primaryLight' => s.primaryLight,
      'primaryDark' => s.primaryDark,
      'primaryGlow' => s.primaryGlow,
      'background' => s.background,
      'surface' => s.surface,
      'surfaceElevated' => s.surfaceElevated,
      'surfaceHighlight' => s.surfaceHighlight,
      'border' => s.border,
      'divider' => s.divider,
      'terminalBackground' => s.terminalBackground,
      'sidebar' => s.sidebar,
      'sidebarGlow' => s.sidebarGlow,
      'terminalPrompt' => s.terminalPrompt,
      'tabBorder' => s.tabBorder,
      'tabActiveBg' => s.tabActiveBg,
      'tabInactiveBg' => s.tabInactiveBg,
      'textPrimary' => s.textPrimary,
      'textSecondary' => s.textSecondary,
      'textMuted' => s.textMuted,
      'textHighlight' => s.textHighlight,
      'terminalText' => s.terminalText,
      'accentGreen' => s.accentGreen,
      'accentGreenDim' => s.accentGreenDim,
      'accentGreenGlow' => s.accentGreenGlow,
      'accentRed' => s.accentRed,
      'accentRedDim' => s.accentRedDim,
      'accentBlue' => s.accentBlue,
      'accentOrange' => s.accentOrange,
      'diffAddBg' => s.diffAddBg,
      'diffAddText' => s.diffAddText,
      'diffRemoveBg' => s.diffRemoveBg,
      'diffRemoveText' => s.diffRemoveText,
      'diffContextBg' => s.diffContextBg,
      'statusActive' => s.statusActive,
      'statusIdle' => s.statusIdle,
      'statusError' => s.statusError,
      'statusWarning' => s.statusWarning,
      'orbCyan' => s.orbCyan,
      'orbPurple' => s.orbPurple,
      'orbPink' => s.orbPink,
      _ => s.primary,
    };
  }

  void _loadColorOverrides(SharedPreferences prefs) {
    _colorOverrides = {};
    // Migrate old key
    var json = prefs.getString('color_overrides') ??
        prefs.getString('accent_overrides');
    if (json == null) return;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final hex = entry.value as String;
        final h = hex.replaceFirst('#', '');
        if (h.length == 6) {
          _colorOverrides[entry.key] =
              Color(int.parse('FF$h', radix: 16));
        } else if (h.length == 8) {
          _colorOverrides[entry.key] = Color(int.parse(h, radix: 16));
        }
      }
    } catch (_) {
      // Ignore malformed data.
    }
  }

  Future<void> _saveColorOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    if (_colorOverrides.isEmpty) {
      await prefs.remove('color_overrides');
      await prefs.remove('accent_overrides');
      return;
    }
    final map = <String, String>{};
    for (final entry in _colorOverrides.entries) {
      map[entry.key] = entry.value.value.toRadixString(16).padLeft(8, '0');
    }
    await prefs.setString('color_overrides', jsonEncode(map));
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

  /// Returns the current effective scheme (base + overrides applied).
  AppColorScheme get effectiveScheme {
    var scheme = baseScheme;
    if (_colorOverrides.isNotEmpty) {
      scheme = _applyOverrides(scheme);
    }
    return scheme;
  }

  /// Returns the effective brightness for the current theme.
  Brightness get effectiveBrightness {
    if (_activeCustomThemeId != null) {
      return _customThemes
              .where((t) => t.id == _activeCustomThemeId)
              .firstOrNull
              ?.brightness ??
          _brightness;
    }
    return _current.defaultBrightness ?? _brightness;
  }

  /// Saves the current theme (with any overrides) as a new custom preset.
  /// Returns the new custom theme's id.
  Future<String> saveCurrentAsPreset(String name) async {
    final custom = CustomTheme(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      scheme: effectiveScheme,
      brightness: effectiveBrightness,
    );
    await _saveCustomTheme(custom);
    _customThemes.add(custom);
    _activeCustomThemeId = custom.id;
    _colorOverrides.clear();
    notifyListeners();
    await _saveColorOverrides();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_theme_id', custom.id);
    return custom.id;
  }

  /// Exports the current theme (with overrides) as a JSON string.
  String exportCurrentAsJson() {
    final json = {
      'name': _activeCustomThemeId != null
          ? (_customThemes
                  .where((t) => t.id == _activeCustomThemeId)
                  .firstOrNull
                  ?.name ??
              'Custom')
          : _current.label,
      'brightness': effectiveBrightness == Brightness.light ? 'light' : 'dark',
      'colors': effectiveScheme.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(json);
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
