import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/services/agent_hook_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/skills/data/skills_install_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';
import 'package:yoloit/features/terminal/data/session_persistence_service.dart';
import 'package:yoloit/features/terminal/data/remote_yoloit_terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_pty_config.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';
import 'package:yoloit/features/workspaces/data/agent_workspace_dir_service.dart';
import 'package:yoloit/features/workspaces/data/workspace_secrets_service.dart';

class TerminalCubit extends Cubit<TerminalState> {
  TerminalCubit({
    TerminalBackendService? backendService,
    SessionPersistenceService? persistence,
    LoggingService? logging,
    TmuxService? tmux,
    AgentHookService? hookService,
    AgentConfigService? agentConfig,
    WorkspaceSecretsService? secretsService,
    AgentWorkspaceDirService? workspaceDirs,
    Future<void> Function(String workspacePath)? hookInstaller,
  }) : _backendService = backendService ?? TerminalBackendService.instance,
       _persistence = persistence ?? SessionPersistenceService.instance,
       _logging = logging ?? LoggingService.instance,
       _tmux = tmux ?? TmuxService.instance,
       _hookService = hookService ?? AgentHookService.instance,
       _agentConfig = agentConfig ?? AgentConfigService.instance,
       _secretsService = secretsService ?? WorkspaceSecretsService.instance,
       _workspaceDirs = workspaceDirs ?? AgentWorkspaceDirService.instance,
       _hookInstaller = hookInstaller ?? AgentHookService.installHooks,
       super(const TerminalInitial());

  final TerminalBackendService _backendService;
  final SessionPersistenceService _persistence;
  final LoggingService _logging;
  final TmuxService _tmux;
  final AgentHookService _hookService;
  final AgentConfigService _agentConfig;
  final WorkspaceSecretsService _secretsService;
  final AgentWorkspaceDirService _workspaceDirs;
  final Future<void> Function(String workspacePath) _hookInstaller;

  /// All sessions across all workspaces (PTYs kept alive when switching workspaces).
  final List<AgentSession> _allSessions = [];
  String? _activeWorkspaceId;

  /// Remembers the active tab index per workspace so switching back restores it.
  final Map<String, int> _activeIndexPerWorkspace = {};

  StreamSubscription<HookEvent>? _hookSub;

  /// Per-session idle timers: fire when PTY goes quiet → clear PTY-detected ThinkingPhase.
  final Map<String, Timer> _ptyIdleTimers = {};

  /// Fallback timers: clear AwaitingApprovalPhase if PTY stays quiet after
  /// the approval dialog was dismissed (i.e. no new approval pattern detected).
  final Map<String, Timer> _approvalClearTimers = {};

  /// Periodic cleanup: clears orphaned AwaitingApprovalPhase (e.g. after hot
  /// reload when in-memory timers are lost but bloc state persists).
  Timer? _approvalSweepTimer;

  /// Rolling tail buffer per session for PTY pattern detection across chunk
  /// boundaries. Holds the last 512 chars of raw PTY output.
  final Map<String, StringBuffer> _ptyTailBuffers = {};
  static const int _ptyTailMaxLen = 512;

  List<AgentSession> get _workspaceSessions =>
      _allSessions.where((s) => s.workspaceId == _activeWorkspaceId).toList();

  /// Re-emits the current state with the visible (workspace) sessions and the
  /// full session list, picking up in-place mutations of `_allSessions`.
  void _emitVisible() {
    final cur = _loaded;
    if (cur != null && !isClosed) {
      emit(
        cur.copyWith(
          sessions: _workspaceSessions,
          allSessions: List.unmodifiable(_allSessions),
        ),
      );
    }
  }

  /// Emits a TerminalLoaded with both visible (workspace) sessions and allSessions.
  void _emitLoaded(
    List<AgentSession> visible,
    int activeIndex, {
    bool requestOpenPanel = false,
  }) {
    emit(
      TerminalLoaded(
        sessions: visible,
        activeIndex: activeIndex,
        allSessions: List.unmodifiable(_allSessions),
        requestOpenPanel: requestOpenPanel,
      ),
    );
  }

