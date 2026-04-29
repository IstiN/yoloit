import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/collaboration/desktop/repo_directory_listing.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/file_tree_card.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/review_card_props_builder.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';

/// Mindmap file-tree card — uses the same presentation widget as the browser.
///
/// Tree state management: prefers [ReviewCubit] when it already owns this
/// repo path (so the review panel and miro board stay in sync). Falls back to
/// a fully-local tree when ReviewCubit is not loaded for this path, so the
/// folders can still be expanded without affecting the review panel state.
class FileTreeNode extends StatefulWidget {
  const FileTreeNode({super.key, required this.data});
  final FileTreeNodeData data;

  @override
  State<FileTreeNode> createState() => _FileTreeNodeState();
}

class _FileTreeNodeState extends State<FileTreeNode> {
  // ── helpers ───────────────────────────────────────────────────────────────

  String get _repoPath => widget.data.repoPath ?? '';

  /// Returns true when the ReviewCubit has already loaded a tree that contains
  /// this repo path as a root, so we can delegate to it instead of managing
  /// local state.
  bool _reviewCubitOwnsPath(ReviewState state) {
    if (state is! ReviewLoaded) return false;
    return state.fileTree.any((n) => n.path == _repoPath);
  }

  /// User-toggled expanded state. Paths not present here use the
  /// default from [listRepoDir] (root = true, others = false).
  final Map<String, bool> _localExpanded = {};

  void _toggleLocal(String path) {
    setState(() {
      // Default expanded state: root is expanded, all else collapsed.
      final currentlyExpanded = _localExpanded[path] ?? (path == _repoPath);
      _localExpanded[path] = !currentlyExpanded;
    });
  }

  /// Builds a flat list of [TreeEntry] from the filesystem, respecting
  /// the [_localExpanded] user-toggle map.
  List<TreeEntry> _buildLocalTree(String dirPath, int depth) {
    final raw = listRepoDir(dirPath);
    if (raw.isEmpty) return const [];

    final result = <TreeEntry>[];
    for (final e in raw) {
      final path = e['path'] as String? ?? '';
      final isDir = e['isDir'] as bool? ?? false;
      final rawDepth = e['depth'] as int? ?? 0;
      final entryDepth = depth + rawDepth;

      // Determine expanded state: explicit toggle overrides, root defaults to true.
      final isExpanded = isDir && (_localExpanded[path] ?? (rawDepth == 0));

      result.add(TreeEntry(
        name: e['name'] as String? ?? '',
        path: path,
        isDir: isDir,
        depth: entryDepth,
        isExpanded: isExpanded,
      ));

      // Recursively expand directories that are open (only their direct
      // children — listRepoDir gives us depth 0 + depth 1, so one level
      // at a time keeps the UI snappy).
      if (isDir && isExpanded && rawDepth > 0) {
        result.addAll(_buildLocalTree(path, entryDepth));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewCubit, ReviewState>(
      builder: (context, state) {
        final useReview = _reviewCubitOwnsPath(state);

        if (useReview) {
          // ── ReviewCubit owns this path — delegate everything to it ─────
          return FileTreeCard(
            props: buildFileTreeCardProps(
              repoPath: _repoPath,
              repoName: widget.data.repoName,
              reviewState: state,
            ),
            onToggle: (path) => context.read<ReviewCubit>().toggleNode(path),
            onSelect: (path) => _openInPanel(context, path),
            onNewFolder: (parentPath) => _createNewFolder(context, parentPath),
            onShowInFinder: (path) => PlatformLauncher.instance.revealInFinder(path),
            onOpenInPanel: (path) => _openInPanel(context, path),
            onRename: (path, currentName) => _renameEntry(context, path, currentName),
            onCreateFile: (dirPath) => _createFile(context, dirPath),
          );
        }

        // ── Local tree mode — manage expansion state in this widget ───────
        final localEntries = _buildLocalTree(_repoPath, 0);
        return FileTreeCard(
          props: FileTreeCardProps(
            repoName: widget.data.repoName,
            repoPath: _repoPath,
            entries: localEntries,
          ),
          onToggle: (path) => _toggleLocal(path),
          onSelect: (path) => _openInPanel(context, path),
          onNewFolder: (parentPath) => _createNewFolder(context, parentPath),
          onShowInFinder: (path) => PlatformLauncher.instance.revealInFinder(path),
          onOpenInPanel: (path) => _openInPanel(context, path),
          onRename: (path, currentName) => _renameEntry(context, path, currentName),
          onCreateFile: (dirPath) => _createFile(context, dirPath),
        );
      },
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
    if (context.mounted) _openInPanel(context, newPath);
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
