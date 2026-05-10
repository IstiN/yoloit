import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';

/// Opens [NewAgentSessionDialog] with the terminal cubit from [context].
void showNewAgentSessionDialog(
  BuildContext context, {
  required Workspace workspace,
  required Map<String, List<WorktreeEntry>> worktrees,
  VoidCallback? onSpawned,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: context.read<TerminalCubit>(),
      child: NewAgentSessionDialog(
        workspace: workspace,
        worktrees: worktrees,
        onSpawned: onSpawned ?? () {},
      ),
    ),
  );
}

class NewAgentSessionDialog extends StatefulWidget {
  const NewAgentSessionDialog({
    super.key,
    required this.workspace,
    required this.worktrees,
    required this.onSpawned,
  });

  final Workspace workspace;
  final Map<String, List<WorktreeEntry>> worktrees;
  final VoidCallback onSpawned;

  @override
  State<NewAgentSessionDialog> createState() => _NewAgentSessionDialogState();
}

class _NewAgentSessionDialogState extends State<NewAgentSessionDialog> {
  AgentType _agentType = AgentType.copilot;
  late Map<String, String?> _selectedBranches; // repoPath → branch name
  final _nameController = TextEditingController();

  /// repoPath → all local branch names
  Map<String, List<String>> _allBranches = {};

  /// repoPath → set of already-checked-out branch names (via existing worktrees)
  Map<String, Set<String>> _checkedOutBranches = {};

  /// repoPath → busy flag
  final Map<String, bool> _busy = {};

  /// repoPath → error string
  final Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    // Default selection = branch checked out at the configured repo path.
    // The worktrees list may contain multiple entries (main + additional worktrees).
    // We match the configured path to the correct worktree entry so that,
    // e.g., a workspace path pointing to a non-main worktree defaults to its branch.
    _selectedBranches = {
      for (final e in widget.worktrees.entries)
        if (e.value.isNotEmpty)
          e.key: (e.value.firstWhere(
                    (wt) => wt.path == e.key,
                    orElse: () => e.value.first,
                  ).branch ??
                  e.value.first.commit),
    };
    _checkedOutBranches = {
      for (final e in widget.worktrees.entries)
        e.key: e.value.map((wt) => wt.branch).whereType<String>().toSet(),
    };
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final result = <String, List<String>>{};
    for (final repoPath in widget.worktrees.keys) {
      result[repoPath] = await WorktreeService.instance.listBranches(repoPath);
    }
    if (mounted) setState(() => _allBranches = result);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Returns the worktree path for a branch, creating one if it doesn't exist yet.
  String _worktreePath(String repoPath, String branch) => p.join(
        p.dirname(repoPath),
        '${p.basename(repoPath)}__${branch.replaceAll('/', '-')}',
      );

  /// Ensures a worktree exists for [branch] in [repoPath].
  /// [createNew] = create a brand-new git branch.
  Future<bool> _ensureWorktree(
    String repoPath,
    String branch, {
    bool createNew = false,
  }) async {
    final alreadyOut = _checkedOutBranches[repoPath]?.contains(branch) ?? false;
    if (alreadyOut) return true; // main worktree already has it
    setState(() {
      _busy[repoPath] = true;
      _errors[repoPath] = null;
    });
    final wtPath = _worktreePath(repoPath, branch);
    final err = await WorktreeService.instance.addWorktree(
      repoPath,
      wtPath,
      branch,
      createNewBranch: createNew,
    );
    if (!mounted) return false;
    if (err != null) {
      setState(() {
        _busy[repoPath] = false;
        _errors[repoPath] = err;
      });
      return false;
    }
    setState(() {
      _busy[repoPath] = false;
      _checkedOutBranches[repoPath] = {
        ..._checkedOutBranches[repoPath] ?? {},
        branch,
      };
    });
    return true;
  }

  bool get _anyBusy => _busy.values.any((v) => v);

  /// Resolves the worktree path for the selected branch in [repoPath].
  String? _resolvedPath(String repoPath) {
    final branch = _selectedBranches[repoPath];
    if (branch == null) return null;
    // Find existing worktree with that branch
    final existing = widget.worktrees[repoPath]
        ?.where((wt) => wt.branch == branch)
        .firstOrNull;
    if (existing != null) return existing.path;
    return _worktreePath(repoPath, branch);
  }

