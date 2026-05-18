import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/local_model_registry_locator.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';

enum LocalAiModelKind { chat, asr }

enum LocalAiModelStatus { notDownloaded, downloading, paused, ready, failed }

class LocalAiModelDefinition {
  const LocalAiModelDefinition({
    required this.id,
    required this.displayName,
    required this.kind,
  });

  final String id;
  final String displayName;
  final LocalAiModelKind kind;
}

class LocalAiModelState {
  const LocalAiModelState({
    required this.status,
    required this.canResume,
    this.error,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSecond = 0,
  });

  final LocalAiModelStatus status;
  final bool canResume;
  final String? error;
  final int downloadedBytes;
  final int totalBytes;
  final int speedBytesPerSecond;

  double? get progress {
    if (totalBytes <= 0) return null;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isDownloading => status == LocalAiModelStatus.downloading;
  bool get hasTransferProgress =>
      status == LocalAiModelStatus.downloading ||
      status == LocalAiModelStatus.paused;
}

class LocalAiModelsService {
  LocalAiModelsService._();

  static final instance = LocalAiModelsService._();

  static const String _defaultChatModelId = 'gemma4-e2b-it-4bit';
  static const String _defaultAsrModelId = 'qwen3-asr-0.6b-4bit';
  static const String _githubOwner = 'IstiN';
  static const String _githubRepository = 'flutter_local_models';

  static const List<LocalAiModelDefinition> _supportedModels = [
    LocalAiModelDefinition(
      id: 'gemma4-e2b-it-4bit',
      displayName: 'Gemma 4 E2B IT 4bit',
      kind: LocalAiModelKind.chat,
    ),
    LocalAiModelDefinition(
      id: 'qwen3-0.6b-4bit',
      displayName: 'Qwen3 0.6B 4bit',
      kind: LocalAiModelKind.chat,
    ),
    LocalAiModelDefinition(
      id: 'qwen3-4b-instruct-4bit',
      displayName: 'Qwen3 4B Instruct 4bit (latest)',
      kind: LocalAiModelKind.chat,
    ),
    LocalAiModelDefinition(
      id: 'qwen3-4b-instruct-2507-4bit',
      displayName: 'Qwen3 4B Instruct 4bit',
      kind: LocalAiModelKind.chat,
    ),
    LocalAiModelDefinition(
      id: 'qwen3-8b-4bit',
      displayName: 'Qwen3 8B 4bit',
      kind: LocalAiModelKind.chat,
    ),
    LocalAiModelDefinition(
      id: 'qwen3-asr-0.6b-4bit',
      displayName: 'Qwen3 ASR 0.6B 4bit',
      kind: LocalAiModelKind.asr,
    ),
    LocalAiModelDefinition(
      id: 'whisper-tiny-asr-4bit',
      displayName: 'Whisper Tiny (fastest, ~26 MB)',
      kind: LocalAiModelKind.asr,
    ),
    LocalAiModelDefinition(
      id: 'whisper-base-asr-4bit',
      displayName: 'Whisper Base (~47 MB)',
      kind: LocalAiModelKind.asr,
    ),
    LocalAiModelDefinition(
      id: 'whisper-small-asr-4bit',
      displayName: 'Whisper Small (best quality, ~144 MB)',
      kind: LocalAiModelKind.asr,
    ),
  ];

  final _changes = StreamController<void>.broadcast();

  sdk.ModelRegistry? _registry;
  sdk.LocalModelStore? _store;
  sdk.LocalModelDownloadManager? _downloadManager;
  bool _initialized = false;
  bool _isInitializing = false;
  String? _initError;
  bool _isCheckingPrerequisites = false;
  sdk.LocalModelsPrerequisitesStatus _prerequisites =
      const sdk.LocalModelsPrerequisitesStatus(
        platformSupported: false,
        metalToolchainAvailable: false,
      );
  String _selectedChatModelId = _defaultChatModelId;
  String _selectedAsrModelId = _defaultAsrModelId;

