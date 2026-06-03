import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/hotkeys/hotkey_definition.dart';

const _kPrefsKey = 'hotkey_bindings_v1';

/// Manages all hotkey definitions and persists user customizations.
///
/// Extends [ChangeNotifier] so that [main_shell.dart] can rebuild the
/// [Shortcuts] widget whenever bindings change.
class HotkeyRegistry extends ChangeNotifier {
  HotkeyRegistry._() {
    // Deep-copy the global list so we own mutable instances.
    definitions = kHotkeyDefinitions
        .map((d) => HotkeyDefinition(
              id: d.id,
              description: d.description,
              category: d.category,
              defaultActivator: d.defaultActivator,
              intent: d.intent,
            ))
        .toList();
  }

  static final HotkeyRegistry instance = HotkeyRegistry._();

  late final List<HotkeyDefinition> definitions;

  /// Current shortcut map — use this in the [Shortcuts] widget.
  Map<SingleActivator, Intent> get shortcuts => {
        for (final d in definitions) d.currentActivator: d.intent,
      };

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Load previously saved bindings from SharedPreferences.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final d in definitions) {
        if (map.containsKey(d.id)) {
          d.fromJson(map[d.id] as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // Corrupted prefs — silently ignore and use defaults
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final d in definitions.where((d) => d.isOverridden))
        d.id: d.toJson(),
    };
    await prefs.setString(_kPrefsKey, jsonEncode(map));
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Update the binding for [id] to [activator] and persist.
  Future<void> setBinding(String id, SingleActivator activator) async {
    final def = _findById(id);
    if (def == null) return;
    def.currentActivator = activator;
    notifyListeners();
    await _save();
  }

  /// Reset the binding for [id] back to its default.
  Future<void> resetBinding(String id) async {
    final def = _findById(id);
    if (def == null) return;
    def.currentActivator = def.defaultActivator;
    notifyListeners();
    await _save();
  }

  /// Reset every binding to default.
  Future<void> resetAll() async {
    for (final d in definitions) {
      d.currentActivator = d.defaultActivator;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKey);
  }

  HotkeyDefinition? _findById(String id) =>
      definitions.where((d) => d.id == id).firstOrNull;
}
