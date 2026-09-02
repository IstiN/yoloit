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

  /// Resets in-memory caches and secure-storage cache. Used by tests to avoid
  /// stale values leaking across test cases.
  @visibleForTesting
  void resetForTesting() {
    _loadAllCache = null;
    _loadAllInFlight = null;
    _loadAllCacheSignature = null;
    _storage.clearCache();
  }

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
  ///
  /// Throws a [StateError] if the OS secure store is unavailable and the
  /// caller has chosen not to fall back to a file-based store.
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
        throw StateError(
          'Unable to save secrets for "${group.name}" because the secure '
          'credential store is not accessible. Unlock your login Keychain '
          '(macOS) or allow YoLoIT to access it, then try again.',
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
    // Write metadata (no values) to JSON only after all secrets are saved.
    await _writeMetaFile(persistedGroups);
    _loadAllCache = List<GlobalEnvGroup>.unmodifiable(persistedGroups);
    _loadAllCacheSignature = await _storageFileSignature();
    _loadAllInFlight = null;
  }

  /// Deletes a group's secure values from the credential store.
  Future<void> deleteGroupSecrets(String groupId) async {
    try {
      final key = _secureStorageKey(groupId);
      if (_useSecureStorage) {
        await _storage.delete(key: key);
      }
      await FileStorageAdapter.instance.delete(_valuesPath(groupId));
      final legacyKey = _legacySecureStorageKey(groupId);
      if (legacyKey != null && legacyKey != key && _useSecureStorage) {
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
    for (final line in lines) {
      final entry = _parseEnvLine(line);
      if (entry != null) result[entry.key] = entry.value;
    }
    return result;
  }

  /// Serializes [values] into `.env` file content — the inverse of
  /// [parseEnvContent].
  ///
  /// Draft keys (empty or `__draft_` prefixed) are skipped. Values that would
  /// not survive the round trip (newlines, tabs, leading/trailing whitespace,
  /// ` #` comment starts, or outer quote pairs) are wrapped in double quotes
  /// with `\n` / `\r` / `\t` escape sequences, which [parseEnvContent]
  /// understands.
  String encodeEnvContent(Map<String, String> values) {
    final buffer = StringBuffer();
    for (final entry in values.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || key.startsWith('__draft_')) continue;
      buffer
        ..write(key)
        ..write('=')
        ..writeln(_encodeEnvValue(entry.value));
    }
    return buffer.toString();
  }

  String _encodeEnvValue(String value) {
    final hasOuterQuotes =
        value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")));
    final needsQuotes =
        hasOuterQuotes ||
        value.contains('\n') ||
        value.contains('\r') ||
        value.contains('\t') ||
        value.contains(' #') ||
        value.trim() != value;
    if (!needsQuotes) return value;
    final escaped =
        value
            .replaceAll('\n', r'\n')
            .replaceAll('\r', r'\r')
            .replaceAll('\t', r'\t');
    return '"$escaped"';
  }

  MapEntry<String, String>? _parseEnvLine(String rawLine) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) return null;
    if (line.startsWith('export ')) {
      line = line.substring(7).trim();
    }
    final eq = line.indexOf('=');
    if (eq <= 0) return null;
    final key = line.substring(0, eq).trim();
    if (key.isEmpty) return null;
    var value = _stripEnvValueDecorations(line.substring(eq + 1).trim());
    value = value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');
    return MapEntry(key, value);
  }

  // Removes surrounding quotes, or the trailing ' # comment' for unquoted values.
  String _stripEnvValueDecorations(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    final commentIndex = value.indexOf(' #');
    if (commentIndex >= 0) {
      return value.substring(0, commentIndex).trimRight();
    }
    return value;
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

  /// Returns `true` if the write succeeded (or was a no-op because the stored
  /// value is already identical).
  Future<bool> _writeSecureValues(
    String groupId,
    Map<String, String> values,
  ) async {
    try {
      final encoded = jsonEncode(values);
      final key = _secureStorageKey(groupId);

      // Avoid touching the OS secure store when nothing changed.  On macOS this
      // prevents repeated Keychain prompts when the keychain is locked.
      if (_useSecureStorage) {
        final existing = await _storage.read(key: key);
        if (existing == encoded) {
          debugPrint(
            '[EnvGroups] _writeSecureValues $groupId: unchanged, skipping',
          );
          return true;
        }
      }

      debugPrint(
        '[EnvGroups] _writeSecureValues $groupId: '
        '${values.length} keys, ${encoded.length} bytes',
      );
      if (_useSecureStorage) {
        await _storage.write(key: key, value: encoded);
      } else {
        // Web demo fallback: values are stored as plain JSON in the adapter.
        // This is not suitable for production secrets but is acceptable for
        // the web demo where no hardware-backed keystore is available.
        await FileStorageAdapter.instance.writeString(_valuesPath(groupId), encoded);
      }
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
      String? raw;
      if (_useSecureStorage) {
        raw = await _storage.read(key: key);
      } else {
        raw = await FileStorageAdapter.instance.readString(_valuesPath(groupId));
      }
      final legacyKey = _legacySecureStorageKey(groupId);
      if ((raw == null || raw.isEmpty) &&
          legacyKey != null &&
          legacyKey != key &&
          _useSecureStorage) {
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

