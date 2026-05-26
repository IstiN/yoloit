import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'collaboration_cipher.dart';

/// Manages the AES-256 space key and stable client identity in the
/// device's secure storage (Keychain on macOS/iOS, Keystore on Android).
///
/// Key lifecycle:
///   Host: [generateKey] → shows hex / QR code → guests import it once.
///   Guest: [importKey] → stored → [loadCipher] on every connect.
///
/// The key is stored under [_kSpaceKey].  The guest client-id is a random
/// opaque string generated once and reused across reconnects so the host can
/// identify returning clients.
class CollaborationKeyStore {
  CollaborationKeyStore._();

  static const _storage = FlutterSecureStorage(
    // Use traditional Keychain for non-sandboxed app.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const _kSpaceKey  = 'collab_space_key_hex_v1';
  static const _kClientId  = 'collab_client_id_v1';

  // ── Key management ─────────────────────────────────────────────────────────

  /// Generates a fresh 256-bit random key, stores it, and returns it as a
  /// 64-char lowercase hex string.  Overwrites any previously stored key.
  static Future<String> generateKey() async {
    final hex = CollaborationCipher.generateKeyHex();
    await _storage.write(key: _kSpaceKey, value: hex);
    return hex;
  }

  /// Returns the stored key hex, or `null` if no key has been set.
  static Future<String?> loadKeyHex() => _storage.read(key: _kSpaceKey);

  /// Validates and stores a key entered by the user (hex string, may have
  /// dashes or spaces as separator).  Throws [ArgumentError] if invalid.
  static Future<void> importKey(String input) async {
    final hex = CollaborationCipher.normaliseKey(input);
    if (hex == null) {
      throw ArgumentError(
        'Invalid key — must be 64 hex characters (32 bytes).',
      );
    }
    await _storage.write(key: _kSpaceKey, value: hex);
  }

  /// Removes the stored key. After this, messages are sent unencrypted.
  static Future<void> clearKey() => _storage.delete(key: _kSpaceKey);

  /// Loads the stored key and returns a ready [CollaborationCipher], or
  /// `null` if no key is stored.
  static Future<CollaborationCipher?> loadCipher() async {
    final hex = await loadKeyHex();
    if (hex == null) return null;
    return CollaborationCipher.fromHex(hex);
  }

  // ── Client identity ────────────────────────────────────────────────────────

  /// Returns a stable client id that persists across app restarts.
  /// Creates and stores a new random id on first call.
  static Future<String> getOrCreateClientId() async {
    final existing = await _storage.read(key: _kClientId);
    if (existing != null) return existing;
    final id = _randomId();
    await _storage.write(key: _kClientId, value: id);
    return id;
  }

  static String _randomId() {
    final rng = Random.secure();
    final hex = List<int>.generate(8, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'c_$hex';
  }
}
