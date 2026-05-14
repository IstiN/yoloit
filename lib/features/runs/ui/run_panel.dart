import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/runs/ui/run_config_dialog.dart';

typedef RunPanelDetachToPanelCallback = Future<void> Function(RunSession session);
typedef RunPanelSendToGroupCallback = Future<void> Function(
  RunSession session,
  String group,
  bool createNewPanel,
);
typedef RunPanelSessionVisibilityChanged =
    void Function(String sessionId, bool hidden);

class RunPanel extends StatelessWidget {
  const RunPanel({
    super.key,
    required this.groupId,
    this.onGroupChanged,
    this.showGroupControls = true,
    this.showConfigList = true,
    this.showSessionTabs = true,
    this.initialAttachedSessionId,
    this.onAttachedSessionChanged,
    this.hiddenSessionIds = const [],
    this.onSessionVisibilityChanged,
    this.onDetachToPanel,
    this.onSendToGroup,
  });

  final String groupId;
  final ValueChanged<String>? onGroupChanged;
  final bool showGroupControls;
  final bool showConfigList;
  final bool showSessionTabs;
  final String? initialAttachedSessionId;
  final ValueChanged<String?>? onAttachedSessionChanged;
  final List<String> hiddenSessionIds;
  final RunPanelSessionVisibilityChanged? onSessionVisibilityChanged;
  final RunPanelDetachToPanelCallback? onDetachToPanel;
  final RunPanelSendToGroupCallback? onSendToGroup;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RunCubit, RunState>(
      builder: (context, state) {
        return _RunPanelView(
          state: state,
          groupId: groupId,
          onGroupChanged: onGroupChanged,
          showGroupControls: showGroupControls,
          showConfigList: showConfigList,
          showSessionTabs: showSessionTabs,
          initialAttachedSessionId: initialAttachedSessionId,
          onAttachedSessionChanged: onAttachedSessionChanged,
          hiddenSessionIds: hiddenSessionIds,
          onSessionVisibilityChanged: onSessionVisibilityChanged,
          onDetachToPanel: onDetachToPanel,
          onSendToGroup: onSendToGroup,
        );
      },
    );
  }
}

class _RunPanelView extends StatefulWidget {
  const _RunPanelView({
    required this.state,
    required this.groupId,
    this.onGroupChanged,
    this.showGroupControls = true,
    this.showConfigList = true,
    this.showSessionTabs = true,
    this.initialAttachedSessionId,
    this.onAttachedSessionChanged,
    this.hiddenSessionIds = const [],
    this.onSessionVisibilityChanged,
    this.onDetachToPanel,
    this.onSendToGroup,
  });
  final RunState state;
  final String groupId;
  final ValueChanged<String>? onGroupChanged;
  final bool showGroupControls;
  final bool showConfigList;
  final bool showSessionTabs;
  final String? initialAttachedSessionId;
  final ValueChanged<String?>? onAttachedSessionChanged;
  final List<String> hiddenSessionIds;
  final RunPanelSessionVisibilityChanged? onSessionVisibilityChanged;
  final RunPanelDetachToPanelCallback? onDetachToPanel;
  final RunPanelSendToGroupCallback? onSendToGroup;

  @override
  State<_RunPanelView> createState() => _RunPanelViewState();
}

class _RunPanelViewState extends State<_RunPanelView> {
  final _scrollController = ScrollController();
  bool _workspaceLoadInFlight = false;
  String? _attachedSessionId;

