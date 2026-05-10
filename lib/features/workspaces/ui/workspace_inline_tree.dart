import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/features/workspaces/ui/new_agent_session_dialog.dart';

class WorkspaceInlineTree extends StatefulWidget {
  const WorkspaceInlineTree({super.key, required this.workspace});

  final Workspace workspace;

  @override
  State<WorkspaceInlineTree> createState() => _WorkspaceInlineTreeState();
}

class _WorkspaceInlineTreeState extends State<WorkspaceInlineTree> {
  /// repoPath → list of worktrees
  Map<String, List<WorktreeEntry>> _worktrees = {};
  bool _loading = true;
  /// repoPath → true if branch-add field is shown
  final Map<String, bool> _showAddBranch = {};
  /// repoPath → controller for branch name input
  final Map<String, TextEditingController> _branchControllers = {};

  @override
  void initState() {
    super.initState();
    _loadWorktrees();
  }

  @override
  void didUpdateWidget(WorkspaceInlineTree old) {
    super.didUpdateWidget(old);
    if (old.workspace.paths != widget.workspace.paths) {
      _loadWorktrees();
    }
  }

  Future<void> _loadWorktrees() async {
    setState(() => _loading = true);
    final result = <String, List<WorktreeEntry>>{};
    for (final path in widget.workspace.paths) {
      result[path] = await WorktreeService.instance.listWorktrees(path);
    }
    if (mounted) {
      setState(() {
        _worktrees = result;
        _loading = false;
      });
    }
  }

  Future<void> _addWorktree(String repoPath, String branchName) async {
    final worktreePath = p.join(
      p.dirname(repoPath),
      '${p.basename(repoPath)}__${branchName.replaceAll('/', '-')}',
    );
    await WorktreeService.instance.addWorktree(
      repoPath,
      worktreePath,
      branchName,
      createNewBranch: true,
    );
    _branchControllers[repoPath]?.clear();
    setState(() => _showAddBranch[repoPath] = false);
    await _loadWorktrees();
  }

