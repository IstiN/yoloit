import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/secure_storage_factory.dart';
import 'package:yoloit/core/platform/yoloit_credential_store_base.dart';

class FlutterSecureStorageAdapter implements SecureStorageLike {
  const FlutterSecureStorageAdapter(this._inner);

  final FlutterSecureStorage _inner;

  @override
  Future<String?> read({required String key}) => _inner.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _inner.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _inner.delete(key: key);
}

/// Cross-build credential store for YoLoIT desktop apps.
///
/// Debug (`com.yoloit.yoloit.debug`) and release (`com.yoloit.yoloit`) builds
/// use separate macOS Keychain partitions. To keep cloud providers, env secrets,
/// and workspace tokens visible in both, desktop builds mirror values to
/// `~/.config/yoloit/credentials/` (mode 0600) and prefer that file on read.
class YoloitCredentialStore implements SecureStorageLike {
  YoloitCredentialStore({SecureStorageLike? secureStorage})
    : _secure =
          secureStorage ??
          FlutterSecureStorageAdapter(SecureStorageFactory.createRaw());

  static const _serviceName = 'yoloit';
  static const Duration _secureIoTimeout = Duration(seconds: 8);

  final SecureStorageLike _secure;

  bool get _mirrorsToConfigDir => Platform.isMacOS || Platform.isLinux;

  @override
  Future<String?> read({required String key}) async {
    if (_mirrorsToConfigDir) {
      final fromFile = await _readFile(key);
      if (fromFile != null && fromFile.isNotEmpty) {
        return fromFile;
      }
    }

    final fromSecure = await _readSecure(key);
    if (fromSecure != null && fromSecure.isNotEmpty) {
      if (_mirrorsToConfigDir) {
        await _writeFile(key, fromSecure);
      }
      return fromSecure;
    }

    if (_mirrorsToConfigDir) {
      final fromLoginKeychain = await _readLoginKeychain(key);
      if (fromLoginKeychain != null && fromLoginKeychain.isNotEmpty) {
        await _writeFile(key, fromLoginKeychain);
        try {
          await _secure
              .write(key: key, value: fromLoginKeychain)
              .timeout(_secureIoTimeout);
        } on Exception {
          // File mirror is enough for desktop debug/release parity.
        }
        return fromLoginKeychain;
      }
    }

    return null;
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null || value.isEmpty) {
      await delete(key: key);
      return;
    }

    if (_mirrorsToConfigDir) {
      await _writeFile(key, value);
    }

    try {
      await _secure.write(key: key, value: value).timeout(_secureIoTimeout);
    } on Exception catch (e) {
      debugPrint('[CredentialStore] secure write failed for $key: $e');
      if (!_mirrorsToConfigDir) rethrow;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    if (_mirrorsToConfigDir) {
      final file = _fileForKey(key);
      if (file.existsSync()) {
        await file.delete();
      }
    }

    try {
      await _secure.delete(key: key).timeout(_secureIoTimeout);
    } on Exception catch (e) {
      debugPrint('[CredentialStore] secure delete failed for $key: $e');
    }
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _secure.read(key: key).timeout(_secureIoTimeout);
    } on Exception {
      return null;
    }
  }

  File _fileForKey(String key) {
    final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(
      p.join(PlatformDirs.instance.configDir, 'credentials', safe),
    );
  }

  Future<String?> _readFile(String key) async {
    try {
      final file = _fileForKey(key);
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      return raw.isEmpty ? null : raw;
    } on Exception {
      return null;
    }
  }

  Future<void> _writeFile(String key, String value) async {
    final file = _fileForKey(key);
    final dir = file.parent;
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(value, flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } on Exception {
        // Best-effort permissions; still better than world-readable.
      }
    }
  }

  /// Reads legacy login-keychain items written before the desktop file mirror.
  ///
  /// Only used on macOS when neither the file mirror nor the app-scoped secure
  /// storage returned data (typical when switching debug ↔ release builds).
  @visibleForTesting
  Future<String?> readLoginKeychainForMigration(String key) =>
      _readLoginKeychain(key);

  Future<String?> _readLoginKeychain(String key) async {
    if (!Platform.isMacOS) return null;
    try {
      final result = await Process.run(
        'security',
        [
          'find-generic-password',
          '-s',
          _serviceName,
          '-a',
          key,
          '-w',
        ],
      ).timeout(_secureIoTimeout);
      if (result.exitCode != 0) return null;
      final raw = (result.stdout as String).trim();
      return raw.isEmpty ? null : raw;
    } on Exception {
      return null;
    }
  }
}
