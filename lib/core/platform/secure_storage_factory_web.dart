import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yoloit/core/platform/yoloit_credential_store.dart';

/// Web stub factory: returns an in-memory credential store.
class SecureStorageFactory {
  SecureStorageFactory._();

  static YoloitCredentialStore create() => YoloitCredentialStore();

  static FlutterSecureStorage createRaw() {
    throw UnsupportedError(
      'SecureStorageFactory.createRaw() is not supported on the web.',
    );
  }
}
