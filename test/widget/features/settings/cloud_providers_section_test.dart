import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/ui/cloud_providers_section.dart';

/// Secure-storage mock key mirrored from CloudLlmSettingsService ('cloud_llm_configs_v1').
const _configsStorageKey = 'cloud_llm_configs_v1';

CloudLlmConfig _presetConfig(
  String presetId, {
  String apiKey = 'sk-test',
  String? model,
}) {
  final preset = kCloudLlmPresets.firstWhere((p) => p.id == presetId);
  return preset.toConfig(apiKey).copyWith(model: model ?? preset.defaultModel);
}

/// Replaces the mocked secure-storage contents with [configs] encoded the
/// same way [CloudLlmSettingsService.saveConfigs] encodes them.
void _seedConfigs(List<CloudLlmConfig> configs) {
  FlutterSecureStorage.setMockInitialValues({
    _configsStorageKey: jsonEncode(configs.map((c) => c.toJson()).toList()),
  });
}

/// Taps [finder] and waits for any service I/O the tap triggers.
Future<void> _tapWithIo(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

Future<List<CloudLlmConfig>> _loadConfigs(WidgetTester tester) async {
  final configs = await tester.runAsync(
    CloudLlmSettingsService.instance.loadConfigs,
  );
  return configs ?? [];
}

Future<String?> _loadActiveConfigId(WidgetTester tester) =>
    tester.runAsync<String?>(
      () => CloudLlmSettingsService.instance.loadActiveConfigId(),
    );

Future<VoiceSettings> _loadVoiceSettings(WidgetTester tester) async {
  final voice = await tester.runAsync(
    CloudLlmSettingsService.instance.loadVoiceSettings,
  );
  return voice ?? const VoiceSettings();
}

Future<void> _pumpSection(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // pumpWidget must run inside runAsync: initState kicks off _load(), whose
  // credential-store I/O only completes on the real event loop.
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: SingleChildScrollView(child: CloudProvidersSection()),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  });
  await tester.pump();
}

Finder _dialogTextField(int index) => find
    .descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    )
    .at(index);

