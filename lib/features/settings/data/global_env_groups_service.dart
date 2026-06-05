import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/secure_storage_factory.dart';

/// Manages global env variable groups.
///
/// **Security model:**
/// - Group metadata (id, name, list of variable keys) is stored in a JSON
///   file at `~/.config/yoloit/env_groups.json`.
/// - Secret **values** are stored in the platform's secure credential store
///   (macOS Keychain / Windows DPAPI / Linux libsecret) via
///   [FlutterSecureStorage], keyed by `env_group_<id>`.
/// - On first load after upgrade, values embedded in the old JSON format are
///   automatically migrated into secure storage and removed from the file.
class GlobalEnvGroupsService {
  GlobalEnvGroupsService._();

  static final instance = GlobalEnvGroupsService._();
  static const _prefsFallbackKey = 'global_env_groups_fallback_v1';
  static const _secureKeyPrefix = 'env_group_';

  String _canonicalGroupId(String groupId) {
    if (groupId.startsWith(_secureKeyPrefix)) {
      return groupId.substring(_secureKeyPrefix.length);
    }
    return groupId;
  }

  String _secureStorageKey(String groupId) {
    return '$_secureKeyPrefix${_canonicalGroupId(groupId)}';
  }

  String? _legacySecureStorageKey(String groupId) {
    if (!groupId.startsWith(_secureKeyPrefix)) return null;
    return '$_secureKeyPrefix$groupId';
  }

  final _storage = SecureStorageFactory.create();
  List<GlobalEnvGroup>? _loadAllCache;
  Future<List<GlobalEnvGroup>>? _loadAllInFlight;
  String? _loadAllCacheSignature;

  File get _storageFile {
    final dir = PlatformDirs.instance.configDir;
    return File(p.join(dir, 'env_groups.json'));
  }

