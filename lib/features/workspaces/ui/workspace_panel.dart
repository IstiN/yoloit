import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/utils/git_init_prompt.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/bloc/skills_state.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/data/workspace_secrets_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/ui/worktree_section.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/workspaces/ui/workspace_inline_tree.dart';

class WorkspacePanel extends StatefulWidget {
  const WorkspacePanel({super.key});

  @override
  State<WorkspacePanel> createState() => WorkspacePanelState();
}

class WorkspacePanelState extends State<WorkspacePanel> {
  bool _showThemePicker = false;

  /// Called from MainShell via GlobalKey to trigger the add-workspace flow.
  void addWorkspace() => _addWorkspace(context);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildWorkspacesList(),
                  _buildSetupSection(),
                ],
              ),
            ),
          ),
          _buildBottomSection(),
        ],
      ),
    );
  }

  Widget _buildWorktreeSection() {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        if (state is! WorkspaceLoaded || state.activeWorkspaceId == null) {
          return const SizedBox.shrink();
        }
        final active = state.workspaces.firstWhere(
          (w) => w.id == state.activeWorkspaceId,
          orElse: () => state.workspaces.first,
        );
        return WorktreeSection(
          workspacePaths: active.paths,
          workspaceName: active.name,
        );
      },
    );
  }

  Widget _buildWorkspacesList() {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        final workspaces = state is WorkspaceLoaded ? state.workspaces : <Workspace>[];
        final activeId = state is WorkspaceLoaded ? state.activeWorkspaceId : null;
        return _WorkspaceList(
          workspaces: workspaces,
          activeId: activeId,
          onAdd: () => _addWorkspace(context),
          onSelect: (ws) => _selectWorkspace(context, ws),
          onRemove: (ws) => _confirmRemoveWorkspace(context, ws),
          onRename: (ws) => _renameWorkspaceDialog(context, ws),
          onSpawnAgent: (ws, type) => _spawnAgent(context, ws, type),
          onColorChange: (ws, color) =>
              context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, color),
          onSecretsOpen: (ws) => _showSecretsDialog(context, ws),
          onAddPath: (ws) => _addPathToWorkspace(context, ws.id),
          onRemovePath: (ws, path) => _confirmRemovePath(context, ws.id, path),
          onAddSkill: (ws) => _showAddSkillDialog(context, ws),
        );
      },
    );
  }

  Widget _buildSetupSection() => const SizedBox.shrink();

  Widget _buildBottomSection() {
    return Column(
      children: [
        _ActiveSessionsPanel(),
        const Divider(height: 1),
        if (_showThemePicker) _buildThemePicker(),
        _SetupItem(
          icon: Icons.color_lens_outlined,
          label: 'Color Themes',
          onTap: () => setState(() => _showThemePicker = !_showThemePicker),
          trailing: Icon(
            _showThemePicker ? Icons.expand_less : Icons.chevron_right,
            size: 14,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildThemePicker() {
    const themes = AppThemePreset.values;
    final current = ThemeManager.instance.current;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: themes.map((t) {
          final isActive = t == current;
          return InkWell(
            onTap: () {
              ThemeManager.instance.setTheme(t);
              setState(() {});
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              decoration: isActive
                  ? BoxDecoration(
                      color: t.color.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: t.color,
                      shape: BoxShape.circle,
                      border: isActive
                          ? Border.all(color: t.color, width: 2)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.label,
                      style: TextStyle(
                        color: isActive ? t.color : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isActive)
                    Icon(Icons.check, size: 12, color: t.color),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _addWorkspace(BuildContext context) async {
    // Step 1: ask for workspace name
    final name = await _showNameDialog(context);
    if (name == null || !context.mounted) return;

    // Step 2: pick at least one folder
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Add Folder to "$name"',
    );
    if (folder == null || !context.mounted) return;

    await maybePromptGitInit(context, folder);
    if (!context.mounted) return;

    final cubit = context.read<WorkspaceCubit>();
    await cubit.addWorkspace(folder, customName: name);

    // Step 3 (optional): offer to add more folders
    while (context.mounted) {
      final addMore = await _showConfirmDialog(
        context,
        title: 'Add Another Folder?',
        message: 'Do you want to add another folder to "$name"?',
        confirmLabel: 'Add Folder',
        isDestructive: false,
      );
      if (!addMore || !context.mounted) break;
      final extra = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Add Folder to "$name"',
      );
      if (extra == null || !context.mounted) break;
      await maybePromptGitInit(context, extra);
      if (!context.mounted) break;
      // Find the newly created workspace by name to get its id
      final state = context.read<WorkspaceCubit>().state;
      if (state is WorkspaceLoaded) {
        final ws = state.workspaces.where((w) => w.name == name).lastOrNull;
        if (ws != null) await cubit.addPathToWorkspace(ws.id, extra);
      }
    }
  }

  Future<String?> _showNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16163A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF32327A)),
        ),
        title: const Text(
          'New Workspace',
          style: TextStyle(color: Color(0xFFE0E0F0), fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFE0E0F0), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Workspace name',
            hintStyle: const TextStyle(color: Color(0xFF6060A0), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF0E0E2A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF32327A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF32327A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF7C7CFF)),
            ),
          ),
          onSubmitted: (v) {
            final trimmed = v.trim();
            if (trimmed.isNotEmpty) Navigator.of(ctx).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.of(ctx).pop(trimmed);
            },
            child: const Text(
              'Next →',
              style: TextStyle(color: Color(0xFF7C7CFF), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addPathToWorkspace(BuildContext context, String workspaceId) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Add Folder to Workspace',
    );
    if (result == null || !context.mounted) return;
    await maybePromptGitInit(context, result);
    if (context.mounted) {
      await context.read<WorkspaceCubit>().addPathToWorkspace(workspaceId, result);
    }
  }

  void _selectWorkspace(BuildContext context, Workspace ws) {
    context.read<WorkspaceCubit>().setActive(ws.id);
    context.read<ReviewCubit>().loadWorkspace(ws.paths);
  }

  void _spawnAgent(BuildContext context, Workspace ws, AgentType type) {
    context.read<WorkspaceCubit>().setActive(ws.id);
    context.read<TerminalCubit>().spawnSession(
          type: type,
          workspacePath: ws.workspaceDir,
          workspaceId: ws.id,
        );
  }

  void _showSecretsDialog(BuildContext context, Workspace ws) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SecretsDialog(workspaceId: ws.id, workspaceName: ws.name),
    );
  }

  void _showAddSkillDialog(BuildContext context, Workspace ws) {
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<SkillsCubit>(),
        child: _AddSkillToWorkspaceDialog(workspace: ws),
      ),
    );
  }

  Future<void> _renameWorkspaceDialog(BuildContext context, Workspace ws) async {
    final controller = TextEditingController(text: ws.name);
    controller.selection = TextSelection(baseOffset: 0, extentOffset: ws.name.length);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16163A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF32327A)),
        ),
        title: const Text(
          'Rename Workspace',
          style: TextStyle(color: Color(0xFFE0E0F0), fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFE0E0F0), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Workspace name',
            hintStyle: const TextStyle(color: Color(0xFF6060A0), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF0E0E2A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF32327A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF32327A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF7C7CFF)),
            ),
          ),
          onSubmitted: (v) {
            final trimmed = v.trim();
            if (trimmed.isNotEmpty) Navigator.of(ctx).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.of(ctx).pop(trimmed);
            },
            child: const Text(
              'Rename',
              style: TextStyle(color: Color(0xFF7C7CFF), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result != ws.name && context.mounted) {
      // Defer the emit until after the dialog-dismiss frame is fully built.
      // Calling renameWorkspace synchronously here can fire a BlocBuilder
      // rebuild while the dialog's InheritedWidget subtree is still
      // deactivating, triggering '_dependents.isEmpty' in framework.dart.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<WorkspaceCubit>().renameWorkspace(ws.id, result);
        }
      });
    }
  }

  Future<void> _confirmRemoveWorkspace(BuildContext context, Workspace ws) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Remove Workspace',
      message: 'Remove "${ws.name}"? This will not delete your files.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (confirmed && context.mounted) {
      await context.read<WorkspaceCubit>().removeWorkspace(ws.id);
    }
  }

  Future<void> _confirmRemovePath(BuildContext context, String workspaceId, String path) async {
    final name = path.split('/').last;
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Remove Folder',
      message: 'Remove "$name" from this workspace?',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (confirmed && context.mounted) {
      await context.read<WorkspaceCubit>().removePathFromWorkspace(workspaceId, path);
    }
  }

  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16163A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF32327A)),
        ),
        title: Text(title, style: const TextStyle(color: Color(0xFFE0E0F0), fontSize: 14)),
        content: Text(message, style: const TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: isDestructive ? Colors.red.shade300 : const Color(0xFF7C7CFF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ─── Path Chip ───────────────────────────────────────────────────────────────

class _PathChip extends StatefulWidget {
  const _PathChip({required this.path, this.onRemove});
  final String path;
  final VoidCallback? onRemove;

  @override
  State<_PathChip> createState() => _PathChipState();
}

class _PathChipState extends State<_PathChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = widget.path.split('/').last;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: widget.path,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, size: 9, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_hovering && widget.onRemove != null) ...[
                const SizedBox(width: 3),
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Icon(Icons.close, size: 9, color: Colors.red.shade300),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Workspace list with sequential active-card transition ───────────────────

class _WorkspaceList extends StatefulWidget {
  const _WorkspaceList({
    required this.workspaces,
    required this.activeId,
    required this.onAdd,
    required this.onSelect,
    required this.onRemove,
    required this.onRename,
    required this.onSpawnAgent,
    required this.onColorChange,
    required this.onSecretsOpen,
    required this.onAddPath,
    required this.onRemovePath,
    required this.onAddSkill,
  });
  final List<Workspace> workspaces;
  final String? activeId;
  final VoidCallback onAdd;
  final void Function(Workspace) onSelect;
  final void Function(Workspace) onRemove;
  final void Function(Workspace) onRename;
  final void Function(Workspace, AgentType) onSpawnAgent;
  final void Function(Workspace, Color) onColorChange;
  final void Function(Workspace) onSecretsOpen;
  final void Function(Workspace) onAddPath;
  final void Function(Workspace, String) onRemovePath;
  final void Function(Workspace) onAddSkill;

  @override
  State<_WorkspaceList> createState() => _WorkspaceListState();
}

class _WorkspaceListState extends State<_WorkspaceList> {
  /// The active ID currently DISPLAYED (may lag behind real activeId during transition).
  String? _displayedActiveId;
  bool _transitioning = false;

  @override
  void initState() {
    super.initState();
    _displayedActiveId = widget.activeId;
  }

  @override
  void didUpdateWidget(_WorkspaceList old) {
    super.didUpdateWidget(old);
    if (widget.activeId != old.activeId && !_transitioning) {
      // Step 1: fade out old card (keep _displayedActiveId = old)
      setState(() => _transitioning = true);
      // Step 2: after fade-out delay, show new card
      Future.delayed(const Duration(milliseconds: 420), () {
        if (mounted) {
          setState(() {
            _displayedActiveId = widget.activeId;
            _transitioning = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
          child: Row(
            children: [
              const Flexible(
                child: Text(
                  'Workspaces / Repositories',
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
                icon: Icons.add,
                onTap: widget.onAdd,
                tooltip: 'Add workspace',
              ),
            ],
          ),
        ),
        if (widget.workspaces.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: widget.onAdd,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.folder_open_outlined, size: 14, color: AppColors.textMuted),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Open a folder...',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...widget.workspaces.map((ws) {
            final isActive = ws.id == _displayedActiveId;
            final accentColor = ws.color ?? colors.primary;
            final tile = _WorkspaceTile(
              workspace: ws,
              isActive: isActive,
              suppressDecoration: isActive,
              onTap: () => widget.onSelect(ws),
              onRemove: () => widget.onRemove(ws),
              onRename: () => widget.onRename(ws),
              onSpawnAgent: (type) => widget.onSpawnAgent(ws, type),
              onColorChange: (color) => widget.onColorChange(ws, color),
              onSecretsOpen: () => widget.onSecretsOpen(ws),
              onAddPath: () => widget.onAddPath(ws),
              onRemovePath: (path) => widget.onRemovePath(ws, path),
              onAddSkill: () => widget.onAddSkill(ws),
            );
            if (!isActive) return tile;
            return _ActiveWorkspaceCard(
              key: ValueKey(ws.id),
              accentColor: accentColor,
              tile: tile,
              workspace: ws,
              // When transitioning, play fade-out instead of fade-in.
              fadeOut: _transitioning,
            );
          }),
      ],
    );
  }
}



class _ActiveWorkspaceCard extends StatefulWidget {
  const _ActiveWorkspaceCard({
    super.key,
    required this.accentColor,
    required this.tile,
    required this.workspace,
    this.fadeOut = false,
  });
  final Color accentColor;
  final Widget tile;
  final Workspace workspace;
  final bool fadeOut;

  @override
  State<_ActiveWorkspaceCard> createState() => _ActiveWorkspaceCardState();
}

class _ActiveWorkspaceCardState extends State<_ActiveWorkspaceCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _borderAnim;
  Animation<double>? _treeAnim;

  void _initAnimations() {
    _ctrl?.dispose();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _borderAnim = CurvedAnimation(
      parent: _ctrl!,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _treeAnim = CurvedAnimation(
      parent: _ctrl!,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    );
  }

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  @override
  void reassemble() {
    // Hot reload: re-create animations if they were lost.
    super.reassemble();
    if (_ctrl == null) _initAnimations();
  }

  @override
  void didUpdateWidget(_ActiveWorkspaceCard old) {
    super.didUpdateWidget(old);
    if (widget.fadeOut && !old.fadeOut) {
      _ctrl?.reverse();
    } else if (!widget.fadeOut && old.fadeOut) {
      _ctrl?.forward();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final borderAnim = _borderAnim ?? const AlwaysStoppedAnimation(1.0);
    final treeAnim = _treeAnim ?? const AlwaysStoppedAnimation(1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Stack(
        children: [
          // Layer 1 (behind): fading border + background decoration.
          // The Positioned.fill sizes itself to the Column (layer 2) below.
          Positioned.fill(
            child: FadeTransition(
              opacity: borderAnim,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withAlpha(80)),
                ),
              ),
            ),
          ),
          // Layer 2 (front): tile always visible + collapsing tree.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.tile, // never fades — no blinking
              ClipRect(
                child: SizeTransition(
                  sizeFactor: treeAnim,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: borderAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 1, thickness: 1, color: accent.withAlpha(50)),
                        WorkspaceInlineTree(workspace: widget.workspace),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Workspace Tile ───────────────────────────────────────────────────────────

class _WorkspaceTile extends StatefulWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.isActive,
    required this.onTap,
    required this.onRemove,
    required this.onRename,
    required this.onSpawnAgent,
    required this.onColorChange,
    required this.onSecretsOpen,
    required this.onAddPath,
    required this.onRemovePath,
    required this.onAddSkill,
    this.suppressDecoration = false,
  });

  final Workspace workspace;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onRename;
  final void Function(AgentType) onSpawnAgent;
  final void Function(Color) onColorChange;
  final VoidCallback onSecretsOpen;
  final VoidCallback onAddPath;
  final void Function(String path) onRemovePath;
  final VoidCallback onAddSkill;
  /// When true the tile renders without its own margin/border/background —
  /// a parent container provides the decoration instead.
  final bool suppressDecoration;

  @override
  State<_WorkspaceTile> createState() => _WorkspaceTileState();
}

class _WorkspaceTileState extends State<_WorkspaceTile> {
  bool _hovering = false;
  bool _showColorPicker = false;

  static const _palette = [
    Color(0xFFC026D3), // purple (default)
    Color(0xFF2563EB), // blue
    Color(0xFF16A34A), // green
    Color(0xFFD97706), // amber
    Color(0xFFDC2626), // red
    Color(0xFF0891B2), // cyan
    Color(0xFFDB2777), // pink
    Color(0xFF6D28D9), // violet
  ];

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final offset = button.localToGlobal(Offset(button.size.width, 0), ancestor: overlay);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx - 160,
        offset.dy,
        offset.dx,
        offset.dy + 200,
      ),
      color: const Color(0xFF16163A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: const Color(0xFF32327A)),
      ),
      items: [
        for (final type in AgentType.values)
          PopupMenuItem(
            value: 'spawn_${type.name}',
            height: 36,
            child: Row(children: [
              Text(type.iconLabel, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Text('Start ${type.displayName}', style: const TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
            ]),
          ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'rename',
          height: 36,
          child: Row(children: [
            const Icon(Icons.drive_file_rename_outline, size: 14, color: Color(0xFFB0B0D0)),
            const SizedBox(width: 8),
            const Text('Rename', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
          ]),
        ),
        PopupMenuItem(
          value: 'add_folder',
          height: 36,
          child: Row(children: [
            const Icon(Icons.create_new_folder_outlined, size: 14, color: Color(0xFFB0B0D0)),
            const SizedBox(width: 8),
            const Text('Add Folder', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
          ]),
        ),
        PopupMenuItem(
          value: 'add_skill',
          height: 36,
          child: Row(children: [
            const Icon(Icons.extension_outlined, size: 14, color: Color(0xFFB0B0D0)),
            const SizedBox(width: 8),
            const Text('Add Skill', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
          ]),
        ),
        PopupMenuItem(
          value: 'secrets',
          height: 36,
          child: Row(children: [
            const Icon(Icons.key_outlined, size: 14, color: Color(0xFFB0B0D0)),
            const SizedBox(width: 8),
            const Text('Workspace Secrets', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
          ]),
        ),
        PopupMenuItem(
          value: 'remove',
          height: 36,
          child: Row(children: [
            Icon(Icons.close, size: 14, color: Colors.red.shade300),
            const SizedBox(width: 8),
            Text('Remove', style: TextStyle(color: Colors.red.shade300, fontSize: 12)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      if (value == 'rename') {
        widget.onRename();
      } else if (value == 'add_folder') {
        widget.onAddPath();
      } else if (value == 'add_skill') {
        widget.onAddSkill();
      } else if (value == 'secrets') {
        widget.onSecretsOpen();
      } else if (value == 'remove') {
        widget.onRemove();
      } else if (value.startsWith('spawn_')) {
        final typeName = value.substring('spawn_'.length);
        final type = AgentType.values.firstWhere((t) => t.name == typeName);
        widget.onSpawnAgent(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ws = widget.workspace;
    final accentColor = ws.color ?? colors.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
      }),
      child: Semantics(
        label: '${ws.name} workspace${widget.isActive ? ', active' : ''}',
        button: true,
        selected: widget.isActive,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: widget.suppressDecoration
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: EdgeInsets.all(10),
            decoration: widget.suppressDecoration
                ? const BoxDecoration()
                : BoxDecoration(
                    color: widget.isActive
                        ? accentColor.withAlpha(30)
                        : _hovering
                            ? colors.surfaceHighlight
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: widget.isActive
                        ? Border.all(color: accentColor.withAlpha(80))
                        : null,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Color dot — click to open color picker
                    GestureDetector(
                      onTap: () => setState(() => _showColorPicker = !_showColorPicker),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withAlpha(60),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ws.name,
                        style: TextStyle(
                          color: widget.isActive ? AppColors.textPrimary : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: widget.isActive ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !widget.isActive,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.neonGreen.withAlpha(30),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              color: AppColors.neonGreen,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ⋯ menu and delete — only visible on hover
                    if (_hovering) ...[
                      _SmallIconButton(
                        icon: Icons.delete_outline,
                        onTap: widget.onRemove,
                        tooltip: 'Remove workspace',
                        color: Colors.red.shade300,
                      ),
                      Builder(
                        builder: (ctx) => _SmallIconButton(
                          icon: Icons.more_horiz,
                          onTap: () => _showMenu(ctx),
                          tooltip: 'More actions',
                        ),
                      ),
                    ],
                  ],
                ),
                // Color picker row
                if (_showColorPicker) ...[
                  SizedBox(height: 8),
                  Row(
                    children: _palette.map((c) {
                      final selected = (ws.color ?? colors.primary) == c;
                      return GestureDetector(
                        onTap: () {
                          widget.onColorChange(c);
                          setState(() => _showColorPicker = false);
                        },
                        child: Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                // Folder path chips — one per referenced folder
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    ...ws.paths.map((path) => _PathChip(
                          path: path,
                          onRemove: ws.paths.length > 1
                              ? () => widget.onRemovePath(path)
                              : null,
                        )),
                  ],
                ),
                if (ws.gitBranch != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.alt_route, size: 10, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          'Git Branch: ${ws.gitBranch}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (ws.addedLines > 0 || ws.removedLines > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (ws.addedLines > 0)
                        Text(
                          '+${ws.addedLines}',
                          style: const TextStyle(
                            color: AppColors.neonGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (ws.addedLines > 0 && ws.removedLines > 0)
                        const Text(' / ', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      if (ws.removedLines > 0)
                        Text(
                          '-${ws.removedLines}',
                          style: const TextStyle(
                            color: AppColors.neonRed,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const Text(
                        ' lines',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupItem extends StatefulWidget {
  const _SetupItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_SetupItem> createState() => _SetupItemState();
}

class _SetupItemState extends State<_SetupItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        label: widget.label,
        button: true,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 100),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _hovering ? colors.surfaceHighlight : Colors.transparent,
            child: Row(
              children: [
                Icon(widget.icon, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
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
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Semantics(
        label: tooltip,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon, size: 12, color: color ?? AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}

class _SecretsDialog extends StatefulWidget {
  const _SecretsDialog({required this.workspaceId, required this.workspaceName});

  final String workspaceId;
  final String workspaceName;

  @override
  State<_SecretsDialog> createState() => _SecretsDialogState();
}

class _SecretsDialogState extends State<_SecretsDialog> {
  Map<String, String> _secrets = {};
  bool _loading = true;
  // Track revealed state per row index
  final Set<int> _revealed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await WorkspaceSecretsService.instance.load(widget.workspaceId);
    if (mounted) setState(() { _secrets = Map.from(loaded); _loading = false; });
  }

  void _addEntry() {
    setState(() => _secrets[''] = '');
  }

  Future<void> _save() async {
    await WorkspaceSecretsService.instance.save(widget.workspaceId, _secrets);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final entries = _secrets.entries.toList();
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
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🔐 Workspace Secrets',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Injected as env vars when launching agents in ${widget.workspaceName}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No secrets yet. Add a KEY=VALUE pair.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final key = entries[i].key;
                      final value = entries[i].value;
                      final revealed = _revealed.contains(i);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _SecretTextField(
                                initialValue: key,
                                hint: 'KEY',
                                onChanged: (newKey) {
                                  final val = _secrets.remove(key) ?? value;
                                  setState(() => _secrets[newKey] = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: _SecretTextField(
                                initialValue: value,
                                hint: 'VALUE',
                                obscure: !revealed,
                                onChanged: (v) => setState(() => _secrets[key] = v),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                              splashRadius: 14,
                              tooltip: revealed ? 'Hide' : 'Reveal',
                              onPressed: () => setState(() {
                                if (revealed) { _revealed.remove(i); } else { _revealed.add(i); }
                              }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.neonRed),
                              splashRadius: 14,
                              tooltip: 'Delete',
                              onPressed: () => setState(() => _secrets.remove(key)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _addEntry,
                  icon: Icon(Icons.add, size: 14),
                  label: Text('Add secret', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: colors.primary),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecretTextField extends StatelessWidget {
  const _SecretTextField({
    required this.initialValue,
    required this.hint,
    required this.onChanged,
    this.obscure = false,
  });

  final String initialValue;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextFormField(
      initialValue: initialValue,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
      ),
      onChanged: onChanged,
    );
  }
}

// ─── Active Sessions Panel ────────────────────────────────────────────────────

class _ActiveSessionsPanel extends StatefulWidget {
  const _ActiveSessionsPanel();

  @override
  State<_ActiveSessionsPanel> createState() => _ActiveSessionsPanelState();
}

class _ActiveSessionsPanelState extends State<_ActiveSessionsPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return BlocBuilder<TerminalCubit, TerminalState>(
      builder: (context, termState) {
        final agentSessions = termState is TerminalLoaded
            ? termState.allSessions
            : <AgentSession>[];
        return BlocBuilder<RunCubit, RunState>(
          builder: (context, runState) {
            final runSessions = runState.sessions;
            final total = agentSessions.length + runSessions.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        Icon(Icons.terminal, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Active Sessions',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        if (total > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.primary.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$total',
                              style: TextStyle(
                                color: colors.primaryLight,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded) ...[
                  ...agentSessions.map((s) => _AgentSessionRow(session: s)),
                  ...runSessions.map((s) => _RunSessionRow(session: s)),
                  if (total == 0)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        'No active sessions',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 10),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

// ─── Agent session row (terminal) ────────────────────────────────────────────

class _AgentSessionRow extends StatefulWidget {
  const _AgentSessionRow({required this.session});
  final AgentSession session;

  @override
  State<_AgentSessionRow> createState() => _AgentSessionRowState();
}

class _AgentSessionRowState extends State<_AgentSessionRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = widget.session;
    final isLive = s.status == AgentStatus.live;
    final dotColor = isLive ? AppColors.neonGreen : AppColors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        color: _hovering ? colors.surfaceHighlight : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(s.type.iconLabel, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                s.workspacePath.split('/').last,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AnimatedOpacity(
              opacity: _hovering ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !_hovering,
                child: GestureDetector(
                  onTap: () =>
                      context.read<TerminalCubit>().closeSession(s.id),
                  child: Tooltip(
                    message: 'Kill session',
                    child: Icon(Icons.close,
                        size: 12, color: Colors.red.shade300),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Run session row ─────────────────────────────────────────────────────────

class _RunSessionRow extends StatefulWidget {
  const _RunSessionRow({required this.session});
  final RunSession session;

  @override
  State<_RunSessionRow> createState() => _RunSessionRowState();
}

class _RunSessionRowState extends State<_RunSessionRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = widget.session;

    final (dotColor, icon) = switch (s.status) {
      RunStatus.running => (AppColors.neonGreen, Icons.play_arrow),
      RunStatus.failed => (AppColors.neonRed, Icons.error_outline),
      _ => (AppColors.textMuted, Icons.stop_circle_outlined),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () => context.read<RunCubit>().setActiveSession(s.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          color: _hovering ? colors.surfaceHighlight : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 11, color: dotColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  s.config.name,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedOpacity(
                opacity: _hovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !_hovering,
                  child: s.status == RunStatus.running
                    ? GestureDetector(
                        onTap: () => context.read<RunCubit>().stopRun(s.id),
                        child: Tooltip(
                          message: 'Stop run',
                          child: Icon(Icons.stop,
                              size: 12, color: Colors.orange.shade300),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => context.read<RunCubit>().removeSession(s.id),
                        child: Tooltip(
                          message: 'Remove',
                          child: Icon(Icons.close,
                              size: 12, color: Colors.red.shade300),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Add Skill to Workspace Dialog ───────────────────────────────────────────

class _AddSkillToWorkspaceDialog extends StatefulWidget {
  const _AddSkillToWorkspaceDialog({required this.workspace});
  final Workspace workspace;

  @override
  State<_AddSkillToWorkspaceDialog> createState() => _AddSkillToWorkspaceDialogState();
}

class _AddSkillToWorkspaceDialogState extends State<_AddSkillToWorkspaceDialog> {
  // Local copy of enabled skills that user is editing.
  late Set<String> _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = Set.of(widget.workspace.enabledSkills);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SkillsCubit, SkillsState>(
      builder: (context, state) {
        final installedSkills = state is SkillsLoaded
            ? state.skills.where((s) => s.isInstalled).toList()
            : <SkillEntry>[];

        return AlertDialog(
          backgroundColor: const Color(0xFF16163A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF32327A)),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Skills to Workspace',
                style: TextStyle(color: Color(0xFFE0E0F0), fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                widget.workspace.name,
                style: const TextStyle(color: Color(0xFF7C7CFF), fontSize: 11),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: installedSkills.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No skills installed yet.\nInstall skills from the Skills panel first.',
                      style: TextStyle(color: Color(0xFF8080B0), fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: installedSkills.length,
                      itemBuilder: (context, i) {
                        final skill = installedSkills[i];
                        final isEnabled = _enabled.contains(skill.id);
                        return InkWell(
                          onTap: () => setState(() {
                            if (isEnabled) {
                              _enabled.remove(skill.id);
                            } else {
                              _enabled.add(skill.id);
                            }
                          }),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Checkbox(
                                    value: isEnabled,
                                    onChanged: (_) => setState(() {
                                      if (isEnabled) {
                                        _enabled.remove(skill.id);
                                      } else {
                                        _enabled.add(skill.id);
                                      }
                                    }),
                                    activeColor: const Color(0xFF7C7CFF),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        skill.name,
                                        style: const TextStyle(color: Color(0xFFE0E0F0), fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                      if (skill.description.isNotEmpty)
                                        Text(
                                          skill.description,
                                          style: const TextStyle(color: Color(0xFF8080B0), fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFFB0B0D0), fontSize: 12)),
            ),
            TextButton(
              onPressed: _saving ? null : () => _save(context),
              child: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(
                      'Apply',
                      style: TextStyle(color: Color(0xFF7C7CFF), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save(BuildContext context) async {
    setState(() => _saving = true);
    final cubit = context.read<SkillsCubit>();
    final wsCubit = context.read<WorkspaceCubit>();
    Workspace updated = widget.workspace;

    final allIds = {...updated.enabledSkills, ..._enabled};
    for (final skillId in allIds) {
      final shouldBeEnabled = _enabled.contains(skillId);
      final result = await cubit.setSkillEnabledForWorkspace(
        skillId: skillId,
        workspace: updated,
        enabled: shouldBeEnabled,
      );
      if (result != null) updated = result;
    }

    await wsCubit.updateWorkspace(updated);
    if (mounted) Navigator.of(context).pop();
  }
}
