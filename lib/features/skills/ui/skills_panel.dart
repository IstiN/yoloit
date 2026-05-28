import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/bloc/skills_state.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/skills/models/skill_store_config.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

/// Skills panel embedded in the Settings dialog.
class SkillsPanel extends StatefulWidget {
  const SkillsPanel({super.key});

  @override
  State<SkillsPanel> createState() => _SkillsPanelState();
}

class _SkillsPanelState extends State<SkillsPanel> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final workspaces = _workspaces();
    context.read<SkillsCubit>().load(workspaces);
  }

  List<Workspace> _workspaces() {
    final wsState = context.read<WorkspaceCubit>().state;
    if (wsState is WorkspaceLoaded) return wsState.workspaces;
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SkillsCubit, SkillsState>(
      listener: (context, state) {
        if (state is SkillsLoaded && state.errorMessage != null) {
          _showError(context, state.errorMessage!);
        }
      },
      builder: (context, state) {
        if (state is SkillsLoading || state is SkillsInitial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is SkillsError) {
          return _ErrorView(message: state.message, onRetry: _load);
        }
        if (state is SkillsLoaded) {
          return _LoadedView(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _showError(BuildContext context, String message) {
    final colors = context.appColors;
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        backgroundColor: colors.accentOrange.withAlpha(200),
        action: SnackBarAction(
          label: 'Dismiss',
          onPressed: () => context.read<SkillsCubit>().clearError(),
        ),
      ),
    );
    context.read<SkillsCubit>().clearError();
  }
}

// ── Loaded view ───────────────────────────────────────────────────────────────

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});
  final SkillsLoaded state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Remote sync status bar
        _SyncStatusBar(loadedFromRemote: state.loadedFromRemote),
        Divider(height: 1, color: colors.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StoresSidebar(state: state),
              VerticalDivider(width: 1, color: colors.border),
              Expanded(child: _SkillsList(state: state)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncStatusBar extends StatelessWidget {
  const _SyncStatusBar({required this.loadedFromRemote});
  final bool loadedFromRemote;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<SkillsCubit>();
    final wsState = context.read<WorkspaceCubit>().state;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Icon(
            loadedFromRemote ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 13,
            color: loadedFromRemote ? colors.accentGreen : colors.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              loadedFromRemote
                  ? 'Catalog synced from github.com/IstiN/yoloit'
                  : 'Using cached catalog — no network or offline',
              style: TextStyle(
                color: loadedFromRemote ? colors.accentGreenDim : colors.textMuted,
                fontSize: 10,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              final workspaces = wsState is WorkspaceLoaded ? wsState.workspaces : <Workspace>[];
              cubit.load(workspaces);
            },
            child: Row(
              children: [
                Icon(Icons.refresh, size: 12, color: colors.textMuted),
                const SizedBox(width: 3),
                Text('Sync', style: TextStyle(color: colors.textMuted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stores sidebar ────────────────────────────────────────────────────────────

class _StoresSidebar extends StatelessWidget {
  const _StoresSidebar({required this.state});
  final SkillsLoaded state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<SkillsCubit>();

    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'STORES',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _StoreTile(
            label: 'All Skills',
            icon: Icons.auto_awesome_outlined,
            isSelected: state.selectedStoreId == null,
            onTap: () => cubit.selectStore(null),
          ),
          _StoreTile(
            label: 'Installed',
            icon: Icons.check_circle_outline,
            isSelected: state.selectedStoreId == '_installed',
            badge: state.installedSkills.length,
            onTap: () => cubit.selectStore('_installed'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Divider(height: 1, color: colors.divider),
          ),
          ...state.config.stores.map((store) => _StoreTile(
                label: store.name,
                icon: _iconForStore(store),
                isSelected: state.selectedStoreId == store.id,
                isBuiltIn: store.isBuiltIn,
                onTap: () => cubit.selectStore(store.id),
                onRemove: store.isBuiltIn
                    ? null
                    : () => cubit.removeStore(store.id),
              )),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: _AddStoreButton(),
          ),
        ],
      ),
    );
  }

  IconData _iconForStore(SkillStore store) {
    switch (store.type) {
      case SkillStoreType.github:
        return Icons.code;
      case SkillStoreType.url:
        return Icons.link;
      case SkillStoreType.installScript:
        return Icons.terminal;
      case SkillStoreType.local:
        return Icons.folder_outlined;
    }
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.isBuiltIn = true,
    this.onRemove,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badge;
  final bool isBuiltIn;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? colors.primary : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null && badge! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.primary.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(color: colors.primary, fontSize: 10),
                ),
              ),
            if (onRemove != null)
              GestureDetector(
                onTap: onRemove,
                child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 12, color: colors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Skills list ───────────────────────────────────────────────────────────────

class _SkillsList extends StatelessWidget {
  const _SkillsList({required this.state});
  final SkillsLoaded state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final List<SkillEntry> skills;
    if (state.selectedStoreId == '_installed') {
      skills = state.installedSkills;
    } else {
      skills = state.filteredSkills;
    }

    if (skills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_outlined, size: 36, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No skills found',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: skills.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider),
      itemBuilder: (context, index) =>
          _SkillCard(skill: skills[index], state: state),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({required this.skill, required this.state});
  final SkillEntry skill;
  final SkillsLoaded state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<SkillsCubit>();
    final isBusy = state.busySkillIds.contains(skill.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 10),
            child: Icon(
              skill.isInstalled ? Icons.check_circle : Icons.extension_outlined,
              size: 16,
              color: skill.isInstalled ? colors.accentGreen : colors.textMuted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        skill.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    _SourceBadge(skill: skill),
                  ],
                ),
                if (skill.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    skill.description,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                // Workspace checkboxes (only when skill is installed)
                if (skill.isInstalled && state.workspaces.isNotEmpty)
                  _WorkspaceCheckboxRow(skill: skill, state: state),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Action buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!skill.isInstalled)
                _SmallButton(
                  label: _installLabel(skill),
                  icon: Icons.download_outlined,
                  onTap: () => cubit.installSkill(skill),
                )
              else ...[
                _SmallButton(
                  label: 'Remove',
                  icon: Icons.delete_outline,
                  color: colors.accentOrange,
                  onTap: () => _confirmUninstall(context, cubit),
                ),
                const SizedBox(height: 4),
                _SmallButton(
                  label: 'To Repo',
                  icon: Icons.folder_open_outlined,
                  onTap: () => _showInstallToRepoDialog(context, cubit),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _installLabel(SkillEntry skill) {
    switch (skill.sourceType) {
      case SkillSourceType.installScript:
        return 'Run Script';
      case SkillSourceType.url:
        return 'Open Docs';
      default:
        return 'Install';
    }
  }

  void _confirmUninstall(BuildContext context, SkillsCubit cubit) {
    final colors = context.appColors;
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        title: Text('Uninstall Skill',
            style: TextStyle(color: colors.textPrimary, fontSize: 15)),
        content: Text(
          'Remove "${skill.name}" from the global skills store? Workspace symlinks will also be removed.',
          style: TextStyle(color: colors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              cubit.uninstallSkill(skill.id);
            },
            child: Text('Remove', style: TextStyle(color: colors.accentOrange)),
          ),
        ],
      ),
    );
  }

  void _showInstallToRepoDialog(BuildContext context, SkillsCubit cubit) {
    showDialog<void>(
      context: context,
      builder: (_) => _InstallToRepoDialog(
        skill: skill,
        workspaces: state.workspaces,
        cubit: cubit,
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.skill});
  final SkillEntry skill;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = switch (skill.sourceType) {
      SkillSourceType.github => 'GitHub',
      SkillSourceType.url => 'URL',
      SkillSourceType.installScript => 'Script',
      SkillSourceType.local => 'Local',
    };
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceHighlight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: colors.textMuted, fontSize: 9),
      ),
    );
  }
}

class _WorkspaceCheckboxRow extends StatelessWidget {
  const _WorkspaceCheckboxRow({required this.skill, required this.state});
  final SkillEntry skill;
  final SkillsLoaded state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SkillsCubit>();
    final wsCubit = context.read<WorkspaceCubit>();
    final colors = context.appColors;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: state.workspaces.map((ws) {
        final enabled = state.isEnabledInWorkspace(skill.id, ws.id);
        return GestureDetector(
          onTap: () async {
            final updated = await cubit.setSkillEnabledForWorkspace(
              skillId: skill.id,
              workspace: ws,
              enabled: !enabled,
            );
            if (updated != null) {
              wsCubit.updateWorkspace(updated);
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: enabled,
                  onChanged: (_) async {
                    final updated = await cubit.setSkillEnabledForWorkspace(
                      skillId: skill.id,
                      workspace: ws,
                      enabled: !enabled,
                    );
                    if (updated != null) {
                      wsCubit.updateWorkspace(updated);
                    }
                  },
                  activeColor: colors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ws.name,
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Add store button ──────────────────────────────────────────────────────────

class _AddStoreButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () => _showAddStoreDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 13, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              'Add Store',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStoreDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<SkillsCubit>(),
        child: const _AddStoreDialog(),
      ),
    );
  }
}

class _AddStoreDialog extends StatefulWidget {
  const _AddStoreDialog();
  @override
  State<_AddStoreDialog> createState() => _AddStoreDialogState();
}

class _AddStoreDialogState extends State<_AddStoreDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  SkillStoreType _type = SkillStoreType.github;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Text(
        'Add Custom Store',
        style: TextStyle(color: colors.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              controller: _nameController,
              label: 'Store Name',
              hint: 'e.g. My Company Skills',
            ),
            const SizedBox(height: 12),
            _field(
              controller: _urlController,
              label: 'URL / GitHub repo / Script',
              hint: 'owner/repo  or  https://...  or  curl -fsSL ...',
            ),
            const SizedBox(height: 12),
            Text('Type', style: TextStyle(color: colors.textMuted, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: SkillStoreType.values.map((t) {
                return ChoiceChip(
                  label: Text(_typeLabel(t), style: const TextStyle(fontSize: 11)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                  selectedColor: colors.primary.withAlpha(60),
                  backgroundColor: colors.surfaceHighlight,
                  labelStyle: TextStyle(
                    color: _type == t ? colors.primary : colors.textMuted,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(color: colors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
            filled: true,
            fillColor: colors.surfaceHighlight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colors.divider),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }

  String _typeLabel(SkillStoreType t) => switch (t) {
        SkillStoreType.github => 'GitHub',
        SkillStoreType.url => 'URL',
        SkillStoreType.installScript => 'Script',
        SkillStoreType.local => 'Local',
      };

  void _submit() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    context.read<SkillsCubit>().addCustomStore(SkillStore(
          id: id,
          name: name,
          type: _type,
          url: url,
        ));
    Navigator.pop(context);
  }
}

// ── Install to repo dialog ────────────────────────────────────────────────────

class _InstallToRepoDialog extends StatefulWidget {
  const _InstallToRepoDialog({
    required this.skill,
    required this.workspaces,
    required this.cubit,
  });
  final SkillEntry skill;
  final List<Workspace> workspaces;
  final SkillsCubit cubit;

  @override
  State<_InstallToRepoDialog> createState() => _InstallToRepoDialogState();
}

class _InstallToRepoDialogState extends State<_InstallToRepoDialog> {
  String? _selectedPath;

  List<String> get _allRepoPaths {
    final paths = <String>[];
    for (final ws in widget.workspaces) {
      paths.addAll(ws.paths);
    }
    return paths.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final paths = _allRepoPaths;

    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Text(
        'Install "${widget.skill.name}" to Repo',
        style: TextStyle(color: colors.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 380,
        child: paths.isEmpty
            ? Text(
                'No repositories found. Add a workspace with a repo path first.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a repository to install the skill into:',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ...paths.map((path) {
                    final name = path.split('/').last;
                    return RadioListTile<String>(
                      value: path,
                      groupValue: _selectedPath,
                      onChanged: (v) => setState(() => _selectedPath = v),
                      title: Text(name,
                          style: TextStyle(
                              color: colors.textPrimary, fontSize: 12)),
                      subtitle: Text(path,
                          style: TextStyle(
                              color: colors.textMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis),
                      activeColor: colors.primary,
                      dense: true,
                    );
                  }),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selectedPath == null
              ? null
              : () {
                  widget.cubit.installSkillToRepo(widget.skill, _selectedPath!);
                  Navigator.pop(context);
                },
          child: const Text('Install'),
        ),
      ],
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.appColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: effectiveColor.withAlpha(80)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: effectiveColor),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(color: effectiveColor, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 32, color: colors.accentOrange),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
