import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class GlobalEnvGroupsService {
  GlobalEnvGroupsService._();

  static final instance = GlobalEnvGroupsService._();
  static const _storageKey = 'global_env_groups_v1';
  static const _prefsFallbackKey = 'global_env_groups_fallback_v1';

  static FlutterSecureStorage _buildStorage() {
    if (Platform.isMacOS) {
      return const FlutterSecureStorage(mOptions: MacOsOptions());
    } else if (Platform.isWindows) {
      return const FlutterSecureStorage(
        wOptions: WindowsOptions(useBackwardCompatibility: false),
      );
    } else {
      return const FlutterSecureStorage(lOptions: LinuxOptions());
    }
  }

  final _storage = _buildStorage();

  Future<List<GlobalEnvGroup>> loadAll() async {
    String? raw;
    try {
      raw = await _storage.read(key: _storageKey);
    } on Exception {
      raw = null;
    }
    if (raw == null || raw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_prefsFallbackKey);
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (e) => GlobalEnvGroup.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<GlobalEnvStorageBackend> saveAll(List<GlobalEnvGroup> groups) async {
    final encoded = jsonEncode(groups.map((e) => e.toJson()).toList());
    try {
      await _storage.write(key: _storageKey, value: encoded);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsFallbackKey);
      return GlobalEnvStorageBackend.secureStorage;
    } on Exception {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsFallbackKey, encoded);
      return GlobalEnvStorageBackend.localPreferences;
    }
  }

  Future<Map<String, String>> resolveSelectedGroups(
    List<String> selectedGroupIds,
  ) async {
    final all = await loadAll();
    final byId = {for (final group in all) group.id: group};
    final merged = <String, String>{};
    for (final id in selectedGroupIds) {
      final group = byId[id];
      if (group == null) continue;
      merged.addAll(group.values);
    }
    return merged;
  }

  Future<List<String>> resolveSelectedGroupNames(
    List<String> selectedGroupIds,
  ) async {
    final all = await loadAll();
    final byId = {for (final group in all) group.id: group};
    return selectedGroupIds
        .map((id) => byId[id]?.name)
        .whereType<String>()
        .toList();
  }

  Future<GlobalEnvGroup> importEnvFileAsGroup(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final name = p.basenameWithoutExtension(filePath).replaceAll('.env', '');
    return GlobalEnvGroup(
      id: 'env_group_${DateTime.now().millisecondsSinceEpoch}',
      name: name.isEmpty ? 'Imported Group' : name,
      values: parseEnvContent(content),
    );
  }

  Map<String, String> parseEnvContent(String content) {
    final result = <String, String>{};
    final lines = content.split(RegExp(r'\r?\n'));
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) {
        line = line.substring(7).trim();
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      if (key.isEmpty) continue;
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      } else {
        final commentIndex = value.indexOf(' #');
        if (commentIndex >= 0) {
          value = value.substring(0, commentIndex).trimRight();
        }
      }
      value = value
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\t', '\t');
      result[key] = value;
    }
    return result;
  }
}

enum GlobalEnvStorageBackend { secureStorage, localPreferences }

class GlobalEnvGroup {
  const GlobalEnvGroup({
    required this.id,
    required this.name,
    required this.values,
  });

  final String id;
  final String name;
  final Map<String, String> values;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'values': values};

  factory GlobalEnvGroup.fromJson(Map<String, dynamic> json) {
    return GlobalEnvGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      values: (json['values'] as Map? ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  }

  GlobalEnvGroup copyWith({
    String? id,
    String? name,
    Map<String, String>? values,
  }) {
    return GlobalEnvGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      values: values ?? this.values,
    );
  }
}
