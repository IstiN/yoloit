import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/secure_storage_factory.dart';

part 'global_env_groups_service.g.dart';

/// Manages global env variable groups.
///
/// **Security model:**
/// - Group metadata (id, name, list of variable keys) is stored in a JSON
///   file at `~/.config/yoloit/env_groups.json`.
/// - Secret **values** are stored in scoped files under
///   `~/.config/yoloit/env_groups_values/` (mode 0600 on macOS/Linux).
///   macOS Keychain is intentionally avoided for env group values because
///   repeated Keychain writes trigger a "Keychain Not Found" system dialog
///   when the user's default keychain is locked or missing.
/// - On first load after upgrade, values stored in the legacy OS secure store
///   (macOS Keychain) are automatically migrated into the file store.
/// - Old JSON files that embedded values inline are also migrated.
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

  static String get _metaPath =>
      p.join(PlatformDirs.instance.configDir, 'env_groups.json');

  /// True when the runtime can use a real OS secure credential store.
  /// Web uses plain adapter entries for the demo because browser storage is
  /// not a hardware-backed enclave and `FlutterSecureStorage` is not wired up
  /// for the web target.
  bool get _useSecureStorage =>
      PlatformCapabilities.current.has(PlatformCapability.processes) &&
      PlatformCapabilities.current.has(PlatformCapability.secureStorage);

  String _valuesPath(String groupId) => p.join(
    PlatformDirs.instance.configDir,
    'env_groups_values',
    '${_canonicalGroupId(groupId)}.json',
  );

  /// Loads all env groups.  Values come from secure storage; only metadata
  /// (id, name, keys) lives in the JSON file.
  ///
  /// Returns a mutable deep copy so callers can edit groups in UI without
  /// mutating the internal cache.
  Future<List<GlobalEnvGroup>> loadAll() async {
    // Older builds stored the metadata file relative to CWD. If the scoped
    // config-dir file is missing but a legacy relative file exists, migrate
    // it before the cache/signature check so the data is visible immediately.
    await _migrateFromLegacyRelativePath();

    final signature = await _storageFileSignature();
    final cached = _loadAllCache;
    if (cached != null && _loadAllCacheSignature == signature) {
      return _cloneGroups(cached);
    }
    return _loadAllInFlight ??= _loadAllUncached().then(
      (groups) async {
        _loadAllCacheSignature = await _storageFileSignature();
        _loadAllCache = List<GlobalEnvGroup>.unmodifiable(groups);
        _loadAllInFlight = null;
        return _cloneGroups(groups);
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
      final storage = FileStorageAdapter.instance;
      if (!await storage.exists(_metaPath)) {
        final migrated = await _migrateFromPrefs();
        if (migrated != null) return migrated;
        return [];
      }
      final raw = await storage.readString(_metaPath);
      if (raw == null || raw.trim().isEmpty) return [];
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
          final ok = await _writeValues(meta.id, values);
          if (!ok) allWritesSucceeded = false;
        } else {
          values = await _readValues(meta.id, meta.keys);
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

  /// Older builds wrote `env_groups.json` relative to the current working
  /// directory instead of inside [PlatformDirs.configDir]. If the scoped file
  /// is missing but a legacy relative file exists, copy it into place.
  Future<void> _migrateFromLegacyRelativePath() async {
    try {
      final legacy = File('env_groups.json');
      if (!await legacy.exists()) return;
      final target = File(_metaPath);
      if (await target.exists()) return;
      await target.parent.create(recursive: true);
      await legacy.copy(target.path);
      debugPrint(
        '[EnvGroups] Migrated legacy env_groups.json from '
        '${legacy.absolute.path} to ${target.path}',
      );
    } catch (_) {}
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
      final ok = await _writeValues(group.id, valuesToPersist);
      if (!ok) {
        debugPrint(
          '[EnvGroups] WARNING: saveAll failed to persist secrets for '
          '${group.name} (${group.id})',
        );
      }
      // Verify the write by reading back.
      final readBack = await _readValues(
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
    _loadAllCacheSignature = await _storageFileSignature();
    _loadAllInFlight = null;
  }

  /// Deletes a group's values from the file store and, as a best-effort
  /// cleanup, from the legacy secure credential store.
  Future<void> deleteGroupSecrets(String groupId) async {
    try {
      await FileStorageAdapter.instance.delete(_valuesPath(groupId));
    } catch (e) {
      debugPrint('[EnvGroups] deleteGroupSecrets file error: $e');
    }

    if (_useSecureStorage) {
      try {
        final key = _secureStorageKey(groupId);
        await _storage.delete(key: key);
        final legacyKey = _legacySecureStorageKey(groupId);
        if (legacyKey != null && legacyKey != key) {
          await _storage.delete(key: legacyKey);
        }
      } catch (e) {
        debugPrint('[EnvGroups] deleteGroupSecrets legacy secure error: $e');
      }
    }

    _loadAllCache = null;
    _loadAllInFlight = null;
    _loadAllCacheSignature = null;
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
    if (!PlatformCapabilities.current.has(PlatformCapability.processes)) {
      // Web cannot read arbitrary file paths; return a placeholder group.
      return GlobalEnvGroup(
        id: 'group_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Imported Group',
        values: const {},
      );
    }
    final file = File(filePath);
    final content = await file.readAsString();
    final name = filePath.split(RegExp(r'[\\/]')).last
        .replaceAll('.env', '');
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

  List<GlobalEnvGroup> _cloneGroups(List<GlobalEnvGroup> groups) {
    return groups
        .map(
          (group) => group.copyWith(
            values: Map<String, String>.from(group.values),
          ),
        )
        .toList();
  }

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
    await FileStorageAdapter.instance.writeString(_metaPath, encoded);
  }

  Future<String> _storageFileSignature() async {
    final storage = FileStorageAdapter.instance;
    if (!await storage.exists(_metaPath)) return '$_metaPath:missing';
    final raw = await storage.readString(_metaPath);
    return '$_metaPath:${raw?.length ?? 0}:${raw.hashCode}';
  }

  /// Returns `true` if the write succeeded.
  Future<Map<String, String>> _mergeWithExistingSecureValues(
    String groupId,
    Map<String, String> incomingValues,
  ) async {
    if (incomingValues.isEmpty) return incomingValues;
    final existingValues = await _readValues(
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

  /// Writes values to a scoped file.  macOS Keychain is intentionally avoided
  /// here because repeated Keychain writes trigger a "Keychain Not Found"
  /// system dialog when the default keychain is locked/missing.  The file is
  /// stored in `~/.config/yoloit/env_groups_values/` with 0600 permissions.
  Future<bool> _writeValues(String groupId, Map<String, String> values) async {
    try {
      final encoded = jsonEncode(values);
      final path = _valuesPath(groupId);
      debugPrint(
        '[EnvGroups] _writeValues $groupId: '
        '${values.length} keys, ${encoded.length} bytes -> $path',
      );
      await FileStorageAdapter.instance.writeString(path, encoded);
      await _setFilePermissions(path);
      return true;
    } catch (e) {
      debugPrint('[EnvGroups] _writeValues FAILED for $groupId: $e');
      return false;
    }
  }

  Future<Map<String, String>> _readValues(
    String groupId,
    List<String> expectedKeys,
  ) async {
    try {
      final path = _valuesPath(groupId);
      String? raw = await FileStorageAdapter.instance.readString(path);

      // One-time migration: older builds stored env group values in the OS
      // secure store (macOS Keychain).  Read them back once and mirror to the
      // file so future accesses never touch Keychain again.
      if ((raw == null || raw.isEmpty) && _useSecureStorage) {
        raw = await _readLegacySecureValue(groupId);
        if (raw != null && raw.isNotEmpty) {
          await FileStorageAdapter.instance.writeString(path, raw);
          await _setFilePermissions(path);
          debugPrint(
            '[EnvGroups] Migrated secure-stored values for $groupId to file',
          );
        }
      }

      if (raw == null || raw.isEmpty) {
        debugPrint(
          '[EnvGroups] _readValues: no data for $groupId '
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
          '[EnvGroups] _readValues: empty values for $groupId '
          'keys: ${emptyKeys.toList()}',
        );
      }
      return result;
    } catch (e) {
      debugPrint('[EnvGroups] _readValues error for $groupId: $e');
      return {for (final k in expectedKeys) k: ''};
    }
  }

  Future<String?> _readLegacySecureValue(String groupId) async {
    try {
      final key = _secureStorageKey(groupId);
      String? raw = await _storage.read(key: key);
      final legacyKey = _legacySecureStorageKey(groupId);
      if ((raw == null || raw.isEmpty) &&
          legacyKey != null &&
          legacyKey != key) {
        raw = await _storage.read(key: legacyKey);
      }
      return raw;
    } catch (e) {
      debugPrint('[EnvGroups] _readLegacySecureValue error for $groupId: $e');
      return null;
    }
  }

  Future<void> _setFilePermissions(String path) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      await Process.run('chmod', ['600', path]);
    } on Exception {
      // Best-effort permissions.
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

@JsonSerializable()
class GlobalEnvGroup {
  const GlobalEnvGroup({
    required this.id,
    required this.name,
    required this.values,
  });

  @JsonKey(defaultValue: '')
  final String id;
  @JsonKey(defaultValue: '')
  final String name;
  @JsonKey(defaultValue: <String, String>{})
  final Map<String, String> values;

  Map<String, dynamic> toJson() => _$GlobalEnvGroupToJson(this);

  factory GlobalEnvGroup.fromJson(Map<String, dynamic> json) =>
      _$GlobalEnvGroupFromJson(json);

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