  @override
  void dispose() {
    for (final c in _branchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    return BlocBuilder<TerminalCubit, TerminalState>(
      builder: (context, termState) {
        final sessions = termState is TerminalLoaded
            ? termState.allSessions
                .where((s) => s.workspaceId == widget.workspace.id)
                .toList()
            : <AgentSession>[];

        final paths = widget.workspace.paths;
        return Container(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...paths.asMap().entries.map((e) {
                final isLast = e.key == paths.length - 1;
                return _RepoTree(
                  repoPath: e.value,
                  worktrees: _worktrees[e.value] ?? [],
                  sessions: sessions,
                  isLast: isLast && sessions.isEmpty,
                  showAddBranch: _showAddBranch[e.value] ?? false,
                  branchController: _branchControllers.putIfAbsent(
                    e.value,
                    TextEditingController.new,
                  ),
                  onToggleAddBranch: () => setState(
                    () => _showAddBranch[e.value] =
                        !(_showAddBranch[e.value] ?? false),
                  ),
                  onAddBranch: (branch) => _addWorktree(e.value, branch),
                );
              }),
              _SessionsSection(
                workspace: widget.workspace,
                sessions: sessions,
                worktrees: _worktrees,
                onRefresh: _loadWorktrees,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RepoTree extends StatelessWidget {
  const _RepoTree({
    required this.repoPath,
    required this.worktrees,
    required this.sessions,
    required this.isLast,
    required this.showAddBranch,
    required this.branchController,
    required this.onToggleAddBranch,
    required this.onAddBranch,
  });

  final String repoPath;
  final List<WorktreeEntry> worktrees;
  final List<AgentSession> sessions;
  final bool isLast;
  final bool showAddBranch;
  final TextEditingController branchController;
  final VoidCallback onToggleAddBranch;
  final ValueChanged<String> onAddBranch;

  @override
  Widget build(BuildContext context) {
    final repoName = p.basename(repoPath);
    final children = <Widget>[];

    for (var i = 0; i < worktrees.length; i++) {
      final wt = worktrees[i];
      final isLastChild = i == worktrees.length - 1 && !showAddBranch;
      final hasSession = sessions.any((s) =>
          s.worktreeContexts != null &&
          s.worktreeContexts![repoPath] == wt.path);
      children.add(
        _BranchRow(
          entry: wt,
          isLast: isLastChild,
          hasSession: hasSession,
        ),
      );
    }

    if (showAddBranch) {
      children.add(_AddBranchField(
        controller: branchController,
        onSubmit: onAddBranch,
        onCancel: onToggleAddBranch,
      ));
    } else {
      children.add(_AddBranchButton(onTap: onToggleAddBranch));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sessions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
            child: Row(
              children: [
                Icon(Icons.folder_open, size: 14, color: AppColors.neonBlue.withAlpha(180)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    repoName,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ...children,
      ],
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.entry,
    required this.isLast,
    required this.hasSession,
  });

  final WorktreeEntry entry;
  final bool isLast;
  final bool hasSession;

  @override
  Widget build(BuildContext context) {
    final branch = entry.branch ?? entry.commit ?? '(detached)';
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface;
    final dotColor = entry.isMain ? AppColors.neonGreen : hasSession ? AppColors.neonBlue : mutedColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 1, 8, 1),
      child: Row(
        children: [
          Text(
            isLast ? '└─ ' : '├─ ',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          Expanded(
            child: Text(
              branch,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBranchButton extends StatelessWidget {
  const _AddBranchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 1, 8, 1),
        child: Row(
          children: [
            Text('└─ ', style: TextStyle(color: mutedColor, fontSize: 10)),
            Flexible(
              child: Text(
                '＋ new branch...',
                style: TextStyle(color: mutedColor, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddBranchField extends StatelessWidget {
  const _AddBranchField({
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 2, 8, 2),
      child: Row(
        children: [
          Text('└─ ', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 10)),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: colors.primary, fontSize: 11),
              decoration: InputDecoration(
                hintText: 'branch-name',
                hintStyle: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 11),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                filled: false,
                border: InputBorder.none,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: colors.border, width: 1),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: colors.primary, width: 1),
                ),
              ),
              onSubmitted: (v) {
                final branch = v.trim();
                if (branch.isNotEmpty) onSubmit(branch);
              },
              onEditingComplete: () {},
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onCancel,
            child: Icon(Icons.close, size: 11, color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _SessionsSection extends StatelessWidget {
  const _SessionsSection({
    required this.workspace,
    required this.sessions,
    required this.worktrees,
    required this.onRefresh,
  });

  final Workspace workspace;
  final List<AgentSession> sessions;
  final Map<String, List<WorktreeEntry>> worktrees;
  final VoidCallback onRefresh;

  String _sessionLabel(AgentSession s) {
    if (s.customName?.isNotEmpty == true) return s.customName!;
    if (s.worktreeContexts != null && s.worktreeContexts!.isNotEmpty) {
      // Resolve the actual branch name from the worktree path.
      // worktreeContexts maps repoPath → worktreePath (e.g. ".../yoloit__my_new_branch").
      // We match against the loaded worktrees list first; fall back to stripping
      // the "<repoName>__" prefix from the directory basename.
      final firstEntry = s.worktreeContexts!.entries.first;
      final repoPath = firstEntry.key;
      final worktreePath = firstEntry.value;

      final wtList = worktrees[repoPath] ?? [];
      String? branchName;
      for (final wt in wtList) {
        if (wt.path == worktreePath) {
          branchName = wt.branch;
          break;
        }
      }
      if (branchName == null) {
        final dirName = p.basename(worktreePath);
        final prefix = '${p.basename(repoPath)}__';
        branchName = dirName.startsWith(prefix) ? dirName.substring(prefix.length) : dirName;
      }
      return '${s.type.displayName} · $branchName';
    }
    return s.type.displayName;
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Text(
            'Agent Sessions',
            style: TextStyle(
              color: mutedColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...sessions.asMap().entries.map((e) {
          final isLast = e.key == sessions.length - 1;
          return _SessionRow(
            session: e.value,
            label: _sessionLabel(e.value),
            isLast: isLast,
          );
        }),
        _NewSessionButton(workspace: workspace, worktrees: worktrees, onSpawned: onRefresh),
      ],
    );
  }
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.session,
    required this.label,
    required this.isLast,
  });

  final AgentSession session;
  final String label;
  final bool isLast;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface;
    final statusColor = switch (widget.session.status) {
      AgentStatus.live => AppColors.neonGreen,
      AgentStatus.idle => mutedColor,
      AgentStatus.error => AppColors.neonRed,
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hovered ? colors.surfaceHighlight : colors.background.withAlpha(0),
        padding: const EdgeInsets.fromLTRB(28, 1, 8, 1),
        child: Row(
          children: [
            Text(
              widget.isLast ? '└─ ' : '├─ ',
              style: TextStyle(color: mutedColor, fontSize: 10),
            ),
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            Text(
              widget.session.type.iconLabel,
              style: TextStyle(color: mutedColor, fontSize: 10),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_hovered)
              GestureDetector(
                onTap: () =>
                    context.read<TerminalCubit>().closeSession(widget.session.id),
                child: Icon(Icons.close, size: 12, color: mutedColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _NewSessionButton extends StatelessWidget {
  const _NewSessionButton({
    required this.workspace,
    required this.worktrees,
    required this.onSpawned,
  });

  final Workspace workspace;
  final Map<String, List<WorktreeEntry>> worktrees;
  final VoidCallback onSpawned;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDialog(context),
      child: Builder(
        builder: (context) {
          final mutedColor = Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface;
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 2, 8, 4),
            child: Row(
              children: [
                Text('└─ ', style: TextStyle(color: mutedColor, fontSize: 10)),
                Flexible(
                  child: Text(
                    '＋ New Agent Session',
                    style: TextStyle(color: mutedColor, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDialog(BuildContext context) {
    showNewAgentSessionDialog(
      context,
      workspace: workspace,
      worktrees: worktrees,
      onSpawned: onSpawned,
    );
  }
}