  Future<void> _confirm() async {
    // Ensure all selected branches have worktrees
    for (final entry in _selectedBranches.entries) {
      final repoPath = entry.key;
      final branch = entry.value;
      if (branch == null) continue;
      final ok = await _ensureWorktree(repoPath, branch);
      if (!ok) return; // stop on first error
    }

    if (!mounted) return;
    final cubit = context.read<TerminalCubit>();
    final name = _nameController.text.trim();
    // Generate ID here so we can rename after spawn with the same ID.
    final sessionId = '${_agentType.name}_${DateTime.now().millisecondsSinceEpoch}';

    final contexts = <String, String>{};
    for (final repoPath in widget.worktrees.keys) {
      final path = _resolvedPath(repoPath);
      // Only include if the session is on a DIFFERENT (worktree) path.
      // When path == repoPath the session is on the main checkout – no agent
      // dir needed; worktreeContexts stays null so the graph builder falls back
      // to ws.paths which is simpler and unambiguous.
      if (path != null && path != repoPath) contexts[repoPath] = path;
    }

    await cubit.spawnSession(
      type: _agentType,
      workspacePath: widget.workspace.workspaceDir,
      workspaceId: widget.workspace.id,
      savedSessionId: sessionId,   // sets the ID, isRestore=false so command still runs
      worktreeContexts: contexts.isEmpty ? null : contexts,
      enabledSkills: widget.workspace.enabledSkills,
    );
    if (name.isNotEmpty) cubit.renameSession(sessionId, name);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onSpawned();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New Agent Session',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _SectionLabel('Agent Type'),
              const SizedBox(height: 6),
              _agentTypeSelector(colors),
              ...widget.worktrees.entries.map(
                (e) => _buildRepoPicker(e.key, e.value, colors),
              ),
              const SizedBox(height: 12),
              _SectionLabel('Session Name (optional)'),
              const SizedBox(height: 6),
              _styledField(
                controller: _nameController,
                hint: 'Leave empty to use agent name',
                colors: colors,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: AppColors.textHighlight,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _anyBusy ? null : _confirm,
                    child: const Text('Start', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentTypeSelector(AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceHighlight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AgentType>(
          value: _agentType,
          dropdownColor: colors.surfaceHighlight,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
          isExpanded: true,
          items: AgentType.values.map((t) {
            return DropdownMenuItem(
              value: t,
              child: Text('${t.iconLabel}  ${t.displayName}'),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _agentType = v);
          },
        ),
      ),
    );
  }

  Widget _buildRepoPicker(
    String repoPath,
    List<WorktreeEntry> worktrees,
    AppColorScheme colors,
  ) {
    if (worktrees.isEmpty) return const SizedBox.shrink();
    final repoName = p.basename(repoPath);
    final isBusy = _busy[repoPath] ?? false;
    final error = _errors[repoPath];
    final allBranches = _allBranches[repoPath] ?? [];
    final checked = _checkedOutBranches[repoPath] ?? {};
    final currentBranch = _selectedBranches[repoPath] ?? worktrees.first.branch ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 11, color: colors.primary),
            const SizedBox(width: 4),
            _SectionLabel(repoName),
          ],
        ),
        const SizedBox(height: 6),
        if (isBusy)
          _BusyRow(colors: colors)
        else
          _BranchPickerField(
            currentBranch: currentBranch,
            allBranches: allBranches,
            checkedOutBranches: checked,
            colors: colors,
            onBranchSelected: (branch, isNew) async {
              setState(() => _selectedBranches[repoPath] = branch);
              if (isNew) {
                await _ensureWorktree(repoPath, branch, createNew: true);
              } else if (!checked.contains(branch)) {
                // Existing branch, not yet a worktree — we'll create it at confirm
              }
            },
          ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: const TextStyle(color: Colors.redAccent, fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _styledField({
    required TextEditingController controller,
    required String hint,
    required AppColorScheme colors,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 12),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: colors.surfaceHighlight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colors.primary),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BranchPickerField — uses OverlayPortal so the dropdown floats above layout
// ---------------------------------------------------------------------------

/// A searchable branch picker that shows a floating dropdown (via OverlayPortal)
/// so the parent dialog never resizes when the list opens.
class _BranchPickerField extends StatefulWidget {
  const _BranchPickerField({
    required this.currentBranch,
    required this.allBranches,
    required this.checkedOutBranches,
    required this.colors,
    required this.onBranchSelected,
  });

  final String currentBranch;
  final List<String> allBranches;
  final Set<String> checkedOutBranches;
  final AppColorScheme colors;
  final Future<void> Function(String branch, bool isNew) onBranchSelected;

  @override
  State<_BranchPickerField> createState() => _BranchPickerFieldState();
}

class _BranchPickerFieldState extends State<_BranchPickerField> {
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();
  final _fieldKey = GlobalKey();
  late final TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  bool get _open => _overlayController.isShowing;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentBranch);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_BranchPickerField old) {
    super.didUpdateWidget(old);
    if (old.currentBranch != widget.currentBranch && !_open) {
      _ctrl.text = widget.currentBranch;
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {
        _query = '';
        _ctrl.selection =
            TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      });
      _overlayController.show();
    }
  }

