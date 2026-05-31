import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WorkspaceSecretsService {
  WorkspaceSecretsService._();
  static final WorkspaceSecretsService instance = WorkspaceSecretsService._();

  // Platform-aware storage options.
  // macOS: uses Keychain with custom account name to avoid clashes.
  // Windows: uses DPAPI-backed credential store.
  // Linux: uses libsecret (gnome-keyring / kwallet).
  static FlutterSecureStorage _buildStorage() {
    if (Platform.isMacOS) {
      return const FlutterSecureStorage(
        mOptions: _FixedMacOsOptions(
          accountName: 'yoloit',
          usesDataProtectionKeychain: false,
        ),
      );
    } else if (Platform.isWindows) {
      return const FlutterSecureStorage(
        wOptions: WindowsOptions(useBackwardCompatibility: false),
      );
    } else {
      // Linux / other Unix: use libsecret default settings.
      return const FlutterSecureStorage(lOptions: LinuxOptions());
    }
  }

  final _storage = _buildStorage();

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

/// Workaround for flutter_secure_storage_darwin 0.2.0 key-name mismatch.
class _FixedMacOsOptions extends MacOsOptions {
  const _FixedMacOsOptions({
    super.accountName,
    super.usesDataProtectionKeychain,
  });

  @override
  Map<String, String> toMap() {
    final base = super.toMap();
    final value = base.remove('usesDataProtectionKeychain');
    if (value != null) {
      base['useDataProtectionKeyChain'] = value;
    }
    return base;
  }
}
