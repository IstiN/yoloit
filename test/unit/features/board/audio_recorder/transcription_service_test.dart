import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/audio_recorder/transcription_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

class FakeCloud implements CloudTranscriber {
  String? nextText;
  Object? nextError;
  final List<String> calls = <String>[];

  @override
  Future<String> transcribeFromFile({
    required String audioPath,
    required VoiceSettings voiceSettings,
  }) async {
    calls.add(audioPath);
    final error = nextError;
    if (error != null) throw error;
    return nextText ?? '';
  }
}

class FakeLocal implements LocalTranscriber {
  String? nextText;
  Object? nextError;
  String? lastLanguage;
  final List<String> calls = <String>[];

  @override
  Future<String> transcribeWithSelectedAsr(
    String audioPath, {
    String? language,
  }) async {
    calls.add(audioPath);
    lastLanguage = language;
    final error = nextError;
    if (error != null) throw error;
    return nextText ?? '';
  }
}

class FakeSettings implements VoiceSettingsProvider {
  FakeSettings(this.value);

  VoiceSettings value;
  int loadCount = 0;

  @override
  Future<VoiceSettings> loadVoiceSettings() async {
    loadCount++;
    return value;
  }
}

void main() {
  test('default mode uses cloud when voiceSettings.useCloudAsr is true',
      () async {
    final cloud = FakeCloud()..nextText = '  hello cloud  ';
    final local = FakeLocal();
    final settings = FakeSettings(const VoiceSettings(useCloudAsr: true));
    final svc = TranscriptionService.testInstance(
      cloud: cloud,
      local: local,
      settings: settings,
    );

    final result = await svc.transcribeFile('/tmp/a.wav');

    expect(result.text, 'hello cloud');
    expect(result.modeUsed, 'cloud');
    expect(cloud.calls, <String>['/tmp/a.wav']);
    expect(local.calls, isEmpty);
  });

  test('default mode uses local when voiceSettings.useCloudAsr is false',
      () async {
    final cloud = FakeCloud();
    final local = FakeLocal()..nextText = 'hi local';
    final settings = FakeSettings(const VoiceSettings(useCloudAsr: false));
    final svc = TranscriptionService.testInstance(
      cloud: cloud,
      local: local,
      settings: settings,
    );

    final result = await svc.transcribeFile('/tmp/b.wav', language: 'en');

    expect(result.text, 'hi local');
    expect(result.modeUsed, 'local');
    expect(local.calls, <String>['/tmp/b.wav']);
    expect(local.lastLanguage, 'en');
    expect(cloud.calls, isEmpty);
  });

  test("explicit mode 'local' bypasses voice settings", () async {
    final cloud = FakeCloud();
    final local = FakeLocal()..nextText = 'forced local';
    // Even though voice settings say "cloud", explicit local must win and must
    // not consult settings at all.
    final settings = FakeSettings(const VoiceSettings(useCloudAsr: true));
    final svc = TranscriptionService.testInstance(
      cloud: cloud,
      local: local,
      settings: settings,
    );

    final result = await svc.transcribeFile('/x.wav', mode: 'local');

    expect(result.modeUsed, 'local');
    expect(result.text, 'forced local');
    expect(local.calls, <String>['/x.wav']);
    expect(cloud.calls, isEmpty);
    expect(settings.loadCount, 0);
  });

  test("explicit mode 'cloud' uses the cloud backend", () async {
    final cloud = FakeCloud()..nextText = 'cloud text';
    final local = FakeLocal();
    final settings = FakeSettings(const VoiceSettings(useCloudAsr: false));
    final svc = TranscriptionService.testInstance(
      cloud: cloud,
      local: local,
      settings: settings,
    );

    final result = await svc.transcribeFile('/y.wav', mode: 'cloud');

    expect(result.modeUsed, 'cloud');
    expect(cloud.calls, <String>['/y.wav']);
    expect(local.calls, isEmpty);
  });

  test('cloud errors propagate to the caller', () async {
    final cloud = FakeCloud()..nextError = StateError('no config');
    final settings = FakeSettings(const VoiceSettings(useCloudAsr: true));
    final svc = TranscriptionService.testInstance(
      cloud: cloud,
      local: FakeLocal(),
      settings: settings,
    );

    await expectLater(
      svc.transcribeFile('/z.wav', mode: 'cloud'),
      throwsA(isA<StateError>()),
    );
  });
}