  void _select(String branch, {bool isNew = false}) {
    _ctrl.text = branch;
    _focusNode.unfocus();
    _overlayController.hide();
    setState(() => _query = '');
    widget.onBranchSelected(branch, isNew);
  }

  void _close() {
    _ctrl.text = widget.currentBranch;
    _focusNode.unfocus();
    _overlayController.hide();
    setState(() => _query = '');
  }

  double get _fieldWidth {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 380;
  }

  List<String> get _filtered {
    final q = _query.toLowerCase();
    if (q.isEmpty) return widget.allBranches;
    return widget.allBranches
        .where((b) => b.toLowerCase().contains(q))
        .toList();
  }

  bool get _exactMatch =>
      widget.allBranches.any((b) => b.toLowerCase() == _query.toLowerCase());

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (_) => _buildOverlay(colors),
        child: TextField(
          key: _fieldKey,
          controller: _ctrl,
          focusNode: _focusNode,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
          onChanged: (v) => setState(() => _query = v.trim()),
          onSubmitted: (v) {
            final q = v.trim();
            if (q.isEmpty) {
              _close();
              return;
            }
            _exactMatch ? _select(q) : _select(q, isNew: true);
          },
          decoration: InputDecoration(
            hintText: 'Search or create branch…',
            hintStyle:
                TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 12),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            filled: true,
            fillColor: colors.surfaceHighlight,
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child:
                  Icon(Icons.call_split, size: 13, color: colors.primary),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
            suffixIcon: _open
                ? GestureDetector(
                    onTap: _close,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.close,
                          size: 14, color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.unfold_more,
                        size: 14, color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface),
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(AppColorScheme colors) {
    final filtered = _filtered;
    final showCreate = _query.isNotEmpty && !_exactMatch;
    final width = _fieldWidth;

    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: width,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: colors.surfaceHighlight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.primary),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  if (filtered.isEmpty && !showCreate)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        'No branches found',
                        style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 11),
                      ),
                    ),
                  ...filtered.map((branch) {
                    final isActive =
                        widget.checkedOutBranches.contains(branch);
                    return _BranchRow(
                      branch: branch,
                      isActive: isActive,
                      isCurrent: branch == widget.currentBranch,
                      colors: colors,
                      onTap: () => _select(branch),
                    );
                  }),
                  if (showCreate) ...[
                    if (filtered.isNotEmpty)
                      Divider(
                          height: 1,
                          color: colors.border,
                          indent: 12,
                          endIndent: 12),
                    _CreateRow(
                      branchName: _query,
                      colors: colors,
                      onTap: () => _select(_query, isNew: true),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row widgets
// ---------------------------------------------------------------------------

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.isActive,
    required this.isCurrent,
    required this.colors,
    required this.onTap,
  });

  final String branch;
  final bool isActive;
  final bool isCurrent;
  final AppColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.account_tree_outlined : Icons.call_split,
              size: 12,
              color: isActive ? colors.primary : (Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                branch,
                style: TextStyle(
                  color: isCurrent
                      ? Theme.of(context).colorScheme.onSurface
                      : (Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface),
                  fontSize: 12,
                  fontWeight:
                      isCurrent ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrent)
              Icon(Icons.check, size: 12, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

class _CreateRow extends StatelessWidget {
  const _CreateRow({
    required this.branchName,
    required this.colors,
    required this.onTap,
  });

  final String branchName;
  final AppColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, size: 12, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              'Create ',
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 12),
            ),
            Expanded(
              child: Text(
                '"$branchName"',
                style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
          color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 10, letterSpacing: 0.8),
    );
  }
}

class _BusyRow extends StatelessWidget {
  const _BusyRow({required this.colors});
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: colors.primary),
          ),
          const SizedBox(width: 8),
          Text('Creating worktree…',
              style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 12)),
        ],
      ),
    );
  }
}
