import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_history.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

class BoardTerminalPanelWidget extends StatefulWidget {
  const BoardTerminalPanelWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
    this.remoteInfo,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;
  final RemoteBoardInfo? remoteInfo;

  @override
  State<BoardTerminalPanelWidget> createState() =>
      _BoardTerminalPanelWidgetState();
}

class _BoardTerminalPanelWidgetState extends State<BoardTerminalPanelWidget> {
  final _manager = BoardTerminalSessionManager.instance;
  final _terminalKey = GlobalKey<TerminalWidgetState>();
  late BoardTerminalConfig _config;
  AgentSession? _session;
  bool _restoring = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _config = _readConfig(widget.panel.state);
    _manager.addListener(_onManagerChanged);
    _ensureConfiguredSession();
  }

  @override
  void didUpdateWidget(covariant BoardTerminalPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextConfig = _readConfig(widget.panel.state);
    if (nextConfig.sessionId != _config.sessionId ||
        nextConfig.sessionName != _config.sessionName ||
        nextConfig.workingDir != _config.workingDir ||
        nextConfig.envGroupIds.join('\u0000') !=
            _config.envGroupIds.join('\u0000')) {
      _config = nextConfig;
      _session =
          _config.sessionId.isEmpty
              ? null
              : _manager.sessionFor(_config.sessionId);
      _ensureConfiguredSession();
    }
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    super.dispose();
  }

  BoardTerminalConfig _readConfig(Map<String, dynamic> state) {
    final raw = state['config'];
    if (raw is Map) {
      return BoardTerminalConfig.fromJson(Map<String, dynamic>.from(raw));
    }
    return const BoardTerminalConfig(
      sessionId: '',
      sessionName: '',
      workingDir: '',
    );
  }

  Future<void> _ensureConfiguredSession() async {
    if (!_config.isConfigured || _restoring || _starting) return;
    if (_config.sessionId.isEmpty) {
      await _createConfiguredSession();
      return;
    }
    final existing = _manager.sessionFor(_config.sessionId);
    if (existing != null) {
      if (mounted) setState(() => _session = existing);
      return;
    }
    setState(() => _restoring = true);
    final restored = await _manager.ensureSession(
      _config,
      remoteInfo: widget.remoteInfo,
      metadata: _resourceMetadata(sessionName: _config.sessionName),
    );
    if (!mounted) return;
    setState(() {
      _session = restored;
      _restoring = false;
    });
  }

  Future<void> _createConfiguredSession() async {
    final workingDir = _config.workingDir.trim();
    if (workingDir.isEmpty) return;
    final sessionName =
        _config.sessionName.trim().isEmpty
            ? p.basename(workingDir)
            : _config.sessionName.trim();
    setState(() => _starting = true);
    late final AgentSession session;
    try {
      session = await _manager.createSession(
        sessionName: sessionName,
        workingDir: workingDir,
        envGroupIds: _config.envGroupIds,
        remoteInfo: widget.remoteInfo,
        metadata: _resourceMetadata(sessionName: sessionName),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start terminal: $error')),
      );
      return;
    }
    if (!mounted) return;
    final nextConfig = _config.copyWith(
      sessionId: session.id,
      sessionName: session.displayName,
      workingDir: workingDir,
    );
    context.read<BoardCubit>().updatePanelTitle(
      widget.panel.id,
      session.displayName,
    );
    setState(() {
      _config = nextConfig;
      _session = session;
      _starting = false;
    });
    widget.onUpdateState({
      ...widget.panel.state,
      'config': nextConfig.toJson(),
    });
  }

  void _onManagerChanged() {
    if (!mounted) return;
    final next =
        _config.sessionId.isEmpty
            ? null
            : _manager.sessionFor(_config.sessionId);
    if (!identical(next, _session)) {
      setState(() => _session = next);
    }
  }

  Future<void> _startSession(
    String workingDir,
    String sessionName,
    List<String> envGroupIds,
  ) async {
    final trimmedDir = workingDir.trim();
    if (trimmedDir.isEmpty) return;
    final trimmedName =
        sessionName.trim().isEmpty
            ? p.basename(trimmedDir)
            : sessionName.trim();
    setState(() => _starting = true);
    late final AgentSession session;
    try {
      session = await _manager.createSession(
        sessionName: trimmedName,
        workingDir: trimmedDir,
        envGroupIds: envGroupIds,
        remoteInfo: widget.remoteInfo,
        metadata: _resourceMetadata(
          sessionName: trimmedName,
          workingDirOverride: trimmedDir,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start terminal: $error')),
      );
      return;
    }
    if (!mounted) return;
    final nextConfig = BoardTerminalConfig(
      sessionId: session.id,
      sessionName: session.displayName,
      workingDir: trimmedDir,
      envGroupIds: envGroupIds,
    );
    context.read<BoardCubit>().updatePanelTitle(
      widget.panel.id,
      session.displayName,
    );
    setState(() {
      _config = nextConfig;
      _session = session;
      _starting = false;
    });
    widget.onUpdateState({
      ...widget.panel.state,
      'config': nextConfig.toJson(),
    });
  }

  Future<void> _restartSession() async {
    if (!_config.isConfigured) return;
    if (_config.sessionId.isEmpty) {
      await _createConfiguredSession();
      return;
    }
    setState(() => _restoring = true);
    final session = await _manager.ensureSession(
      _config,
      remoteInfo: widget.remoteInfo,
      metadata: _resourceMetadata(sessionName: _config.sessionName),
    );
    if (!mounted) return;
    setState(() {
      _session = session;
      _restoring = false;
    });
  }

  Future<void> _killCurrentSession() async {
    if (_config.sessionId.isEmpty) return;
    await _manager.killSession(_config.sessionId);
    if (!mounted) return;
    setState(() => _session = null);
  }

  ResourceSessionMetadata _resourceMetadata({
    required String sessionName,
    String? workingDirOverride,
  }) {
    final board = context.read<BoardCubit>().state.activeBoard;
    return ResourceSessionMetadata(
      kind: 'terminal',
      boardId: board?.id,
      boardName: board?.name,
      panelId: widget.panel.id,
      panelTitle:
          widget.panel.title.trim().isEmpty
              ? (sessionName.trim().isEmpty ? 'Terminal' : sessionName.trim())
              : widget.panel.title,
      panelType: widget.panel.type,
      workspacePath: (workingDirOverride ?? _config.workingDir).trim(),
      provider: 'terminal',
    );
  }

  void _showHistoryDialog() {
    showDialog<void>(
      context: context,
      builder:
          (_) => BoardTerminalSessionHistoryDialog(
            currentSessionId: _config.sessionId,
          ),
    );
  }

  void _openFullView() {
    if (_session == null) return;
    final termKey = GlobalKey<TerminalWidgetState>();
    final logs = <String>[];
    final logScroll = ScrollController();
    var forceAltScrollKeys = false;

    void addLog(String msg) {
      final now = DateTime.now().toIso8601String().substring(11, 23);
      logs.add('$now $msg');
      if (logs.length > 400) logs.removeAt(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!logScroll.hasClients) return;
        logScroll.jumpTo(logScroll.position.maxScrollExtent);
      });
    }

    String escapeForLog(String data) {
      return data
          .replaceAll('\x1B', r'\e')
          .replaceAll('\r', r'\r')
          .replaceAll('\n', r'\n')
          .replaceAll('\x02', r'\x02');
    }

    showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, dialogSetState) {
              final terminal = _session!.terminal;
              final state = termKey.currentState;
              final fontSize = state?.currentFontSize ?? 13.0;
              final debugState =
                  state?.debugStateSummary ??
                  'alt=${terminal.isUsingAltBuffer} '
                      'mouse=${terminal.mouseMode} '
                      'altScroll=${terminal.altBufferMouseScrollMode} '
                      'buf=${terminal.buffer.height} '
                      'lines=${terminal.lines.length}';

              void logAndRefresh(String msg) {
                dialogSetState(() => addLog(msg));
              }

              void send(String seq, String label) {
                logAndRefresh('send $label bytes="${escapeForLog(seq)}"');
                state?.writeToPty(seq);
              }

              return Dialog(
                insetPadding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 1000,
                  height: 800,
                  child: Column(
                    children: [
                      _BoardTerminalInfoBar(
                        config: _config,
                        onHistory: () {},
                        onKill: () {},
                        onEnvGroupsChanged: (_) {},
                      ),
                      Expanded(
                        flex: 3,
                        child: TerminalWidget(
                          key: termKey,
                          session: _session!,
                          isActive: true,
                          debugForceAltScrollKeyFallback: forceAltScrollKeys,
                          debugLabel:
                              'fullview:${widget.panel.id}:session:${_session!.id}',
                          debugLogSink:
                              (message) => logAndRefresh('scroll $message'),
                          terminalOutputWriter: (sessionId, data) {
                            logAndRefresh(
                              'pty[$sessionId] "${escapeForLog(data)}"',
                            );
                            TerminalBackendService.instance.write(
                              sessionId,
                              data,
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        color:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    debugState,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Dump terminal state',
                                  icon: const Icon(Icons.bug_report, size: 16),
                                  onPressed:
                                      () => logAndRefresh('state $debugState'),
                                ),
                                IconButton(
                                  tooltip: 'Copy logs',
                                  icon: const Icon(Icons.copy, size: 16),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: logs.join('\n')),
                                    );
                                    logAndRefresh(
                                      'copied ${logs.length} log lines',
                                    );
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Clear logs',
                                  icon: const Icon(Icons.clear_all, size: 16),
                                  onPressed: () => dialogSetState(logs.clear),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                ElevatedButton(
                                  onPressed: () => send('\x1B[5~', 'PgUp'),
                                  child: const Text('PgUp'),
                                ),
                                ElevatedButton(
                                  onPressed: () => send('\x1B[6~', 'PgDn'),
                                  child: const Text('PgDn'),
                                ),
                                ElevatedButton(
                                  onPressed: () => send('\x1B[A', 'Up'),
                                  child: const Text('↑'),
                                ),
                                ElevatedButton(
                                  onPressed: () => send('\x1B[B', 'Down'),
                                  child: const Text('↓'),
                                ),
                                ElevatedButton(
                                  onPressed: () => send('\x02[', 'CopyMode'),
                                  child: const Text('Copy'),
                                ),
                                ElevatedButton(
                                  onPressed: () => send('q', 'ExitCopy'),
                                  child: const Text('Exit'),
                                ),
                                ElevatedButton(
                                  onPressed:
                                      () => send(
                                        '\x1B[?1000h\x1B[?1002h\x1B[?1006h',
                                        'MouseOn',
                                      ),
                                  child: const Text('MouseOn'),
                                ),
                                ElevatedButton(
                                  onPressed:
                                      () => send(
                                        '\x1B[?1000l\x1B[?1002l\x1B[?1006l',
                                        'MouseOff',
                                      ),
                                  child: const Text('MouseOff'),
                                ),
                                ElevatedButton(
                                  onPressed:
                                      () => send('\x1B[?1049l', 'NormBuf'),
                                  child: const Text('NormBuf'),
                                ),
                                ElevatedButton(
                                  onPressed:
                                      () => send('\x1B[?1049h', 'AltBuf'),
                                  child: const Text('AltBuf'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    dialogSetState(() {
                                      forceAltScrollKeys = !forceAltScrollKeys;
                                      addLog(
                                        'forceAltScrollKeys=$forceAltScrollKeys',
                                      );
                                    });
                                  },
                                  child: Text(
                                    forceAltScrollKeys
                                        ? 'ForceKeysOn'
                                        : 'ForceKeysOff',
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    state?.setFontSize(fontSize + 1);
                                    dialogSetState(() {});
                                  },
                                  child: const Text('Font+'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    state?.setFontSize(fontSize - 1);
                                    dialogSetState(() {});
                                  },
                                  child: const Text('Font-'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    GestureBinding.instance.handlePointerEvent(
                                      const PointerScrollEvent(
                                        device: 0,
                                        position: Offset.zero,
                                        scrollDelta: Offset(0, -50),
                                      ),
                                    );
                                    addLog('sim scroll -50');
                                  },
                                  child: const Text('Wheel↑'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    GestureBinding.instance.handlePointerEvent(
                                      const PointerScrollEvent(
                                        device: 0,
                                        position: Offset.zero,
                                        scrollDelta: Offset(0, 50),
                                      ),
                                    );
                                    addLog('sim scroll +50');
                                  },
                                  child: const Text('Wheel↓'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Container(
                          color: context.appColors.background,
                          padding: const EdgeInsets.all(4),
                          child: ListView.builder(
                            controller: logScroll,
                            itemCount: logs.length,
                            itemBuilder:
                                (_, i) => Text(
                                  logs[i],
                                  style: const TextStyle(
                                    color: Colors.lightGreenAccent,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _onEnvGroupsChanged(List<String> envGroupIds) async {
    final nextConfig = _config.copyWith(envGroupIds: envGroupIds);
    _config = nextConfig;
    widget.onUpdateState({'config': nextConfig.toJson()});
    // Respawn terminal with new env vars
    if (_config.sessionId.isNotEmpty && _session != null) {
      setState(() => _restoring = true);
      await _manager.killSession(_config.sessionId);
      final session = await _manager.createSession(
        sessionName: _config.sessionName,
        workingDir: _config.workingDir,
        envGroupIds: envGroupIds,
        remoteInfo: widget.remoteInfo,
      );
      if (!mounted) return;
      final updatedConfig = _config.copyWith(sessionId: session.id);
      _config = updatedConfig;
      widget.onUpdateState({'config': updatedConfig.toJson()});
      setState(() {
        _session = session;
        _restoring = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (!_config.isConfigured) {
      return _BoardTerminalSetupView(
        onStart: _startSession,
        remoteInfo: widget.remoteInfo,
        starting: _starting,
      );
    }
    if (_restoring) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_session == null) {
      return _TerminalDisconnectedView(
        sessionName: _config.sessionName,
        workingDir: _config.workingDir,
        onRestart: _restartSession,
        onHistory: _showHistoryDialog,
      );
    }
    return Column(
      children: [
        _BoardTerminalInfoBar(
          config: _config,
          onHistory: _showHistoryDialog,
          onKill: _killCurrentSession,
          onEnvGroupsChanged: _onEnvGroupsChanged,
          onOpenFullView: _openFullView,
          onScrollUp: () => _terminalKey.currentState?.scrollPageUp(),
          onScrollDown: () => _terminalKey.currentState?.scrollPageDown(),
        ),
        Expanded(
          child: ScrollableCardMarker(
            child: ScrollableCardRegion(
              child: TerminalWidget(
                key: _terminalKey,
                session: _session!,
                isActive: true,
                debugLabel: 'board:${widget.panel.id}:session:${_session!.id}',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BoardTerminalInfoBar extends StatefulWidget {
  const _BoardTerminalInfoBar({
    required this.config,
    required this.onHistory,
    required this.onKill,
    required this.onEnvGroupsChanged,
    this.onOpenFullView,
    this.onScrollUp,
    this.onScrollDown,
  });

  final BoardTerminalConfig config;
  final VoidCallback onHistory;
  final VoidCallback onKill;
  final ValueChanged<List<String>> onEnvGroupsChanged;
  final VoidCallback? onOpenFullView;
  final VoidCallback? onScrollUp;
  final VoidCallback? onScrollDown;

  @override
  State<_BoardTerminalInfoBar> createState() => _BoardTerminalInfoBarState();
}

class _BoardTerminalInfoBarState extends State<_BoardTerminalInfoBar> {
  late Future<List<String>> _envNamesFuture;

  @override
  void initState() {
    super.initState();
    _envNamesFuture = GlobalEnvGroupsService.instance.resolveSelectedGroupNames(
      widget.config.envGroupIds,
    );
  }

  @override
  void didUpdateWidget(covariant _BoardTerminalInfoBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.envGroupIds.join('\u0000') !=
        widget.config.envGroupIds.join('\u0000')) {
      _envNamesFuture = GlobalEnvGroupsService.instance
          .resolveSelectedGroupNames(widget.config.envGroupIds);
    }
  }

  String _shortPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return path;
    return '.../${parts[parts.length - 2]}/${parts.last}';
  }

  Future<void> _pickEnvGroups() async {
    final selected = await showEnvGroupPickerDialog(
      context,
      initialSelected: widget.config.envGroupIds,
    );
    if (selected != null) {
      widget.onEnvGroupsChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 12, color: mutedColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _shortPath(widget.config.workingDir),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: mutedColor),
            ),
          ),
          FutureBuilder<List<String>>(
            future: _envNamesFuture,
            builder: (context, snapshot) {
              final names = snapshot.data ?? const <String>[];
              final hasEnv = widget.config.envGroupIds.isNotEmpty;
              return GestureDetector(
                onTap: _pickEnvGroups,
                child: Tooltip(
                  message:
                      hasEnv ? 'Env: ${names.join(", ")}' : 'Select env groups',
                  child: Icon(
                    Icons.key_outlined,
                    size: 14,
                    color: hasEnv ? colors.accentGreen : mutedColor,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          if (widget.onScrollUp != null)
            GestureDetector(
              onTap: widget.onScrollUp,
              child: Tooltip(
                message: 'Scroll up',
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 16,
                  color: mutedColor,
                ),
              ),
            ),
          if (widget.onScrollUp != null) const SizedBox(width: 8),
          if (widget.onScrollDown != null)
            GestureDetector(
              onTap: widget.onScrollDown,
              child: Tooltip(
                message: 'Scroll down',
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: mutedColor,
                ),
              ),
            ),
          if (widget.onScrollDown != null) const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onHistory,
            child: Tooltip(
              message: 'Terminal history',
              child: Icon(Icons.history, size: 14, color: mutedColor),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.onOpenFullView != null)
            GestureDetector(
              onTap: widget.onOpenFullView,
              child: Tooltip(
                message: 'Open full view',
                child: Icon(
                  Icons.open_in_full_rounded,
                  size: 14,
                  color: mutedColor,
                ),
              ),
            ),
          if (widget.onOpenFullView != null) const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onKill,
            child: Tooltip(
              message: 'Kill terminal session',
              child: Icon(
                Icons.stop_circle_outlined,
                size: 14,
                color: colors.accentRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardTerminalSetupView extends StatefulWidget {
  const _BoardTerminalSetupView({
    required this.onStart,
    required this.starting,
    this.remoteInfo,
  });

  final Future<void> Function(
    String workingDir,
    String sessionName,
    List<String> envGroupIds,
  )
  onStart;
  final bool starting;
  final RemoteBoardInfo? remoteInfo;

  @override
  State<_BoardTerminalSetupView> createState() =>
      _BoardTerminalSetupViewState();
}

class _BoardTerminalSetupViewState extends State<_BoardTerminalSetupView> {
  final _dirCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  List<String> _selectedEnvGroupIds = const [];

  @override
  void dispose() {
    _dirCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create terminal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Working Directory',
            style: TextStyle(fontSize: 11, color: mutedColor),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () async {
              final dir = await BoardFilePicker.pickDirectory(
                context,
                remoteInfo: widget.remoteInfo,
                initialPath: _dirCtrl.text,
                title: 'Select terminal working directory',
              );
              if (dir == null || !mounted) return;
              setState(() {
                _dirCtrl.text = dir;
                if (_nameCtrl.text.trim().isEmpty) {
                  _nameCtrl.text = p.basename(dir);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: colors.surfaceElevated,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: colors.accentGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dirCtrl.text.isEmpty ? 'Select folder…' : _dirCtrl.text,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: _dirCtrl.text.isEmpty ? mutedColor : onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Session Name',
            style: TextStyle(fontSize: 11, color: mutedColor),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(fontSize: 12, color: onSurface),
            decoration: InputDecoration(
              hintText: 'Defaults to folder name',
              hintStyle: TextStyle(fontSize: 12, color: mutedColor),
              filled: true,
              fillColor: colors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          EnvGroupSelectionField(
            selectedGroupIds: _selectedEnvGroupIds,
            onChanged: (value) {
              setState(() => _selectedEnvGroupIds = value);
            },
          ),
          const Spacer(),
          FilledButton(
            onPressed:
                widget.starting || _dirCtrl.text.trim().isEmpty
                    ? null
                    : () async {
                      try {
                        await widget.onStart(
                          _dirCtrl.text,
                          _nameCtrl.text,
                          _selectedEnvGroupIds,
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not start terminal: $error'),
                          ),
                        );
                      }
                    },
            style: FilledButton.styleFrom(
              backgroundColor: colors.accentGreen,
              foregroundColor: colors.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child:
                widget.starting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text(
                      'Start Terminal',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
          ),
        ],
      ),
    );
  }
}

class _TerminalDisconnectedView extends StatelessWidget {
  const _TerminalDisconnectedView({
    required this.sessionName,
    required this.workingDir,
    required this.onRestart,
    required this.onHistory,
  });

  final String sessionName;
  final String workingDir;
  final VoidCallback onRestart;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 40, color: mutedColor),
            const SizedBox(height: 12),
            Text(
              sessionName.isEmpty ? 'Terminal ended' : '$sessionName ended',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              workingDir,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: mutedColor),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: onHistory,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.border),
                    foregroundColor: onSurface,
                  ),
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text('History'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onRestart,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accentGreen,
                    foregroundColor: colors.background,
                  ),
                  icon: const Icon(Icons.restart_alt, size: 14),
                  label: const Text('Restart'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BoardTerminalSessionHistoryDialog extends StatefulWidget {
  const BoardTerminalSessionHistoryDialog({super.key, this.currentSessionId});

  final String? currentSessionId;

  @override
  State<BoardTerminalSessionHistoryDialog> createState() =>
      _BoardTerminalSessionHistoryDialogState();
}

class _BoardTerminalSessionHistoryDialogState
    extends State<BoardTerminalSessionHistoryDialog> {
  late Future<List<BoardTerminalSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = BoardTerminalSessionHistory.instance.loadAll();
  }

  void _refresh() {
    setState(() {
      _entriesFuture = BoardTerminalSessionHistory.instance.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final manager = BoardTerminalSessionManager.instance;
    final colors = context.appColors;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;
    final secondaryColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.history, size: 18, color: secondaryColor),
          const SizedBox(width: 8),
          Text(
            'Terminal history',
            style: TextStyle(color: onSurface, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 420,
        child: AnimatedBuilder(
          animation: manager,
          builder: (context, _) {
            return FutureBuilder<List<BoardTerminalSessionEntry>>(
              future: _entriesFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return Center(
                    child: Text(
                      'No terminal sessions yet.',
                      style: TextStyle(color: mutedColor, fontSize: 13),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder:
                      (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isCurrent = entry.id == widget.currentSessionId;
                    final isLive = manager.isLive(entry.id);
                    return GestureDetector(
                      onTap:
                          isCurrent
                              ? null
                              : () async {
                                Navigator.pop(context);
                                await context
                                    .read<BoardCubit>()
                                    .createTerminalPanel(
                                      title: entry.sessionName,
                                      sessionId: entry.id,
                                      sessionName: entry.sessionName,
                                      workingDir: entry.workingDir,
                                      envGroupIds: entry.envGroupIds,
                                    );
                              },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isCurrent
                                  ? colors.surfaceElevated
                                  : colors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              isCurrent
                                  ? Border.all(
                                    color: colors.accentGreen,
                                    width: 0.5,
                                  )
                                  : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.terminal,
                              size: 14,
                              color: isLive ? colors.accentGreen : mutedColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.sessionName.isEmpty
                                        ? 'Unnamed terminal'
                                        : entry.sessionName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          isCurrent
                                              ? colors.accentGreen
                                              : onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${isLive ? 'live' : 'saved'} • ${entry.workingDir}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mutedColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isCurrent)
                              _historyActionButton(
                                icon: Icons.restore,
                                color: colors.accentBlue,
                                tooltip: 'Restore as new terminal panel',
                                onTap: () async {
                                  Navigator.pop(context);
                                  await context
                                      .read<BoardCubit>()
                                      .createTerminalPanel(
                                        title: entry.sessionName,
                                        sessionId: entry.id,
                                        sessionName: entry.sessionName,
                                        workingDir: entry.workingDir,
                                        envGroupIds: entry.envGroupIds,
                                      );
                                },
                              ),
                            _historyActionButton(
                              icon:
                                  isLive
                                      ? Icons.stop_circle_outlined
                                      : Icons.delete_outline,
                              color:
                                  isLive
                                      ? colors.accentOrange
                                      : colors.accentRed,
                              tooltip:
                                  isLive ? 'Kill session' : 'Delete history',
                              onTap: () async {
                                if (isLive) {
                                  await manager.killSession(entry.id);
                                } else {
                                  await BoardTerminalSessionHistory.instance
                                      .delete(entry.id);
                                }
                                _refresh();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

Widget _historyActionButton({
  required IconData icon,
  required Color color,
  required String tooltip,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    ),
  );
}
