import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

import 'local_ai_models_service_harness.dart';

/// Polls [condition] until it holds or [timeout] elapses.
///
/// Used instead of fixed `Future.delayed` waits so assertions do not race
/// real async file I/O when the suite runs under load.
Future<void> waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration interval = const Duration(milliseconds: 20),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out after $timeout waiting for condition.');
    }
    await Future<void>.delayed(interval);
  }
}

void main() {
  late Directory tmpDir;

  setUpAll(() {
    registerFallbackValue(buildTask('fallback', sdk.DownloadTaskStatus.queued));
    registerFallbackValue(buildManifest('fallback'));
    registerFallbackValue(sdk.DownloadSourceKind.githubRelease);
    registerFallbackValue(<sdk.RemoteFileDescriptor>[]);
  });

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('local_ai_models_dl_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  sdk.ModelRegistry registryWith(String modelId) {
    return sdk.ModelRegistry(<sdk.LocalModelManifest>[buildManifest(modelId)]);
  }

  group('downloadOrUpdateModel', () {
    test('throws stored init error when registry is missing', () async {
      final service = buildReadyService(initError: 'kaboom');
      await expectLater(
        service.downloadOrUpdateModel('m1'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'kaboom'),
        ),
      );
    });

    test(
      'throws default error when uninitialized without init error',
      () async {
        final service = buildReadyService();
        await expectLater(
          service.downloadOrUpdateModel('m1'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Local model service is not initialized',
            ),
          ),
        );
      },
    );

    test('skips when an active task already exists', () async {
      final manager = MockDownloadManager();
      final service = buildReadyService(
        registry: registryWith('m1'),
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask('m1', sdk.DownloadTaskStatus.installing),
        },
      );
      await service.downloadOrUpdateModel('m1');
      verifyNever(() => manager.run(any()));
    });

    test('resumes an existing paused task', () async {
      final manager = MockDownloadManager();
      final task = buildTask('m1', sdk.DownloadTaskStatus.paused);
      when(() => manager.run(any())).thenAnswer(
        (_) async => buildInstalled('m1', p.join(tmpDir.path, 'm1')),
      );
      final service = buildReadyService(
        registry: registryWith('m1'),
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{'m1': task},
      );
      await service.downloadOrUpdateModel('m1');
      verify(() => manager.run(task)).called(1);
    });

    test('resumes an existing failed task', () async {
      final manager = MockDownloadManager();
      final task = buildTask('m1', sdk.DownloadTaskStatus.failed);
      when(() => manager.run(any())).thenAnswer(
        (_) async => buildInstalled('m1', p.join(tmpDir.path, 'm1')),
      );
      final service = buildReadyService(
        registry: registryWith('m1'),
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{'m1': task},
      );
      await service.downloadOrUpdateModel('m1');
      verify(() => manager.run(task)).called(1);
    });

    test('swallows errors from the resumed task runner', () async {
      final manager = MockDownloadManager();
      final task = buildTask('m1', sdk.DownloadTaskStatus.failed);
      when(() => manager.run(any())).thenThrow(StateError('run failed'));
      final service = buildReadyService(
        registry: registryWith('m1'),
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{'m1': task},
      );
      await service.downloadOrUpdateModel('m1');
      verify(() => manager.run(task)).called(1);
    });

    test('throws when the manifest is not in the registry', () async {
      final service = buildReadyService(
        registry: sdk.ModelRegistry(<sdk.LocalModelManifest>[]),
        downloadManager: MockDownloadManager(),
      );
      await expectLater(
        service.downloadOrUpdateModel('unknown'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Manifest not found for model: unknown',
          ),
        ),
      );
    });

    test('refreshes metadata instead of downloading when current', () async {
      final manager = MockDownloadManager();
      final store = storeInRoot(tmpDir);
      final modelDir = Directory(p.join(store.paths.modelsDirectory.path, 'm1'))
        ..createSync(recursive: true);
      File(p.join(modelDir.path, 'config.json')).writeAsStringSync('{}');
      final service = buildReadyService(
        registry: registryWith('m1'),
        store: store,
        downloadManager: manager,
        installedById: <String, sdk.InstalledModel>{
          'm1': buildInstalled('m1', modelDir.path),
        },
      );
      await service.downloadOrUpdateModel('m1');
      verifyNever(
        () => manager.startDownload(
          manifest: any(named: 'manifest'),
          sourceKind: any(named: 'sourceKind'),
          sourceLabel: any(named: 'sourceLabel'),
          files: any(named: 'files'),
        ),
      );
      final metadataFile = File(
        p.join(modelDir.path, '.flutter_local_model.json'),
      );
      expect(metadataFile.existsSync(), isTrue);
      final decoded =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      expect(decoded['metadataUpdatedAt'], isNotNull);
      expect(service.installedModelById('m1'), isNotNull);
    });

    test(
      'a completed task record falls through to the manifest lookup',
      () async {
        final service = buildReadyService(
          registry: sdk.ModelRegistry(<sdk.LocalModelManifest>[]),
          downloadManager: MockDownloadManager(),
          taskByModelId: <String, sdk.DownloadTaskRecord>{
            'm1': buildTask('m1', sdk.DownloadTaskStatus.completed),
          },
        );
        await expectLater(
          service.downloadOrUpdateModel('m1'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('resumeModelDownload', () {
    test('does nothing when no task is tracked', () async {
      final manager = MockDownloadManager();
      final service = buildReadyService(downloadManager: manager);
      await service.resumeModelDownload('m1');
      verifyNever(() => manager.run(any()));
    });

    test('does nothing for an active task', () async {
      final manager = MockDownloadManager();
      final service = buildReadyService(
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask('m1', sdk.DownloadTaskStatus.queued),
        },
      );
      await service.resumeModelDownload('m1');
      verifyNever(() => manager.run(any()));
    });

    test('resumes a paused task', () async {
      final manager = MockDownloadManager();
      final task = buildTask('m1', sdk.DownloadTaskStatus.paused);
      when(() => manager.run(any())).thenAnswer(
        (_) async => buildInstalled('m1', p.join(tmpDir.path, 'm1')),
      );
      final service = buildReadyService(
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{'m1': task},
      );
      await service.resumeModelDownload('m1');
      verify(() => manager.run(task)).called(1);
    });
  });

  group('pause/cancel/stop downloads', () {
    test('pause and cancel are no-ops without a download manager', () async {
      final service = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'm1': buildTask('m1', sdk.DownloadTaskStatus.running),
        },
      );
      await service.pauseModelDownload('m1');
      await service.cancelModelDownload('m1');
    });

    test('pause delegates for active tasks only', () async {
      final manager = MockDownloadManager();
      final running = buildTask('running', sdk.DownloadTaskStatus.running);
      final installing = buildTask(
        'installing',
        sdk.DownloadTaskStatus.installing,
      );
      final queued = buildTask('queued', sdk.DownloadTaskStatus.queued);
      final paused = buildTask('paused', sdk.DownloadTaskStatus.paused);
      final service = LocalAiModelsService.forTesting(
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'running': running,
          'installing': installing,
          'queued': queued,
          'paused': paused,
        },
      );
      await service.pauseModelDownload('missing');
      await service.pauseModelDownload('running');
      await service.pauseModelDownload('installing');
      await service.pauseModelDownload('queued');
      await service.pauseModelDownload('paused');
      verify(() => manager.pause(running)).called(1);
      verify(() => manager.pause(installing)).called(1);
      verify(() => manager.pause(queued)).called(1);
      verifyNever(() => manager.pause(paused));
    });

    test('cancel delegates for active or paused tasks only', () async {
      final manager = MockDownloadManager();
      final running = buildTask('running', sdk.DownloadTaskStatus.running);
      final paused = buildTask('paused', sdk.DownloadTaskStatus.paused);
      final completed = buildTask(
        'completed',
        sdk.DownloadTaskStatus.completed,
      );
      final failed = buildTask('failed', sdk.DownloadTaskStatus.failed);
      final service = LocalAiModelsService.forTesting(
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{
          'running': running,
          'paused': paused,
          'completed': completed,
          'failed': failed,
        },
      );
      await service.cancelModelDownload('missing');
      await service.cancelModelDownload('running');
      await service.cancelModelDownload('paused');
      await service.cancelModelDownload('completed');
      await service.cancelModelDownload('failed');
      verify(() => manager.cancel(running)).called(1);
      verify(() => manager.cancel(paused)).called(1);
      verifyNever(() => manager.cancel(completed));
      verifyNever(() => manager.cancel(failed));
    });

    test('stopModelDownload is an alias for pause', () async {
      final manager = MockDownloadManager();
      final running = buildTask('m1', sdk.DownloadTaskStatus.running);
      final service = LocalAiModelsService.forTesting(
        downloadManager: manager,
        taskByModelId: <String, sdk.DownloadTaskRecord>{'m1': running},
      );
      await service.stopModelDownload('m1');
      verify(() => manager.pause(running)).called(1);
    });
  });

  group('handleTaskChangedForTesting', () {
    test('canceled task is removed and stage directory deleted', () async {
      final stageDir = Directory(p.join(tmpDir.path, 'stage'))
        ..createSync(recursive: true);
      final task = buildTask(
        'm1',
        sdk.DownloadTaskStatus.canceled,
        stagePath: stageDir.path,
      );
      final service = LocalAiModelsService.forTesting(
        taskByModelId: <String, sdk.DownloadTaskRecord>{'m1': task},
      );
      service.handleTaskChangedForTesting(task);
      expect(
        service.stateForModel('m1').status,
        LocalAiModelStatus.notDownloaded,
      );
      // The service deletes the stage directory via an unawaited async
      // delete, so poll until it finishes instead of asserting
      // synchronously. This also drains the in-flight delete before
      // tearDown removes the temp tree.
      await waitForCondition(() => !stageDir.existsSync());
      expect(stageDir.existsSync(), isFalse);
    });

    test('canceled task with missing stage directory is tolerated', () {
      final task = buildTask('m1', sdk.DownloadTaskStatus.canceled);
      final service = LocalAiModelsService.forTesting();
      service.handleTaskChangedForTesting(task);
      expect(
        service.stateForModel('m1').status,
        LocalAiModelStatus.notDownloaded,
      );
    });

    test('running task is tracked and reflected in state', () {
      final task = buildTask(
        'm1',
        sdk.DownloadTaskStatus.running,
        totalBytes: 10,
      );
      final service = LocalAiModelsService.forTesting();
      service.handleTaskChangedForTesting(task);
      expect(
        service.stateForModel('m1').status,
        LocalAiModelStatus.downloading,
      );
    });

    test('completed task triggers installed refresh', () async {
      final store = storeInRoot(tmpDir);
      final modelDir = Directory(p.join(store.paths.modelsDirectory.path, 'm1'))
        ..createSync(recursive: true);
      File(p.join(modelDir.path, 'config.json')).writeAsStringSync('{}');
      await store.writeInstallMetadata(
        modelDir,
        buildManifest('m1'),
        sourceLabel: 'test',
      );
      final task = buildTask('m1', sdk.DownloadTaskStatus.completed);
      final service = LocalAiModelsService.forTesting(store: store);
      service.handleTaskChangedForTesting(task);
      await service.refreshInstalled();
      expect(service.stateForModel('m1').status, LocalAiModelStatus.ready);
    });
  });

  group('deleteInstalledModel', () {
    test('is a no-op without a store or installed model', () async {
      final service = LocalAiModelsService.forTesting(initialized: true);
      await service.deleteInstalledModel('m1');
      final withStore = LocalAiModelsService.forTesting(
        initialized: true,
        store: storeInRoot(tmpDir),
      );
      await withStore.deleteInstalledModel('m1');
    });

    test('deletes the installed model directory and state', () async {
      final store = storeInRoot(tmpDir);
      final modelDir = Directory(p.join(tmpDir.path, 'models', 'm1'))
        ..createSync(recursive: true);
      final service = LocalAiModelsService.forTesting(
        initialized: true,
        store: store,
        installedById: <String, sdk.InstalledModel>{
          'm1': buildInstalled('m1', modelDir.path),
        },
      );
      await service.deleteInstalledModel('m1');
      expect(modelDir.existsSync(), isFalse);
      expect(service.installedModelById('m1'), isNull);
    });
  });
}
