import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/services/git_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/review/data/diff_service.dart';
import 'package:yoloit/features/review/data/file_viewer_service.dart';
import 'package:yoloit/features/review/models/review_models.dart';

class ReviewCubit extends Cubit<ReviewState> {
  ReviewCubit() : super(const ReviewInitial());

  List<String> _workspacePaths = [];
  String? _workspaceId;
  Timer? _changedFilesTimer;

  /// Primary path used for git operations (first path in the list).
  String? get _primaryPath => _workspacePaths.isEmpty ? null : _workspacePaths.first;

  Future<void> loadWorkspace(List<String> paths, {String? workspaceId}) async {
    _workspacePaths = paths;
    _workspaceId = workspaceId;
    emit(const ReviewLoaded(fileTree: [], changedFiles: []));
    await refresh();
    _startChangedFilesTimer();
  }

  /// Reloads the file tree with [paths] scoped to [sessionId].
  /// Called when the active agent session changes.
  Future<void> loadSession(List<String> paths, String sessionId) async {
    await loadWorkspace(paths, workspaceId: sessionId);
  }

  Future<void> refresh() async {
    if (_workspacePaths.isEmpty) return;

    final current = _loaded;
    // Build a root node per path, each expanded one level.
    List<FileTreeNode> roots = [];
    for (final path in _workspacePaths) {
      final children = await _buildFileTree(path);
      roots.add(FileTreeNode(
        name: p.basename(path),
        path: path,
        isDirectory: true,
        isExpanded: true,
        children: children,
      ));
    }
    // Collect changed files from all paths.
    final List<FileChange> allChanged = [];
    for (final path in _workspacePaths) {
      try {
        final changed = await DiffService.instance.getChangedFiles(path);
        allChanged.addAll(changed);
      } catch (_) {}
    }

    // Restore previously expanded directories.
    final id = _workspaceId;
    if (id != null) {
      final expandedPaths = await SessionPrefs.loadExpandedPaths(id);
      for (final path in expandedPaths) {
        // Skip root paths (already expanded above).
        if (_workspacePaths.contains(path)) continue;
        roots = _toggleNodeInTree(roots, path);
      }
    }

    emit(ReviewLoaded(
      fileTree: roots,
      changedFiles: allChanged,
      selectedFilePath: current?.selectedFilePath,
      diffHunks: current?.diffHunks ?? [],
      fileContent: current?.fileContent,
      fileLanguage: current?.fileLanguage,
      viewMode: current?.viewMode ?? ReviewViewMode.diff,
      prStatus: current?.prStatus,
    ));
  }

  Future<void> selectFile(String absolutePath) async {
    final current = _loaded;
    debugPrint('[ReviewCubit] selectFile: $absolutePath');
    debugPrint('[ReviewCubit] _workspacePaths: $_workspacePaths');
    debugPrint('[ReviewCubit] _primaryPath: $_primaryPath');
    if (current == null) {
      debugPrint('[ReviewCubit] selectFile: _loaded is null, returning early!');
      return;
    }

    emit(current.copyWith(
      selectedFilePath: absolutePath,
      isLoadingDiff: true,
      isLoadingFile: true,
    ));

    // Find which workspace root this file belongs to.
    final gitRoot = _gitRootFor(absolutePath) ?? _primaryPath ?? '';
    final relativePath = p.relative(absolutePath, from: gitRoot);
    debugPrint('[ReviewCubit] gitRoot=$gitRoot relativePath=$relativePath');

    // Load diff and file content in parallel
    final diffFuture = DiffService.instance.getDiff(gitRoot, relativePath);
    final fileFuture = FileViewerService.instance.readFile(absolutePath);

    final results = await Future.wait([diffFuture, fileFuture]);
    final hunks = results[0] as List<DiffHunk>;
    final fileResult = results[1] as FileViewResult;
    debugPrint('[ReviewCubit] selectFile done: ${hunks.length} hunks');

    if (!isClosed) {
      emit(current.copyWith(
        selectedFilePath: absolutePath,
        diffHunks: hunks,
        fileContent: fileResult.content,
        fileLanguage: fileResult.language,
        isLoadingDiff: false,
        isLoadingFile: false,
      ));
    }
  }

  void setViewMode(ReviewViewMode mode) {
    final current = _loaded;
    if (current == null) return;
    emit(current.copyWith(viewMode: mode));
  }

  void toggleNode(String nodePath) {
    final current = _loaded;
    if (current == null) return;
    final updatedTree = _toggleNodeInTree(current.fileTree, nodePath);
    emit(current.copyWith(fileTree: updatedTree));
    _saveExpandedPaths(updatedTree);
  }

