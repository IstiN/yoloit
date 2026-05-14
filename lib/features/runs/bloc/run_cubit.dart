import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/data/run_config_storage.dart';
import 'package:yoloit/features/runs/data/run_service.dart';
import 'package:yoloit/features/runs/data/run_session_storage.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';

class RunCubit extends Cubit<RunState> {
  RunCubit() : super(const RunState());

  static const _maxOutputLines = 5000;

  Future<void> loadForWorkspace(String workspacePath) async {
    final configs = await RunConfigStorage.instance.load(workspacePath);
    final savedSessions = await RunSessionStorage.instance.load(workspacePath);

    final seededConfigs =
        configs.isEmpty && await _isFlutterProject(workspacePath)
            ? [
              RunConfig.flutterRunMacos(workspacePath),
              RunConfig.flutterTest(),
              RunConfig.flutterBuildMacos(),
            ]
            : configs;
    final effectiveConfigs = _dedupeConfigs(seededConfigs);

    if (!_sameConfigs(effectiveConfigs, configs)) {
      await RunConfigStorage.instance.save(workspacePath, effectiveConfigs);
    }

    emit(
      state.copyWith(
        configs: effectiveConfigs,
        workspacePath: workspacePath,
        sessions: savedSessions,
        activeSessionId: savedSessions.lastOrNull?.id,
      ),
    );

    // Reconnect to any sessions that were running when the app last closed
    for (final session in savedSessions.where(
      (s) => s.status == RunStatus.running,
    )) {
      final alive = await RunService.instance.reconnect(
        sessionId: session.id,
        configId: session.config.id,
        onOutput: (line, isError) => _appendOutput(session.id, line, isError),
        onExit: (code) => _onExit(session.id, code),
      );
      if (!alive) {
        // tmux session gone — mark as stopped
        _updateSession(
          session.id,
          (s) => s.copyWith(status: RunStatus.stopped),
        );
      }
    }
  }

  Future<bool> _isFlutterProject(String path) async {
    final pubspec = File('$path/pubspec.yaml');
    if (!await pubspec.exists()) return false;
    final content = await pubspec.readAsString();
    return content.contains('flutter:');
  }

  Future<RunSession?> startRun(RunConfig config) async {
    final workspacePath = state.workspacePath;
    if (workspacePath == null) return null;

    final sessionId = '${config.id}_${DateTime.now().millisecondsSinceEpoch}';
    final session = RunSession(
      id: sessionId,
      config: config,
      workspacePath: workspacePath,
      status: RunStatus.running,
      startedAt: DateTime.now(),
    );

    emit(
      state.copyWith(
        sessions: [...state.sessions, session],
        activeSessionId: sessionId,
      ),
    );

    // Persist immediately so status=running is saved before any app restart
    _persistSessions();

    final effectiveDir = config.workingDir ?? workspacePath;

    await RunService.instance.start(
      sessionId: sessionId,
      configId: config.id,
      command: config.command,
      workingDir: effectiveDir,
      env: config.env,
      onOutput: (line, isError) => _appendOutput(sessionId, line, isError),
      onExit: (code) => _onExit(sessionId, code),
    );
    return session;
  }

  Future<RunSession?> restartSession(String sessionId) async {
    RunSession? existing;
    for (final session in state.sessions) {
      if (session.id == sessionId) {
        existing = session;
        break;
      }
    }
    if (existing == null) return null;

    RunService.instance.stop(sessionId);

    final workspacePath = state.workspacePath ?? existing.workspacePath;
    final restarted = existing.copyWith(
      status: RunStatus.running,
      output: const [],
      clearExitCode: true,
      startedAt: DateTime.now(),
      workspacePath: workspacePath,
    );

    final sessions =
        state.sessions.map((s) => s.id == sessionId ? restarted : s).toList();
    emit(state.copyWith(sessions: sessions, activeSessionId: sessionId));
    _persistSessions();

    final effectiveDir = restarted.config.workingDir ?? workspacePath;
    await RunService.instance.start(
      sessionId: restarted.id,
      configId: restarted.config.id,
      command: restarted.config.command,
      workingDir: effectiveDir,
      env: restarted.config.env,
      onOutput: (line, isError) => _appendOutput(restarted.id, line, isError),
      onExit: (code) => _onExit(restarted.id, code),
    );
    return restarted;
  }

  void stopRun(String sessionId) {
    RunService.instance.stop(sessionId);
    _updateSession(sessionId, (s) => s.copyWith(status: RunStatus.stopped));
    _persistSessions();
  }

  void sendHotReload(String sessionId) {
    RunService.instance.sendStdin(sessionId, 'r');
  }

  void sendHotRestart(String sessionId) {
    RunService.instance.sendStdin(sessionId, 'R');
  }

  void sendInput(String sessionId, String text) {
    if (text.isEmpty) return;
    RunService.instance.sendStdin(sessionId, text);
  }

  void triggerQuickAction(String sessionId, RunQuickAction action) {
    if (action.command.trim().isEmpty) return;
    final payload =
        action.appendNewline ? '${action.command}\n' : action.command;
    RunService.instance.sendStdin(sessionId, payload);
  }

  void clearOutput(String sessionId) {
    _updateSession(sessionId, (s) => s.copyWith(output: []));
    _persistSessions();
  }

