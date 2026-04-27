import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/collaboration/desktop/repo_directory_listing.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/file_tree_card.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/review_card_props_builder.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';

/// Mindmap file-tree card — uses the same presentation widget as the browser.
class FileTreeNode extends StatelessWidget {
  const FileTreeNode({super.key, required this.data});
  final FileTreeNodeData data;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewCubit, ReviewState>(
      builder: (context, state) => FileTreeCard(
        props: buildFileTreeCardProps(
          repoPath: data.repoPath ?? '',
          repoName: data.repoName,
          reviewState: state,
          listDirectory: listRepoDir,
        ),
        onToggle: (path) => context.read<ReviewCubit>().toggleNode(path),
        onSelect: (path) => _openInPanel(context, path),
        onNewFolder: (parentPath) => _createNewFolder(context, parentPath),
        onShowInFinder: (path) => PlatformLauncher.instance.revealInFinder(path),
        onOpenInPanel: (path) => _openInPanel(context, path),
        onRename: (path, currentName) => _renameEntry(context, path, currentName),
        onCreateFile: (dirPath) => _createFile(context, dirPath),
      ),
    );
  }

  Future<void> _createNewFolder(BuildContext context, String parentPath) async {
    // Ask user for the new folder name.
    final navigator = Navigator.of(context, rootNavigator: true);
    final reviewCubit = context.read<ReviewCubit>();
    final ctrl = TextEditingController();

    final name = await showDialog<String>(
      context: navigator.context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2A),
        title: const Text('New Folder',
            style: TextStyle(color: Color(0xFFCECEEE), fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFCECEEE), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: const TextStyle(color: Color(0xFF6B7898), fontSize: 13),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: const Color(0xFF0F1117),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2A3040)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF7C3AED)),
            ),
          ),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7898), fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Create',
                style: TextStyle(color: Color(0xFF7C3AED), fontSize: 12)),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (name == null || name.isEmpty) return;

    // Use ReviewCubit.createFolder so the tree refreshes automatically.
    if (!reviewCubit.isClosed) {
      await reviewCubit.createFolder(parentPath, name);
    }
  }

  Future<void> _renameEntry(BuildContext context, String path, String currentName) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final reviewCubit = context.read<ReviewCubit>();
    final ctrl = TextEditingController(text: currentName);
    // Select name without extension for files
    final dotIdx = currentName.lastIndexOf('.');
    final selectEnd = (dotIdx > 0) ? dotIdx : currentName.length;

    final newName = await showDialog<String>(
      context: navigator.context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2A),
        title: const Text('Rename',
            style: TextStyle(color: Color(0xFFCECEEE), fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFCECEEE), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: const TextStyle(color: Color(0xFF6B7898), fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: const Color(0xFF0F1117),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2A3040)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF7C3AED)),
            ),
          ),
          onTap: () => ctrl.selection = TextSelection(
            baseOffset: 0, extentOffset: selectEnd),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7898), fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Rename',
                style: TextStyle(color: Color(0xFF7C3AED), fontSize: 12)),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (newName == null || newName.isEmpty || newName == currentName) return;
    if (!reviewCubit.isClosed) {
      await reviewCubit.renameEntry(path, newName);
    }
  }

  Future<void> _createFile(BuildContext context, String dirPath) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final reviewCubit = context.read<ReviewCubit>();
    final mindMapCubit = context.read<MindMapCubit>();
    final ctrl = TextEditingController();

    final fileName = await showDialog<String>(
      context: navigator.context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2A),
        title: const Text('New File',
            style: TextStyle(color: Color(0xFFCECEEE), fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFCECEEE), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'filename.dart',
            hintStyle: const TextStyle(color: Color(0xFF6B7898), fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: const Color(0xFF0F1117),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2A3040)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF7C3AED)),
            ),
          ),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7898), fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Create',
                style: TextStyle(color: Color(0xFF7C3AED), fontSize: 12)),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (fileName == null || fileName.isEmpty) return;
    if (!reviewCubit.isClosed) {
      await reviewCubit.createFile(dirPath, fileName);
    }
    // Open the new file in a mindmap panel
    final newPath = p.join(dirPath, fileName);
    _openInPanel(context, newPath);
  }

  void _openInPanel(BuildContext context, String path) {
    debugPrint('[FileTreeNode] _openInPanel called: path=$path');
    final nodeId = 'panel:${path.hashCode}';
    if (!context.mounted) {
      debugPrint('[FileTreeNode] context not mounted, aborting');
      return;
    }
    try {
      context.read<MindMapCubit>().openFileAsPanel(
        id: nodeId,
        filePath: path,
      );
      debugPrint('[FileTreeNode] openFileAsPanel completed');
    } catch (e, st) {
      debugPrint('[FileTreeNode] ERROR: $e\n$st');
    }
  }
}
