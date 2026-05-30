import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';

class AgentConfig {
  final String id;
  final String displayName;
  final String iconLabel;
  final String launchCommand;
  final bool visible;
  final bool isBuiltIn;
  final String? streamAdapter;
  final bool passDefaultArgs;
  final bool disableModel;

  /// Default model for this provider (null = use catalog/provider default).
  final String? defaultModel;

  /// Transcription (ASR) mode: 'default' (inherit global), 'local', or 'cloud'.
  final String asrMode;

  /// Cloud provider config ID to use for ASR (when asrMode == 'cloud').
  final String? asrCloudConfigId;

  /// Cloud ASR model override, e.g. 'whisper-1' (when asrMode == 'cloud').
  final String? asrCloudModel;

  const AgentConfig({
    required this.id,
    required this.displayName,
    required this.iconLabel,
    required this.launchCommand,
    required this.visible,
    required this.isBuiltIn,
    this.streamAdapter,
    this.passDefaultArgs = true,
    this.disableModel = false,
    this.defaultModel,
    this.asrMode = 'default',
    this.asrCloudConfigId,
    this.asrCloudModel,
  });

  AgentConfig copyWith({
    String? displayName,
    String? iconLabel,
    String? launchCommand,
    bool? visible,
    Object? streamAdapter = _sentinel,
    bool? passDefaultArgs,
    bool? disableModel,
    Object? defaultModel = _sentinel,
    String? asrMode,
    Object? asrCloudConfigId = _sentinel,
    Object? asrCloudModel = _sentinel,
  }) => AgentConfig(
    id: id,
    displayName: displayName ?? this.displayName,
    iconLabel: iconLabel ?? this.iconLabel,
    launchCommand: launchCommand ?? this.launchCommand,
    visible: visible ?? this.visible,
    isBuiltIn: isBuiltIn,
    streamAdapter:
        streamAdapter == _sentinel
            ? this.streamAdapter
            : streamAdapter as String?,
    passDefaultArgs: passDefaultArgs ?? this.passDefaultArgs,
    disableModel: disableModel ?? this.disableModel,
    defaultModel:
        defaultModel == _sentinel ? this.defaultModel : defaultModel as String?,
    asrMode: asrMode ?? this.asrMode,
    asrCloudConfigId:
        asrCloudConfigId == _sentinel
            ? this.asrCloudConfigId
            : asrCloudConfigId as String?,
    asrCloudModel:
        asrCloudModel == _sentinel
            ? this.asrCloudModel
            : asrCloudModel as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'iconLabel': iconLabel,
    'launchCommand': launchCommand,
    'visible': visible,
    'isBuiltIn': isBuiltIn,
    if (streamAdapter != null) 'streamAdapter': streamAdapter,
    'passDefaultArgs': passDefaultArgs,
    'disableModel': disableModel,
    if (defaultModel != null) 'defaultModel': defaultModel,
    if (asrMode != 'default') 'asrMode': asrMode,
    if (asrCloudConfigId != null) 'asrCloudConfigId': asrCloudConfigId,
    if (asrCloudModel != null) 'asrCloudModel': asrCloudModel,
  };

  factory AgentConfig.fromJson(Map<String, dynamic> j) => AgentConfig(
    id: j['id'] as String,
    displayName: j['displayName'] as String,
    iconLabel: j['iconLabel'] as String? ?? '◈',
    launchCommand: j['launchCommand'] as String? ?? '',
    visible: j['visible'] as bool? ?? true,
    isBuiltIn: j['isBuiltIn'] as bool? ?? false,
    streamAdapter: j['streamAdapter'] as String?,
    passDefaultArgs: j['passDefaultArgs'] as bool? ?? true,
    disableModel: j['disableModel'] as bool? ?? false,
    defaultModel: j['defaultModel'] as String?,
    asrMode: j['asrMode'] as String? ?? 'default',
    asrCloudConfigId: j['asrCloudConfigId'] as String?,
    asrCloudModel: j['asrCloudModel'] as String?,
  );
}

const _sentinel = Object();

class AgentConfigService {
  AgentConfigService._();
  static final instance = AgentConfigService._();

  // In-memory cache so cubit can read without async on every spawn.
  List<AgentConfig> _cached = [];
  String? _defaultAgentId;

