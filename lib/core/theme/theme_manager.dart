import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_theme.dart';

class ThemeManager extends ChangeNotifier {
  ThemeManager._();

  static final ThemeManager instance = ThemeManager._();

  AppThemePreset _current = AppThemePreset.neonPurple;
  Brightness _brightness = Brightness.dark;

  AppThemePreset get current => _current;
  Brightness get brightness => _brightness;
  bool get isDark => _brightness == Brightness.dark;
  ThemeData get theme => _current.themeForBrightness(_brightness);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('theme_preset') ?? AppThemePreset.neonPurple.name;
    _current = AppThemePreset.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AppThemePreset.neonPurple,
    );
    final bright = prefs.getString('theme_brightness') ?? 'dark';
    _brightness = bright == 'light' ? Brightness.light : Brightness.dark;
    AppColors.setAccent(_current.color);
    notifyListeners();
  }

  Future<void> setTheme(AppThemePreset preset) async {
    _current = preset;
    AppColors.setAccent(preset.color);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preset', preset.name);
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
}
