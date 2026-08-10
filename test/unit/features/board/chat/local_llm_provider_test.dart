import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/local_llm_provider.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

/// Service fake that only implements the reads [_loadInstalledModel]
/// performs through [LocalLlmProvider.localAiModelsServiceOverride].
class _FakeLocalAiModelsService extends Fake implements LocalAiModelsService {
  String selectedId = 'plain-model';
  final Map<String, sdk.InstalledModel> installed = {};
  List<LocalAiModelDefinition> chatModelDefs = const [];
  var initializeCalls = 0;
  var ensureRuntimeReadyCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> ensureRuntimeReady() async {
    ensureRuntimeReadyCalls++;
  }

  @override
  String get selectedChatModelId => selectedId;

  @override
  List<LocalAiModelDefinition> get chatModels => chatModelDefs;

  @override
  sdk.InstalledModel? installedModelById(String modelId) =>
      installed[modelId];
}

flm.LocalModelManifest _manifest(String id) {
  return flm.LocalModelManifest(
    id: id,
    displayName: id,
    description: 'Test model',
    runtimeAdapter: flm.RuntimeAdapter.mlxLm,
    tasks: const [flm.ModelTask.chat],
    source: flm.ModelSource(
      provider: 'huggingface',
      repo: 'test/$id',
      revision: 'main',
      license: 'apache-2.0',
    ),
    packaging: const flm.PackagingSpec(
      releaseTag: 'test',
      archiveName: 'test.tar',
      chunkSizeBytes: 0,
      assetPrefix: 'test',
    ),
    requirements: const flm.SystemRequirements(
      platform: 'macos-apple-silicon',
      minMemoryGb: 4,
      recommendedMemoryGb: 8,
      notes: [],
    ),
    capabilities: const flm.CapabilitySpec(
      audioInput: false,
      audioOutput: false,
      toolCalling: false,
    ),
  );
}

sdk.InstalledModel _sdkInstalled(String id) {
  return sdk.InstalledModel(
    manifest: _manifest(id),
    directory: Directory.systemTemp,
    sourceLabel: 'test',
    installedAt: DateTime(2024),
    sizeBytes: 0,
  );
}

flm.InstalledModel _flmInstalled(String id) {
  return flm.InstalledModel(
    manifest: _manifest(id),
    directory: Directory.systemTemp,
    sourceLabel: 'test',
    installedAt: DateTime(2024),
    sizeBytes: 0,
  );
}

LocalAiModelDefinition _def(String id) =>
    LocalAiModelDefinition(id: id, displayName: id, kind: LocalAiModelKind.chat);

void main() {
  group('LocalLlmProvider._loadInstalledModel', () {
    late _FakeLocalAiModelsService service;

    setUp(() {
      service = _FakeLocalAiModelsService();
      LocalLlmProvider.localAiModelsServiceOverride = service;
    });

    tearDown(() {
      LocalLlmProvider.localAiModelsServiceOverride = null;
    });

    test('returns the loader result when an installedModelLoader is given',
        () async {
      final provider = LocalLlmProvider(
        installedModelLoader: () async => _flmInstalled('loader-model'),
      );

      final installed = await provider.loadInstalledModelForTest();

      expect(installed.manifest.id, 'loader-model');
      // The service must not be touched when a loader is injected.
      expect(service.initializeCalls, 0);
    });

    test('loads the selected chat model through the service', () async {
      service.selectedId = 'plain-model';
      service.installed['plain-model'] = _sdkInstalled('plain-model');
      final provider = LocalLlmProvider();

      final installed = await provider.loadInstalledModelForTest();

      expect(installed.manifest.id, 'plain-model');
      expect(service.initializeCalls, 1);
      expect(service.ensureRuntimeReadyCalls, 1);
    });

    test('uses the runtimeReady callback instead of ensureRuntimeReady',
        () async {
      service.selectedId = 'plain-model';
      service.installed['plain-model'] = _sdkInstalled('plain-model');
      var readyCalls = 0;
      final provider = LocalLlmProvider(
        runtimeReady: () async {
          readyCalls++;
        },
      );

      await provider.loadInstalledModelForTest();

      expect(readyCalls, 1);
      expect(service.ensureRuntimeReadyCalls, 0);
    });

    test('throws when the selected model is not installed', () {
      service.selectedId = 'ghost-model';
      final provider = LocalLlmProvider();

      expect(
        provider.loadInstalledModelForTest,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('ghost-model'), contains('not installed')),
          ),
        ),
      );
    });

    test('auto-switches a router selection to an installed orchestrator',
        () async {
      service.selectedId = 'yoloit-router-v6';
      service.chatModelDefs = [
        _def('yoloit-router-v6'),
        _def('gemma4-e2b-it-4bit'),
      ];
      service.installed['gemma4-e2b-it-4bit'] =
          _sdkInstalled('gemma4-e2b-it-4bit');
      final provider = LocalLlmProvider();

      final installed = await provider.loadInstalledModelForTest();

      expect(installed.manifest.id, 'gemma4-e2b-it-4bit');
    });

    test('keeps the router id (and throws) when no orchestrator is installed',
        () {
      service.selectedId = 'yoloit-router-v6';
      service.chatModelDefs = [
        _def('yoloit-router-v6'),
        _def('gemma4-e2b-it-4bit'),
      ];
      // The orchestrator is listed but not installed → no switch.
      final provider = LocalLlmProvider();

      expect(
        provider.loadInstalledModelForTest,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('yoloit-router-v6'),
          ),
        ),
      );
    });
  });

  group('LocalLlmProvider._appendSummarySections', () {
    late LocalLlmProvider provider;

    setUp(() {
      provider = LocalLlmProvider();
    });

    String buildFor(ChatRuntimeContext? context) {
      final buf = StringBuffer();
      provider.appendSummarySectionsForTest(buf, context);
      return buf.toString();
    }

    test('appends boards, panels and focus panel sections', () {
      final result = buildFor(
        const ChatRuntimeContext(
          availableBoardsSummary: '- Board A (id: a)',
          currentBoardPanelsSummary: '- Panel X (id: x)',
          targetPanelSummary: '- Panel Y (id: y)',
        ),
      );

      expect(result, contains('Available boards:'));
      expect(result, contains('- Board A (id: a)'));
      expect(result, contains('board:focus'));
      expect(result, contains('Current board panels:'));
      expect(result, contains('- Panel X (id: x)'));
      expect(result, contains('Focus panel'));
      expect(result, contains('- Panel Y (id: y)'));
    });

    test('appends nothing when the runtime context is null', () {
      expect(buildFor(null), isEmpty);
    });

    test('skips blank summaries', () {
      final result = buildFor(
        const ChatRuntimeContext(
          availableBoardsSummary: '   ',
          currentBoardPanelsSummary: '',
        ),
      );

      expect(result, isEmpty);
    });

    test('appends only the sections that have content', () {
      final result = buildFor(
        const ChatRuntimeContext(targetPanelSummary: '- Panel Y (id: y)'),
      );

      expect(result, isNot(contains('Available boards:')));
      expect(result, isNot(contains('Current board panels:')));
      expect(result, contains('Focus panel'));
      expect(result, contains('- Panel Y (id: y)'));
    });
  });
}