  // Global default ASR config (applied to agents whose asrMode == 'default').
  String _defaultAsrMode = 'local';
  String? _defaultAsrCloudConfigId;
  String? _defaultAsrCloudModel;
  TerminalBackendMode _terminalBackendMode = TerminalBackendMode.runtime;
  TerminalRenderEngine _terminalRenderEngine = TerminalRenderEngine.kterm;

  final ValueNotifier<TerminalBackendMode> terminalBackendModeNotifier =
      ValueNotifier<TerminalBackendMode>(TerminalBackendMode.runtime);

  final ValueNotifier<TerminalRenderEngine> terminalRenderEngineNotifier =
      ValueNotifier<TerminalRenderEngine>(TerminalRenderEngine.kterm);

  static List<AgentConfig> get _defaults => [
    ...AgentType.values.map(
      (t) => AgentConfig(
        id: t.name,
        displayName: t.displayName,
        iconLabel: t.iconLabel,
        launchCommand: t.launchCommand,
        visible: true,
        isBuiltIn: true,
        streamAdapter:
            t.name == 'copilot'
                ? 'copilot'
                : t.name == 'cursor'
                ? 'cursor'
                : null,
      ),
    ),
    const AgentConfig(
      id: 'opencode',
      displayName: 'OpenCode',
      iconLabel: 'OC',
      launchCommand: 'opencode',
      visible: true,
      isBuiltIn: true,
      streamAdapter: 'opencode',
    ),
  ];

  String get _configPath =>
      p.join(PlatformDirs.instance.configDir, 'agent_configs.json');

  String get _prefsPath =>
      p.join(PlatformDirs.instance.configDir, 'agent_prefs.json');

  Future<List<AgentConfig>> load() async {
    try {
      final file = File(_configPath);
      if (!await file.exists()) {
        _cached = _defaults;
      } else {
        final data = jsonDecode(await file.readAsString()) as List;
        final saved =
            data
                .map((e) => AgentConfig.fromJson(e as Map<String, dynamic>))
                .toList();
        // Merge: ensure all built-ins are present and have default stream adapters if null
        final updatedSaved = <AgentConfig>[];
        for (final s in saved) {
          final def = _defaults.where((d) => d.id == s.id).firstOrNull;
          if (def != null &&
              s.streamAdapter == null &&
              def.streamAdapter != null) {
            updatedSaved.add(s.copyWith(streamAdapter: def.streamAdapter));
          } else {
            updatedSaved.add(s);
          }
        }
        final savedIds = updatedSaved.map((c) => c.id).toSet();
        for (final d in _defaults) {
          if (!savedIds.contains(d.id)) updatedSaved.add(d);
        }
        _cached = updatedSaved;
      }
    } catch (_) {
      _cached = _defaults;
    }

    try {
      final prefsFile = File(_prefsPath);
      if (await prefsFile.exists()) {
        final prefs =
            jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;
        _defaultAgentId = prefs['defaultAgentId'] as String?;
        _defaultAsrMode = prefs['defaultAsrMode'] as String? ?? 'local';
        _defaultAsrCloudConfigId = prefs['defaultAsrCloudConfigId'] as String?;
        _defaultAsrCloudModel = prefs['defaultAsrCloudModel'] as String?;
        _terminalRenderEngine = TerminalRenderEngineX.fromId(
          prefs['terminalRenderEngine'] as String?,
        );
        _terminalBackendMode = TerminalBackendModeX.fromId(
          prefs['terminalBackendMode'] as String?,
        );
      }
    } catch (_) {}
    terminalBackendModeNotifier.value = _terminalBackendMode;
    terminalRenderEngineNotifier.value = _terminalRenderEngine;

    return _cached;
  }

