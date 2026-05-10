import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_history.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

class BoardTerminalPanelWidget extends StatefulWidget {
  const BoardTerminalPanelWidget({
    super.key,
    required this.panel,
    required this.onUpdateState,
  });

  final BoardPanelInstance panel;
  final ValueChanged<Map<String, dynamic>> onUpdateState;

  @override
  State<BoardTerminalPanelWidget> createState() =>
      _BoardTerminalPanelWidgetState();
}

class _BoardTerminalPanelWidgetState extends State<BoardTerminalPanelWidget> {
  final _manager = BoardTerminalSessionManager.instance;
  late BoardTerminalConfig _config;
  AgentSession? _session;
  bool _restoring = false;

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
    if (!_config.isConfigured || _config.sessionId.isEmpty) return;
    final existing = _manager.sessionFor(_config.sessionId);
    if (existing != null) {
      if (mounted) setState(() => _session = existing);
      return;
    }
    setState(() => _restoring = true);
    final restored = await _manager.ensureSession(_config);
    if (!mounted) return;
    setState(() {
      _session = restored;
      _restoring = false;
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
    final session = await _manager.createSession(
      sessionName: trimmedName,
      workingDir: trimmedDir,
      envGroupIds: envGroupIds,
    );
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
    });
    widget.onUpdateState({
      ...widget.panel.state,
      'config': nextConfig.toJson(),
    });
  }

  Future<void> _restartSession() async {
    if (!_config.isConfigured) return;
    setState(() => _restoring = true);
    final session = await _manager.ensureSession(_config);
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

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder:
          (_) => BoardTerminalSessionHistoryDialog(
            currentSessionId: _config.sessionId,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_config.isConfigured) {
      return _BoardTerminalSetupView(onStart: _startSession);
    }
    if (_restoring) {
      return const Center(child: CircularProgressIndicator());
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
        ),
        Expanded(
          child: TerminalWidget(
            key: ValueKey('board-terminal-${_session!.id}'),
            session: _session!,
            isActive: true,
          ),
        ),
      ],
    );
  }
}

class _BoardTerminalInfoBar extends StatelessWidget {
  const _BoardTerminalInfoBar({
    required this.config,
    required this.onHistory,
    required this.onKill,
  });

  final BoardTerminalConfig config;
  final VoidCallback onHistory;
  final VoidCallback onKill;

  String _shortPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return path;
    return '.../${parts[parts.length - 2]}/${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 12, color: mutedColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _shortPath(config.workingDir),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: mutedColor),
            ),
          ),
          GestureDetector(
            onTap: onHistory,
            child: Tooltip(
              message: 'Terminal history',
              child: Icon(Icons.history, size: 14, color: mutedColor),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onKill,
            child: const Tooltip(
              message: 'Kill terminal session',
              child: Icon(
                Icons.stop_circle_outlined,
                size: 14,
                color: Color(0xFFF87171),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardTerminalSetupView extends StatefulWidget {
  const _BoardTerminalSetupView({required this.onStart});

  final Future<void> Function(
    String workingDir,
    String sessionName,
    List<String> envGroupIds,
  )
  onStart;

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
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ??
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
              final dir = await FilePicker.getDirectoryPath(
                dialogTitle: 'Select terminal working directory',
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
                  const Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dirCtrl.text.isEmpty ? 'Select folder…' : _dirCtrl.text,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            _dirCtrl.text.isEmpty ? mutedColor : onSurface,
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
              hintStyle: TextStyle(
                fontSize: 12,
                color: mutedColor,
              ),
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
                _dirCtrl.text.trim().isEmpty
                    ? null
                    : () => widget.onStart(
                      _dirCtrl.text,
                      _nameCtrl.text,
                      _selectedEnvGroupIds,
                    ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: colors.surface,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
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
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ??
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
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text('History'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onRestart,
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
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;
    final secondaryColor = Theme.of(context).textTheme.bodyMedium?.color ??
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
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
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
                                  ? const Color(0xFF153225)
                                  : colors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              isCurrent
                                  ? Border.all(
                                    color: const Color(0xFF22C55E),
                                    width: 0.5,
                                  )
                                  : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.terminal,
                              size: 14,
                              color:
                                  isLive
                                      ? const Color(0xFF22C55E)
                                      : mutedColor,
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
                                              ? const Color(0xFF22C55E)
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
                                color: const Color(0xFF60A5FA),
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
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFFF87171),
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
