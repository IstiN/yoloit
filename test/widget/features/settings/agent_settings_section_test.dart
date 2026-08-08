import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';
import 'package:yoloit/features/settings/ui/sections/agent_settings_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    home = Directory.systemTemp.createTempSync('agent_settings_test_');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    CloudLlmSettingsService.instance.resetForTests();
    CloudLlmSettingsService.secureReadTimeout = Duration.zero;
    ProviderModelCatalogService.skipCliDiscoveryForTests = true;
  });

  tearDown(() {
    ProviderModelCatalogService.skipCliDiscoveryForTests = false;
    CloudLlmSettingsService.secureReadTimeout = const Duration(seconds: 8);
    PlatformDirs.reset();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: const Scaffold(
          body: SingleChildScrollView(child: AgentSettingsSection()),
        ),
      ),
    );
  }

  /// Pumps until the async _loadConfigs() has completed and the section
  /// shows its content.
  Future<void> pumpLoaded(WidgetTester tester) async {
    await pumpSection(tester);
    // First frame: loading indicator while the configs load.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump();
    expect(find.text('Default ASR:'), findsOneWidget);
  }

  group('AgentSettingsSection.build', () {
    testWidgets('renders the ASR row and board-chat agent rows', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await pumpLoaded(tester);

        // Global default ASR falls back to the cloud label with no config.
        expect(find.text('Cloud · — · —'), findsOneWidget);
        // Board-chat agents with stream adapters are listed.
        expect(find.text('OpenCode'), findsWidgets);
        expect(find.text('Add Custom Agent'), findsOneWidget);
        // Model picker rows appear once the catalog has loaded.
        expect(find.text('Default model:'), findsWidgets);
        expect(find.text('Launch command:'), findsWidgets);
        // Dividers separate the rows.
        expect(find.byType(Divider), findsWidgets);
      });
    });

    testWidgets('shows the cloud ASR label with provider and model names', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Seed agent prefs with a cloud default ASR selection.
        final configDir = PlatformDirs.instance.configDir;
        Directory(configDir).createSync(recursive: true);
        File(p.join(configDir, 'agent_prefs.json')).writeAsStringSync(
          jsonEncode({
            'defaultAsrMode': 'cloud',
            'defaultAsrCloudConfigId': 'cfg1',
            'defaultAsrCloudModel': 'whisper-1',
          }),
        );
        // Seed a matching cloud provider config (SharedPreferences fallback).
        SharedPreferences.setMockInitialValues({
          'cloud_llm_configs_fallback_v1': jsonEncode([
            {
              'id': 'cfg1',
              'name': 'My OpenAI',
              'baseUrl': 'https://api.openai.com/v1',
              'apiKey': 'k',
              'model': 'gpt-4o',
            },
          ]),
        });

        await pumpLoaded(tester);

        expect(find.text('Cloud · My OpenAI · whisper-1'), findsOneWidget);
      });
    });

    testWidgets('star toggles the favorite agent and persists it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await pumpLoaded(tester);

        expect(AgentConfigService.instance.defaultAgentId, isNull);

        await tester.tap(find.byIcon(Icons.star_border).first);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();

        final chosen = AgentConfigService.instance.defaultAgentId;
        expect(chosen, isNotNull);
        expect(find.byIcon(Icons.star), findsOneWidget);

        // Tapping the same star again unsets the favorite.
        await tester.tap(find.byIcon(Icons.star));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();

        expect(AgentConfigService.instance.defaultAgentId, isNull);
      });
    });

    testWidgets('adds and deletes a custom agent', (tester) async {
      await tester.runAsync(() async {
        await pumpLoaded(tester);

        await tester.tap(find.text('Add Custom Agent'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        await tester.pump();

        expect(find.text('Custom Agent'), findsOneWidget);
        // Custom agents get a delete button; built-ins do not.
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);

        // The new config was persisted to disk.
        final configFile = File(
          p.join(PlatformDirs.instance.configDir, 'agent_configs.json'),
        );
        expect(configFile.existsSync(), isTrue);
        expect(configFile.readAsStringSync(), contains('Custom Agent'));

        await tester.tap(find.byIcon(Icons.delete_outline));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();

        expect(find.text('Custom Agent'), findsNothing);
      });
    });

    testWidgets('toggling visibility and flags persists the config', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await pumpLoaded(tester);

        final switches = find.byType(Switch);
        expect(switches, findsWidgets);

        // First switch is the visibility toggle of the first row.
        await tester.tap(switches.first);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();

        final configFile = File(
          p.join(PlatformDirs.instance.configDir, 'agent_configs.json'),
        );
        expect(configFile.existsSync(), isTrue);
        expect(configFile.readAsStringSync(), contains('"visible":false'));
      });
    });
  });
}
