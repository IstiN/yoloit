@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudLlmSettingsService web persistence', () {
    late CloudLlmSettingsService service;

    setUp(() {
      service = CloudLlmSettingsService.instance..resetForTests();
      SharedPreferences.setMockInitialValues({});
    });

    test('saveConfigs writes to SharedPreferences', () async {
      final configs = [
        const CloudLlmConfig(
          id: 'openrouter',
          name: 'OpenRouter',
          baseUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'sk-test',
          model: 'google/gemma-4-31b-it',
        ),
      ];

      await service.saveConfigs(configs);
      final loaded = await service.loadConfigs();

      expect(loaded.length, 1);
      expect(loaded.first.id, 'openrouter');
      expect(loaded.first.apiKey, 'sk-test');
    });

    test('loadConfigs reads from SharedPreferences fallback key', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cloud_llm_configs_fallback_v1',
        jsonEncode([
          const CloudLlmConfig(
            id: 'gemini',
            name: 'Gemini',
            baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
            apiKey: 'gemini-key',
            model: 'gemini-2.0-flash',
          ).toJson(),
        ]),
      );

      final loaded = await service.loadConfigs();

      expect(loaded.length, 1);
      expect(loaded.first.id, 'gemini');
    });

    test('upsert updates existing config by id', () async {
      const original = CloudLlmConfig(
        id: 'openrouter',
        name: 'OpenRouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'old-key',
        model: 'google/gemma-4-31b-it',
      );
      await service.saveConfigs([original]);

      await service.upsertConfig(original.copyWith(apiKey: 'new-key'));
      final loaded = await service.loadConfigs();

      expect(loaded.first.apiKey, 'new-key');
    });
  });
}