  final Map<String, sdk.InstalledModel> _installedById = {};
  final Map<String, sdk.DownloadTaskRecord> _taskByModelId = {};

  List<LocalAiModelDefinition> get supportedModels =>
      List<LocalAiModelDefinition>.unmodifiable(_supportedModels);

  List<LocalAiModelDefinition> get chatModels =>
      _supportedModels.where((m) => m.kind == LocalAiModelKind.chat).toList();

  List<LocalAiModelDefinition> get asrModels =>
      _supportedModels.where((m) => m.kind == LocalAiModelKind.asr).toList();

  String get selectedChatModelId => _selectedChatModelId;
  String get selectedAsrModelId => _selectedAsrModelId;
  bool get isInitializing => _isInitializing;
  String? get initError => _initError;
  bool get isReady => _initialized && _initError == null;
  bool get isCheckingPrerequisites => _isCheckingPrerequisites;
  sdk.LocalModelsPrerequisitesStatus get prerequisites => _prerequisites;

  Stream<void> get changes => _changes.stream;

  Future<void> initialize() async {
    if (_initialized || _isInitializing) return;
    _isInitializing = true;
    _notify();
    try {
      await refreshPrerequisites();
      await _loadPreferences();
      final registryDir = await _resolveRegistryDirectory();
      _registry = await sdk.ModelRegistry.loadDirectory(registryDir.path);
      _store = sdk.LocalModelStore(registry: _registry!);
      _downloadManager = sdk.LocalModelDownloadManager(
        store: _store!,
        maxConcurrentDownloads: 4,
        onTaskChanged: _onTaskChanged,
      );
      await refreshInstalled();
      _initError = null;
      _initialized = true;
    } catch (e) {
      _initError = '$e';
    } finally {
      _isInitializing = false;
      _notify();
    }
  }

  Future<void> refreshInstalled() async {
    final store = _store;
    if (store == null) return;
    final installed = await store.listInstalledModels();
    _installedById
      ..clear()
      ..addEntries(installed.map((m) => MapEntry(m.manifest.id, m)));
    _notify();
  }

  Future<void> refreshPrerequisites() async {
    if (_isCheckingPrerequisites) return;
    _isCheckingPrerequisites = true;
    _notify();
    try {
      _prerequisites = await sdk.LocalModelsPrerequisitesChecker.check(
        environment: Platform.environment,
      );
    } finally {
      _isCheckingPrerequisites = false;
      _notify();
    }
  }

  Future<void> installMissingPrerequisites() async {
    _isCheckingPrerequisites = true;
    _notify();
    try {
      _prerequisites = await sdk
          .LocalModelsPrerequisitesChecker.installMissingPrerequisites(
        environment: Platform.environment,
      );
    } finally {
      _isCheckingPrerequisites = false;
      _notify();
    }
  }

  Future<void> ensureRuntimeReady() async {
    await refreshPrerequisites();
    _ensurePrerequisitesReady();
  }

  Future<void> setSelectedChatModel(String modelId) async {
    _selectedChatModelId = modelId;
    await _savePreferences();
    _notify();
  }

  Future<void> setSelectedAsrModel(String modelId) async {
    _selectedAsrModelId = modelId;
    await _savePreferences();
    _notify();
  }

  sdk.InstalledModel? installedModelById(String modelId) =>
      _installedById[modelId];

  bool get hasSelectedAsrInstalled =>
      installedModelById(_selectedAsrModelId) != null;

  Future<String> transcribeWithSelectedAsr(
    String audioPath, {
    String? language,
  }) async {
    await initialize();
    await ensureRuntimeReady();
    final selected = installedModelById(_selectedAsrModelId);
    if (selected == null) {
      throw StateError(
        'ASR model "$_selectedAsrModelId" is not installed. Install it in Settings → AI Models.',
      );
    }
    final audioRunner = flm.LocalAudioRunner();
    final flmModel = flm.InstalledModel(
      manifest: selected.manifest,
      directory: selected.directory,
      sourceLabel: selected.sourceLabel,
      installedAt: selected.installedAt,
      sizeBytes: selected.sizeBytes,
      metadataUpdatedAt: selected.metadataUpdatedAt,
    );
    try {
      return await audioRunner.transcribeAudio(
        model: flmModel,
        audioPath: audioPath,
        language: language,
      );
    } catch (error) {
      final raw = error.toString();
      if (raw.contains('flm_dispatch_json')) {
        throw StateError(
          'Local ASR runtime mismatch: missing symbol "flm_dispatch_json". '
          'Update/reinstall local models in Settings → AI Models and restart YoLoIT.',
        );
      }
      rethrow;
    }
  }