  void setActiveSession(String sessionId) {
    emit(state.copyWith(activeSessionId: sessionId));
  }

  void attachSession(String sessionId) {
    final exists = state.sessions.any((session) => session.id == sessionId);
    if (!exists) return;
    emit(state.copyWith(activeSessionId: sessionId));
  }

  void detachSession(String sessionId) {
    if (state.activeSessionId != sessionId) return;
    emit(state.copyWith(clearActiveSession: true));
  }

  void removeSession(String sessionId) {
    RunService.instance.stop(sessionId);
    final sessions = state.sessions.where((s) => s.id != sessionId).toList();
    final activeId =
        state.activeSessionId == sessionId
            ? sessions.lastOrNull?.id
            : state.activeSessionId;
    emit(
      state.copyWith(
        sessions: sessions,
        activeSessionId: activeId,
        clearActiveSession: activeId == null,
      ),
    );
    _persistSessions();
  }

  Future<RunConfig> addConfig(RunConfig config) async {
    final existing = _findEquivalentConfig(config);
    if (existing != null) {
      return existing;
    }
    final configs = [...state.configs, config];
    await RunConfigStorage.instance.save(state.workspacePath ?? '', configs);
    emit(state.copyWith(configs: configs));
    return config;
  }

  Future<void> ensureGroupInitialized(String group) async {
    final normalizedGroup = group.trim();
    if (normalizedGroup.isEmpty) return;
    if (state.configs.any((config) => config.group == normalizedGroup)) return;
    final workspacePath = state.workspacePath;
    if (workspacePath == null || workspacePath.trim().isEmpty) return;
    if (!await _isFlutterProject(workspacePath)) return;

    final suffix = _groupIdSuffix(normalizedGroup);
    final presets = [
      RunConfig.flutterRunMacos(
        workspacePath,
        group: normalizedGroup,
      ).copyWith(id: 'preset_flutter_run_macos_$suffix'),
      RunConfig.flutterTest(group: normalizedGroup).copyWith(
        id: 'preset_flutter_test_$suffix',
      ),
      RunConfig.flutterBuildMacos(group: normalizedGroup).copyWith(
        id: 'preset_flutter_build_macos_$suffix',
      ),
    ];

    final configs = [...state.configs];
    for (final preset in presets) {
      if (_findEquivalentConfig(preset) != null) continue;
      configs.add(preset);
    }
    if (configs.length == state.configs.length) return;
    await RunConfigStorage.instance.save(workspacePath, configs);
    emit(state.copyWith(configs: configs));
  }

  Future<void> updateConfig(RunConfig config) async {
    final configs =
        state.configs.map((c) => c.id == config.id ? config : c).toList();
    await RunConfigStorage.instance.save(state.workspacePath ?? '', configs);
    emit(state.copyWith(configs: configs));
  }

  Future<void> removeConfig(String id) async {
    final configs = state.configs.where((c) => c.id != id).toList();
    await RunConfigStorage.instance.save(state.workspacePath ?? '', configs);
    emit(state.copyWith(configs: configs));
  }

  void _appendOutput(String sessionId, String line, bool isError) {
    _updateSession(sessionId, (s) {
      final lines = [
        ...s.output,
        RunOutputLine(text: line, isError: isError, timestamp: DateTime.now()),
      ];
      return s.copyWith(
        output:
            lines.length > _maxOutputLines
                ? lines.sublist(lines.length - _maxOutputLines)
                : lines,
      );
    });
  }

  void _onExit(String sessionId, int code) {
    _appendOutput(sessionId, '\n[Process exited with code $code]', code != 0);
    _updateSession(
      sessionId,
      (s) => s.copyWith(
        status: code == 0 ? RunStatus.stopped : RunStatus.failed,
        exitCode: code,
      ),
    );
    _persistSessions();
  }

  void _updateSession(
    String sessionId,
    RunSession Function(RunSession) updater,
  ) {
    final sessions =
        state.sessions.map((s) => s.id == sessionId ? updater(s) : s).toList();
    emit(state.copyWith(sessions: sessions));
  }

  void _persistSessions() {
    final path = state.workspacePath;
    if (path == null) return;
    RunSessionStorage.instance.save(path, state.sessions);
  }

  RunConfig? _findEquivalentConfig(RunConfig candidate) {
    final key = _configSignature(candidate);
    for (final config in state.configs) {
      if (_configSignature(config) == key) return config;
    }
    return null;
  }

  List<RunConfig> _dedupeConfigs(List<RunConfig> configs) {
    final bySignature = <String, RunConfig>{};
    for (final config in configs) {
      final key = _configSignature(config);
      bySignature.putIfAbsent(key, () => config);
    }
    return bySignature.values.toList();
  }

  String _configSignature(RunConfig config) {
    final normalizedDir = (config.workingDir ?? '').trim();
    final normalizedGroup = config.group.trim().toLowerCase();
    return '${config.name.trim().toLowerCase()}|${config.command.trim().toLowerCase()}|$normalizedDir|$normalizedGroup';
  }

  String _groupIdSuffix(String group) {
    final cleaned = group.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return cleaned.isEmpty ? 'group' : cleaned;
  }

  bool _sameConfigs(List<RunConfig> a, List<RunConfig> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
