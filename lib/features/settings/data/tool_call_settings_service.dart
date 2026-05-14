import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ToolCallSettingsService {
  ToolCallSettingsService._();
  static final instance = ToolCallSettingsService._();

  static const _ignoredToolsKey = 'chat.ignoredToolCalls';
  static const _defaultIgnored = <String>{'report_intent'};

  final ValueNotifier<Set<String>> _ignoredTools = ValueNotifier({
    ..._defaultIgnored,
  });
  bool _loaded = false;

  ValueListenable<Set<String>> get ignoredToolsListenable => _ignoredTools;

  Set<String> get ignoredTools => {..._ignoredTools.value};

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_ignoredToolsKey);
    if (saved != null) {
      _ignoredTools.value =
          saved.map(_normalize).where((s) => s.isNotEmpty).toSet();
    } else {
      _ignoredTools.value = {..._defaultIgnored};
    }
    _loaded = true;
  }

  Future<void> setIgnoredTools(Set<String> tools) async {
    final normalized = tools.map(_normalize).where((s) => s.isNotEmpty).toSet();
    _ignoredTools.value = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ignoredToolsKey, normalized.toList()..sort());
  }

  bool isIgnored(String toolName) =>
      _ignoredTools.value.contains(_normalize(toolName));

  static String _normalize(String value) => value.trim().toLowerCase();
}