  LocalAiModelState stateForModel(String modelId) {
    final task = _taskByModelId[modelId];
    if (task != null) {
      switch (task.status) {
        case sdk.DownloadTaskStatus.running:
        case sdk.DownloadTaskStatus.installing:
        case sdk.DownloadTaskStatus.queued:
          return LocalAiModelState(
            status: LocalAiModelStatus.downloading,
            canResume: false,
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes,
            speedBytesPerSecond: task.downloadSpeedBytesPerSecond,
          );
        case sdk.DownloadTaskStatus.failed:
          final canceled = (task.errorMessage ?? '').contains(
            'DownloadCanceledException',
          );
          if (canceled) {
            return const LocalAiModelState(
              status: LocalAiModelStatus.notDownloaded,
              canResume: false,
            );
          }
          return LocalAiModelState(
            status: LocalAiModelStatus.failed,
            canResume: true,
            error: task.errorMessage,
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes,
            speedBytesPerSecond: task.downloadSpeedBytesPerSecond,
          );
        case sdk.DownloadTaskStatus.paused:
          return LocalAiModelState(
            status: LocalAiModelStatus.paused,
            canResume: true,
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes,
            speedBytesPerSecond: task.downloadSpeedBytesPerSecond,
          );
        case sdk.DownloadTaskStatus.completed:
          if (_installedById.containsKey(modelId)) {
            return const LocalAiModelState(
              status: LocalAiModelStatus.ready,
              canResume: false,
            );
          }
          return const LocalAiModelState(
            status: LocalAiModelStatus.notDownloaded,
            canResume: false,
          );
        case sdk.DownloadTaskStatus.canceled:
          return const LocalAiModelState(
            status: LocalAiModelStatus.notDownloaded,
            canResume: false,
          );
      }
    }
    if (_installedById.containsKey(modelId)) {
      return const LocalAiModelState(
        status: LocalAiModelStatus.ready,
        canResume: false,
      );
    }
    final integrityError = _integrityErrorForModel(modelId);
    if (integrityError != null) {
      return LocalAiModelState(
        status: LocalAiModelStatus.failed,
        canResume: false,
        error: integrityError,
      );
    }
    return const LocalAiModelState(
      status: LocalAiModelStatus.notDownloaded,
      canResume: false,
    );
  }

  Future<void> downloadOrUpdateModel(String modelId) async {
    await initialize();
    await ensureRuntimeReady();
    final registry = _registry;
    final downloadManager = _downloadManager;
    if (registry == null || downloadManager == null) {
      throw StateError(_initError ?? 'Local model service is not initialized');
    }

    final existingTask = _taskByModelId[modelId];
    if (existingTask != null) {
      if (existingTask.status == sdk.DownloadTaskStatus.running ||
          existingTask.status == sdk.DownloadTaskStatus.installing ||
          existingTask.status == sdk.DownloadTaskStatus.queued) {
        return;
      }
      if (existingTask.status == sdk.DownloadTaskStatus.failed ||
          existingTask.status == sdk.DownloadTaskStatus.paused) {
        unawaited(_runTask(existingTask));
        return;
      }
    }

    final manifest = _findManifest(modelId);
    if (manifest == null) {
      throw StateError('Manifest not found for model: $modelId');
    }

    final installed = _installedById[modelId];
    if (installed != null &&
        installed.manifest.packaging.releaseTag ==
            manifest.packaging.releaseTag) {
      await _store!.writeInstallMetadata(
        installed.directory,
        manifest,
        sourceLabel: installed.sourceLabel,
        installedAt: installed.installedAt,
        metadataUpdatedAt: DateTime.now(),
      );
      await refreshInstalled();
      return;
    }

    final files = await sdk.fetchGitHubReleaseFileDescriptors(
      owner: _githubOwner,
      repository: _githubRepository,
      releaseTag: manifest.packaging.releaseTag,
      githubToken: Platform.environment['GITHUB_TOKEN'],
    );
    if (files.isEmpty) {
      throw StateError(
        'No assets found for release tag ${manifest.packaging.releaseTag}',
      );
    }

    final record = await downloadManager.startDownload(
      manifest: manifest,
      sourceKind: sdk.DownloadSourceKind.githubRelease,
      sourceLabel:
          'GitHub Release: $_githubOwner/$_githubRepository@${manifest.packaging.releaseTag}',
      files: files,
    );
    _taskByModelId[modelId] = record;
    _notify();
  }

