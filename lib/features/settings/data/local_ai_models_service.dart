import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:local_models_sdk/local_models_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';

enum LocalAiModelKind { chat, asr }

enum LocalAiModelStatus { notDownloaded, downloading, ready, failed }

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
  });

  final LocalAiModelStatus status;
  final bool canResume;
  final String? error;
}

class LocalAiModelsService {
  LocalAiModelsService._();

  static final instance = LocalAiModelsService._();

  static const String _defaultChatModelId = 'gemma4-e2b-it-4bit';
  static const String _defaultAsrModelId = 'qwen3-asr-0.6b-4bit';

  static const List<LocalAiModelDefinition> _supportedModels = [
    LocalAiModelDefinition(
      id: 'gemma4-e2b-it-4bit',
      displayName: 'Gemma 4 E2B IT 4bit',
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
  ];

  final _changes = StreamController<void>.broadcast();

  sdk.ModelRegistry? _registry;
  sdk.LocalModelStore? _store;
  sdk.LocalModelDownloadManager? _downloadManager;
  bool _initialized = false;
  bool _isInitializing = false;
  String? _initError;
  String _selectedChatModelId = _defaultChatModelId;
  String _selectedAsrModelId = _defaultAsrModelId;

  final Map<String, sdk.InstalledModel> _installedById = {};
  final Map<String, sdk.DownloadTaskRecord> _taskByModelId = {};

  List<LocalAiModelDefinition> get chatModels =>
      _supportedModels.where((m) => m.kind == LocalAiModelKind.chat).toList();

  List<LocalAiModelDefinition> get asrModels =>
      _supportedModels.where((m) => m.kind == LocalAiModelKind.asr).toList();

  String get selectedChatModelId => _selectedChatModelId;
  String get selectedAsrModelId => _selectedAsrModelId;
  bool get isInitializing => _isInitializing;
  String? get initError => _initError;
  bool get isReady => _initialized && _initError == null;

  Stream<void> get changes => _changes.stream;

  Future<void> initialize() async {
    if (_initialized || _isInitializing) return;
    _isInitializing = true;
    _notify();
    try {
      await _loadPreferences();
      final registryDir = _resolveRegistryDirectory();
      _registry = await sdk.ModelRegistry.loadDirectory(registryDir.path);
      _store = sdk.LocalModelStore(registry: _registry!);
      _downloadManager = sdk.LocalModelDownloadManager(
        store: _store!,
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

  LocalAiModelState stateForModel(String modelId) {
    final task = _taskByModelId[modelId];
    if (task != null) {
      switch (task.status) {
        case sdk.DownloadTaskStatus.running:
        case sdk.DownloadTaskStatus.installing:
        case sdk.DownloadTaskStatus.queued:
          return const LocalAiModelState(
            status: LocalAiModelStatus.downloading,
            canResume: false,
          );
        case sdk.DownloadTaskStatus.failed:
          return LocalAiModelState(
            status: LocalAiModelStatus.failed,
            canResume: true,
            error: task.errorMessage,
          );
        case sdk.DownloadTaskStatus.paused:
          return const LocalAiModelState(
            status: LocalAiModelStatus.failed,
            canResume: true,
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
    return const LocalAiModelState(
      status: LocalAiModelStatus.notDownloaded,
      canResume: false,
    );
  }

  Future<void> downloadOrUpdateModel(String modelId) async {
    await initialize();
    final registry = _registry;
    final downloadManager = _downloadManager;
    if (registry == null || downloadManager == null) {
      throw StateError(_initError ?? 'Local model service is not initialized');
    }
    sdk.LocalModelManifest? manifest;
    for (final candidate in registry.manifests) {
      if (candidate.id == modelId) {
        manifest = candidate;
        break;
      }
    }
    if (manifest == null) {
      throw StateError('Manifest not found for model: $modelId');
    }
    await downloadManager.downloadAndInstallFromGitHubRelease(
      manifest: manifest,
    );
    await refreshInstalled();
  }

  Future<void> resumeModelDownload(String modelId) async {
    final task = _taskByModelId[modelId];
    final downloadManager = _downloadManager;
    if (task == null || downloadManager == null) return;
    if (task.status != sdk.DownloadTaskStatus.failed &&
        task.status != sdk.DownloadTaskStatus.paused) {
      return;
    }
    await downloadManager.run(task);
    await refreshInstalled();
  }

  Future<void> deleteInstalledModel(String modelId) async {
    await initialize();
    final store = _store;
    final installed = _installedById[modelId];
    if (store == null || installed == null) return;
    await store.deleteInstalledModel(installed);
    _installedById.remove(modelId);
    _notify();
  }

  String resolveChatModelForSession(String requestedModelId) {
    final chatIds = chatModels.map((m) => m.id).toSet();
    if (chatIds.contains(requestedModelId)) {
      return requestedModelId;
    }
    return _selectedChatModelId;
  }

  void _onTaskChanged(sdk.DownloadTaskRecord record) {
    _taskByModelId[record.modelId] = record;
    _notify();
  }

  Directory _resolveRegistryDirectory() {
    final candidates = <Directory>[
      Directory(
        p.join(
          Directory.current.path,
          'third_party',
          'flutter_local_models',
          'registry',
          'models',
        ),
      ),
      Directory(
        p.join(
          Directory.current.path,
          'yoloit',
          'third_party',
          'flutter_local_models',
          'registry',
          'models',
        ),
      ),
    ];
    for (final dir in candidates) {
      if (dir.existsSync()) return dir;
    }
    throw StateError(
      'Cannot find flutter_local_models registry at third_party/flutter_local_models/registry/models',
    );
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
}