  Future<void> save(List<AgentConfig> configs) async {
    _cached = configs;
    final file = File(_configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> setDefaultAgentId(String? id) async {
    _defaultAgentId = id;
    await _savePrefs();
  }

  Future<void> saveDefaultAsr({
    required String mode,
    String? configId,
    String? model,
  }) async {
    _defaultAsrMode = mode;
    _defaultAsrCloudConfigId = configId;
    _defaultAsrCloudModel = model;
    await _savePrefs();
  }

  Future<void> setTerminalRenderEngine(TerminalRenderEngine engine) async {
    _terminalRenderEngine = engine;
    terminalRenderEngineNotifier.value = engine;
    await _savePrefs();
  }

  @visibleForTesting
  void setTerminalRenderEngineForTesting(TerminalRenderEngine engine) {
    _terminalRenderEngine = engine;
    terminalRenderEngineNotifier.value = engine;
  }

  Future<void> setTerminalBackendMode(TerminalBackendMode mode) async {
    _terminalBackendMode = mode;
    terminalBackendModeNotifier.value = mode;
    await _savePrefs();
  }

  @visibleForTesting
  void setTerminalBackendModeForTesting(TerminalBackendMode mode) {
    _terminalBackendMode = mode;
    terminalBackendModeNotifier.value = mode;
  }

  Future<void> _savePrefs() async {
    final prefsFile = File(_prefsPath);
    await prefsFile.parent.create(recursive: true);
    await prefsFile.writeAsString(
      jsonEncode({
        'defaultAgentId': _defaultAgentId,
        if (_defaultAsrMode != 'local') 'defaultAsrMode': _defaultAsrMode,
        if (_defaultAsrCloudConfigId != null)
          'defaultAsrCloudConfigId': _defaultAsrCloudConfigId,
        if (_defaultAsrCloudModel != null)
          'defaultAsrCloudModel': _defaultAsrCloudModel,
        if (_terminalRenderEngine != TerminalRenderEngine.kterm)
          'terminalRenderEngine': _terminalRenderEngine.id,
        if (_terminalBackendMode != TerminalBackendMode.runtime)
          'terminalBackendMode': _terminalBackendMode.id,
      }),
    );
  }

  String? get defaultAgentId => _defaultAgentId;
  String get defaultAsrMode => _defaultAsrMode;
  String? get defaultAsrCloudConfigId => _defaultAsrCloudConfigId;
  String? get defaultAsrCloudModel => _defaultAsrCloudModel;
  TerminalBackendMode get terminalBackendMode => _terminalBackendMode;
  TerminalRenderEngine get terminalRenderEngine => _terminalRenderEngine;

  /// Returns the AgentType for the configured default, falling back to Copilot.
  AgentType get defaultAgentType {
    if (_defaultAgentId == null) return AgentType.copilot;
    try {
      return AgentType.values.firstWhere((t) => t.name == _defaultAgentId);
    } catch (_) {
      return AgentType.copilot;
    }
  }

  /// Returns the effective launch command for a given AgentType,
  /// using the user-configured override if available.
  String effectiveLaunchCommand(AgentType type) {
    try {
      final config = _cached.firstWhere((c) => c.id == type.name);
      return config.launchCommand;
    } catch (_) {
      return type.launchCommand;
    }
  }

  /// Returns the user-configured default model for [agentId], or null if not set.
  String? defaultModelForAgent(String agentId) {
    try {
      return _cached.firstWhere((c) => c.id == agentId).defaultModel;
    } catch (_) {
      return null;
    }
  }

  /// Returns the config for [agentId], or null if not found.
  AgentConfig? configForAgent(String agentId) {
    try {
      return _cached.firstWhere((c) => c.id == agentId);
    } catch (_) {
      return null;
    }
  }

  /// Returns the effective ASR config for [agentId], resolving 'default' mode
  /// to the global default ASR settings.
  ({String mode, String? configId, String? model}) effectiveAsr(
    String agentId,
  ) {
    final cfg = configForAgent(agentId);
    final mode = cfg?.asrMode ?? 'default';
    if (mode == 'default') {
      return (
        mode: _defaultAsrMode,
        configId: _defaultAsrCloudConfigId,
        model: _defaultAsrCloudModel,
      );
    }
    return (
      mode: mode,
      configId: cfg?.asrCloudConfigId,
      model: cfg?.asrCloudModel,
    );
  }

  /// All currently loaded configs.
  List<AgentConfig> get configs => List.unmodifiable(_cached);

  AgentConfig? defaultConfigForId(String id) {
    try {
      return _defaults.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  static String defaultBoardChatCommand(String adapter) {
    return switch (adapter) {
      'opencode' => 'opencode run --format json --dangerously-skip-permissions',
      'cursor' =>
        'cursor-agent --print --output-format stream-json --stream-partial-output --yolo',
      'copilot' => 'copilot --output-format json --yolo',
      _ => '',
    };
  }
}