  Future<void> resumeModelDownload(String modelId) async {
    await ensureRuntimeReady();
    final task = _taskByModelId[modelId];
    if (task == null) return;
    if (task.status != sdk.DownloadTaskStatus.failed &&
        task.status != sdk.DownloadTaskStatus.paused) {
      return;
    }
    unawaited(_runTask(task));
  }

  Future<void> pauseModelDownload(String modelId) async {
    final task = _taskByModelId[modelId];
    final downloadManager = _downloadManager;
    if (task == null || downloadManager == null) return;
    if (task.status != sdk.DownloadTaskStatus.running &&
        task.status != sdk.DownloadTaskStatus.installing &&
        task.status != sdk.DownloadTaskStatus.queued) {
      return;
    }
    downloadManager.pause(task);
    _notify();
  }

  Future<void> cancelModelDownload(String modelId) async {
    final task = _taskByModelId[modelId];
    final downloadManager = _downloadManager;
    if (task == null || downloadManager == null) return;
    if (task.status != sdk.DownloadTaskStatus.running &&
        task.status != sdk.DownloadTaskStatus.installing &&
        task.status != sdk.DownloadTaskStatus.queued &&
        task.status != sdk.DownloadTaskStatus.paused) {
      return;
    }
    downloadManager.cancel(task);
    _notify();
  }

  // Backward-compatible alias for older API/CLI integrations.
  Future<void> stopModelDownload(String modelId) => pauseModelDownload(modelId);

  Future<void> deleteInstalledModel(String modelId) async {
    await initialize();
    final store = _store;
    final installed = _installedById[modelId];
    if (store == null || installed == null) return;
    await store.deleteInstalledModel(installed);
    _installedById.remove(modelId);
    _notify();
  }

  Map<String, dynamic> snapshot() {
    final models = <Map<String, dynamic>>[];
    for (final def in _supportedModels) {
      final state = stateForModel(def.id);
      models.add({
        'id': def.id,
        'displayName': def.displayName,
        'kind': def.kind.name,
        'selected':
            (def.kind == LocalAiModelKind.chat &&
                def.id == _selectedChatModelId) ||
            (def.kind == LocalAiModelKind.asr && def.id == _selectedAsrModelId),
        'installed': _installedById.containsKey(def.id),
        'status': state.status.name,
        'canResume': state.canResume,
        'downloadedBytes': state.downloadedBytes,
        'totalBytes': state.totalBytes,
        'speedBytesPerSecond': state.speedBytesPerSecond,
        'progress': state.progress,
        if (state.error != null && state.error!.trim().isNotEmpty)
          'error': state.error,
      });
    }
    return {
      'ok': true,
      'ready': isReady,
      'prerequisites': {
        'platformSupported': _prerequisites.platformSupported,
        'metalToolchainAvailable': _prerequisites.metalToolchainAvailable,
        'ready': _prerequisites.isReady,
        if (_prerequisites.metalPath != null)
          'metalPath': _prerequisites.metalPath,
        if (_prerequisites.message != null) 'message': _prerequisites.message,
        if (_prerequisites.installHint != null)
          'installHint': _prerequisites.installHint,
      },
      if (_initError != null) 'error': _initError,
      'selected': {'chat': _selectedChatModelId, 'asr': _selectedAsrModelId},
      'models': models,
    };
  }

