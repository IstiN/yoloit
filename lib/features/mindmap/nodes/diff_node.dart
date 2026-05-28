import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/diff_card.dart';
import 'package:yoloit/features/review/data/diff_service.dart';
import 'package:yoloit/features/review/models/review_models.dart'
    show FileChange, FileChangeStatus;

/// Self-contained DiffNode: polls its own repoPath every 4s.
/// Clicking a file opens a separate FileDiffPanelNode on the canvas.
class DiffNode extends StatefulWidget {
  const DiffNode({super.key, required this.data});
  final DiffNodeData data;

  @override
  State<DiffNode> createState() => _DiffNodeState();
}

class _DiffNodeState extends State<DiffNode> {
  Timer? _timer;
  List<FileChange> _changedFiles = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final path = widget.data.repoPath;
    if (path == null || path.isEmpty) return;
    try {
      final files = await DiffService.instance.getChangedFiles(path);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _changedFiles = files);
        });
      }
    } catch (_) {}
  }

  void _onFileTap(String relativePath) {
    final repoPath = widget.data.repoPath ?? '';
    final absPath = relativePath.startsWith('/')
        ? relativePath
        : '$repoPath/$relativePath';
    debugPrint('[DiffNode] _onFileTap called: relativePath=$relativePath, absPath=$absPath, repoPath=$repoPath');
    try {
      context.read<MindMapCubit>().openFileDiffAsPanel(
        filePath: absPath,
        repoPath: repoPath,
        connectorColor: context.appColors.accentBlue.withValues(alpha: 112 / 255),
      );
      debugPrint('[DiffNode] openFileDiffAsPanel completed');
    } catch (e, st) {
      debugPrint('[DiffNode] ERROR in openFileDiffAsPanel: $e\n$st');
    }
  }

  String _statusName(FileChangeStatus s) {
    switch (s) {
      case FileChangeStatus.added: return 'A';
      case FileChangeStatus.deleted: return 'D';
      case FileChangeStatus.modified: return 'M';
      case FileChangeStatus.renamed: return 'R';
      case FileChangeStatus.untracked: return 'U';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final changedEntries = _changedFiles
        .map((f) => ChangedFileEntry(
              path: f.path,
              name: f.path.split('/').last,
              status: _statusName(f.status),
              addedLines: f.addedLines,
              removedLines: f.removedLines,
            ))
        .toList();

    return DiffCard(
      props: DiffCardProps(
        repoName: widget.data.repoName,
        repoPath: widget.data.repoPath ?? '',
        changedFiles: changedEntries,
        selectedFilePath: null,
        hunks: const [],
      ),
      onFileTap: _onFileTap,
    );
  }
}
