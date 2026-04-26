import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
        final dir = await FilePicker.platform.getDirectoryPath(
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
    final current = ws.color ?? const Color(0xFF60A5FA);
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<WorkspaceCubit>(),
        child: _WsColorPickerDialog(
          workspaceId: ws.id,
          current: current,
          onSave: (c) => context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, c),
          onReset: () => context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, null),
        ),
      ),
    );
  }

  Future<void> _openSessionDialog(BuildContext context) async {
    final ws = data.workspace;
    // Capture both the navigator context and TerminalCubit BEFORE any async
    // gap so the dialog receives proper keyboard focus on macOS.
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
  static const _palette = [
    Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFD97706),
    Color(0xFFDC2626), Color(0xFF0891B2), Color(0xFFDB2777), Color(0xFF6D28D9),
    Color(0xFF60A5FA), Color(0xFF34D399), Color(0xFFF59E0B), Color(0xFFF87171),
  ];
  late Color _color;

  @override
  void initState() {
    super.initState();
    _color = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF12151C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2A3040)),
      ),
      title: const Text(
        'Workspace Color',
        style: TextStyle(color: Color(0xFFE8E8FF), fontSize: 14),
      ),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in _palette)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c,
                  border: _color == c
                      ? Border.all(color: Colors.white, width: 2)
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
          child: const Text('Reset', style: TextStyle(color: Color(0xFF6B7898))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7898))),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_color);
            Navigator.pop(context);
          },
          child: const Text('Save', style: TextStyle(color: Color(0xFF60A5FA))),
        ),
      ],
    );
  }
}
