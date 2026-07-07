import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/yoloit_credential_store_web.dart';

/// Tests the web implementation of [YoloitCredentialStore].
///
/// These run on the VM but import the web stub directly to verify its
/// in-memory behavior.
void main() {
  group('YoloitCredentialStore web stub', () {
    test('read returns null when key is absent', () async {
      final store = YoloitCredentialStore();
      final value = await store.read(key: 'missing');
      expect(value, isNull);
    });

    test('write and read round-trip', () async {
      final store = YoloitCredentialStore();
      await store.write(key: 'k1', value: 'v1');
      final value = await store.read(key: 'k1');
      expect(value, 'v1');
    });

    test('write null removes key', () async {
      final store = YoloitCredentialStore();
      await store.write(key: 'k2', value: 'v2');
      await store.write(key: 'k2', value: null);
      final value = await store.read(key: 'k2');
      expect(value, isNull);
    });

    test('delete removes key', () async {
      final store = YoloitCredentialStore();
      await store.write(key: 'k3', value: 'v3');
      await store.delete(key: 'k3');
      final value = await store.read(key: 'k3');
      expect(value, isNull);
    });
  });
}