  /// Loads all env groups.  Values come from secure storage; only metadata
  /// (id, name, keys) lives in the JSON file.
  Future<List<GlobalEnvGroup>> loadAll() async {
    final signature = _storageFileSignature();
    final cached = _loadAllCache;
    if (cached != null && _loadAllCacheSignature == signature) return cached;
    return _loadAllInFlight ??= _loadAllUncached().then(
      (groups) {
        _loadAllCacheSignature = _storageFileSignature();
        _loadAllCache = groups;
        _loadAllInFlight = null;
        return groups;
      },
      onError: (Object error, StackTrace stackTrace) {
        _loadAllInFlight = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<List<GlobalEnvGroup>> _loadAllUncached() async {
    try {
      List<_GroupMeta> metas;
      final file = _storageFile;
      if (!file.existsSync()) {
        final migrated = await _migrateFromPrefs();
        if (migrated != null) return migrated;
        return [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      metas =
          decoded.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return _GroupMeta.fromJson(m);
          }).toList();

      // If the JSON still has embedded values (pre-migration format), migrate
      // them into secure storage now.
      final needsMigration = metas.any((m) => m.embeddedValues.isNotEmpty);

      final groups = <GlobalEnvGroup>[];
      var allWritesSucceeded = true;
      for (final meta in metas) {
        Map<String, String> values;
        if (meta.embeddedValues.isNotEmpty) {
          // Migration: move embedded values → secure storage.
          values = meta.embeddedValues;
          final ok = await _writeSecureValues(meta.id, values);
          if (!ok) allWritesSucceeded = false;
        } else {
          values = await _readSecureValues(meta.id, meta.keys);
        }
        groups.add(
          GlobalEnvGroup(id: meta.id, name: meta.name, values: values),
        );
      }

      // Only strip embedded values from JSON when ALL secure writes succeed.
      // If any write failed, keep the values in JSON to prevent data loss.
      if (needsMigration && allWritesSucceeded) {
        await _writeMetaFile(groups);
        debugPrint(
          '[EnvGroups] Migrated ${groups.length} group(s) to secure storage',
        );
      } else if (needsMigration) {
        debugPrint(
          '[EnvGroups] Migration SKIPPED — secure storage writes failed, '
          'keeping values in JSON to prevent data loss',
        );
      }

      return groups;
    } catch (e) {
      debugPrint('[EnvGroups] loadAll error: $e');
      return [];
    }
  }

  Future<List<GlobalEnvGroup>?> _migrateFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsFallbackKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List;
      final groups =
          decoded
              .map(
                (e) => GlobalEnvGroup.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
      await saveAll(groups);
      await prefs.remove(_prefsFallbackKey);
      return groups;
    } catch (_) {
      return null;
    }
  }

  /// Persists all groups: metadata to JSON, values to secure storage.
  Future<void> saveAll(List<GlobalEnvGroup> groups) async {
    final persistedGroups = <GlobalEnvGroup>[];
    // Write secret values to secure storage.
    for (final group in groups) {
      final valuesToPersist = await _mergeWithExistingSecureValues(
        group.id,
        group.values,
      );
      final persistedGroup = group.copyWith(values: valuesToPersist);
      persistedGroups.add(persistedGroup);
      final ok = await _writeSecureValues(group.id, valuesToPersist);
      if (!ok) {
        debugPrint(
          '[EnvGroups] WARNING: saveAll failed to persist secrets for '
          '${group.name} (${group.id})',
        );
      }
      // Verify the write by reading back
      final readBack = await _readSecureValues(
        group.id,
        valuesToPersist.keys.toList(),
      );
      final nonEmpty = readBack.values.where((v) => v.isNotEmpty).length;
      debugPrint(
        '[EnvGroups] saveAll verify ${group.name}: '
        '$nonEmpty/${valuesToPersist.length} keys persisted',
      );
    }
    // Write metadata (no values) to JSON.
    await _writeMetaFile(persistedGroups);
    _loadAllCache = List<GlobalEnvGroup>.unmodifiable(persistedGroups);
    _loadAllCacheSignature = _storageFileSignature();
    _loadAllInFlight = null;
  }

  /// Deletes a group's secure values from the credential store.
  Future<void> deleteGroupSecrets(String groupId) async {
    try {
      final key = _secureStorageKey(groupId);
      await _storage.delete(key: key);
      final legacyKey = _legacySecureStorageKey(groupId);
      if (legacyKey != null && legacyKey != key) {
        await _storage.delete(key: legacyKey);
      }
      _loadAllCache = null;
      _loadAllInFlight = null;
      _loadAllCacheSignature = null;
    } catch (e) {
      debugPrint('[EnvGroups] deleteGroupSecrets error: $e');
    }
  }

  Future<Map<String, String>> resolveSelectedGroups(
    List<String> selectedGroupIds,
  ) async {
    if (selectedGroupIds.isEmpty) return const {};
    final all = await loadAll();
    final byId = {for (final group in all) group.id: group};
    final merged = <String, String>{};
    for (final id in selectedGroupIds) {
      final group = byId[id];
      if (group == null) continue;
      // Only merge non-empty values — a failed secure-storage read returns
      // empty strings which would silently overwrite valid env vars.
      for (final entry in group.values.entries) {
        if (entry.value.isNotEmpty) {
          merged[entry.key] = entry.value;
        }
      }
    }
    debugPrint(
      '[EnvGroups] resolveSelectedGroups ids=$selectedGroupIds → '
      'keys=${merged.keys.toList()}',
    );
    return merged;
  }

  Future<List<String>> resolveSelectedGroupNames(
    List<String> selectedGroupIds,
  ) async {
    if (selectedGroupIds.isEmpty) return const [];
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
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
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

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Writes group metadata JSON (id, name, keys — no values).
  Future<void> _writeMetaFile(List<GlobalEnvGroup> groups) async {
    final metas =
        groups
            .map(
              (g) => {
                'id': g.id,
                'name': g.name,
                'keys': g.values.keys.toList(),
              },
            )
            .toList();
    final encoded = const JsonEncoder.withIndent('  ').convert(metas);
    final file = _storageFile;
    final dir = file.parent;
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(encoded, flush: true);
  }

  String _storageFileSignature() {
    final file = _storageFile;
    if (!file.existsSync()) return '${file.path}:missing';
    final stat = file.statSync();
    return '${file.path}:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
  }

  /// Returns `true` if the write succeeded.
  Future<Map<String, String>> _mergeWithExistingSecureValues(
    String groupId,
    Map<String, String> incomingValues,
  ) async {
    if (incomingValues.isEmpty) return incomingValues;
    final existingValues = await _readSecureValues(
      groupId,
      incomingValues.keys.toList(),
    );
    return {
      for (final entry in incomingValues.entries)
        entry.key:
            entry.value.isNotEmpty
                ? entry.value
                : (existingValues[entry.key]?.isNotEmpty == true
                    ? existingValues[entry.key]!
                    : entry.value),
    };
  }

  /// Returns `true` if the write succeeded.
  Future<bool> _writeSecureValues(
    String groupId,
    Map<String, String> values,
  ) async {
    try {
      final encoded = jsonEncode(values);
      final key = _secureStorageKey(groupId);
      debugPrint(
        '[EnvGroups] _writeSecureValues $groupId: '
        '${values.length} keys, ${encoded.length} bytes',
      );
      await _storage.write(key: key, value: encoded);
      final legacyKey = _legacySecureStorageKey(groupId);
      if (legacyKey != null && legacyKey != key) {
        await _storage.delete(key: legacyKey);
      }
      return true;
    } catch (e) {
      debugPrint('[EnvGroups] _writeSecureValues FAILED for $groupId: $e');
      return false;
    }
  }

  Future<Map<String, String>> _readSecureValues(
    String groupId,
    List<String> expectedKeys,
  ) async {
    try {
      final key = _secureStorageKey(groupId);
      var raw = await _storage.read(key: key);
      final legacyKey = _legacySecureStorageKey(groupId);
      if ((raw == null || raw.isEmpty) &&
          legacyKey != null &&
          legacyKey != key) {
        raw = await _storage.read(key: legacyKey);
        if (raw != null && raw.isNotEmpty) {
          await _storage.write(key: key, value: raw);
          await _storage.delete(key: legacyKey);
          debugPrint(
            '[EnvGroups] Migrated legacy secure key for $groupId '
            '($legacyKey -> $key)',
          );
        }
      }
      if (raw == null || raw.isEmpty) {
        debugPrint(
          '[EnvGroups] _readSecureValues: no data for $groupId '
          '(keys: $expectedKeys)',
        );
        return {for (final k in expectedKeys) k: ''};
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final result = {
        for (final k in expectedKeys) k: (decoded[k] ?? '').toString(),
      };
      final emptyKeys = result.entries
          .where((e) => e.value.isEmpty)
          .map((e) => e.key);
      if (emptyKeys.isNotEmpty) {
        debugPrint(
          '[EnvGroups] _readSecureValues: empty values for $groupId '
          'keys: ${emptyKeys.toList()}',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[EnvGroups] _readSecureValues error for $groupId: $e');
      return {for (final k in expectedKeys) k: ''};
    }
  }
}

/// Internal model for JSON metadata (may contain embedded values during
/// migration from the old format).
class _GroupMeta {
  _GroupMeta({
    required this.id,
    required this.name,
    required this.keys,
    required this.embeddedValues,
  });

  final String id;
  final String name;
  final List<String> keys;

  /// Non-empty only when reading the old JSON format that had values inline.
  final Map<String, String> embeddedValues;

  factory _GroupMeta.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? '';

    // New format: keys is a List<String>, no values.
    if (json.containsKey('keys') && json['keys'] is List) {
      final keys = (json['keys'] as List).map((e) => e.toString()).toList();
      return _GroupMeta(
        id: id,
        name: name,
        keys: keys,
        embeddedValues: const {},
      );
    }

    // Old format: values is a Map<String, String>.
    final valuesRaw = json['values'] as Map? ?? const {};
    final values = valuesRaw.map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    );
    return _GroupMeta(
      id: id,
      name: name,
      keys: values.keys.toList(),
      embeddedValues: values,
    );
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

