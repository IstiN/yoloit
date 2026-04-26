import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/workspace_card.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

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
      onRemoveFolder: (path) async {
        await context.read<WorkspaceCubit>().removePathFromWorkspace(ws.id, path);
      },
      onCreateSession: () => _createSession(context, ws.paths.isNotEmpty ? ws.paths.first : null, ws.id),
    );
  }

  Future<void> _createSession(BuildContext context, String? path, String wsId) async {
    if (path == null) return;
    final type = await showDialog<AgentType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF12151C),
        title: const Text('New Session', style: TextStyle(color: Color(0xFFE8E8FF), fontSize: 14)),
        children: [
          for (final t in AgentType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(t.displayName, style: const TextStyle(color: Color(0xFFCECEEE))),
            ),
        ],
      ),
    );
    if (type == null || !context.mounted) return;
    await context.read<TerminalCubit>().spawnSession(
      type:          type,
      workspacePath: path,
      workspaceId:   wsId,
    );
  }
}
