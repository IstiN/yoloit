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
    // Delete the temp home before resetting PlatformDirs so that any stray
    // in-flight write fails loudly here instead of landing in the real
    // user config directory.
    if (home.existsSync()) home.deleteSync(recursive: true);
    PlatformDirs.reset();
  });

  /// Polls (real async, inside runAsync) until [condition] holds or the
  /// timeout elapses. Robust replacement for fixed delays, which are flaky
  /// when the full suite runs many isolates concurrently.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    while (!condition() && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    await tester.pump();
  }

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
    await pumpUntil(
      tester,
      () => find.text('Default ASR:').evaluate().isNotEmpty,
    );
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
        await pumpUntil(
          tester,
          () => AgentConfigService.instance.defaultAgentId != null,
        );

        final chosen = AgentConfigService.instance.defaultAgentId;
        expect(chosen, isNotNull);
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.star).evaluate().isNotEmpty,
        );
        expect(find.byIcon(Icons.star), findsOneWidget);

        // Tapping the same star again unsets the favorite.
        await tester.tap(find.byIcon(Icons.star));
        await pumpUntil(
          tester,
          () => AgentConfigService.instance.defaultAgentId == null,
        );

        expect(AgentConfigService.instance.defaultAgentId, isNull);

        // Drain the unawaited _savePrefs() write before tearDown deletes
        // the temp dir — otherwise the in-flight write can throw
        // asynchronously and fail the test under load.
        final prefsFile = File(
          p.join(PlatformDirs.instance.configDir, 'agent_prefs.json'),
        );
        await pumpUntil(
          tester,
          () =>
              prefsFile.existsSync() &&
              prefsFile.readAsStringSync().contains('"defaultAgentId":null'),
        );
      });
    });

    testWidgets('adds and deletes a custom agent', (tester) async {
      await tester.runAsync(() async {
        await pumpLoaded(tester);

        await tester.tap(find.text('Add Custom Agent'));
        await pumpUntil(
          tester,
          () => find.text('Custom Agent').evaluate().isNotEmpty,
        );

        expect(find.text('Custom Agent'), findsOneWidget);
        // Custom agents get a delete button; built-ins do not.
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);

        // The new config was persisted to disk (async save — poll for it).
        final configFile = File(
          p.join(PlatformDirs.instance.configDir, 'agent_configs.json'),
        );
        await pumpUntil(
          tester,
          () =>
              configFile.existsSync() &&
              configFile.readAsStringSync().contains('Custom Agent'),
        );
        expect(configFile.existsSync(), isTrue);
        expect(configFile.readAsStringSync(), contains('Custom Agent'));

        await tester.tap(find.byIcon(Icons.delete_outline));
        await pumpUntil(
          tester,
          () => find.text('Custom Agent').evaluate().isEmpty,
        );

        expect(find.text('Custom Agent'), findsNothing);

        // Drain the unawaited save after the delete before tearDown
        // deletes the temp dir (in-flight writes can fail the test
        // asynchronously under load).
        await pumpUntil(
          tester,
          () => !configFile.readAsStringSync().contains('Custom Agent'),
        );
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

        // The save is unawaited real async I/O — poll for the persisted
        // content instead of relying on a fixed delay.
        final configFile = File(
          p.join(PlatformDirs.instance.configDir, 'agent_configs.json'),
        );
        await pumpUntil(
          tester,
          () =>
              configFile.existsSync() &&
              configFile.readAsStringSync().contains('"visible":false'),
        );

        expect(configFile.existsSync(), isTrue);
        expect(configFile.readAsStringSync(), contains('"visible":false'));
      });
    });
  });
}
