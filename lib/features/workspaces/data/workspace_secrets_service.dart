import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/secure_storage_factory.dart';

class WorkspaceSecretsService {
  WorkspaceSecretsService._();
  static final WorkspaceSecretsService instance = WorkspaceSecretsService._();

  final _storage = SecureStorageFactory.create();

  /// Resets the secure-storage cache. Used by tests to avoid stale values
  /// leaking across test cases.
  @visibleForTesting
  void resetForTesting() => _storage.clearCache();

  String _key(String workspaceId) => 'ws_secrets_$workspaceId';

  Future<Map<String, String>> load(String workspaceId) async {
    try {
      final raw = await _storage.read(key: _key(workspaceId));
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(String workspaceId, Map<String, String> secrets) async {
    final existing = await load(workspaceId);
    final valuesToPersist = {
      for (final entry in secrets.entries)
        entry.key:
            entry.value.isNotEmpty
                ? entry.value
                : (existing[entry.key]?.isNotEmpty == true
                    ? existing[entry.key]!
                    : entry.value),
    };
    await _storage.write(
      key: _key(workspaceId),
      value: jsonEncode(valuesToPersist),
    );
  }

  Future<void> delete(String workspaceId) async {
    await _storage.delete(key: _key(workspaceId));
  }
}