  @override
  void initState() {
    super.initState();
    _attachedSessionId =
        widget.initialAttachedSessionId ?? widget.state.activeSessionId;
    _ensureWorkspaceLoaded();
    _ensureGroupLoaded();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_RunPanelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAttachedSessionId != widget.initialAttachedSessionId &&
        widget.initialAttachedSessionId != null &&
        widget.initialAttachedSessionId != _attachedSessionId) {
      _attachedSessionId = widget.initialAttachedSessionId;
    }
    _ensureWorkspaceLoaded();
    if (oldWidget.groupId != widget.groupId) {
      _ensureGroupLoaded();
    }
    final oldSession = _findSession(
      oldWidget.state.sessions,
      _attachedSessionId,
    );
    final newSession = _findSession(widget.state.sessions, _attachedSessionId);
    if (newSession != null &&
        newSession.output.length != (oldSession?.output.length ?? 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _ensureWorkspaceLoaded() {
    if (_workspaceLoadInFlight || widget.state.workspacePath != null) return;
    _workspaceLoadInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<RunCubit>()
          .loadForWorkspace(Directory.current.path)
          .whenComplete(() {
            _workspaceLoadInFlight = false;
          });
    });
  }

  void _ensureGroupLoaded() {
    final group = widget.groupId.trim();
    if (group.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RunCubit>().ensureGroupInitialized(group);
    });
  }

  RunSession? _findSession(List<RunSession> sessions, String? sessionId) {
    if (sessionId == null) return null;
    for (final session in sessions) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  void _attachSession(String? sessionId) {
    if (_attachedSessionId == sessionId) return;
    setState(() {
      _attachedSessionId = sessionId;
    });
    widget.onAttachedSessionChanged?.call(sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = widget.state;
    final group = widget.groupId.trim();
    final hidden = widget.hiddenSessionIds.toSet();
    final configs =
        state.configs.where((config) => config.group == group).toList();
    final sessions =
        state.sessions
            .where(
              (session) =>
                  session.config.group == group && !hidden.contains(session.id),
            )
            .toList();
    final activeSessionId =
        sessions.any((s) => s.id == _attachedSessionId) ? _attachedSessionId : null;
    if (activeSessionId == null && _attachedSessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _attachSession(null);
      });
    }
    final scopedState = state.copyWith(
      configs: configs,
      sessions: sessions,
      activeSessionId: activeSessionId,
    );

    return Container(
      color: colors.terminalBackground,
      child: Row(
        children: [
          if (widget.showConfigList) ...[
            // Left: configurations list
            _ConfigList(
              state: scopedState,
              groupId: group,
              onGroupChanged: widget.onGroupChanged,
              showGroupControls: widget.showGroupControls,
              onAttachSession: _attachSession,
            ),
            Container(width: 1, color: colors.divider),
          ],
          // Right: session tabs + console output
          Expanded(
            child: Column(
              children: [
                _ConsoleHeader(
                  state: scopedState,
                  allSessions: state.sessions,
                  allConfigs: state.configs,
                  currentGroup: group,
                  showSessionTabs: widget.showSessionTabs,
                  onGroupChanged: widget.onGroupChanged,
                  onAttachSession: _attachSession,
                  onSessionVisibilityChanged: widget.onSessionVisibilityChanged,
                  onDetachToPanel: widget.onDetachToPanel,
                  onSendToGroup: widget.onSendToGroup,
                ),
                Expanded(
                  child: _Console(
                    state: scopedState,
                    scrollController: _scrollController,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Console Header (tabs + action buttons, shown inside the right area) ──────

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({
    required this.state,
    required this.allSessions,
    required this.allConfigs,
    required this.currentGroup,
    required this.showSessionTabs,
    this.onGroupChanged,
    required this.onAttachSession,
    this.onSessionVisibilityChanged,
    this.onDetachToPanel,
    this.onSendToGroup,
  });
  final RunState state;
  final List<RunSession> allSessions;
  final List<RunConfig> allConfigs;
  final String currentGroup;
  final bool showSessionTabs;
  final ValueChanged<String>? onGroupChanged;
  final ValueChanged<String?> onAttachSession;
  final RunPanelSessionVisibilityChanged? onSessionVisibilityChanged;
  final RunPanelDetachToPanelCallback? onDetachToPanel;
  final RunPanelSendToGroupCallback? onSendToGroup;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<RunCubit>();
    final activeSession = state.activeSession;
    final isRunning = activeSession?.status == RunStatus.running;
    final quickActions = _effectiveQuickActions(activeSession?.config);
    final attachCandidate =
        allSessions
            .where((session) => session.status == RunStatus.running)
            .lastOrNull ??
        allSessions.lastOrNull;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Session tabs (hidden in detached panel mode)
          Expanded(
            child:
                showSessionTabs
                    ? ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ...state.sessions.map(
                          (s) => _SessionTab(
                            session: s,
                            isActive: s.id == state.activeSessionId,
                            onTap: () => onAttachSession(s.id),
                            onClose: () => cubit.removeSession(s.id),
                          ),
                        ),
                      ],
                    )
                    : (activeSession == null
                        ? const SizedBox.shrink()
                        : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              activeSession.config.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        )),
          ),
          // Action buttons
          if (activeSession != null) ...[
            if (isRunning)
              ...quickActions.map(
                (action) => _HeaderButton(
                  tooltip:
                      action.appendNewline
                          ? '${action.label} (sends Enter)'
                          : action.label,
                  icon: _quickActionIcon(action.icon),
                  label: action.label.isNotEmpty ? action.label[0] : 'A',
                  iconColor: AppColors.neonGreen,
                  onTap:
                      () => cubit.triggerQuickAction(activeSession.id, action),
                ),
              ),
            if (isRunning)
              _HeaderButton(
                tooltip: 'Stop',
                icon: Icons.stop_rounded,
                iconColor: AppColors.neonRed,
                onTap: () => cubit.stopRun(activeSession.id),
              )
            else
              _HeaderButton(
                tooltip: 'Re-run',
                icon: Icons.refresh_rounded,
                iconColor: AppColors.neonGreen,
                onTap: () => cubit.restartSession(activeSession.id),
              ),
            _HeaderButton(
              tooltip: 'Clear output',
              icon: Icons.clear_all_rounded,
              iconColor: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              onTap: () => cubit.clearOutput(activeSession.id),
            ),
            _HeaderButton(
              tooltip: 'Detach session',
              icon: Icons.link_off_rounded,
              iconColor: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              onTap: () {
                onSessionVisibilityChanged?.call(activeSession.id, true);
                onAttachSession(null);
              },
            ),
            if (onDetachToPanel != null)
              _HeaderButton(
                tooltip: 'Detach to new panel',
                icon: Icons.open_in_new_rounded,
                iconColor: AppColors.neonGreen,
                onTap: () async {
                  onSessionVisibilityChanged?.call(activeSession.id, true);
                  await onDetachToPanel!(activeSession);
                  onAttachSession(null);
                },
              ),
            if (onSendToGroup != null)
              _HeaderButton(
                tooltip: 'Send to group',
                icon: Icons.group_work_rounded,
                iconColor: AppColors.neonGreen,
                onTap: () async {
                  final target = await _pickSendTarget(
                    context,
                    allSessions: allSessions,
                    allConfigs: allConfigs,
                    currentGroup: currentGroup,
                  );
                  if (target == null) return;
                  onSessionVisibilityChanged?.call(activeSession.id, true);
                  await onSendToGroup!(
                    activeSession,
                    target.group,
                    target.createNewPanel,
                  );
                  onAttachSession(null);
                },
              ),
            PopupMenuButton<String>(
              tooltip: 'Run menu',
              padding: EdgeInsets.zero,
              color: colors.surfaceElevated,
              onSelected: (value) async {
                if (value == 'detach') {
                  onSessionVisibilityChanged?.call(activeSession.id, true);
                  onAttachSession(null);
                } else if (value == 'popout') {
                  if (onDetachToPanel != null) {
                    onSessionVisibilityChanged?.call(activeSession.id, true);
                    await onDetachToPanel!(activeSession);
                    onAttachSession(null);
                  }
                } else if (value == 'send-group') {
                  if (onSendToGroup != null) {
                    final target = await _pickSendTarget(
                      context,
                      allSessions: allSessions,
                      allConfigs: allConfigs,
                      currentGroup: currentGroup,
                    );
                    if (target == null) return;
                    onSessionVisibilityChanged?.call(activeSession.id, true);
                    await onSendToGroup!(
                      activeSession,
                      target.group,
                      target.createNewPanel,
                    );
                    onAttachSession(null);
                  }
                } else if (value == 'attach-latest') {
                  if (attachCandidate != null) {
                    onSessionVisibilityChanged?.call(attachCandidate.id, false);
                    if (attachCandidate.config.group != currentGroup) {
                      onGroupChanged?.call(attachCandidate.config.group);
                    }
                    onAttachSession(attachCandidate.id);
                  }
                } else if (value == 'attach') {
                  final selected = await _pickAttachTarget(context, allSessions);
                  if (selected != null) {
                    onSessionVisibilityChanged?.call(selected.id, false);
                    if (selected.config.group != currentGroup) {
                      onGroupChanged?.call(selected.config.group);
                    }
                    onAttachSession(selected.id);
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'attach',
                  child: Text('Attach…'),
                ),
                const PopupMenuItem(
                  value: 'detach',
                  child: Text('Detach from console'),
                ),
                if (onDetachToPanel != null)
                  const PopupMenuItem(
                    value: 'popout',
                    child: Text('Detach to new panel'),
                  ),
                if (onSendToGroup != null)
                  const PopupMenuItem(
                    value: 'send-group',
                    child: Text('Send to group'),
                  ),
                if (attachCandidate != null)
                  const PopupMenuItem(
                    value: 'attach-latest',
                    child: Text('Attach latest session'),
                  ),
              ],
              child: Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ],
          if (activeSession == null && attachCandidate != null)
            _HeaderButton(
              tooltip: 'Attach session',
              icon: Icons.link_rounded,
              iconColor: AppColors.neonGreen,
              onTap: () async {
                final selected = await _pickAttachTarget(context, allSessions);
                if (selected == null) return;
                onSessionVisibilityChanged?.call(selected.id, false);
                if (selected.config.group != currentGroup) {
                  onGroupChanged?.call(selected.config.group);
                }
                onAttachSession(selected.id);
              },
            ),
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  List<RunQuickAction> _effectiveQuickActions(RunConfig? config) {
    if (config == null) return const [];
    if (config.quickActions.isNotEmpty) return config.quickActions;
    if (!config.isFlutterRun) return const [];
    return const [
      RunQuickAction(
        id: 'flutter_hot_reload',
        label: 'Hot Reload',
        icon: 'local_fire_department',
        command: 'r',
      ),
      RunQuickAction(
        id: 'flutter_hot_restart',
        label: 'Hot Restart',
        icon: 'restart_alt',
        command: 'R',
      ),
    ];
  }

  IconData _quickActionIcon(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'local_fire_department':
      case 'fire':
      case 'hot_reload':
        return Icons.local_fire_department_rounded;
      case 'restart_alt':
      case 'restart':
      case 'hot_restart':
        return Icons.restart_alt_rounded;
      case 'play':
      case 'play_arrow':
        return Icons.play_arrow_rounded;
      case 'pause':
        return Icons.pause_rounded;
      case 'stop':
        return Icons.stop_rounded;
      case 'bolt':
      default:
        return Icons.bolt_rounded;
    }
  }

  Future<RunSession?> _pickAttachTarget(
    BuildContext context,
    List<RunSession> sessions,
  ) {
    final grouped = <String, List<RunSession>>{};
    for (final session in sessions.reversed) {
      grouped.putIfAbsent(session.config.group, () => <RunSession>[]).add(session);
    }
    if (grouped.isEmpty) return Future.value(null);
    return showDialog<RunSession>(
      context: context,
      builder: (dialogContext) {
        final colors = context.appColors;
        return AlertDialog(
          title: const Text('Attach session'),
          backgroundColor: colors.surfaceElevated,
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: grouped.entries.map((entry) {
                final group = entry.key;
                final groupSessions = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(170),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...groupSessions.map((session) {
                        final isRunning = session.status == RunStatus.running;
                        return InkWell(
                          onTap: () => Navigator.of(dialogContext).pop(session),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 8,
                                  color:
                                      isRunning
                                          ? AppColors.neonGreen
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withAlpha(120),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    session.config.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  session.id.split('_').last,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withAlpha(120),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<_SendGroupTarget?> _pickSendTarget(
    BuildContext context, {
    required List<RunSession> allSessions,
    required List<RunConfig> allConfigs,
    required String currentGroup,
  }) async {
    final groups = <String>{};
    for (final config in allConfigs) {
      if (config.group.trim().isNotEmpty) groups.add(config.group.trim());
    }
    for (final session in allSessions) {
      if (session.config.group.trim().isNotEmpty) {
        groups.add(session.config.group.trim());
      }
    }
    groups.remove(currentGroup);
    final sorted = groups.toList()..sort();

    return showDialog<_SendGroupTarget>(
      context: context,
      builder: (dialogContext) {
        final colors = context.appColors;
        return AlertDialog(
          title: const Text('Send to group'),
          backgroundColor: colors.surfaceElevated,
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...sorted.map(
                  (group) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_open_rounded, size: 18),
                    title: Text(group),
                    subtitle: const Text('Return to existing group panel'),
                    onTap: () {
                      Navigator.of(dialogContext).pop(
                        _SendGroupTarget(group: group, createNewPanel: false),
                      );
                    },
                  ),
                ),
                const Divider(height: 10),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.create_new_folder_rounded, size: 18),
                  title: const Text('Create new group panel'),
                  subtitle: const Text('Choose group name'),
                  onTap: () async {
                    final group = await _askGroupName(dialogContext);
                    if (group == null || group.trim().isEmpty) return;
                    if (!context.mounted) return;
                    Navigator.of(dialogContext).pop(
                      _SendGroupTarget(
                        group: group.trim(),
                        createNewPanel: true,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _askGroupName(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('New group'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Group name'),
            onSubmitted: (_) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}

class _SendGroupTarget {
  const _SendGroupTarget({required this.group, required this.createNewPanel});
  final String group;
  final bool createNewPanel;
}

class _SessionTab extends StatelessWidget {
  const _SessionTab({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  final RunSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isRunning = session.status == RunStatus.running;
    final dotColor =
        session.config.color ??
        (isRunning
            ? AppColors.neonGreen
            : Theme.of(context).colorScheme.onSurface.withAlpha(120));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? colors.tabActiveBg : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? colors.tabBorder : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRunning)
              SizedBox(width: 8, height: 8, child: _PulsingDot(color: dotColor))
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      session.status == RunStatus.failed
                          ? AppColors.neonRed
                          : dotColor,
                ),
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                session.config.name,
                style: TextStyle(
                  color:
                      isActive
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClose,
              child: Icon(
                Icons.close,
                size: 10,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    this.icon,
    this.iconColor,
    this.label,
    required this.onTap,
  });

  final String tooltip;
  final IconData? icon;
  final Color? iconColor;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child:
              icon != null
                  ? Icon(icon, size: 14, color: iconColor)
                  : Text(
                    label ?? '',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
        ),
      ),
    );
  }
}

// ── Config List ──────────────────────────────────────────────────────────────

class _ConfigList extends StatelessWidget {
  const _ConfigList({
    required this.state,
    required this.groupId,
    this.onGroupChanged,
    this.showGroupControls = true,
    this.onAttachSession,
  });
  final RunState state;
  final String groupId;
  final ValueChanged<String>? onGroupChanged;
  final bool showGroupControls;
  final ValueChanged<String>? onAttachSession;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<RunCubit>();
    final groupLabel =
        groupId.length > 14
            ? '${groupId.substring(0, 6)}…${groupId.substring(groupId.length - 4)}'
            : groupId;
    final sessionsByConfig = <String, List<RunSession>>{};
    for (final session in state.sessions.reversed) {
      sessionsByConfig
          .putIfAbsent(session.config.id, () => <RunSession>[])
          .add(session);
    }

    return SizedBox(
      width: 180,
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'CONFIGURATIONS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onSurface.withAlpha(120),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (showGroupControls) ...[
                  Tooltip(
                    message: 'Group',
                    child: Text(
                      groupLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color:
                            Theme.of(context).textTheme.bodySmall?.color ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
                if (showGroupControls && onGroupChanged != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () async {
                      final next = await _askGroupName(
                        context,
                        initialValue: groupId,
                      );
                      if (next == null || next.trim().isEmpty) return;
                      onGroupChanged!(next.trim());
                    },
                    child: Icon(
                      Icons.edit_outlined,
                      size: 12,
                      color:
                          Theme.of(context).textTheme.bodySmall?.color ??
                          Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 4),
              children: [
                ...state.configs.map((c) {
                  final runningSession =
                      state.sessions
                          .where(
                            (s) =>
                                s.config.id == c.id &&
                                s.status == RunStatus.running,
                          )
                          .firstOrNull;
                  final stoppedSession =
                      state.sessions
                          .where(
                            (s) =>
                                s.config.id == c.id &&
                                s.status != RunStatus.running,
                          )
                          .lastOrNull;
                  return _ConfigItem(
                    config: c,
                    isRunning: runningSession != null,
                    onRun: () {
                      if (runningSession != null) {
                        // Already running — hot reload if flutter, else focus
                        if (c.isFlutterRun) {
                          cubit.sendHotReload(runningSession.id);
                        }
                        onAttachSession?.call(runningSession.id);
                      } else if (stoppedSession != null) {
                        cubit.restartSession(stoppedSession.id);
                        onAttachSession?.call(stoppedSession.id);
                      } else {
                        cubit.startRun(c).then((started) {
                          if (started != null) {
                            onAttachSession?.call(started.id);
                          }
                        });
                      }
                    },
                    onEdit: () async {
                      final updated = await RunConfigDialog.show(
                        context,
                        initial: c,
                      );
                      if (updated != null) {
                        cubit.updateConfig(updated.copyWith(group: groupId));
                      }
                    },
                    onDelete: () => cubit.removeConfig(c.id),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: InkWell(
                    onTap: () async {
                      final config = await RunConfigDialog.show(context);
                      if (config == null) return;
                      final added = await cubit.addConfig(
                        config.copyWith(group: groupId),
                      );
                      if (!context.mounted) return;
                      if (added.id != config.id) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Configuration already exists: ${added.name}',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 12, color: colors.primary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Add Configuration',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (state.sessions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'RUN SESSIONS',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(120),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  ...state.configs
                      .where((c) => sessionsByConfig[c.id] != null)
                      .map((config) {
                        final sessions = sessionsByConfig[config.id]!;
                        return _SessionGroup(
                          config: config,
                          sessions: sessions,
                          activeSessionId: state.activeSessionId,
                          onTapSession: (sessionId) {
                            onAttachSession?.call(sessionId);
                          },
                          onDeleteSession: cubit.removeSession,
                        );
                      }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _askGroupName(
    BuildContext context, {
    required String initialValue,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: initialValue);
        return AlertDialog(
          title: const Text('Run group'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Group',
              hintText: 'e.g. backend, ui, test',
            ),
            onSubmitted: (_) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }
}

class _SessionGroup extends StatelessWidget {
  const _SessionGroup({
    required this.config,
    required this.sessions,
    required this.activeSessionId,
    required this.onTapSession,
    required this.onDeleteSession,
  });

  final RunConfig config;
  final List<RunSession> sessions;
  final String? activeSessionId;
  final ValueChanged<String> onTapSession;
  final ValueChanged<String> onDeleteSession;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final runningCount =
        sessions.where((s) => s.status == RunStatus.running).length;
    final titleColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface.withAlpha(150);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: colors.surfaceHighlight.withAlpha(70),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border.withAlpha(100)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${config.name} (${sessions.length})',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: runningCount > 0 ? AppColors.neonGreen : titleColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            ...sessions.take(4).map((session) {
              final isActive = session.id == activeSessionId;
              final isRunning = session.status == RunStatus.running;
              final markerColor =
                  isRunning
                      ? AppColors.neonGreen
                      : session.status == RunStatus.failed
                      ? AppColors.neonRed
                      : Theme.of(context).colorScheme.onSurface.withAlpha(110);
              final startedAt = session.startedAt;
              final trailingTime =
                  startedAt == null ? '' : _formatMiniTime(startedAt);
              return InkWell(
                onTap: () => onTapSession(session.id),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration:
                      isActive
                          ? BoxDecoration(
                            color: colors.tabActiveBg,
                            borderRadius: BorderRadius.circular(4),
                          )
                          : null,
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 7, color: markerColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          session.id.split('_').last,
                          style: TextStyle(
                            fontSize: 9,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trailingTime.isNotEmpty)
                        Text(
                          trailingTime,
                          style: TextStyle(
                            fontSize: 8,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color ??
                                Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => onDeleteSession(session.id),
                        child: Icon(
                          Icons.close,
                          size: 9,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatMiniTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _ConfigItem extends StatefulWidget {
  const _ConfigItem({
    required this.config,
    required this.isRunning,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  final RunConfig config;
  final bool isRunning;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ConfigItem> createState() => _ConfigItemState();
}

class _ConfigItemState extends State<_ConfigItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dotColor =
        widget.config.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: _hovering ? colors.surfaceHighlight : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.config.name,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Always reserve space for buttons; show/hide via Opacity to
            // prevent layout jump on hover.
            Opacity(
              opacity: widget.isRunning ? 1.0 : 0.0,
              child: const _SmallIconButton(
                icon: Icons.fiber_manual_record,
                color: AppColors.neonGreen,
                tooltip: 'Running',
                onTap: null,
              ),
            ),
            Opacity(
              opacity: (_hovering || widget.isRunning) ? 1.0 : 0.0,
              child: _SmallIconButton(
                icon: Icons.play_arrow_rounded,
                color: AppColors.neonGreen,
                tooltip: 'Run',
                onTap: (_hovering || widget.isRunning) ? widget.onRun : null,
              ),
            ),
            Opacity(
              opacity: (_hovering || widget.isRunning) ? 1.0 : 0.0,
              child: _SmallIconButton(
                icon: Icons.more_vert,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                tooltip: 'Options',
                onTap:
                    (_hovering || widget.isRunning)
                        ? () => _showMenu(context)
                        : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + box.size.width,
        offset.dy,
        offset.dx + box.size.width + 160,
        offset.dy + 100,
      ),
      color: context.appColors.surfaceElevated,
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 32,
          child: Text(
            'Edit',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          height: 32,
          child: Text(
            'Delete',
            style: TextStyle(color: AppColors.neonRed, fontSize: 12),
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit') widget.onEdit();
      if (value == 'delete') widget.onDelete();
    });
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 28,
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }
}

// ── Console Output ───────────────────────────────────────────────────────────

class _Console extends StatefulWidget {
  const _Console({required this.state, required this.scrollController});
  final RunState state;
  final ScrollController scrollController;

  @override
  State<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<_Console> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _copyAll() {
    final session = widget.state.activeSession;
    if (session == null) return;
    final text = session.output.map((l) => l.text).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Output copied to clipboard'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<RunCubit>();
    final session = widget.state.activeSession;

    if (session == null) {
      return _EmptyConsole(
        hasWorkspace: widget.state.workspacePath != null,
        configs: widget.state.configs,
      );
    }

    final output = session.output;
    final isRunning = session.status == RunStatus.running;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyA) {
          _copyAll();
        }
      },
      child: GestureDetector(
        onTap: _focusNode.requestFocus,
        child: Container(
          color: colors.terminalBackground,
          child: Column(
            children: [
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: colors.surface,
                child: ClipRect(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '> ${session.config.command}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(120),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (session.startedAt != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(session.startedAt!),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(120),
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Copy all (⌘A)',
                        child: InkWell(
                          onTap: _copyAll,
                          child: Icon(
                            Icons.copy_outlined,
                            size: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(120),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: isRunning ? 'Already running' : 'Re-run',
                        child: InkWell(
                          onTap:
                              isRunning
                                  ? null
                                  : () => cubit.restartSession(session.id),
                          child: Icon(
                            Icons.replay_rounded,
                            size: 12,
                            color:
                                isRunning
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withAlpha(80)
                                    : AppColors.neonGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
              Expanded(
                child:
                    output.isEmpty
                        ? Center(
                          child: Text(
                            'No output yet…',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(120),
                              fontSize: 12,
                            ),
                          ),
                        )
                        : _FullLogView(
                          output: output,
                          scrollController: widget.scrollController,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// Renders all output lines as a single selectable block.
/// Ctrl+A / ⌘A selects everything; ⌘C copies the selection.
class _FullLogView extends StatelessWidget {
  const _FullLogView({required this.output, required this.scrollController});

  final List<RunOutputLine> output;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    // Build a TextSpan that colours error lines red / orange.
    final spans = <TextSpan>[];
    for (final line in output) {
      final t = line.text;
      final Color color;
      if (t.startsWith('\n[Process exited')) {
        color = const Color(0xFF44446A);
      } else if (t.startsWith('Reloaded') || t.contains('🔥')) {
        color = AppColors.neonGreen;
      } else if (line.isError) {
        color = AppColors.neonRed;
      } else if (t.toLowerCase().contains('error')) {
        color = AppColors.neonOrange;
      } else {
        color = AppColors.terminalText;
      }
      spans.add(TextSpan(text: '$t\n', style: TextStyle(color: color)));
    }

    return Scrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SelectableText.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            children: spans,
          ),
          // Let the OS handle Ctrl+A / ⌘A for select-all within this widget.
          contextMenuBuilder:
              (context, editableTextState) =>
                  AdaptiveTextSelectionToolbar.editableText(
                    editableTextState: editableTextState,
                  ),
        ),
      ),
    );
  }
}

class _EmptyConsole extends StatelessWidget {
  const _EmptyConsole({required this.hasWorkspace, required this.configs});

  final bool hasWorkspace;
  final List<RunConfig> configs;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<RunCubit>();

    return Container(
      color: colors.terminalBackground,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primary.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  size: 32,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Run Configurations',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasWorkspace
                    ? 'Select a configuration from the left panel to run it'
                    : 'Open a workspace to get started',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                  fontSize: 12,
                ),
              ),
              if (hasWorkspace && configs.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  children:
                      configs
                          .take(3)
                          .map(
                            (c) => _RunQuickButton(
                              config: c,
                              onTap: () => cubit.startRun(c),
                            ),
                          )
                          .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RunQuickButton extends StatelessWidget {
  const _RunQuickButton({required this.config, required this.onTap});
  final RunConfig config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dotColor = config.color ?? colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 12, color: dotColor),
            const SizedBox(width: 4),
            Text(
              config.name,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pulsing dot animation ────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder:
          (_, __) => Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withAlpha((_anim.value * 255).round()),
            ),
          ),
    );
  }
}
