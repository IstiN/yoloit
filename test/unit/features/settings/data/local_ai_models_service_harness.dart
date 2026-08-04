import 'dart:io';

import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

class MockDownloadManager extends Mock
    implements sdk.LocalModelDownloadManager {}

class TempPlatformDirs extends PlatformDirs {
  const TempPlatformDirs(this._root);

  final String _root;

  @override
  String get configDir => _root;

  @override
  String get dataDir => _root;

  @override
  String get logsDir => _root;

  @override
  String get tempDir => _root;

  @override
  String get skillsDir => '$_root/skills';

  @override
  String get yoloitTempDir => '$_root/tmp';
}

sdk.LocalModelManifest buildManifest(String id, {String releaseTag = 'v1'}) {
  return sdk.LocalModelManifest(
    id: id,
    displayName: 'Display $id',
    description: 'Test manifest for $id',
    runtimeAdapter: sdk.RuntimeAdapter.mlxLm,
    tasks: const <sdk.ModelTask>[sdk.ModelTask.chat],
    source: const sdk.ModelSource(
      provider: 'huggingface',
      repo: 'test/repo',
      revision: 'main',
      license: 'mit',
    ),
    packaging: sdk.PackagingSpec(
      releaseTag: releaseTag,
      archiveName: '$id.tar.gz',
      chunkSizeBytes: 1024,
      assetPrefix: id,
    ),
    requirements: const sdk.SystemRequirements(
      platform: 'macos',
      minMemoryGb: 4,
      recommendedMemoryGb: 8,
      notes: <String>[],
    ),
    capabilities: const sdk.CapabilitySpec(
      audioInput: false,
      audioOutput: false,
      toolCalling: false,
    ),
  );
}

sdk.DownloadTaskRecord buildTask(
  String modelId,
  sdk.DownloadTaskStatus status, {
  String? stagePath,
  String? errorMessage,
  int downloadedBytes = 0,
  int totalBytes = 0,
  int speed = 0,
}) {
  return sdk.DownloadTaskRecord(
      id: 'task-$modelId',
      title: 'Task $modelId',
      sourceKind: sdk.DownloadSourceKind.githubRelease,
      modelId: modelId,
      sourceLabel: 'GitHub Release: test',
      stageDirectory: Directory(stagePath ?? '/nonexistent-stage-$modelId'),
      files: const <sdk.RemoteFileDescriptor>[],
      manifest: buildManifest(modelId),
    )
    ..status = status
    ..downloadedBytes = downloadedBytes
    ..totalBytes = totalBytes
    ..downloadSpeedBytesPerSecond = speed
    ..errorMessage = errorMessage;
}

sdk.InstalledModel buildInstalled(
  String modelId,
  String directory, {
  String releaseTag = 'v1',
}) {
  return sdk.InstalledModel(
    manifest: buildManifest(modelId, releaseTag: releaseTag),
    directory: Directory(directory),
    sourceLabel: 'GitHub Release: test',
    installedAt: DateTime.utc(2024),
    sizeBytes: 42,
  );
}

Future<sdk.LocalModelsPrerequisitesStatus> readyChecker({
  Map<String, String>? environment,
}) async {
  return const sdk.LocalModelsPrerequisitesStatus(
    platformSupported: true,
    metalToolchainAvailable: true,
    metalPath: '/usr/bin/metal',
  );
}

sdk.LocalModelStore storeInRoot(Directory root) {
  return sdk.LocalModelStore(
    registry: sdk.ModelRegistry(<sdk.LocalModelManifest>[buildManifest('m1')]),
    paths: sdk.LocalModelsSdkPaths(baseDirectory: root),
  );
}

/// A fully initialized service whose prerequisites always pass.
LocalAiModelsService buildReadyService({
  sdk.ModelRegistry? registry,
  sdk.LocalModelStore? store,
  sdk.LocalModelDownloadManager? downloadManager,
  Map<String, sdk.InstalledModel>? installedById,
  Map<String, sdk.DownloadTaskRecord>? taskByModelId,
  String? initError,
}) {
  return LocalAiModelsService.forTesting(
    registry: registry,
    store: store,
    downloadManager: downloadManager,
    installedById: installedById,
    taskByModelId: taskByModelId,
    initialized: true,
    initError: initError,
    prerequisitesChecker: readyChecker,
  );
}
