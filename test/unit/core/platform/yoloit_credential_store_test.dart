import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/yoloit_credential_store.dart';

class _MapSecureStorage implements SecureStorageLike {
  _MapSecureStorage(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null || value.isEmpty) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }
}

void main() {
  late Directory tempHome;

  setUp(() async {
    tempHome = await Directory.systemTemp.createTemp('yoloit_cred_test_');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempHome.path));
  });

  tearDown(() async {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    if (tempHome.existsSync()) {
      await tempHome.delete(recursive: true);
    }
  });

  test('prefers config-dir file over app-scoped secure storage', () async {
    final secure = _MapSecureStorage({'cloud_llm_configs_v1': 'from-secure'});
    final store = YoloitCredentialStore(secureStorage: secure);

    final credDir = Directory(
      '${tempHome.path}/.config/yoloit/credentials',
    );
    await credDir.create(recursive: true);
    await File('${credDir.path}/cloud_llm_configs_v1').writeAsString(
      'from-file',
    );

    final raw = await store.read(key: 'cloud_llm_configs_v1');
    expect(raw, 'from-file');
  });

  test('mirrors secure storage value into config-dir file', () async {
    final secure = _MapSecureStorage({
      'cloud_llm_configs_v1': '[{"id":"openrouter"}]',
    });
    final store = YoloitCredentialStore(secureStorage: secure);

    final raw = await store.read(key: 'cloud_llm_configs_v1');
    expect(raw, '[{"id":"openrouter"}]');

    final file = File(
      '${tempHome.path}/.config/yoloit/credentials/cloud_llm_configs_v1',
    );
    expect(file.existsSync(), isTrue);
    expect(await file.readAsString(), '[{"id":"openrouter"}]');
  });

  test('write updates both secure storage and config-dir file', () async {
    final secure = _MapSecureStorage({});
    final store = YoloitCredentialStore(secureStorage: secure);

    await store.write(key: 'env_group_test', value: '{"TOKEN":"abc"}');

    expect(secure.values['env_group_test'], '{"TOKEN":"abc"}');
    final file = File(
      '${tempHome.path}/.config/yoloit/credentials/env_group_test',
    );
    expect(await file.readAsString(), '{"TOKEN":"abc"}');
  });

  test('delete removes secure storage and config-dir file', () async {
    final secure = _MapSecureStorage({});
    final store = YoloitCredentialStore(secureStorage: secure);
    await store.write(key: 'ws_secrets_a', value: '{"k":"v"}');

    await store.delete(key: 'ws_secrets_a');

    expect(secure.values.containsKey('ws_secrets_a'), isFalse);
    final file = File(
      '${tempHome.path}/.config/yoloit/credentials/ws_secrets_a',
    );
    expect(file.existsSync(), isFalse);
  });
}
