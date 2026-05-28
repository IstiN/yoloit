import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/workspace_card.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/features/workspaces/ui/new_agent_session_dialog.dart';

class WorkspaceNode extends StatelessWidget {
  const WorkspaceNode({super.key, required this.data});

  final WorkspaceNodeData data;

  @override
  Widget build(BuildContext context) {
    final ws = data.workspace;
    return WorkspaceCard(
      props: WorkspaceCardProps(
        name: ws.name,
        color: ws.color,
        paths: ws.paths,
      ),
      onAddFolder: () async {
        final dir = await FilePicker.getDirectoryPath(
          dialogTitle: 'Add folder to "${ws.name}"',
        );
        if (dir == null || !context.mounted) return;
        await context.read<WorkspaceCubit>().addPathToWorkspace(ws.id, dir);
      },
      onCreateSession: () => _openSessionDialog(context),
      onColorDotTap: () => _pickColor(context),
      onRemoveFolder: (path) async {
        await context.read<WorkspaceCubit>().removePathFromWorkspace(ws.id, path);
      },
    );
  }

  void _pickColor(BuildContext context) {
    final ws = data.workspace;
    final current = ws.color ?? context.appColors.accentBlue;
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<WorkspaceCubit>(),
        child: _WsColorPickerDialog(
          workspaceId: ws.id,
          current: current,
          onSave: (color) =>
              context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, color),
          onReset: () =>
              context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, null),
        ),
      ),
    );
  }

  Future<void> _openSessionDialog(BuildContext context) async {
    final ws = data.workspace;
    final navigator = Navigator.of(context, rootNavigator: true);
    final terminalCubit = context.read<TerminalCubit>();

    final worktrees = <String, List<WorktreeEntry>>{};
    for (final repoPath in ws.paths) {
      worktrees[repoPath] =
          await WorktreeService.instance.listWorktrees(repoPath);
    }
    if (!navigator.mounted) return;
    showDialog<void>(
      context: navigator.context,
      builder: (_) => BlocProvider.value(
        value: terminalCubit,
        child: NewAgentSessionDialog(
          workspace: ws,
          worktrees: worktrees,
          onSpawned: () {},
        ),
      ),
    );
  }
}

class _WsColorPickerDialog extends StatefulWidget {
  const _WsColorPickerDialog({
    required this.workspaceId,
    required this.current,
    required this.onSave,
    required this.onReset,
  });

  final String workspaceId;
  final Color current;
  final void Function(Color) onSave;
  final VoidCallback onReset;

  @override
  State<_WsColorPickerDialog> createState() => _WsColorPickerDialogState();
}

class _WsColorPickerDialogState extends State<_WsColorPickerDialog> {
  late Color _color;

  List<Color> _palette(AppColorScheme colors) => [
        colors.primary,
        colors.primaryLight,
        colors.primaryDark,
        colors.accentBlue,
        colors.accentGreen,
        colors.accentGreenDim,
        colors.accentOrange,
        colors.accentRed,
        colors.accentRedDim,
        colors.statusActive,
        colors.statusWarning,
        colors.statusIdle,
      ];

  @override
  void initState() {
    super.initState();
    _color = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final palette = _palette(colors);
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border),
      ),
      title: Text(
        'Workspace Color',
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
      ),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final color in palette)
            GestureDetector(
              onTap: () => setState(() => _color = color),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: _color == color
                      ? Border.all(
                          color: colors.textHighlight,
                          width: 2,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onReset();
            Navigator.pop(context);
          },
          child: Text(
            'Reset',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_color);
            Navigator.pop(context);
          },
          child: Text(
            'Save',
            style: TextStyle(color: colors.accentBlue),
          ),
        ),
      ],
    );
  }
}
