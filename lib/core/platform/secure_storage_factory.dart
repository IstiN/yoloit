import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yoloit/core/platform/yoloit_credential_store.dart';

/// Factory that creates a [FlutterSecureStorage] instance with correct
/// platform-specific options for macOS, Windows, and Linux.
///
/// Replaces the repeated `_buildStorage()` boilerplate scattered across
/// settings and workspace services.
class SecureStorageFactory {
  SecureStorageFactory._();

  /// Returns a credential store shared across debug and release desktop builds.
  static YoloitCredentialStore create() => YoloitCredentialStore(
    secureStorage: FlutterSecureStorageAdapter(createRaw()),
  );

  /// Returns a raw [FlutterSecureStorage] with platform-aware options.
  ///
  /// - **macOS**: Uses a fixed [MacOsOptions] subclass that works around
  ///   `flutter_secure_storage_darwin` key-name mismatch.
  /// - **Windows**: Uses [WindowsOptions] with `useBackwardCompatibility: false`.
  /// - **Linux / other**: Uses default [LinuxOptions].
  static FlutterSecureStorage createRaw() {
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
      return const FlutterSecureStorage(lOptions: LinuxOptions());
    }
  }
}

/// Workaround for `flutter_secure_storage_darwin` 0.2.0 key-name mismatch.
///
/// The native Swift code reads `useDataProtectionKeyChain` (no 's', capital C)
/// but [MacOsOptions.toMap] sends `usesDataProtectionKeychain` (with 's',
/// lowercase c). This class overrides [toMap] to emit the correct key so the
/// option actually reaches the native layer.
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