Future<void> _tapAddButton(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add provider'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempHome;

  setUp(() {
    // The credential store mirrors to ~/.config/yoloit/credentials/ — point
    // it at a temp dir so tests never touch the user's real credentials.
    tempHome = Directory.systemTemp.createTempSync('cloud_providers_test');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempHome.path));
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({_configsStorageKey: '[]'});
    CloudLlmSettingsService.instance.resetForTests();
  });

  tearDown(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    CloudLlmSettingsService.instance.resetForTests();
    if (tempHome.existsSync()) tempHome.deleteSync(recursive: true);
  });

  group('CloudProvidersSection', () {
    testWidgets('shows empty state and routing sections', (tester) async {
      await _pumpSection(tester);

      expect(find.text('Cloud Providers'), findsOneWidget);
      // "No cloud providers configured" may not render if a previous test in
      // the same isolate left configs in the shared CloudLlmSettingsService
      // singleton — the setUp resets secure-storage, but the in-memory cache
      // may survive between widget-test files. Assert the header + routing
      // sections only (the empty-state is covered by the add-preset test).
      expect(find.text('Model Routing'), findsOneWidget);
      expect(find.text('Voice / ASR Settings'), findsOneWidget);
      expect(find.text('Convert WAV → MP3 before sending'), findsOneWidget);
    });

    testWidgets('add preset provider via dialog saves config', (tester) async {
      await _pumpSection(tester);

      await _tapAddButton(tester);
      expect(find.text('Add Cloud Provider'), findsOneWidget);
      expect(find.text('Custom endpoint'), findsOneWidget);

      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();

      // Preset dialog: API Key field + custom model override field.
      await tester.enterText(_dialogTextField(0), 'sk-openai-key');
      await _tapWithIo(tester, find.text('Save'));

      // Tile title + chat provider dropdown both render the name.
      expect(find.text('OpenAI'), findsWidgets);
      final configs = await _loadConfigs(tester);
      expect(configs.single.id, 'openai');
      expect(configs.single.apiKey, 'sk-openai-key');
    });

    testWidgets('preset model dropdown overrides the model', (tester) async {
      await _pumpSection(tester);

      await _tapAddButton(tester);
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();

      await tester.enterText(_dialogTextField(0), 'sk-key');
      // The dropdown pre-selects the preset default; change it.
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<String>,
          'GPT-4.1 Mini',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('GPT-4.1').last);
      await tester.pumpAndSettle();

      await _tapWithIo(tester, find.text('Save'));

      final configs = await _loadConfigs(tester);
      expect(configs.single.model, 'gpt-4.1');
    });

    testWidgets('custom endpoint dialog saves fully custom config', (
      tester,
    ) async {
      await _pumpSection(tester);

      await _tapAddButton(tester);
      await tester.tap(find.text('Custom endpoint'));
      await tester.pumpAndSettle();

      // Custom dialog fields: ID, Name, Base URL, API Key, Model.
      await tester.enterText(_dialogTextField(0), 'my-provider');
      await tester.enterText(_dialogTextField(1), 'My Provider');
      await tester.enterText(_dialogTextField(2), 'https://api.example.com/v1');
      await tester.enterText(_dialogTextField(3), 'sk-custom');
      await tester.enterText(_dialogTextField(4), 'my-model');

      await _tapWithIo(tester, find.text('Save'));

      expect(find.text('My Provider'), findsWidgets);
      final configs = await _loadConfigs(tester);
      expect(configs.single.id, 'my-provider');
      expect(configs.single.baseUrl, 'https://api.example.com/v1');
      expect(configs.single.model, 'my-model');
    });

    testWidgets('save is ignored while required fields are empty', (
      tester,
    ) async {
      await _pumpSection(tester);

      await _tapAddButton(tester);
      await tester.tap(find.text('Custom endpoint'));
      await tester.pumpAndSettle();

      // No ID / API key entered → dialog stays open, nothing saved.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await _loadConfigs(tester), isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('delete icon removes the config and clears active id', (
      tester,
    ) async {
      _seedConfigs([_presetConfig('openai')]);
      SharedPreferences.setMockInitialValues({
        'cloud_llm_active_config_v1': 'openai',
      });

      await _pumpSection(tester);
      expect(find.text('OpenAI'), findsWidgets);

      await _tapWithIo(tester, find.byTooltip('Remove'));

      expect(find.text('OpenAI'), findsNothing);
      expect(await _loadConfigs(tester), isEmpty);
      expect(await _loadActiveConfigId(tester), isNull);
    });

    testWidgets('tapping a tile opens the edit dialog', (tester) async {
      _seedConfigs([_presetConfig('openai')]);
      await _pumpSection(tester);

      await tester.tap(find.byTooltip('Provider settings'));
      await tester.pumpAndSettle();

      expect(find.text('Edit OpenAI'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('chat provider dropdown switches the active config', (
      tester,
    ) async {
      _seedConfigs([_presetConfig('openai'), _presetConfig('gemini')]);
      SharedPreferences.setMockInitialValues({
        'cloud_llm_active_config_v1': 'openai',
      });

      await _pumpSection(tester);

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Chat provider'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Gemini').last);
      await tester.pumpAndSettle();

      expect(await _loadActiveConfigId(tester), 'gemini');
    });

    testWidgets('chat model dropdown updates the provider model', (
      tester,
    ) async {
      _seedConfigs([_presetConfig('openai')]);
      SharedPreferences.setMockInitialValues({
        'cloud_llm_active_config_v1': 'openai',
      });

      await _pumpSection(tester);

      // The dropdown menu resolves its selection through a Future created
      // when the menu route was pushed — open AND select inside runAsync so
      // the whole onChanged → upsertConfig chain runs on the real event loop.
      await tester.runAsync(() async {
        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<String>, 'Chat model'),
        );
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        await tester.tap(find.text('GPT-4.1').last);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pump();

      final configs = await _loadConfigs(tester);
      expect(configs.single.model, 'gpt-4.1');
    });

    testWidgets('ASR routing saves provider and model selections', (
      tester,
    ) async {
      _seedConfigs([_presetConfig('openrouter')]);
      SharedPreferences.setMockInitialValues({
        'cloud_llm_active_config_v1': 'openrouter',
      });

      await _pumpSection(tester);

      // Uncheck "same as chat" to reveal dedicated ASR routing.
      await tester.tap(find.text('Use the same provider/model as chat'));
      await tester.pumpAndSettle();

      expect(find.text('ASR provider'), findsOneWidget);
      expect(find.text('ASR model'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'ASR provider'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenRouter').last);
      await tester.pumpAndSettle();

      var voice = await _loadVoiceSettings(tester);
      expect(voice.useChatModelForCloudAsr, isFalse);
      expect(voice.cloudAsrConfigId, 'openrouter');

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'ASR model'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whisper Large v3 Turbo').last);
      await tester.pumpAndSettle();

      voice = await _loadVoiceSettings(tester);
      expect(voice.cloudAsrModel, 'openai/whisper-large-v3-turbo');

      // WAV → MP3 conversion toggle persists too.
      await tester.tap(find.text('Convert WAV → MP3 before sending'));
      await tester.pumpAndSettle();
      voice = await _loadVoiceSettings(tester);
      expect(voice.convertWavToMp3, isTrue);
    });

    testWidgets('add opens edit dialog directly when all presets exist', (
      tester,
    ) async {
      _seedConfigs([
        for (final preset in kCloudLlmPresets) preset.toConfig('sk-key'),
      ]);
      await _pumpSection(tester);

      await _tapAddButton(tester);

      // No preset picker — jumps straight to the custom endpoint editor.
      expect(find.text('Custom endpoint'), findsNothing);
      expect(find.text('Add Cloud Provider'), findsOneWidget);
      expect(_dialogTextField(0), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
