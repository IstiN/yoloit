import 'package:yoloit/core/platform/yoloit_credential_store_base.dart';

/// Web stub credential store that keeps secrets in memory.
///
/// Browsers do not expose a hardware-backed keystore that matches the desktop
/// Keychain/DPAPI/libsecret model, so the web build uses an ephemeral in-memory
/// store. Values survive for the session but are not persisted across page
/// reloads.
class YoloitCredentialStore implements SecureStorageLike {
  YoloitCredentialStore({SecureStorageLike? secureStorage})
    : _secure = secureStorage ?? const _WebInMemoryStorage();

  final SecureStorageLike _secure;

  @override
  Future<String?> read({required String key}) => _secure.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) => _secure.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _secure.delete(key: key);
}

class _WebInMemoryStorage implements SecureStorageLike {
  const _WebInMemoryStorage();

  static final Map<String, String> _memory = {};

  @override
  Future<String?> read({required String key}) async => _memory[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null || value.isEmpty) {
      _memory.remove(key);
    } else {
      _memory[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async => _memory.remove(key);
}