  void _saveExpandedPaths(List<FileTreeNode> tree) {
    final id = _workspaceId;
    if (id == null) return;
    final paths = <String>[];
    _collectExpandedPaths(tree, paths);
    SessionPrefs.saveExpandedPaths(id, paths);
  }

  void _collectExpandedPaths(List<FileTreeNode> nodes, List<String> result) {
    for (final node in nodes) {
      if (node.isDirectory && node.isExpanded) {
        result.add(node.path);
        _collectExpandedPaths(node.children, result);
      }
    }
  }

  Future<void> stageFile(String filePath) async {
    final root = _gitRootFor(filePath) ?? _primaryPath;
    if (root == null) return;
    await GitService.instance.stageFile(root, filePath);
    await refresh();
  }

  Future<void> unstageFile(String filePath) async {
    final root = _gitRootFor(filePath) ?? _primaryPath;
    if (root == null) return;
    await GitService.instance.unstageFile(root, filePath);
    await refresh();
  }

  /// Returns the workspace path that is a prefix of [absolutePath].
  String? _gitRootFor(String absolutePath) {
    for (final path in _workspacePaths) {
      if (absolutePath.startsWith(path)) return path;
    }
    return null;
  }

  Future<void> renameEntry(String oldPath, String newName) async {
    final parent = p.dirname(oldPath);
    final newPath = p.join(parent, newName);
    try {
      final isDir = await FileSystemEntity.isDirectory(oldPath);
      if (isDir) {
        await Directory(oldPath).rename(newPath);
      } else {
        await File(oldPath).rename(newPath);
      }
      await refresh();
    } catch (e) {
      debugPrint('[ReviewCubit] renameEntry error: $e');
    }
  }

  Future<void> createFile(String parentDirPath, String fileName) async {
    final newPath = p.join(parentDirPath, fileName);
    try {
      await File(newPath).create(recursive: true);
      await refresh();
    } catch (e) {
      debugPrint('[ReviewCubit] createFile error: $e');
    }
  }

  Future<void> createFolder(String parentDirPath, String folderName) async {    final newDir = Directory(p.join(parentDirPath, folderName));
    await newDir.create(recursive: true);
    // Add .gitkeep so git tracks the empty directory.
    final gitkeep = File(p.join(newDir.path, '.gitkeep'));
    await gitkeep.writeAsString('');
    await refresh();
  }

  List<FileSystemEntity> _listAndSortEntities(String dirPath) {
    final dir = Directory(dirPath);
    return dir.listSync(followLinks: true)
      ..sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
  }

  Future<List<FileTreeNode>> _buildFileTree(String dirPath) async {
    try {
      final entities = _listAndSortEntities(dirPath);

      return entities
          .where((e) => p.basename(e.path) != '.git')
          .map((e) {
            final isDir = e is Directory;
            return FileTreeNode(
              name: p.basename(e.path),
              path: e.path,
              isDirectory: isDir,
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<FileTreeNode> _toggleNodeInTree(List<FileTreeNode> nodes, String targetPath) {
    return nodes.map((node) {
      if (node.path == targetPath && node.isDirectory) {
        if (!node.isExpanded) {
          // Expand: load children
          final entities = _listAndSortEntities(targetPath);
          final children = entities
              .where((e) => p.basename(e.path) != '.git')
              .map((e) => FileTreeNode(
                    name: p.basename(e.path),
                    path: e.path,
                    isDirectory: e is Directory,
                  ))
              .toList();
          return node.copyWith(isExpanded: true, children: children);
        } else {
          return node.copyWith(isExpanded: false, children: []);
        }
      }
      if (node.isDirectory && node.isExpanded) {
        return node.copyWith(children: _toggleNodeInTree(node.children, targetPath));
      }
      return node;
    }).toList();
  }

  ReviewLoaded? get _loaded {
    final s = state;
    return s is ReviewLoaded ? s : null;
  }

  void _startChangedFilesTimer() {
    _changedFilesTimer?.cancel();
    _changedFilesTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (isClosed || _workspacePaths.isEmpty) return;
      final current = _loaded;
      if (current == null) return;
      final List<FileChange> allChanged = [];
      for (final path in _workspacePaths) {
        try {
          allChanged.addAll(await DiffService.instance.getChangedFiles(path));
        } catch (_) {}
      }
      if (!isClosed) emit(current.copyWith(changedFiles: allChanged));
    });
  }

  @override
  Future<void> close() {
    _changedFilesTimer?.cancel();
    return super.close();
  }
}
