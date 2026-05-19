import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

class AgentConfig {
  final String id;
  final String displayName;
  final String iconLabel;
  final String launchCommand;
  final bool visible;
  final bool isBuiltIn;
  /// Default model for this provider (null = use catalog/provider default).
  final String? defaultModel;

  const AgentConfig({
    required this.id,
    required this.displayName,
    required this.iconLabel,
    required this.launchCommand,
    required this.visible,
    required this.isBuiltIn,
    this.defaultModel,
  });

  AgentConfig copyWith({
    String? displayName,
    String? iconLabel,
    String? launchCommand,
    bool? visible,
    Object? defaultModel = _sentinel,
  }) =>
      AgentConfig(
        id: id,
        displayName: displayName ?? this.displayName,
        iconLabel: iconLabel ?? this.iconLabel,
        launchCommand: launchCommand ?? this.launchCommand,
        visible: visible ?? this.visible,
        isBuiltIn: isBuiltIn,
        defaultModel: defaultModel == _sentinel
            ? this.defaultModel
            : defaultModel as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'iconLabel': iconLabel,
        'launchCommand': launchCommand,
        'visible': visible,
        'isBuiltIn': isBuiltIn,
        if (defaultModel != null) 'defaultModel': defaultModel,
      };

  factory AgentConfig.fromJson(Map<String, dynamic> j) => AgentConfig(
        id: j['id'] as String,
        displayName: j['displayName'] as String,
        iconLabel: j['iconLabel'] as String? ?? '◈',
        launchCommand: j['launchCommand'] as String? ?? '',
        visible: j['visible'] as bool? ?? true,
        isBuiltIn: j['isBuiltIn'] as bool? ?? false,
        defaultModel: j['defaultModel'] as String?,
      );
}

const _sentinel = Object();

class AgentConfigService {
  AgentConfigService._();
  static final instance = AgentConfigService._();

  // In-memory cache so cubit can read without async on every spawn.
  List<AgentConfig> _cached = [];
  String? _defaultAgentId;

  static List<AgentConfig> get _defaults => AgentType.values
      .map(
        (t) => AgentConfig(
          id: t.name,
          displayName: t.displayName,
          iconLabel: t.iconLabel,
          launchCommand: t.launchCommand,
          visible: true,
          isBuiltIn: true,
        ),
      )
      .toList();

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
        final saved = data
            .map((e) => AgentConfig.fromJson(e as Map<String, dynamic>))
            .toList();
        // Merge: ensure all built-ins are present
        final savedIds = saved.map((c) => c.id).toSet();
        for (final d in _defaults) {
          if (!savedIds.contains(d.id)) saved.add(d);
        }
        _cached = saved;
      }
    } catch (_) {
      _cached = _defaults;
    }

    try {
      final prefsFile = File(_prefsPath);
      if (await prefsFile.exists()) {
        final prefs = jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;
        _defaultAgentId = prefs['defaultAgentId'] as String?;
      }
    } catch (_) {}

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
    final prefsFile = File(_prefsPath);
    await prefsFile.parent.create(recursive: true);
    await prefsFile.writeAsString(jsonEncode({'defaultAgentId': id}));
  }

  String? get defaultAgentId => _defaultAgentId;

  /// Returns the AgentType for the configured default, falling back to terminal.
  AgentType get defaultAgentType {
    if (_defaultAgentId == null) return AgentType.terminal;
    try {
      return AgentType.values.firstWhere((t) => t.name == _defaultAgentId);
    } catch (_) {
      return AgentType.terminal;
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
}
