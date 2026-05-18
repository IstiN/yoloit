import 'package:shared_preferences/shared_preferences.dart';

/// Global permission toggles for JS API methods available in widget/app panels.
class WidgetPermissionsService {
  WidgetPermissionsService._();
  static final instance = WidgetPermissionsService._();

  static const _prefix = 'widget_perm_v1_';

  static const permissions = [
    WidgetPermission(
      key: 'exec',
      label: 'CLI Execution',
      description: 'yoloit.exec() — run yoloit CLI commands from widgets',
    ),
    WidgetPermission(
      key: 'fetch',
      label: 'HTTP Fetch',
      description: 'yoloit.fetchJson() — make HTTP requests from widgets',
    ),
    WidgetPermission(
      key: 'secrets',
      label: 'Secrets Storage',
      description: 'yoloit.secrets — read/write encrypted key-value secrets',
    ),
    WidgetPermission(
      key: 'storage',
      label: 'Local Storage',
      description: 'yoloit.storage — read/write persistent panel storage',
    ),
  ];

  final _values = <String, bool>{};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    for (final p in permissions) {
      _values[p.key] = prefs.getBool('$_prefix${p.key}') ?? true;
    }
    _loaded = true;
  }

  bool isAllowed(String key) => _values[key] ?? true;

  Future<void> setAllowed(String key, bool allowed) async {
    _values[key] = allowed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', allowed);
  }
}

class WidgetPermission {
  const WidgetPermission({
    required this.key,
    required this.label,
    required this.description,
  });

  final String key;
  final String label;
  final String description;
}