  void _ensurePrerequisitesReady() {
    final pre = _prerequisites;
    if (pre.isReady) return;
    final message =
        pre.message ??
        'Local AI model prerequisites are not satisfied on this machine.';
    final hint = pre.installHint;
    throw StateError(
      hint == null || hint.isEmpty ? message : '$message Run: $hint',
    );
  }

  Future<void> _runTask(sdk.DownloadTaskRecord task) async {
    final manager = _downloadManager;
    if (manager == null) return;
    try {
      await manager.run(task);
      await refreshInstalled();
    } catch (_) {
      _notify();
    }
  }

  sdk.LocalModelManifest? _findManifest(String modelId) {
    final registry = _registry;
    if (registry == null) return null;
    for (final candidate in registry.manifests) {
      if (candidate.id == modelId) {
        return candidate;
      }
    }
    return null;
  }

  void _onTaskChanged(sdk.DownloadTaskRecord record) {
    if (record.status == sdk.DownloadTaskStatus.canceled) {
      _taskByModelId.remove(record.modelId);
      if (record.stageDirectory.existsSync()) {
        unawaited(record.stageDirectory.delete(recursive: true));
      }
      _notify();
      return;
    }
    _taskByModelId[record.modelId] = record;
    if (record.status == sdk.DownloadTaskStatus.completed) {
      unawaited(refreshInstalled());
    } else {
      _notify();
    }
  }

  Future<Directory> _resolveRegistryDirectory() async {
    // Always sync bundled registry assets to configDir so the registry
    // is up to date with the installed app version.
    await _syncRegistryAssets();
    return LocalModelRegistryLocator.resolveAsync(
      currentDirectory: PlatformDirs.instance.configDir,
    );
  }

  static const _registryAssetPrefix =
      'third_party/flutter_local_models/registry/models/';

  Future<void> _syncRegistryAssets() async {
    final destDir = Directory(
      p.join(
        PlatformDirs.instance.configDir,
        'third_party',
        'flutter_local_models',
        'registry',
        'models',
      ),
    );
    await destDir.create(recursive: true);

    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = assetManifest
        .listAssets()
        .where((k) => k.startsWith(_registryAssetPrefix));

    // Always overwrite to ensure bundled assets are up to date.
    for (final assetKey in assets) {
      final fileName = p.basename(assetKey);
      final destFile = File(p.join(destDir.path, fileName));
      final data = await rootBundle.load(assetKey);
      await destFile.writeAsBytes(data.buffer.asUint8List());
    }
  }

  String get _preferencesPath =>
      p.join(PlatformDirs.instance.configDir, 'local_ai_models.json');

  Future<void> _loadPreferences() async {
    final file = File(_preferencesPath);
    if (!await file.exists()) return;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final chat = json['selectedChatModelId'] as String?;
    final asr = json['selectedAsrModelId'] as String?;
    if (chat != null && chat.isNotEmpty) {
      _selectedChatModelId = chat;
    }
    if (asr != null && asr.isNotEmpty) {
      _selectedAsrModelId = asr;
    }
  }

  Future<void> _savePreferences() async {
    final file = File(_preferencesPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'selectedChatModelId': _selectedChatModelId,
        'selectedAsrModelId': _selectedAsrModelId,
      }),
    );
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  String? _integrityErrorForModel(String modelId) {
    final store = _store;
    if (store == null) return null;
    final modelDir = Directory(
      p.join(store.paths.modelsDirectory.path, modelId),
    );
    if (!modelDir.existsSync()) {
      return null;
    }
    final missing = sdk.LocalModelStore.missingCriticalFiles(
      directory: modelDir,
    );
    if (missing.isEmpty) {
      return null;
    }
    return 'Model files are incomplete (${missing.join(', ')} missing). '
        'Please download/update the model again.';
  }
}
