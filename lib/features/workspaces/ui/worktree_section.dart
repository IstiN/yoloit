

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

class WorktreeSection extends StatefulWidget {
  const WorktreeSection({
    super.key,
    required this.workspacePaths,
    required this.workspaceName,
  });

  final List<String> workspacePaths;
  final String workspaceName;

  @override
  State<WorktreeSection> createState() => _WorktreeSectionState();
}

class _WorktreeSectionState extends State<WorktreeSection> {
  /// path → worktrees for that repo
  Map<String, List<WorktreeEntry>> _worktreesByPath = {};
  Map<String, String?> _errorsByPath = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WorktreeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePaths != widget.workspacePaths) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorsByPath = {};
    });
    final results = <String, List<WorktreeEntry>>{};
    final errors = <String, String?>{};
    for (final path in widget.workspacePaths) {
      try {
        results[path] = await WorktreeService.instance.listWorktrees(path);
        errors[path] = null;
      } catch (e) {
        results[path] = [];
        errors[path] = e.toString();
      }
    }
    if (mounted) {
      setState(() {
        _worktreesByPath = results;
        _errorsByPath = errors;
        _loading = false;
      });
    }
  }

  Future<void> _prune(String path) async {
    await WorktreeService.instance.pruneWorktrees(path);
    await _load();
  }

  Future<void> _removeWorktree(String repoPath, WorktreeEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmRemoveDialog(worktreePath: entry.path),
    );
    if (confirmed != true || !mounted) return;

    final error = await WorktreeService.instance.removeWorktree(
      repoPath,
      entry.path,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(fontSize: 12)),
          backgroundColor: AppColors.neonRed,
        ),
      );
    } else {
      await _load();
    }
  }

  Future<void> _showAddDialog(String repoPath) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddWorktreeDialog(
        repoPath: repoPath,
        onAdded: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final multiRepo = widget.workspacePaths.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 11, color: AppColors.textMuted),
              const SizedBox(width: 5),
              const Flexible(
                child: Text(
                  'Worktrees',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              _SmallIconButton(
                icon: Icons.refresh,
                onTap: _load,
                tooltip: 'Refresh worktrees',
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          )
        else
          for (final path in widget.workspacePaths) ...[
            // Per-repo header when multiple repos
            if (multiRepo)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 11, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        p.basename(path),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    _SmallIconButton(
                      icon: Icons.cleaning_services_outlined,
                      onTap: () => _prune(path),
                      tooltip: 'Prune stale worktrees',
                    ),
                  ],
                ),
              ),
            if (_errorsByPath[path] != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  _errorsByPath[path]!,
                  style: const TextStyle(color: AppColors.neonRed, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else ...[
              ...(_worktreesByPath[path] ?? []).map((entry) => _WorktreeTile(
                    entry: entry,
                    onRemove: entry.isMain ? null : () => _removeWorktree(path, entry),
                  )),
              // Add worktree button (only for single repo, or inline per repo)
              if (!multiRepo)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: GestureDetector(
                    onTap: () => _showAddDialog(path),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add, size: 11, color: AppColors.textMuted),
                          SizedBox(width: 5),
                          Text(
                            'Add worktree',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (multiRepo && (_worktreesByPath[path]?.isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 12, 4),
                  child: GestureDetector(
                    onTap: () => _showAddDialog(path),
                    child: Row(
                      children: [
                        const Icon(Icons.add, size: 10, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          'Add worktree',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (multiRepo && path != widget.workspacePaths.last)
              const Divider(height: 4, thickness: 0.5, indent: 12, endIndent: 12),
          ],
      ],
    );
  }
}

class _WorktreeTile extends StatefulWidget {
  const _WorktreeTile({required this.entry, this.onRemove});

  final WorktreeEntry entry;
  final VoidCallback? onRemove;

  @override
  State<_WorktreeTile> createState() => _WorktreeTileState();
}

class _WorktreeTileState extends State<_WorktreeTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final entry = widget.entry;
    final displayPath = p.basename(entry.path);
    final branchLabel = entry.branch ?? (entry.commit != null ? entry.commit! : 'detached');
    final accentColor = entry.isMain ? colors.primary : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        height: 36,
        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _hovering ? colors.surfaceHighlight : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              entry.isLocked ? Icons.lock_outline : Icons.folder_special_outlined,
              size: 12,
              color: entry.isLocked ? Colors.amber : accentColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayPath,
                          style: TextStyle(
                            color: entry.isMain ? AppColors.textPrimary : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: entry.isMain ? FontWeight.w600 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isMain) ...[
                        SizedBox(width: 4),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.primary.withAlpha(40),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'main',
                            style: TextStyle(
                              color: colors.primaryLight,
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (entry.isLocked) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.lock, size: 9, color: Colors.amber),
                      ],
                    ],
                  ),
                  Text(
                    branchLabel,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (_hovering && widget.onRemove != null)
              GestureDetector(
                onTap: widget.onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 11, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRemoveDialog extends StatelessWidget {
  const _ConfirmRemoveDialog({required this.worktreePath});

  final String worktreePath;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Remove Worktree',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Remove worktree at:\n$worktreePath',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Remove', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddWorktreeDialog extends StatefulWidget {
  const _AddWorktreeDialog({required this.repoPath, required this.onAdded});

  final String repoPath;
  final VoidCallback onAdded;

  @override
  State<_AddWorktreeDialog> createState() => _AddWorktreeDialogState();
}

class _AddWorktreeDialogState extends State<_AddWorktreeDialog> {
  final _pathController = TextEditingController();
  final _newBranchController = TextEditingController();
  List<String> _branches = [];
  String? _selectedBranch;
  bool _createNewBranch = false;
  bool _loading = false;
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _newBranchController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final branches = await WorktreeService.instance.listBranches(widget.repoPath);
    if (mounted) {
      setState(() {
        _branches = branches;
        _selectedBranch = branches.isNotEmpty ? branches.first : null;
        _loadingBranches = false;
      });
    }
  }

  Future<void> _browse() async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Worktree Directory',
    );
    if (dir != null && mounted) {
      _pathController.text = dir;
    }
  }

  Future<void> _submit() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      _showError('Path cannot be empty');
      return;
    }

    final branchOrCommit = _createNewBranch
        ? _newBranchController.text.trim()
        : (_selectedBranch ?? '');
    if (branchOrCommit.isEmpty) {
      _showError('Branch cannot be empty');
      return;
    }

    setState(() => _loading = true);
    final error = await WorktreeService.instance.addWorktree(
      widget.repoPath,
      path,
      branchOrCommit,
      createNewBranch: _createNewBranch,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      _showError(error);
    } else {
      Navigator.of(context).pop();
      widget.onAdded();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        backgroundColor: AppColors.neonRed,
      ),
    );
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_tree_outlined, size: 18, color: AppColors.textPrimary),
                  SizedBox(width: 8),
                  Text(
                    'Add Worktree',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Path row
              const Text(
                'Worktree path',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Material(
                      type: MaterialType.transparency,
                      child: TextField(
                        controller: _pathController,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        decoration: _inputDecoration('e.g. /path/to/worktree', context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _OutlineButton(label: 'Browse', onTap: _browse),
                ],
              ),
              const SizedBox(height: 14),
              // Create new branch toggle
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: _createNewBranch,
                      onChanged: (v) => setState(() => _createNewBranch = v ?? false),
                      activeColor: colors.primary,
                      side: BorderSide(color: colors.border),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Create new branch',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_createNewBranch) ...[
                const Text(
                  'New branch name',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _newBranchController,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                    decoration: _inputDecoration('e.g. feature/my-feature', context),
                  ),
                ),
              ] else ...[
                const Text(
                  'Branch / commit',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 6),
                if (_loadingBranches)
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else if (_branches.isEmpty)
                  const Text(
                    'No branches found',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.border),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: DropdownButton<String>(
                      value: _selectedBranch,
                      isExpanded: true,
                      underline: SizedBox.shrink(),
                      dropdownColor: colors.surfaceElevated,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                      items: _branches
                          .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedBranch = v),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, BuildContext context) {
    final colors = context.appColors;
    return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
        filled: true,
        fillColor: colors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colors.primary),
        ),
      );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(4),
          color: colors.surfaceElevated,
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 12, color: AppColors.textMuted),
        ),
      ),
    );
  }
}
