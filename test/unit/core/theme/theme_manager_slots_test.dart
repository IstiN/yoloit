import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/theme_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('colorForSlot reads every color scheme slot and preserves fallback', () async {
    final manager = ThemeManager.instance;
    await manager.clearColorOverrides();
    final scheme = manager.baseScheme;
    final expected = <String, Color>{
      'primary': scheme.primary,
      'primaryLight': scheme.primaryLight,
      'primaryDark': scheme.primaryDark,
      'primaryGlow': scheme.primaryGlow,
      'background': scheme.background,
      'surface': scheme.surface,
      'surfaceElevated': scheme.surfaceElevated,
      'surfaceHighlight': scheme.surfaceHighlight,
      'border': scheme.border,
      'divider': scheme.divider,
      'terminalBackground': scheme.terminalBackground,
      'sidebar': scheme.sidebar,
      'sidebarGlow': scheme.sidebarGlow,
      'terminalPrompt': scheme.terminalPrompt,
      'tabBorder': scheme.tabBorder,
      'tabActiveBg': scheme.tabActiveBg,
      'tabInactiveBg': scheme.tabInactiveBg,
      'textPrimary': scheme.textPrimary,
      'textSecondary': scheme.textSecondary,
      'textMuted': scheme.textMuted,
      'textHighlight': scheme.textHighlight,
      'terminalText': scheme.terminalText,
      'accentGreen': scheme.accentGreen,
      'accentGreenDim': scheme.accentGreenDim,
      'accentGreenGlow': scheme.accentGreenGlow,
      'accentRed': scheme.accentRed,
      'accentRedDim': scheme.accentRedDim,
      'accentBlue': scheme.accentBlue,
      'accentOrange': scheme.accentOrange,
      'diffAddBg': scheme.diffAddBg,
      'diffAddText': scheme.diffAddText,
      'diffRemoveBg': scheme.diffRemoveBg,
      'diffRemoveText': scheme.diffRemoveText,
      'diffContextBg': scheme.diffContextBg,
      'statusActive': scheme.statusActive,
      'statusIdle': scheme.statusIdle,
      'statusError': scheme.statusError,
      'statusWarning': scheme.statusWarning,
      'orbCyan': scheme.orbCyan,
      'orbPurple': scheme.orbPurple,
      'orbPink': scheme.orbPink,
    };

    for (final entry in expected.entries) {
      expect(manager.colorForSlot(entry.key), entry.value, reason: entry.key);
    }
    expect(manager.colorForSlot('unknown'), scheme.primary);
    expect(manager.colorForSlot(''), scheme.primary);
  });
}