  /// Initialises services (no sessions loaded yet — call setActiveWorkspace).
  Future<void> initialize() async {
    await Future.wait([
      _logging.init(),
      _tmux.init(),
      _agentConfig.load(), // pre-load agent configs + default
    ]);
    _emitLoaded([], 0);

    // Periodic sweep: clear any AwaitingApprovalPhase that has no running
    // timer (e.g. orphaned after hot reload). 30 s interval is generous enough
    // to not interfere with real dialogs that stream continuously.
    _approvalSweepTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      var changed = false;
      for (var i = 0; i < _allSessions.length; i++) {
        final s = _allSessions[i];
        if (s.hookPhase is AwaitingApprovalPhase &&
            !_approvalClearTimers.containsKey(s.id)) {
          _allSessions[i] = s.copyWith(clearHookPhase: true);
          changed = true;
        }
      }
      if (changed) {
        final cur = _loaded;
        if (cur != null && !isClosed) {
          _emitVisible();
        }
      }
    });
    _hookService.start();
    _hookSub = _hookService.events.listen(_onHookEvent);
  }

  /// Loads persisted session metadata for other (non-active) workspaces so
  /// the mindmap view can render them as idle cards without spawning PTYs.
  /// Existing sessions are preserved; new stubs get status=idle.
  Future<void> loadPersistedMetadataForWorkspaces(
    List<String> workspaceIds,
  ) async {
    var added = false;
    final existingIds = _allSessions.map((s) => s.id).toSet();
    for (final wsId in workspaceIds) {
      if (wsId == _activeWorkspaceId) continue;
      final saved = await _persistence.load(wsId);
      for (final s in saved) {
        if (existingIds.contains(s.id)) continue;
        _allSessions.add(
          AgentSession(
            id: s.id,
            type: s.type,
            workspacePath: s.workspacePath,
            workspaceId: s.workspaceId ?? wsId,
            status: AgentStatus.idle,
          ),
        );
        existingIds.add(s.id);
        added = true;
      }
    }
    if (added) {
      final cur = _loaded;
      if (cur != null) {
        _emitLoaded(cur.sessions, cur.activeIndex);
      } else {
        _emitLoaded(const [], 0);
      }
    }
  }

  /// Switch to a workspace: load its sessions or spawn a default terminal.
  Future<void> setActiveWorkspace({
    required String workspaceId,
    required String workspacePath,
    List<String>? workspacePaths,
  }) async {
    // Save current workspace's active index before switching
    final prevWsId = _activeWorkspaceId;
    final prevState = _loaded;
    if (prevWsId != null && prevState != null) {
      _activeIndexPerWorkspace[prevWsId] = prevState.activeIndex;
    }

    _activeWorkspaceId = workspaceId;

    // Show workspace sessions that are already running in memory.
    final running = _workspaceSessions;
    if (running.isNotEmpty) {
      final savedIdx = (_activeIndexPerWorkspace[workspaceId] ?? 0).clamp(
        0,
        running.length - 1,
      );
      _emitLoaded(running, savedIdx);
      return;
    }

    _emitLoaded([], 0);

    // Restore persisted sessions for this workspace.
    final saved = await _persistence.load(workspaceId);
    final allWsPaths = workspacePaths ?? [workspacePath];
    if (saved.isNotEmpty) {
      for (var i = 0; i < saved.length; i++) {
        if (i > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        final s = saved[i];

        // Recover worktreeContexts from symlinks if not persisted (old format).
        var worktreeContexts = s.worktreeContexts;
        worktreeContexts ??= await _workspaceDirs.readWorktreeContexts(
          s.workspaceId ?? workspaceId,
          s.id,
          allWsPaths,
        );

        await spawnSession(
          type: s.type,
          workspacePath: s.workspacePath,
          workspaceId: s.workspaceId ?? workspaceId,
          savedSessionId: s.id,
          isRestore: true,
          worktreeContexts: worktreeContexts,
          customName: s.customName,
        );
      }
    } else {
      // No saved sessions → spawn the user-configured default agent.
      final defaultType = _agentConfig.defaultAgentType;
      await spawnSession(
        type: defaultType,
        workspacePath: workspacePath,
        workspaceId: workspaceId,
      );
    }
  }

  Future<void> spawnSession({
    required AgentType type,
    required String workspacePath,
    String? workspaceId,
    String? savedSessionId,
    bool isRestore = false,
    bool requestOpenPanel = false,
    Map<String, String>? worktreeContexts,
    List<String> enabledSkills = const [],
    String? customName,
  }) async {
    if (state is! TerminalLoaded) return;

    final sessionId =
        savedSessionId ??
        '${type.name}_${DateTime.now().millisecondsSinceEpoch}';

    final effectivePath = await _prepareSessionDir(
      sessionId,
      workspacePath,
      workspaceId,
      worktreeContexts,
      enabledSkills,
    );

    final effectiveWorkspaceId = workspaceId ?? _activeWorkspaceId;

    final session = AgentSession(
      id: sessionId,
      type: type,
      workspacePath: effectivePath,
      workspaceId: effectiveWorkspaceId,
      status: AgentStatus.live,
      sessionId: _generateSessionId(),
      worktreeContexts: worktreeContexts,
      customName: customName,
    );

    final extraEnv = await _loadWorkspaceSecrets(effectiveWorkspaceId);

    final process = await _backendService.launch(
      sessionId: sessionId,
      label: type.displayName,
      workspacePath: effectivePath,
      extraEnv: extraEnv,
    );
    final backendMode = _backendService.modeFor(sessionId);
    final useTmux = backendMode == TerminalBackendMode.tmux;
    final attachedRuntime =
        backendMode == TerminalBackendMode.runtime && process.attachedExisting;

    unawaited(
      _logging.startSession(sessionId, '${type.displayName} @ $effectivePath'),
    );
    _attachProcessToSession(process, session);

    // Install YoLoIT hooks into the workspace so Copilot CLI can pick them up.
    unawaited(_hookInstaller(effectivePath));

    // Remove any idle metadata stub with the same id (from loadPersistedMetadata).
    _allSessions.removeWhere((s) => s.id == sessionId);
    _allSessions.add(session);
    final visible = _workspaceSessions;
    _emitLoaded(
      visible,
      visible.length - 1,
      requestOpenPanel: requestOpenPanel,
    );

    _persistWorkspaceSessions(effectiveWorkspaceId);

    // Auto-run agent command (skip for plain terminal and when restoring tmux session).
    await _autoRunAgentCommand(
      sessionId,
      type,
      skipAutoRun: isRestore && (useTmux || attachedRuntime),
    );
  }

  /// Creates the agent worktree dir when [worktreeContexts] are present and
  /// syncs enabled skills into it. Returns the effective workspace path.
  Future<String> _prepareSessionDir(
    String sessionId,
    String workspacePath,
    String? workspaceId,
    Map<String, String>? worktreeContexts,
    List<String> enabledSkills,
  ) async {
    var effectivePath = workspacePath;
    if (worktreeContexts != null && workspaceId != null) {
      effectivePath = await _workspaceDirs.createAgentDir(
        workspaceId,
        sessionId,
        worktreeContexts,
      );
      if (enabledSkills.isNotEmpty) {
        unawaited(
          SkillsInstallService.instance.syncSessionSkills(
            sessionDir: effectivePath,
            enabledSkillIds: enabledSkills,
          ),
        );
      }
    }
    return effectivePath;
  }

  /// Loads workspace secrets as extra env vars (null when none configured).
  Future<Map<String, String>?> _loadWorkspaceSecrets(
    String? workspaceId,
  ) async {
    final secrets = workspaceId != null
        ? await _secretsService.load(workspaceId)
        : <String, String>{};
    return secrets.isEmpty ? null : secrets;
  }

  void _persistWorkspaceSessions(String? workspaceId) {
    if (workspaceId == null) return;
    unawaited(
      _persistence.save(
        _allSessions.where((s) => s.workspaceId == workspaceId).toList(),
        workspaceId,
      ),
    );
  }

  /// Writes the agent's launch command into the session after a short delay,
  /// unless [skipAutoRun] (restored tmux/runtime session) or no command is
  /// configured (plain terminal).
  Future<void> _autoRunAgentCommand(
    String sessionId,
    AgentType type, {
    required bool skipAutoRun,
  }) async {
    final effectiveCommand = _agentConfig.effectiveLaunchCommand(type);
    if (effectiveCommand.isEmpty || skipAutoRun) return;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    _backendService.write(sessionId, '$effectiveCommand\n');
  }

  /// Spawns a plain shell on a remote YoLoIT device (used from mobile/browser).
  Future<void> createRemoteSession({
    required RemoteBoardInfo remoteInfo,
    required String cwd,
    String? name,
  }) async {
    if (state is! TerminalLoaded) return;

    final sessionId = 'remote_${DateTime.now().millisecondsSinceEpoch}';
    final session = AgentSession(
      id: sessionId,
      type: AgentType.terminal,
      workspacePath: cwd,
      workspaceId: null,
      status: AgentStatus.live,
      sessionId: _generateSessionId(),
      customName: name?.trim().isNotEmpty == true ? name!.trim() : 'Remote',
    );

    final process = await _backendService.launch(
      sessionId: sessionId,
      workspacePath: cwd,
      backendOverride: RemoteYoloitTerminalBackend(remoteInfo: remoteInfo),
    );
    _attachProcessToSession(process, session);
    _allSessions.removeWhere((s) => s.id == sessionId);
    _allSessions.add(session);
    final visible = _workspaceSessions;
    _emitLoaded(visible, visible.length - 1);
  }

  void switchTab(int index) {
    final current = _loaded;
    if (current == null) return;
    if (index < 0 || index >= current.sessions.length) return;
    emit(
      current.copyWith(
        activeIndex: index,
        allSessions: List.unmodifiable(_allSessions),
      ),
    );
    if (_activeWorkspaceId != null) {
      _activeIndexPerWorkspace[_activeWorkspaceId!] = index;
    }
    unawaited(SessionPrefs.saveActiveTerminalIdx(index));
  }

  void sendInput(String sessionId, String text) {
    _backendService.write(sessionId, text);
  }

  /// Switches the active session to the one with [sessionId].
  /// No-op if the session is not in the current workspace or already active.
  void setActiveSessionById(String sessionId) {
    final current = _loaded;
    if (current == null) return;
    final idx = current.sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1 || idx == current.activeIndex) return;
    switchTab(idx);
  }

  void renameSession(String sessionId, String name) {
    final idx = _allSessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;
    _allSessions[idx] = _allSessions[idx].copyWith(
      customName: name.trim().isEmpty ? null : name.trim(),
      clearCustomName: name.trim().isEmpty,
    );
    final visible = _workspaceSessions;
    final current = _loaded;
    _emitLoaded(visible, current?.activeIndex ?? 0);
    final wsId = _activeWorkspaceId;
    if (wsId != null) unawaited(_persistence.save(visible, wsId));
  }

  /// Updates the worktree path for [repoPath] inside [sessionId].
  /// Returns the updated [AgentSession] so callers can react (e.g. reload file tree).
  AgentSession? updateSessionWorktree(
    String sessionId,
    String repoPath,
    String newWorktreePath,
  ) {
    final idx = _allSessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return null;
    final old = _allSessions[idx];
    final updatedContexts = Map<String, String>.from(
      old.worktreeContexts ?? {},
    );
    updatedContexts[repoPath] = newWorktreePath;
    _allSessions[idx] = old.copyWith(worktreeContexts: updatedContexts);
    final visible = _workspaceSessions;
    final current = _loaded;
    _emitLoaded(visible, current?.activeIndex ?? 0);
    final wsId = _activeWorkspaceId;
    if (wsId != null) unawaited(_persistence.save(visible, wsId));
    return _allSessions[idx];
  }

  void closeSession(String sessionId) {
    final current = _loaded;
    if (current == null) return;

    // Find session before removing it (needed for cleanup).
    final session = _allSessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => AgentSession(
        id: sessionId,
        type: AgentType.claude,
        workspacePath: '',
        status: AgentStatus.live,
        sessionId: '',
      ),
    );

    _backendService.kill(sessionId);
    unawaited(_logging.endSession(sessionId));

    // Delete the agent dir if one was created (session had worktree contexts).
    if (session.worktreeContexts != null && session.workspaceId != null) {
      unawaited(_workspaceDirs.deleteAgentDir(session.workspaceId!, sessionId));
    }

    _allSessions.removeWhere((s) => s.id == sessionId);
    final visible = _workspaceSessions;
    final newIndex = visible.isEmpty
        ? 0
        : current.activeIndex.clamp(0, visible.length - 1);
    _emitLoaded(visible, newIndex);
    final wsId = _activeWorkspaceId;
    if (wsId != null) unawaited(_persistence.save(visible, wsId));
  }

  void resizeActiveTerminal(int columns, int rows) {
    final current = _loaded;
    if (current == null) return;
    final active = current.activeSession;
    if (active == null) return;
    _backendService.resize(active.id, columns, rows);
  }

  /// Called when the user presses plain Enter in the terminal (not Shift+Enter).
  /// If the session is awaiting approval/confirmation, immediately transitions
  /// to ThinkingPhase so the UI responds without waiting for PTY spinner output.
  void onTerminalEnterPressed(String sessionId) {
    final i = _allSessions.indexWhere((s) => s.id == sessionId);
    if (i < 0) return;
    if (_allSessions[i].hookPhase is! AwaitingApprovalPhase) return;
    _approvalClearTimers[sessionId]?.cancel();
    _approvalClearTimers.remove(sessionId);
    _ptyTailBuffers[sessionId]?.clear();
    _allSessions[i] = _allSessions[i].copyWith(
      hookPhase: const ThinkingPhase(),
    );
    final cur = _loaded;
    if (cur != null && !isClosed) {
      _emitVisible();
    }
  }

  void _onHookEvent(HookEvent event) {
    assert(() {
      debugPrint(
        '[HookEvent] event=${event.event} phase=${event.phase} cwd=${event.workspacePath}',
      );
      return true;
    }());

    final idx = _findSessionIndexForWorkspacePath(event.workspacePath);
    if (idx < 0) {
      if (_allSessions.isEmpty) return;
      assert(() {
        debugPrint(
          '[HookEvent] NO MATCH for cwd=${event.workspacePath}  '
          'sessions: ${_allSessions.map((s) => s.workspacePath).toList()}',
        );
        return true;
      }());
      return;
    }

    // sessionStart → phase is null, already handled by AgentStatus.live.
    final newPhase = event.phase; // AgentPhase? — null means clear

    assert(() {
      debugPrint(
        '[HookEvent] MATCHED session[${_allSessions[idx].id}] → newPhase=$newPhase',
      );
      return true;
    }());

    // ThinkingPhase auto-clears after 15s if no other event fires.
    // PTY idle-timer (5s) will usually clear it sooner via spinner detection.
    if (newPhase is ThinkingPhase) {
      _schedulePhaseClear(
        event.workspacePath,
        ThinkingPhase,
        const Duration(seconds: 15),
      );
    }

    // DonePhase auto-clears after 3s (brief green flash).
    if (newPhase is DonePhase) {
      _schedulePhaseClear(
        event.workspacePath,
        DonePhase,
        const Duration(seconds: 3),
      );
    }

    _allSessions[idx] = _allSessions[idx].copyWith(
      hookPhase: newPhase,
      // Don't clear AwaitingApprovalPhase via postToolUse (newPhase == null):
      // it must persist until the user explicitly responds in the terminal.
      // It will be cleared when: userPromptSubmitted fires (new user request)
      // or explicitly via another hook event with a non-null phase.
      clearHookPhase:
          newPhase == null &&
          _allSessions[idx].hookPhase is! AwaitingApprovalPhase,
    );

    final cur = _loaded;
    if (cur != null && !isClosed) {
      final visible = _workspaceSessions;
      emit(
        cur.copyWith(
          sessions: visible,
          allSessions: List.unmodifiable(_allSessions),
        ),
      );
    }
  }

  int _findSessionIndexForWorkspacePath(String workspacePath) {
    final eventPath = _normalizeWorkspacePath(workspacePath);
    if (eventPath.isEmpty) return -1;

    final exact = _allSessions.indexWhere(
      (s) => _normalizeWorkspacePath(s.workspacePath) == eventPath,
    );
    if (exact >= 0) return exact;

    return _allSessions.indexWhere((s) {
      final sessionPath = _normalizeWorkspacePath(s.workspacePath);
      return eventPath.startsWith('$sessionPath/') ||
          sessionPath.startsWith('$eventPath/');
    });
  }

  String _normalizeWorkspacePath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty) return normalized;
    normalized = normalized.replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  void _schedulePhaseClear(
    String workspacePath,
    Type phaseType,
    Duration delay,
  ) {
    Future.delayed(delay, () {
      final i = _findSessionIndexForWorkspacePath(workspacePath);
      if (i >= 0 && _allSessions[i].hookPhase.runtimeType == phaseType) {
        _allSessions[i] = _allSessions[i].copyWith(clearHookPhase: true);
        final cur = _loaded;
        if (cur != null && !isClosed) {
          final visible = _workspaceSessions;
          emit(
            cur.copyWith(
              sessions: visible,
              allSessions: List.unmodifiable(_allSessions),
            ),
          );
        }
      }
    });
  }

  /// Batched output buffer per session to avoid flooding the xterm
  /// [notifyListeners] bridge on every PTY chunk.  When a runner dumps
  /// thousands of lines per second, each [Terminal.write] triggers a full
  /// UI rebuild; batching reduces that to ~20 rebuilds/sec.
  ///
  /// Chunks are kept as a List<String> of the ORIGINAL chunk references with
  /// a running byte counter — a StringBuffer would copy every byte in and
  /// then copy the whole 16 KB batch out again on toString().
  final Map<String, List<String>> _batchedOutput = {};
  // Byte-path twin of [_batchedOutput]: raw UTF-8 chunks when the process
  // exposes [TerminalProcess.outputBytes]. A session uses exactly one of the
  // two buffers, picked at attach time.
  final Map<String, List<Uint8List>> _batchedByteOutput = {};
  final Map<String, int> _batchedOutputBytes = {};
  final Map<String, Timer> _batchFlushTimers = {};
  static const _batchFlushIntervalMs = 50;
  static const _batchMaxBytes = 16384;

  void _attachProcessToSession(TerminalProcess process, AgentSession session) {
    final sessionId = session.id;
    // Byte-level output is preferred when the backend offers it (see
    // Pty.outputBytes): chunks skip the per-KB UTF-8 decode on the UI
    // isolate and are flushed through Terminal.writeBytes, which decodes
    // incrementally itself. Exactly one of the two streams is listened —
    // they wrap the same single-subscription native stream.
    final byteStream = process.outputBytes;

    void flushStringBatch() {
      final chunks = _batchedOutput.remove(sessionId);
      _batchedOutputBytes.remove(sessionId);
      if (chunks == null || chunks.isEmpty) return;
      // Ordering is preserved exactly: chunks are written in arrival order.
      for (final chunk in chunks) {
        session.terminal.write(chunk);
        _logging.write(sessionId, chunk);
      }
      session.appendOutputChunks(chunks);
    }

    void flushByteBatch() {
      final chunks = _batchedByteOutput.remove(sessionId);
      _batchedOutputBytes.remove(sessionId);
      if (chunks == null || chunks.isEmpty) return;
      // Concatenate the batch into ONE buffer so writeBytes runs a single
      // decode+parse pass per flush instead of one per KB-sized PTY chunk.
      // The buffer is freshly allocated and never reused afterwards —
      // writeBytes may retain it when the flush ends mid UTF-8/escape
      // sequence.
      var total = 0;
      for (final chunk in chunks) {
        total += chunk.length;
      }
      final combined = Uint8List(total);
      var offset = 0;
      for (final chunk in chunks) {
        combined.setAll(offset, chunk);
        offset += chunk.length;
      }
      session.terminal.writeBytes(combined);
      // History, logging, and pattern detection all consume the SAME single
      // malformed-tolerant decode of the flush — the exact text the String
      // path would have produced from these bytes.
      final text = utf8.decode(combined, allowMalformed: true);
      _logging.write(sessionId, text);
      session.appendOutputChunks([text]);

      // PTY activity detection (backup when hooks don't fire). Runs once per
      // flush on the byte path (vs per chunk on the String path); the
      // rolling tail buffer keeps patterns split across flushes detectable.
      final ptyConfig = session.type.ptyConfig;
      if (ptyConfig.hasDetection) {
        _onPtyActivity(session, text, ptyConfig);
      }
    }

    void flushBatch() {
      // Only one of the two buffers is ever non-empty per session.
      flushStringBatch();
      flushByteBatch();
    }

    void scheduleFlush() {
      // Do not reset an already-scheduled flush: recreating the timer on
      // every chunk starves it under continuous output, so the flush ends
      // up running on every 16 KB (full terminal re-raster per flush)
      // instead of ~20 times/sec.
      _batchFlushTimers.putIfAbsent(
        sessionId,
        () => Timer(const Duration(milliseconds: _batchFlushIntervalMs), () {
          _batchFlushTimers.remove(sessionId);
          flushBatch();
        }),
      );
    }

    void handleDone() {
      _batchFlushTimers[sessionId]?.cancel();
      _batchFlushTimers.remove(sessionId);
      flushBatch();
      _onSessionDone(sessionId);
    }

    void handleError(Object e) {
      _batchFlushTimers[sessionId]?.cancel();
      _batchFlushTimers.remove(sessionId);
      flushBatch();
      _onSessionDone(sessionId);
    }

    if (byteStream != null) {
      byteStream.listen(
        (chunk) {
          // Accumulate into the chunk list (original references, no copying).
          final chunks =
              _batchedByteOutput.putIfAbsent(sessionId, () => <Uint8List>[]);
          chunks.add(chunk);
          final bytes = (_batchedOutputBytes[sessionId] ?? 0) + chunk.length;
          _batchedOutputBytes[sessionId] = bytes;

          // Flush immediately if the batch is large, otherwise schedule.
          if (bytes >= _batchMaxBytes) {
            _batchFlushTimers[sessionId]?.cancel();
            _batchFlushTimers.remove(sessionId);
            flushBatch();
          } else {
            scheduleFlush();
          }
        },
        onDone: handleDone,
        onError: handleError,
      );
      return;
    }

    process.output.listen(
      (data) {
        // Accumulate into the chunk list (original references, no copying).
        final chunks = _batchedOutput.putIfAbsent(sessionId, () => <String>[]);
        chunks.add(data);
        final bytes = (_batchedOutputBytes[sessionId] ?? 0) + data.length;
        _batchedOutputBytes[sessionId] = bytes;

        // Flush immediately if the batch is large, otherwise schedule.
        if (bytes >= _batchMaxBytes) {
          _batchFlushTimers[sessionId]?.cancel();
          _batchFlushTimers.remove(sessionId);
          flushBatch();
        } else {
          scheduleFlush();
        }

        // PTY activity detection (backup when hooks don't fire).
        // Use the *original* chunk so patterns aren't split across batches.
        final ptyConfig = session.type.ptyConfig;
        if (ptyConfig.hasDetection) {
          _onPtyActivity(session, data, ptyConfig);
        }
      },
      onDone: handleDone,
      onError: handleError,
    );
  }

  void _onCopilotPromptDetected(String sessionId) {
    final current = _loaded;
    if (current == null || isClosed) return;
    final i = _allSessions.indexWhere((s) => s.id == sessionId);
    if (i < 0) return;
    final phase = _allSessions[i].hookPhase;
    if (phase is! ThinkingPhase && phase is! AwaitingApprovalPhase) return;

    // Flash DonePhase briefly then clear.
    _allSessions[i] = _allSessions[i].copyWith(hookPhase: const DonePhase());
    final visible = _workspaceSessions;
    emit(
      current.copyWith(
        sessions: visible,
        allSessions: List.unmodifiable(_allSessions),
      ),
    );

    // Play completion sound (interactive mode micro-completion).
    _playCompletionSound();

    _scheduleDonePhaseClear(sessionId);
  }

  void _playCompletionSound() {
    SessionPrefs.isCompletionSoundEnabled().then((enabled) {
      if (enabled && Platform.isMacOS) {
        Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
      }
    });
  }

  void _scheduleDonePhaseClear(String sessionId) {
    Future.delayed(const Duration(seconds: 3), () {
      final i2 = _allSessions.indexWhere((s) => s.id == sessionId);
      if (i2 >= 0 && _allSessions[i2].hookPhase is DonePhase) {
        _allSessions[i2] = _allSessions[i2].copyWith(clearHookPhase: true);
        final cur = _loaded;
        if (cur != null && !isClosed) {
          _emitVisible();
        }
      }
    });
  }

  /// Called on every PTY output chunk for sessions with [AgentPtyConfig].
  /// Uses per-agent config to detect spinner (→ ThinkingPhase),
  /// done-prompts (→ DonePhase + sound), and approval dialogs
  /// (→ AwaitingApprovalPhase + urgent sound).
  void _onPtyActivity(
    AgentSession session,
    String data,
    AgentPtyConfig config,
  ) {
    final sessionId = session.id;

    // Always look up CURRENT session state — the captured `session` is stale.
    final i = _allSessions.indexWhere((s) => s.id == sessionId);
    if (i < 0) return;
    final current = _allSessions[i];

    // Use the tail for approval detection; raw data still used for spinner/done.
    final checkData = _appendPtyTail(sessionId, data);

    // Approval dialog detected → AwaitingApprovalPhase + urgent sound.
    if (_handleApprovalActivity(sessionId, i, current, checkData, config)) {
      return;
    }

    // Done-prompt detected while thinking → transition to done.
    if (current.hookPhase is ThinkingPhase && config.containsDonePrompt(data)) {
      _onCopilotPromptDetected(sessionId);
      return;
    }

    if (!config.containsSpinner(data)) return;

    // Reset idle timer — clear phase when PTY goes quiet.
    _restartPtyIdleTimer(sessionId, config);

    // Only set ThinkingPhase if no hook phase is already active.
    if (current.hookPhase != null) return;

    _allSessions[i] = current.copyWith(hookPhase: const ThinkingPhase());
    final cur = _loaded;
    if (cur != null && !isClosed) {
      _emitVisible();
    }
  }

  /// Maintains a rolling tail buffer so patterns split across chunks are
  /// caught. Returns the current tail contents.
  String _appendPtyTail(String sessionId, String data) {
    final buf = _ptyTailBuffers.putIfAbsent(sessionId, StringBuffer.new)
      ..write(data);
    final tail = buf.toString();
    if (tail.length <= _ptyTailMaxLen) {
      return tail;
    }
    final trimmed = tail.substring(tail.length - _ptyTailMaxLen);
    buf.clear();
    buf.write(trimmed);
    return trimmed;
  }

  /// Handles approval-dialog detection for one PTY activity chunk.
  /// Returns true when the chunk has been fully handled and the caller
  /// must stop processing it.
  bool _handleApprovalActivity(
    String sessionId,
    int i,
    AgentSession current,
    String checkData,
    AgentPtyConfig config,
  ) {
    // Approval dialog detected → AwaitingApprovalPhase + urgent sound.
    if (config.containsApproval(checkData) &&
        current.hookPhase is! AwaitingApprovalPhase) {
      _enterAwaitingApproval(sessionId, i, current);
    }

    // If already awaiting approval, restart the fallback clear timer on every
    // PTY chunk — approval pattern keeps resetting it while dialog is visible;
    // once the dialog is dismissed PTY data stops matching and the timer fires.
    if (current.hookPhase is AwaitingApprovalPhase ||
        config.containsApproval(checkData)) {
      _restartApprovalClearTimer(sessionId);
      if (config.containsApproval(checkData)) return true;
    }
    return false;
  }

  void _enterAwaitingApproval(String sessionId, int i, AgentSession current) {
    _ptyIdleTimers[sessionId]?.cancel();
    _allSessions[i] = current.copyWith(
      hookPhase: const AwaitingApprovalPhase(),
    );
    final cur = _loaded;
    if (cur != null && !isClosed) {
      _emitVisible();
    }
    // Urgent sound — different from completion sound.
    SessionPrefs.isApprovalSoundEnabled().then((enabled) {
      if (enabled && Platform.isMacOS) {
        Process.run('afplay', ['/System/Library/Sounds/Sosumi.aiff']);
      }
    });
  }

  void _restartApprovalClearTimer(String sessionId) {
    _approvalClearTimers[sessionId]?.cancel();
    _approvalClearTimers[sessionId] = Timer(const Duration(seconds: 15), () {
      _approvalClearTimers.remove(sessionId);
      _ptyTailBuffers[sessionId]?.clear(); // reset buffer after dialog gone
      final j = _allSessions.indexWhere((s) => s.id == sessionId);
      if (j >= 0 && _allSessions[j].hookPhase is AwaitingApprovalPhase) {
        _allSessions[j] = _allSessions[j].copyWith(clearHookPhase: true);
        final cur = _loaded;
        if (cur != null && !isClosed) {
          _emitVisible();
        }
      }
    });
  }

  /// Resets the idle timer — clears the phase when the PTY goes quiet.
  void _restartPtyIdleTimer(String sessionId, AgentPtyConfig config) {
    _ptyIdleTimers[sessionId]?.cancel();
    _ptyIdleTimers[sessionId] = Timer(config.idleTimeout, () {
      _ptyIdleTimers.remove(sessionId);
      final j = _allSessions.indexWhere((s) => s.id == sessionId);
      if (j >= 0 && _allSessions[j].hookPhase is ThinkingPhase) {
        _allSessions[j] = _allSessions[j].copyWith(clearHookPhase: true);
        final cur = _loaded;
        if (cur != null && !isClosed) {
          _emitVisible();
        }
      }
    });
  }

  void _onSessionDone(String sessionId) {
    final current = _loaded;
    if (current == null) return;
    // Update status in _allSessions
    final idx = _allSessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      _allSessions[idx] = _allSessions[idx].copyWith(status: AgentStatus.idle);
    }
    final visible = _workspaceSessions;
    if (!isClosed) {
      emit(
        current.copyWith(
          sessions: visible,
          allSessions: List.unmodifiable(_allSessions),
        ),
      );
    }
  }

  String _generateSessionId() {
    final now = DateTime.now();
    return '${_randomHex(8)}-${_randomHex(4)}-${_randomHex(2)}-${now.millisecondsSinceEpoch % 100}';
  }

  String _randomHex(int length) {
    const chars = '0123456789abcdef';
    final rand = DateTime.now().microsecondsSinceEpoch;
    return List.generate(length, (i) => chars[(rand >> (i * 4)) & 0xf]).join();
  }

  TerminalLoaded? get _loaded {
    final s = state;
    if (s is TerminalLoaded) return s;
    return null;
  }

  @override
  Future<void> close() {
    _hookSub?.cancel();
    _approvalSweepTimer?.cancel();
    for (final t in _ptyIdleTimers.values) {
      t.cancel();
    }
    _ptyIdleTimers.clear();
    for (final t in _approvalClearTimers.values) {
      t.cancel();
    }
    _approvalClearTimers.clear();
    for (final t in _batchFlushTimers.values) {
      t.cancel();
    }
    _batchFlushTimers.clear();
    _batchedOutput.clear();
    _batchedByteOutput.clear();
    _hookService.stop();
    // Local PTY sessions are owned by their backend. Runtime sessions are
    // intentionally left alive across app shutdowns.
    return super.close();
  }
}

// ignore_for_file: discarded_futures
void unawaited(Future<void> future) {}
