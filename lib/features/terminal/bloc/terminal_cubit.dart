import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:yoloit/core/services/agent_hook_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/skills/data/skills_install_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';
import 'package:yoloit/features/terminal/data/pty_service.dart';
import 'package:yoloit/features/terminal/data/session_persistence_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_pty_config.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/data/agent_workspace_dir_service.dart';
import 'package:yoloit/features/workspaces/data/workspace_secrets_service.dart';

class TerminalCubit extends Cubit<TerminalState> {
  TerminalCubit() : super(const TerminalInitial());

  final _ptyService = PtyService.instance;
  final _persistence = SessionPersistenceService.instance;
  final _logging = LoggingService.instance;
  final _tmux = TmuxService.instance;

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

  /// Emits a TerminalLoaded with both visible (workspace) sessions and allSessions.
  void _emitLoaded(List<AgentSession> visible, int activeIndex) {
    emit(TerminalLoaded(
      sessions: visible,
      activeIndex: activeIndex,
      allSessions: List.unmodifiable(_allSessions),
    ));
  }

  /// Initialises services (no sessions loaded yet — call setActiveWorkspace).
  Future<void> initialize() async {
    await Future.wait([
      _logging.init(),
      _tmux.init(),
      AgentConfigService.instance.load(), // pre-load agent configs + default
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
          emit(cur.copyWith(
              sessions: _workspaceSessions,
              allSessions: List.unmodifiable(_allSessions)));
        }
      }
    });
    AgentHookService.instance.start();
    _hookSub = AgentHookService.instance.events.listen(_onHookEvent);
  }

  /// Loads persisted session metadata for other (non-active) workspaces so
  /// the mindmap view can render them as idle cards without spawning PTYs.
  /// Existing sessions are preserved; new stubs get status=idle.
  Future<void> loadPersistedMetadataForWorkspaces(List<String> workspaceIds) async {
    var added = false;
    final existingIds = _allSessions.map((s) => s.id).toSet();
    for (final wsId in workspaceIds) {
      if (wsId == _activeWorkspaceId) continue;
      final saved = await _persistence.load(wsId);
      for (final s in saved) {
        if (existingIds.contains(s.id)) continue;
        _allSessions.add(AgentSession(
          id: s.id,
          type: s.type,
          workspacePath: s.workspacePath,
          workspaceId: s.workspaceId ?? wsId,
          status: AgentStatus.idle,
        ));
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
      final savedIdx = (_activeIndexPerWorkspace[workspaceId] ?? 0)
          .clamp(0, running.length - 1);
      _emitLoaded(running, savedIdx);
      return;
    }

    _emitLoaded([], 0);

    // Restore persisted sessions for this workspace.
    final saved = await _persistence.load(workspaceId);
    final allWsPaths = workspacePaths ?? [workspacePath];
    if (saved.isNotEmpty) {
      for (var i = 0; i < saved.length; i++) {
        if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 200));
        final s = saved[i];

        // Recover worktreeContexts from symlinks if not persisted (old format).
        var worktreeContexts = s.worktreeContexts;
        if (worktreeContexts == null) {
          worktreeContexts = await AgentWorkspaceDirService.instance
              .readWorktreeContexts(
                  s.workspaceId ?? workspaceId, s.id, allWsPaths);
        }

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
      final defaultType = AgentConfigService.instance.defaultAgentType;
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
    Map<String, String>? worktreeContexts,
    List<String> enabledSkills = const [],
    String? customName,
  }) async {
    if (state is! TerminalLoaded) return;

    final sessionId =
        savedSessionId ?? '${type.name}_${DateTime.now().millisecondsSinceEpoch}';

    String effectivePath = workspacePath;
    if (worktreeContexts != null && workspaceId != null) {
      effectivePath = await AgentWorkspaceDirService.instance
          .createAgentDir(workspaceId, sessionId, worktreeContexts);
      if (enabledSkills.isNotEmpty) {
        unawaited(SkillsInstallService.instance.syncSessionSkills(
          sessionDir: effectivePath,
          enabledSkillIds: enabledSkills,
        ));
      }
    }

    final session = AgentSession(
      id: sessionId,
      type: type,
      workspacePath: effectivePath,
      workspaceId: workspaceId,
      status: AgentStatus.live,
      sessionId: _generateSessionId(),
      worktreeContexts: worktreeContexts,
      customName: customName,
    );

    final secrets = workspaceId != null
        ? await WorkspaceSecretsService.instance.load(workspaceId)
        : <String, String>{};
    final extraEnv = secrets.isEmpty ? null : secrets;

    final Pty pty;
    if (_tmux.isActive) {
      pty = _ptyService.launchTmux(
        sessionId: sessionId,
        label: type.displayName,
        workspacePath: effectivePath,
        tmuxLauncher: _tmux.launch,
        extraEnv: extraEnv,
      );
    } else {
      pty = _ptyService.launch(
        sessionId: sessionId,
        label: type.displayName,
        workspacePath: effectivePath,
        extraEnv: extraEnv,
      );
    }

    unawaited(_logging.startSession(sessionId, '${type.displayName} @ $effectivePath'));
    _attachPtyToSession(pty, session);

    // Install YoLoIT hooks into the workspace so Copilot CLI can pick them up.
    unawaited(AgentHookService.installHooks(effectivePath));

    // Remove any idle metadata stub with the same id (from loadPersistedMetadata).
    _allSessions.removeWhere((s) => s.id == sessionId);
    _allSessions.add(session);
    final visible = _workspaceSessions;
    _emitLoaded(visible, visible.length - 1);

    final effectiveWorkspaceId = workspaceId ?? _activeWorkspaceId;
    if (effectiveWorkspaceId != null) {
      unawaited(_persistence.save(
        _allSessions.where((s) => s.workspaceId == effectiveWorkspaceId).toList(),
        effectiveWorkspaceId,
      ));
    }

    // Auto-run agent command (skip for plain terminal and when restoring tmux session).
    final effectiveCommand = AgentConfigService.instance.effectiveLaunchCommand(type);
    if (effectiveCommand.isNotEmpty && !(isRestore && _tmux.isActive)) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      _ptyService.write(sessionId, '$effectiveCommand\n');
    }
  }

  void switchTab(int index) {
    final current = _loaded;
    if (current == null) return;
    if (index < 0 || index >= current.sessions.length) return;
    emit(current.copyWith(activeIndex: index, allSessions: List.unmodifiable(_allSessions)));
    if (_activeWorkspaceId != null) {
      _activeIndexPerWorkspace[_activeWorkspaceId!] = index;
    }
    unawaited(SessionPrefs.saveActiveTerminalIdx(index));
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
  AgentSession? updateSessionWorktree(String sessionId, String repoPath, String newWorktreePath) {
    final idx = _allSessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return null;
    final old = _allSessions[idx];
    final updatedContexts = Map<String, String>.from(old.worktreeContexts ?? {});
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

    _ptyService.kill(
      sessionId,
      onKillTmux: _tmux.isActive ? _tmux.killSession : null,
    );
    unawaited(_logging.endSession(sessionId));

    // Delete the agent dir if one was created (session had worktree contexts).
    if (session.worktreeContexts != null && session.workspaceId != null) {
      unawaited(
        AgentWorkspaceDirService.instance.deleteAgentDir(session.workspaceId!, sessionId),
      );
    }

    _allSessions.removeWhere((s) => s.id == sessionId);
    final visible = _workspaceSessions;
    final newIndex = visible.isEmpty ? 0 : current.activeIndex.clamp(0, visible.length - 1);
    _emitLoaded(visible, newIndex);
    final wsId = _activeWorkspaceId;
    if (wsId != null) unawaited(_persistence.save(visible, wsId));
  }

  void resizeActiveTerminal(int columns, int rows) {
    final current = _loaded;
    if (current == null) return;
    final active = current.activeSession;
    if (active == null) return;
    _ptyService.resize(active.id, columns, rows);
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
    _allSessions[i] = _allSessions[i].copyWith(hookPhase: const ThinkingPhase());
    final cur = _loaded;
    if (cur != null && !isClosed) {
      emit(cur.copyWith(
          sessions: _workspaceSessions,
          allSessions: List.unmodifiable(_allSessions)));
    }
  }

  void _onHookEvent(HookEvent event) {
    debugPrint('[HookEvent] event=${event.event} phase=${event.phase} cwd=${event.workspacePath}');

    // Match the event's workspace path to a session with the same workspacePath.
    final idx = _allSessions.indexWhere(
      (s) => s.workspacePath == event.workspacePath,
    );
    if (idx < 0) {
      debugPrint('[HookEvent] NO MATCH for cwd=${event.workspacePath}  '
          'sessions: ${_allSessions.map((s) => s.workspacePath).toList()}');
      return;
    }

    // sessionStart → phase is null, already handled by AgentStatus.live.
    final newPhase = event.phase; // AgentPhase? — null means clear

    debugPrint('[HookEvent] MATCHED session[${_allSessions[idx].id}] → newPhase=$newPhase');

    // ThinkingPhase auto-clears after 15s if no other event fires.
    // PTY idle-timer (5s) will usually clear it sooner via spinner detection.
    if (newPhase is ThinkingPhase) {
      Future.delayed(const Duration(seconds: 15), () {
        final i = _allSessions.indexWhere((s) => s.workspacePath == event.workspacePath);
        if (i >= 0 && _allSessions[i].hookPhase is ThinkingPhase) {
          _allSessions[i] = _allSessions[i].copyWith(clearHookPhase: true);
          final cur = _loaded;
          if (cur != null && !isClosed) {
            final visible = _workspaceSessions;
            emit(cur.copyWith(sessions: visible, allSessions: List.unmodifiable(_allSessions)));
          }
        }
      });
    }

    // DonePhase auto-clears after 3s (brief green flash).
    if (newPhase is DonePhase) {
      Future.delayed(const Duration(seconds: 3), () {
        final i = _allSessions.indexWhere((s) => s.workspacePath == event.workspacePath);
        if (i >= 0 && _allSessions[i].hookPhase is DonePhase) {
          _allSessions[i] = _allSessions[i].copyWith(clearHookPhase: true);
          final cur = _loaded;
          if (cur != null && !isClosed) {
            final visible = _workspaceSessions;
            emit(cur.copyWith(sessions: visible, allSessions: List.unmodifiable(_allSessions)));
          }
        }
      });
    }

    _allSessions[idx] = _allSessions[idx].copyWith(
      hookPhase: newPhase,
      // Don't clear AwaitingApprovalPhase via postToolUse (newPhase == null):
      // it must persist until the user explicitly responds in the terminal.
      // It will be cleared when: userPromptSubmitted fires (new user request)
      // or explicitly via another hook event with a non-null phase.
      clearHookPhase: newPhase == null &&
          _allSessions[idx].hookPhase is! AwaitingApprovalPhase,
    );

    final cur = _loaded;
    if (cur != null && !isClosed) {
      final visible = _workspaceSessions;
      emit(cur.copyWith(sessions: visible, allSessions: List.unmodifiable(_allSessions)));
    }
  }

  void _attachPtyToSession(Pty pty, AgentSession session) {
    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (data) {
            session.terminal.write(data);
            _logging.write(session.id, data);
            session.appendOutput(data); // capture for browser streaming

            // ── PTY activity detection (backup when hooks don't fire) ──────
            final ptyConfig = session.type.ptyConfig;
            if (ptyConfig.hasDetection) {
              _onPtyActivity(session, data, ptyConfig);
            }

            // Done-prompt detection is now handled inside _onPtyActivity via config.
          },
          onDone: () => _onSessionDone(session.id),
          // ignore: avoid_types_on_closure_parameters
          onError: (Object e) => _onSessionDone(session.id),
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
    emit(current.copyWith(sessions: visible, allSessions: List.unmodifiable(_allSessions)));

    // Play completion sound (interactive mode micro-completion).
    SessionPrefs.isCompletionSoundEnabled().then((enabled) {
      if (enabled) Process.run('afplay', ['/System/Library/Sounds/Glass.aiff']);
    });

    Future.delayed(const Duration(seconds: 3), () {
      final i2 = _allSessions.indexWhere((s) => s.id == sessionId);
      if (i2 >= 0 && _allSessions[i2].hookPhase is DonePhase) {
        _allSessions[i2] = _allSessions[i2].copyWith(clearHookPhase: true);
        final cur = _loaded;
        if (cur != null && !isClosed) {
          emit(cur.copyWith(sessions: _workspaceSessions, allSessions: List.unmodifiable(_allSessions)));
        }
      }
    });
  }

  /// Called on every PTY output chunk for sessions with [AgentPtyConfig].
  /// Uses per-agent config to detect spinner (→ ThinkingPhase),
  /// done-prompts (→ DonePhase + sound), and approval dialogs
  /// (→ AwaitingApprovalPhase + urgent sound).
  void _onPtyActivity(AgentSession session, String data, AgentPtyConfig config) {
    final sessionId = session.id;

    // Always look up CURRENT session state — the captured `session` is stale.
    final i = _allSessions.indexWhere((s) => s.id == sessionId);
    if (i < 0) return;
    final current = _allSessions[i];

    // Maintain a rolling tail buffer so patterns split across chunks are caught.
    final buf = _ptyTailBuffers.putIfAbsent(sessionId, StringBuffer.new)
      ..write(data);
    final tail = buf.toString();
    if (tail.length > _ptyTailMaxLen) {
      final trimmed = tail.substring(tail.length - _ptyTailMaxLen);
      buf.clear();
      buf.write(trimmed);
    }
    // Use the tail for approval detection; raw data still used for spinner/done.
    final checkData = buf.toString();

    // Approval dialog detected → AwaitingApprovalPhase + urgent sound.
    if (config.containsApproval(checkData) &&
        current.hookPhase is! AwaitingApprovalPhase) {
      _ptyIdleTimers[sessionId]?.cancel();
      _allSessions[i] = current.copyWith(
          hookPhase: const AwaitingApprovalPhase());
      final cur = _loaded;
      if (cur != null && !isClosed) {
        emit(cur.copyWith(
            sessions: _workspaceSessions,
            allSessions: List.unmodifiable(_allSessions)));
      }
      // Urgent sound — different from completion sound.
      SessionPrefs.isApprovalSoundEnabled().then((enabled) {
        if (enabled) Process.run('afplay', ['/System/Library/Sounds/Sosumi.aiff']);
      });
    }

    // If already awaiting approval, restart the fallback clear timer on every
    // PTY chunk — approval pattern keeps resetting it while dialog is visible;
    // once the dialog is dismissed PTY data stops matching and the timer fires.
    if (current.hookPhase is AwaitingApprovalPhase ||
        config.containsApproval(checkData)) {
      _approvalClearTimers[sessionId]?.cancel();
      _approvalClearTimers[sessionId] = Timer(const Duration(seconds: 15), () {
        _approvalClearTimers.remove(sessionId);
        _ptyTailBuffers[sessionId]?.clear(); // reset buffer after dialog gone
        final j = _allSessions.indexWhere((s) => s.id == sessionId);
        if (j >= 0 && _allSessions[j].hookPhase is AwaitingApprovalPhase) {
          _allSessions[j] = _allSessions[j].copyWith(clearHookPhase: true);
          final cur = _loaded;
          if (cur != null && !isClosed) {
            emit(cur.copyWith(
                sessions: _workspaceSessions,
                allSessions: List.unmodifiable(_allSessions)));
          }
        }
      });
      if (config.containsApproval(checkData)) return;
    }

    // Done-prompt detected while thinking → transition to done.
    if (current.hookPhase is ThinkingPhase &&
        config.containsDonePrompt(data)) {
      _onCopilotPromptDetected(sessionId);
      return;
    }

    if (!config.containsSpinner(data)) return;

    // Reset idle timer — clear phase when PTY goes quiet.
    _ptyIdleTimers[sessionId]?.cancel();
    _ptyIdleTimers[sessionId] = Timer(config.idleTimeout, () {
      _ptyIdleTimers.remove(sessionId);
      final j = _allSessions.indexWhere((s) => s.id == sessionId);
      if (j >= 0 && _allSessions[j].hookPhase is ThinkingPhase) {
        _allSessions[j] = _allSessions[j].copyWith(clearHookPhase: true);
        final cur = _loaded;
        if (cur != null && !isClosed) {
          emit(cur.copyWith(sessions: _workspaceSessions, allSessions: List.unmodifiable(_allSessions)));
        }
      }
    });

    // Only set ThinkingPhase if no hook phase is already active.
    if (current.hookPhase != null) return;

    _allSessions[i] = current.copyWith(hookPhase: const ThinkingPhase());
    final cur = _loaded;
    if (cur != null && !isClosed) {
      emit(cur.copyWith(sessions: _workspaceSessions, allSessions: List.unmodifiable(_allSessions)));
    }
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
    if (!isClosed) emit(current.copyWith(sessions: visible, allSessions: List.unmodifiable(_allSessions)));
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
    AgentHookService.instance.stop();
    _ptyService.killAll();
    return super.close();
  }
}

// ignore_for_file: discarded_futures
void unawaited(Future<void> future) {}
