import 'dart:io';

import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';

/// Shared bridge to the real run backend.
///
/// Board widgets, CLI handlers, and chat guidance use this instead of storing
/// a second mock run state in panel-local state.
class RunBridge {
  RunBridge._();
  static final instance = RunBridge._();

  RunCubit? _cubit;

  void attach(RunCubit cubit) {
    _cubit = cubit;
  }

  RunCubit get _requireCubit {
    final cubit = _cubit;
    if (cubit == null) {
      throw StateError('Run backend is not attached');
    }
    return cubit;
  }

  RunState get state => _cubit?.state ?? const RunState();

  String? get workspacePath => state.workspacePath;

  RunConfig? findConfig([String? identifier, String? group]) {
    final configs = state.configs;
    final groupKey = group?.trim();
    if (identifier == null || identifier.trim().isEmpty) {
      if (configs.length == 1) return configs.single;
      final active = state.activeSession?.config;
      if (active == null) return null;
      if (groupKey == null || groupKey.isEmpty || active.group == groupKey) {
        return active;
      }
      return null;
    }
    final needle = identifier.trim().toLowerCase();
    for (final config in configs) {
      if (groupKey != null && groupKey.isNotEmpty && config.group != groupKey) {
        continue;
      }
      if (config.id == identifier || config.name.toLowerCase() == needle) {
        return config;
      }
    }
    return null;
  }

  RunSession? findSession(
    String? identifier, {
    bool runningOnly = false,
    String? group,
  }) {
    final groupKey = group?.trim();
    final sessions = state.sessions.reversed.where((session) {
      if (runningOnly && session.status != RunStatus.running) return false;
      if (groupKey != null &&
          groupKey.isNotEmpty &&
          session.config.group != groupKey) {
        return false;
      }
      if (identifier == null || identifier.trim().isEmpty) return true;
      final config = session.config;
      return session.id == identifier ||
          config.id == identifier ||
          config.name.toLowerCase() == identifier.trim().toLowerCase();
    });
    return sessions.isEmpty ? null : sessions.first;
  }

  Future<RunConfig> addConfig({
    required String name,
    required String command,
    String group = 'default',
    String? workingDir,
    Map<String, String> env = const {},
    bool isFlutterRun = false,
    List<RunQuickAction> quickActions = const [],
  }) async {
    await _ensureWorkspace(preferredWorkingDir: workingDir);
    final config = RunConfig(
      id: 'cli_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      command: command,
      group: group,
      workingDir: workingDir,
      env: env,
      isFlutterRun: isFlutterRun,
      quickActions: quickActions,
    );
    final persisted = await _requireCubit.addConfig(config);
    return persisted;
  }

  Future<RunSession> startConfig([String? identifier, String? group]) async {
    final config = findConfig(identifier, group);
    if (config == null) {
      throw StateError('Run configuration not found');
    }
    await _ensureWorkspace(preferredWorkingDir: config.workingDir);
    final effectiveWorkspace = state.workspacePath;
    if (effectiveWorkspace == null || effectiveWorkspace.trim().isEmpty) {
      throw StateError('Run workspace is not initialized');
    }
    final started = await _requireCubit.startRun(config);
    if (started != null) return started;
    throw StateError('Run session was not created');
  }

  Future<RunSession> stopSession([String? identifier, String? group]) async {
    final session = findSession(identifier, runningOnly: true, group: group);
    if (session == null) {
      throw StateError('No running session found');
    }
    _requireCubit.stopRun(session.id);
    return session;
  }

  Future<RunSession> detachSession([String? identifier, String? group]) async {
    final session = findSession(identifier, group: group);
    if (session == null) {
      throw StateError('Run session not found');
    }
    _requireCubit.detachSession(session.id);
    return session;
  }

  Future<RunSession> attachSession({
    String? identifier,
    String? group,
    bool runningOnly = true,
  }) async {
    var session = findSession(identifier, runningOnly: runningOnly, group: group);
    session ??= findSession(identifier, runningOnly: false, group: group);
    if (session == null) {
      throw StateError('Run session not found');
    }
    _requireCubit.attachSession(session.id);
    return session;
  }

  Future<RunSession> sendInput({
    String? identifier,
    String? group,
    required String text,
    bool appendNewline = false,
  }) async {
    final session = findSession(identifier, runningOnly: true, group: group);
    if (session == null) {
      throw StateError('No running session found');
    }
    final payload = appendNewline ? '$text\n' : text;
    _requireCubit.sendInput(session.id, payload);
    return session;
  }

  Future<void> removeConfig(String identifier) =>
      _requireCubit.removeConfig(identifier);

  Future<RunConfig> updateConfig({
    required String identifier,
    String? group,
    String? name,
    String? command,
    String? workingDir,
    Map<String, String>? env,
    bool? isFlutterRun,
    List<RunQuickAction>? quickActions,
  }) async {
    final existing = findConfig(identifier, group);
    if (existing == null) {
      throw StateError('Run configuration not found');
    }
    final updated = existing.copyWith(
      name: name,
      command: command,
      workingDir: workingDir,
      env: env,
      isFlutterRun: isFlutterRun,
      quickActions: quickActions,
    );
    await _requireCubit.updateConfig(updated);
    return updated;
  }

  Future<void> _ensureWorkspace({String? preferredWorkingDir}) async {
    final current = state.workspacePath;
    if (current != null && current.trim().isNotEmpty) return;
    final bootstrap =
        (preferredWorkingDir != null && preferredWorkingDir.trim().isNotEmpty)
            ? preferredWorkingDir.trim()
            : Directory.current.path;
    await _requireCubit.loadForWorkspace(bootstrap);
  }

  Map<String, dynamic> serializeConfig(RunConfig config) => {
    'id': config.id,
    'name': config.name,
    'command': config.command,
    'group': config.group,
    'workingDir': config.workingDir,
    'env': config.env,
    'isFlutterRun': config.isFlutterRun,
    'quickActions': config.quickActions.map((a) => a.toJson()).toList(),
  };

  Map<String, dynamic> serializeSession(RunSession session) => {
    'id': session.id,
    'configId': session.config.id,
    'configName': session.config.name,
    'status': session.status.name,
    'workspacePath': session.workspacePath,
    'exitCode': session.exitCode,
    'startedAt': session.startedAt?.toIso8601String(),
    'output': session.output.map((line) => line.text).join('\n'),
    'outputLines':
        session.output
            .map(
              (line) => {
                'text': line.text,
                'isError': line.isError,
                'timestamp': line.timestamp.toIso8601String(),
              },
            )
            .toList(),
  };
}
