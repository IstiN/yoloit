import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudLlmSettingsService SharedPreferences paths', () {
    late CloudLlmSettingsService service;

    setUp(() {
      service = CloudLlmSettingsService.instance;
      SharedPreferences.setMockInitialValues({});
    });

    test('active config id round-trips', () async {
      await service.saveActiveConfigId('openrouter');
      expect(await service.loadActiveConfigId(), 'openrouter');

      await service.saveActiveConfigId(null);
      expect(await service.loadActiveConfigId(), isNull);
    });

    test('assistant provider type defaults to cloud', () async {
      expect(await service.loadAssistantProviderType(), 'cloud');
    });

    test('voice settings migrate useCloudAsr to true', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'voice_settings_v1',
        '{"useCloudAsr":false,"convertWavToMp3":false}',
      );

      final settings = await service.loadVoiceSettings();

      expect(settings.useCloudAsr, isTrue);
      expect(settings.useChatModelForCloudAsr, isTrue);
    });
  });
}
