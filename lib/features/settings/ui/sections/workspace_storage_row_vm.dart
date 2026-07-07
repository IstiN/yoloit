import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

// ignore: must_be_immutable
class WorkspaceStorageRow extends StatefulWidget {
  const WorkspaceStorageRow({super.key});

  @override
  State<WorkspaceStorageRow> createState() => WorkspaceStorageRowState();
}

class WorkspaceStorageRowState extends State<WorkspaceStorageRow> {
  late String _currentPath;

  @override
  void initState() {
    super.initState();
    _currentPath = AppConfig.instance.workspacesFilePath;
  }

  Future<void> _pickDirectory(BuildContext context) async {
    final result = await BoardFilePicker.pickDirectory(
      context,
      initialPath: p.dirname(_currentPath),
      title: 'Choose workspace storage folder',
    );
    if (result == null) return;
    final newPath = '$result/workspaces.json';
    await AppConfig.instance.setWorkspacesFilePath(newPath);
    if (mounted) {
      setState(() => _currentPath = newPath);
      if (context.mounted) await context.read<WorkspaceCubit>().load();
    }
  }

  Future<void> _resetPath(BuildContext context) async {
    await AppConfig.instance.resetWorkspacesFilePath();
    if (mounted) {
      setState(() => _currentPath = AppConfig.instance.workspacesFilePath);
      if (context.mounted) await context.read<WorkspaceCubit>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDefault = _currentPath == AppConfig.defaultWorkspacesFilePath;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 16, color: context.appColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workspace storage',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentPath,
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _pickDirectory(context),
            child: Text(
              'Change…',
              style: TextStyle(fontSize: 12, color: colors.primary),
            ),
          ),
          if (!isDefault)
            TextButton(
              onPressed: () => _resetPath(context),
              child: Text(
                'Reset',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).textTheme.bodyMedium?.color ??
                      Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
