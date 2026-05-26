import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';

class GlobalEnvGroupsService {
  GlobalEnvGroupsService._();

  static final instance = GlobalEnvGroupsService._();
  static const _prefsFallbackKey = 'global_env_groups_fallback_v1';

  File get _storageFile {
    final dir = PlatformDirs.instance.configDir;
    return File(p.join(dir, 'env_groups.json'));
  }

  Future<List<GlobalEnvGroup>> loadAll() async {
    try {
      final file = _storageFile;
      if (!file.existsSync()) {
        // Migrate from SharedPreferences fallback if present
        final migrated = await _migrateFromPrefs();
        if (migrated != null) return migrated;
        return [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
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

  Future<List<GlobalEnvGroup>?> _migrateFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsFallbackKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List;
      final groups = decoded
          .map(
            (e) => GlobalEnvGroup.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      // Save to file-based storage
      await saveAll(groups);
      // Remove old fallback
      await prefs.remove(_prefsFallbackKey);
      return groups;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAll(List<GlobalEnvGroup> groups) async {
    final encoded =
        const JsonEncoder.withIndent('  ').convert(
          groups.map((e) => e.toJson()).toList(),
        );
    final file = _storageFile;
    final dir = file.parent;
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(encoded, flush: true);
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
