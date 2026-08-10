import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HotkeyRegistry.load', () {
    test('keeps defaults when nothing was persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final registry = HotkeyRegistry.instance;

      await registry.load();

      final closeTab =
          registry.definitions.singleWhere((d) => d.id == 'close_tab');
      expect(closeTab.isOverridden, isFalse);
      expect(
        closeTab.currentActivator.trigger,
        equals(LogicalKeyboardKey.keyW),
      );
    });

    test('restores persisted overrides onto matching definitions', () async {
      SharedPreferences.setMockInitialValues({
        'hotkey_bindings_v1': jsonEncode({
          'close_tab': {
            'keyId': LogicalKeyboardKey.keyQ.keyId,
            'meta': true,
            'shift': true,
            'alt': false,
            'control': false,
          },
        }),
      });
      final registry = HotkeyRegistry.instance;

      await registry.load();

      final closeTab =
          registry.definitions.singleWhere((d) => d.id == 'close_tab');
      expect(closeTab.currentActivator.trigger, LogicalKeyboardKey.keyQ);
      expect(closeTab.currentActivator.meta, isTrue);
      expect(closeTab.currentActivator.shift, isTrue);
      expect(closeTab.isOverridden, isTrue);

      // Untouched definitions stay at their defaults.
      final prevTab =
          registry.definitions.singleWhere((d) => d.id == 'prev_tab');
      expect(prevTab.isOverridden, isFalse);

      // Clean up the singleton override for other tests in this isolate.
      await registry.resetAll();
    });

    test('ignores corrupted persisted JSON and keeps defaults', () async {
      SharedPreferences.setMockInitialValues({
        'hotkey_bindings_v1': '{not valid json',
      });
      final registry = HotkeyRegistry.instance;

      await registry.load();

      expect(registry.definitions.every((d) => !d.isOverridden), isTrue);
    });

    test('ignores persisted entries for unknown or malformed bindings',
        () async {
      SharedPreferences.setMockInitialValues({
        'hotkey_bindings_v1': jsonEncode({
          'no_such_hotkey': {'keyId': LogicalKeyboardKey.keyA.keyId},
          'focus_terminal': {'keyId': null},
        }),
      });
      final registry = HotkeyRegistry.instance;

      await registry.load();

      final focusTerminal =
          registry.definitions.singleWhere((d) => d.id == 'focus_terminal');
      expect(focusTerminal.isOverridden, isFalse);
      expect(registry.definitions.any((d) => d.id == 'no_such_hotkey'),
          isFalse);
    });
  });
}
