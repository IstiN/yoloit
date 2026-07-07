import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yoloit/core/platform/yoloit_credential_store.dart';

/// Factory that creates a [FlutterSecureStorage] instance with correct
/// platform-specific options for macOS, Windows, and Linux.
class SecureStorageFactory {
  SecureStorageFactory._();

  /// Returns a credential store shared across debug and release desktop builds.
  static YoloitCredentialStore create() => YoloitCredentialStore(
    secureStorage: FlutterSecureStorageAdapter(createRaw()),
  );

  /// Returns a raw [FlutterSecureStorage] with platform-aware options.
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
