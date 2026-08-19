import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/runs/models/run_config.dart';

class RunConfigStorage {
  RunConfigStorage._();
  static final instance = RunConfigStorage._();

  String _key(String workspacePath) => 'run_configs_$workspacePath';

  // In-memory cache per workspace — loadForWorkspace runs on every board /
  // workspace switch and re-parsed the JSON list each time.
  final _cache = <String, List<RunConfig>>{};

  Future<List<RunConfig>> load(String workspacePath) async {
    final cached = _cache[workspacePath];
    if (cached != null) return List<RunConfig>.of(cached);
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key(workspacePath));
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    final configs = list
        .map((e) => RunConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    _cache[workspacePath] = configs;
    return List<RunConfig>.of(configs);
  }

  Future<void> save(String workspacePath, List<RunConfig> configs) async {
    _cache[workspacePath] = List<RunConfig>.of(configs);
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(_key(workspacePath), json);
  }
}
