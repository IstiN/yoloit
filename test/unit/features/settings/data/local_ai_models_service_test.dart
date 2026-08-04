import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

import 'local_ai_models_service_harness.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('local_ai_models_test_');
  });

  tearDown(() {
    PlatformDirs.reset();
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  group('stateForModel', () {
    test('returns notDownloaded when nothing is known about the model', () {
      final service = LocalAiModelsService.forTesting();
      final state = service.stateForModel('m1');
      expect(state.status, LocalAiModelStatus.notDownloaded);
      expect(state.canResume, isFalse);
    });

    test('returns ready when the model is installed', () {
      final service = LocalAiModelsService.forTesting(
        installedById: <String, sdk.InstalledModel>{
          'm1': buildInstalled('m1', p.join(tmpDir.path, 'm1')),
        },
      );
      expect(service.stateForModel('m1').status, LocalAiModelStatus.ready);
      expect(service.installedModelById('m1'), isNotNull);
      expect(service.installedModelById('nope'), isNull);
    });

    test('maps active task statuses to downloading with progress', () {
      for (final status in <sdk.DownloadTaskStatus>[
        sdk.DownloadTaskStatus.running,
        sdk.DownloadTaskStatus.installing,
        sdk.DownloadTaskStatus.queued,
      ]) {
        final service = LocalAiModelsService.forTesting(
          taskByModelId: <String, sdk.DownloadTaskRecord>{
            'm1': buildTask(
              'm1',
              status,
              downloadedBytes: 50,
              totalBytes: 200,
              speed: 7,
            ),
          },
        );
        final state = service.stateForModel('m1');
        expect(state.status, LocalAiModelStatus.downloading);
        expect(state.downloadedBytes, 50);
        expect(state.totalBytes, 200);
        expect(state.speedBytesPerSecond, 7);
        expect(state.progress, 0.25);
        expect(state.isDownloading, isTrue);
        expect(state.hasTransferProgress, isTrue);
      }
    });

    test('maps paused task to resumable paused state', () {
      final service = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask('m1', sdk.DownloadTaskStatus.paused),
        },
      );
      final state = service.stateForModel('m1');
      expect(state.status, LocalAiModelStatus.paused);
      expect(state.canResume, isTrue);
      expect(state.progress, isNull);
      expect(state.hasTransferProgress, isTrue);
    });

    test('maps failed task to resumable failed state with error', () {
      final service = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask(
            'm1',
            sdk.DownloadTaskStatus.failed,
            errorMessage: 'network down',
          ),
        },
      );
      final state = service.stateForModel('m1');
      expect(state.status, LocalAiModelStatus.failed);
      expect(state.canResume, isTrue);
      expect(state.error, 'network down');
    });

    test('maps canceled-by-exception failure to notDownloaded', () {
      final service = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask(
            'm1',
            sdk.DownloadTaskStatus.failed,
            errorMessage: 'DownloadCanceledException: aborted',
          ),
        },
      );
      expect(
        service.stateForModel('m1').status,
        LocalAiModelStatus.notDownloaded,
      );
    });

    test('maps canceled task to notDownloaded', () {
      final service = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask('m1', sdk.DownloadTaskStatus.canceled),
        },
      );
      expect(
        service.stateForModel('m1').status,
        LocalAiModelStatus.notDownloaded,
      );
    });

    test('maps completed task by installed presence', () {
      final installed = LocalAiModelsService.forTesting(
        installedById: <String, sdk.InstalledModel>{
          'm1': buildInstalled('m1', p.join(tmpDir.path, 'm1')),
        },
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask('m1', sdk.DownloadTaskStatus.completed),
        },
      );
      expect(installed.stateForModel('m1').status, LocalAiModelStatus.ready);

      final missing = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask('m1', sdk.DownloadTaskStatus.completed),
        },
      );
      expect(
        missing.stateForModel('m1').status,
        LocalAiModelStatus.notDownloaded,
      );
    });

    test('reports integrity failure when critical files are missing', () {
      final store = storeInRoot(tmpDir);
      Directory(
        p.join(store.paths.modelsDirectory.path, 'm1'),
      ).createSync(recursive: true);
      final service = LocalAiModelsService.forTesting(store: store);
      final state = service.stateForModel('m1');
      expect(state.status, LocalAiModelStatus.failed);
      expect(state.error, contains('config.json'));
    });

    test('ignores integrity check when critical files exist', () {
      final store = storeInRoot(tmpDir);
      final okDir = Directory(p.join(store.paths.modelsDirectory.path, 'm1'))
        ..createSync(recursive: true);
      File(p.join(okDir.path, 'config.json')).writeAsStringSync('{}');
      final service = LocalAiModelsService.forTesting(store: store);
      expect(
        service.stateForModel('m1').status,
        LocalAiModelStatus.notDownloaded,
      );
    });
  });

  group('snapshot', () {
    test('includes full prerequisites, error and per-model state', () {
      final service = LocalAiModelsService.forTesting(
        initialized: true,
        initError: 'boom',
        prerequisites: const sdk.LocalModelsPrerequisitesStatus(
          platformSupported: true,
          metalToolchainAvailable: false,
          metalPath: '/usr/bin/metal',
          message: 'metal missing',
          installHint: 'install it',
        ),
        installedById: <String, sdk.InstalledModel>{
          'gemma4-e2b-it-4bit': buildInstalled(
            'gemma4-e2b-it-4bit',
            p.join(tmpDir.path, 'g'),
          ),
        },
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'qwen3-0.6b-4bit': buildTask(
            'qwen3-0.6b-4bit',
            sdk.DownloadTaskStatus.running,
            downloadedBytes: 10,
            totalBytes: 20,
          ),
        },
      );
      final snap = service.snapshot();
      expect(snap['ok'], isTrue);
      expect(snap['ready'], isFalse);
      expect(snap['error'], 'boom');
      final pre = snap['prerequisites'] as Map<String, dynamic>;
      expect(pre['platformSupported'], isTrue);
      expect(pre['ready'], isFalse);
      expect(pre['metalPath'], '/usr/bin/metal');
      expect(pre['message'], 'metal missing');
      expect(pre['installHint'], 'install it');
      final selected = snap['selected'] as Map<String, dynamic>;
      expect(selected['chat'], 'gemma4-e2b-it-4bit');
      final models = (snap['models'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(models, hasLength(service.supportedModels.length));
      final chat = models.firstWhere((m) => m['id'] == 'gemma4-e2b-it-4bit');
      expect(chat['selected'], isTrue);
      expect(chat['installed'], isTrue);
      expect(chat['status'], 'ready');
      expect(chat.containsKey('error'), isFalse);
      final downloading = models.firstWhere(
        (m) => m['id'] == 'qwen3-0.6b-4bit',
      );
      expect(downloading['status'], 'downloading');
      expect(downloading['progress'], 0.5);
      final asr = models.firstWhere((m) => m['id'] == 'qwen3-asr-0.6b-4bit');
      expect(asr['selected'], isTrue);
      expect(asr['kind'], 'asr');
    });

    test('omits optional keys and includes model error when present', () {
      final service = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'qwen3-0.6b-4bit': buildTask(
            'qwen3-0.6b-4bit',
            sdk.DownloadTaskStatus.failed,
            errorMessage: 'oops',
          ),
        },
      );
      final snap = service.snapshot();
      expect(snap.containsKey('error'), isFalse);
      final pre = snap['prerequisites'] as Map<String, dynamic>;
      expect(pre.containsKey('metalPath'), isFalse);
      expect(pre.containsKey('message'), isFalse);
      expect(pre.containsKey('installHint'), isFalse);
      final failed = (snap['models'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((m) => m['id'] == 'qwen3-0.6b-4bit');
      expect(failed['status'], 'failed');
      expect(failed['error'], 'oops');
      expect(failed['canResume'], isTrue);
    });
  });

  group('model lists and selection state', () {
    test('splits supported models by kind', () {
      final service = LocalAiModelsService.forTesting();
      expect(service.chatModels, isNotEmpty);
      expect(service.asrModels, isNotEmpty);
      expect(
        service.chatModels.every((m) => m.kind == LocalAiModelKind.chat),
        isTrue,
      );
      expect(
        service.asrModels.every((m) => m.kind == LocalAiModelKind.asr),
        isTrue,
      );
      expect(service.isReady, isFalse);
      expect(service.hasSelectedAsrInstalled, isFalse);
    });
  });

  group('ensureRuntimeReady', () {
    test('passes when prerequisites are satisfied', () async {
      final service = LocalAiModelsService.forTesting(
        prerequisitesChecker: readyChecker,
      );
      await service.ensureRuntimeReady();
      expect(service.prerequisites.isReady, isTrue);
    });

    test('throws message with install hint when not ready', () async {
      final service = LocalAiModelsService.forTesting(
        prerequisitesChecker: ({Map<String, String>? environment}) async =>
            const sdk.LocalModelsPrerequisitesStatus(
              platformSupported: true,
              metalToolchainAvailable: false,
              message: 'metal missing',
              installHint: 'xcodebuild -downloadComponent MetalToolchain',
            ),
      );
      await expectLater(
        service.ensureRuntimeReady(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Run: xcodebuild'),
          ),
        ),
      );
    });

    test('throws plain message when no install hint', () async {
      final service = LocalAiModelsService.forTesting(
        prerequisitesChecker: ({Map<String, String>? environment}) async =>
            const sdk.LocalModelsPrerequisitesStatus(
              platformSupported: false,
              metalToolchainAvailable: false,
              message: 'unsupported',
            ),
      );
      await expectLater(
        service.ensureRuntimeReady(),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'unsupported'),
        ),
      );
    });

    test('throws default message when no message provided', () async {
      final service = LocalAiModelsService.forTesting(
        prerequisitesChecker: ({Map<String, String>? environment}) async =>
            const sdk.LocalModelsPrerequisitesStatus(
              platformSupported: false,
              metalToolchainAvailable: false,
            ),
      );
      await expectLater(
        service.ensureRuntimeReady(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('prerequisites are not satisfied'),
          ),
        ),
      );
    });
  });

  group('preferences', () {
    test('selection setters persist and load preferences', () async {
      PlatformDirs.setInstance(TempPlatformDirs(tmpDir.path));
      final writer = LocalAiModelsService.forTesting();
      await writer.setSelectedChatModel('chat-x');
      await writer.setSelectedAsrModel('asr-y');
      expect(writer.selectedChatModelId, 'chat-x');
      expect(writer.selectedAsrModelId, 'asr-y');

      final file = File(p.join(tmpDir.path, 'local_ai_models.json'));
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['selectedChatModelId'], 'chat-x');
      expect(decoded['selectedAsrModelId'], 'asr-y');

      final reader = LocalAiModelsService.forTesting();
      await reader.loadPreferencesForTesting();
      expect(reader.selectedChatModelId, 'chat-x');
      expect(reader.selectedAsrModelId, 'asr-y');
    });

    test('load ignores a missing preferences file', () async {
      PlatformDirs.setInstance(TempPlatformDirs(tmpDir.path));
      final service = LocalAiModelsService.forTesting();
      await service.loadPreferencesForTesting();
      expect(service.selectedChatModelId, 'gemma4-e2b-it-4bit');
      expect(service.selectedAsrModelId, 'qwen3-asr-0.6b-4bit');
    });

    test('load ignores an empty preferences file', () async {
      PlatformDirs.setInstance(TempPlatformDirs(tmpDir.path));
      File(p.join(tmpDir.path, 'local_ai_models.json')).writeAsStringSync('  ');
      final service = LocalAiModelsService.forTesting();
      await service.loadPreferencesForTesting();
      expect(service.selectedChatModelId, 'gemma4-e2b-it-4bit');
    });

    test('load keeps defaults for empty or missing values', () async {
      PlatformDirs.setInstance(TempPlatformDirs(tmpDir.path));
      File(p.join(tmpDir.path, 'local_ai_models.json')).writeAsStringSync(
        jsonEncode(<String, dynamic>{'selectedChatModelId': ''}),
      );
      final service = LocalAiModelsService.forTesting();
      await service.loadPreferencesForTesting();
      expect(service.selectedChatModelId, 'gemma4-e2b-it-4bit');
      expect(service.selectedAsrModelId, 'qwen3-asr-0.6b-4bit');
    });
  });

  group('refreshInstalled', () {
    test('is a no-op without a store', () async {
      final service = LocalAiModelsService.forTesting();
      await service.refreshInstalled();
      expect(service.installedModelById('m1'), isNull);
    });

    test('discovers installed models from the store', () async {
      final store = storeInRoot(tmpDir);
      final modelDir = Directory(p.join(store.paths.modelsDirectory.path, 'm1'))
        ..createSync(recursive: true);
      File(p.join(modelDir.path, 'config.json')).writeAsStringSync('{}');
      await store.writeInstallMetadata(
        modelDir,
        buildManifest('m1'),
        sourceLabel: 'test',
      );
      final service = LocalAiModelsService.forTesting(store: store);
      await service.refreshInstalled();
      expect(service.installedModelById('m1'), isNotNull);
      expect(service.stateForModel('m1').status, LocalAiModelStatus.ready);
    });
  });
}
