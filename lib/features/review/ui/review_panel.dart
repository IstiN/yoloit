import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/utils/file_type_utils.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/review/models/review_models.dart';
import 'package:yoloit/features/runs/ui/run_panel.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

enum _FileTreeTab { files, diff }

class ReviewPanel extends StatelessWidget {
  const ReviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewCubit, ReviewState>(
      builder: (context, state) {
        if (state is ReviewLoaded) {
          return _ReviewContent(state: state);
        }
        return _EmptyReview();
      },
    );
  }
}

class _EmptyReview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.surface,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rate_review_outlined, size: 32, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'Changes & Review',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Open a workspace to see file changes',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewContent extends StatefulWidget {
  const _ReviewContent({required this.state});
  final ReviewLoaded state;

  @override
  State<_ReviewContent> createState() => _ReviewContentState();
}

class _ReviewContentState extends State<_ReviewContent> {
  bool _runCollapsed = false;
  _FileTreeTab _currentTab = _FileTreeTab.files;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewTabBar(
            state: widget.state,
            currentTab: _currentTab,
            onTabChanged: (tab) => setState(() => _currentTab = tab),
          ),
          Expanded(
            child: _currentTab == _FileTreeTab.files
                ? _FileTreeSection(state: widget.state)
                : _GitChangesSection(state: widget.state),
          ),
          if (widget.state.prStatus != null) _PrStatusSection(pr: widget.state.prStatus!),
          // ── Run panel (collapsible) ───────────────────────────────────────
          _CollapsibleRunPanel(
            collapsed: _runCollapsed,
            onToggle: () => setState(() => _runCollapsed = !_runCollapsed),
          ),
        ],
      ),
    );
  }
}

/// Collapsible, vertically resizable Run panel shown at the bottom of the Review panel.
class _CollapsibleRunPanel extends StatefulWidget {
  const _CollapsibleRunPanel({required this.collapsed, required this.onToggle});
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<_CollapsibleRunPanel> createState() => _CollapsibleRunPanelState();
}

class _CollapsibleRunPanelState extends State<_CollapsibleRunPanel> {
  static const _minHeight = 80.0;
  static const _maxHeight = 800.0;
  static const _defaultHeight = 220.0;

  double _height = _defaultHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle strip (also acts as toggle header)
        GestureDetector(
          onTap: widget.onToggle,
          onVerticalDragUpdate: (details) {
            if (widget.collapsed) return;
            setState(() {
              _height = (_height - details.delta.dy)
                  .clamp(_minHeight, _maxHeight);
            });
          },
          child: MouseRegion(
            cursor: widget.collapsed
                ? SystemMouseCursors.click
                : SystemMouseCursors.resizeRow,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_outline, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  const Text(
                    'Run',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (!widget.collapsed)
                    const Icon(Icons.drag_handle, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: widget.collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_less, size: 14, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Body (collapses / resizes)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: widget.collapsed
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: SizedBox(height: _height, child: const RunPanel()),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Tab bar replacing the old "Changes & Review" header ─────────────────────
class _ReviewTabBar extends StatelessWidget {
  const _ReviewTabBar({
    required this.state,
    required this.currentTab,
    required this.onTabChanged,
  });

  final ReviewLoaded state;
  final _FileTreeTab currentTab;
  final ValueChanged<_FileTreeTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final changedCount = state.changedFiles.length;

    return Container(
      height: 36,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: const Color(0xFF32327A), width: 1)),
      ),
      child: Row(
        children: [
          _TabItem(
            label: 'FILES',
            isActive: currentTab == _FileTreeTab.files,
            onTap: () => onTabChanged(_FileTreeTab.files),
          ),
          _TabItem(
            label: 'DIFF',
            badge: changedCount > 0 ? changedCount : null,
            isActive: currentTab == _FileTreeTab.diff,
            onTap: () => onTabChanged(_FileTreeTab.diff),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.read<ReviewCubit>().refresh(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.refresh, size: 14, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final labelColor = widget.isActive ? AppColors.textPrimary : AppColors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovering && !widget.isActive
                ? colors.surfaceHighlight
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.isActive ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.6,
                ),
              ),
              if (widget.badge != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.neonOrange.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.badge}',
                    style: const TextStyle(
                      color: AppColors.neonOrange,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Git Changes tab ──────────────────────────────────────────────────────────
class _GitChangesSection extends StatelessWidget {
  const _GitChangesSection({required this.state});
  final ReviewLoaded state;

  @override
  Widget build(BuildContext context) {
    final staged = state.changedFiles.where((f) => f.isStaged).toList();
    final unstaged = state.changedFiles.where((f) => !f.isStaged).toList();

    if (state.changedFiles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 28, color: AppColors.textMuted),
            SizedBox(height: 10),
            Text(
              'No changes',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Group files by repoPath, preserving insertion order.
    Map<String?, List<FileChange>> _groupByRepo(List<FileChange> files) {
      final map = <String?, List<FileChange>>{};
      for (final f in files) {
        (map[f.repoPath] ??= []).add(f);
      }
      return map;
    }

    final stagedByRepo = _groupByRepo(staged);
    final unstagedByRepo = _groupByRepo(unstaged);
    final multipleRepos = state.fileTree.length > 1;

    Widget buildGroup(
      String label,
      IconData icon,
      Color iconColor,
      Map<String?, List<FileChange>> byRepo,
    ) {
      final items = <Widget>[];
      items.add(_ChangesSectionHeader(
        label: label,
        count: byRepo.values.fold(0, (s, l) => s + l.length),
        icon: icon,
        iconColor: iconColor,
      ));
      for (final entry in byRepo.entries) {
        if (multipleRepos && entry.key != null) {
          items.add(_RepoGroupHeader(repoName: entry.key!.split('/').last));
        }
        for (final f in entry.value) {
          items.add(_ChangedFileTile(file: f, workspacePath: entry.key));
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (staged.isNotEmpty)
          buildGroup('STAGED', Icons.check_circle_outline, AppColors.neonGreen, stagedByRepo),
        if (unstaged.isNotEmpty)
          buildGroup('CHANGES', Icons.edit_outlined, AppColors.neonOrange, unstagedByRepo),
      ],
    );
  }
}

class _ChangesSectionHeader extends StatelessWidget {
  const _ChangesSectionHeader({
    required this.label,
    required this.count,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 11, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '($count)',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}


class _RepoGroupHeader extends StatelessWidget {
  const _RepoGroupHeader({required this.repoName});
  final String repoName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 2),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            repoName,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class _FileTreeSection extends StatelessWidget {
  const _FileTreeSection({required this.state});
  final ReviewLoaded state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: const Row(
            children: [
              Text(
                'File Tree',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              Spacer(),
              Icon(Icons.unfold_more, size: 12, color: AppColors.textMuted),
            ],
          ),
        ),
        Expanded(
          child: state.fileTree.isEmpty
              ? const Center(
                  child: Text(
                    'No files',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  itemCount: state.fileTree.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, i) {
                    return _FileTreeNodeWidget(
                      node: state.fileTree[i],
                      depth: 0,
                      selectedPath: state.selectedFilePath,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FileTreeNodeWidget extends StatefulWidget {
  const _FileTreeNodeWidget({
    required this.node,
    required this.depth,
    this.selectedPath,
  });

  final FileTreeNode node;
  final int depth;
  final String? selectedPath;

  @override
  State<_FileTreeNodeWidget> createState() => _FileTreeNodeWidgetState();
}

class _FileTreeNodeWidgetState extends State<_FileTreeNodeWidget> {
  bool _hovering = false;
  bool _renaming = false;
  late TextEditingController _renameCtrl;
  final _renameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController();
    _renameFocus.addListener(() {
      if (!_renameFocus.hasFocus && _renaming) _commitRename();
    });
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _startRename() {
    _renameCtrl.text = widget.node.name;
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _renameFocus.requestFocus();
        _renameCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _renameCtrl.text.lastIndexOf('.') > 0
              ? _renameCtrl.text.lastIndexOf('.')
              : _renameCtrl.text.length,
        );
      }
    });
  }

  void _showNewFolderDialog(BuildContext context, String parentDirPath) {
    final ctrl = TextEditingController();
    final colors = context.appColors;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('New Folder', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.primary, width: 1.5),
            ),
          ),
          onSubmitted: (value) {
            final name = value.trim();
            Navigator.of(dialogContext).pop();
            if (name.isEmpty) return;
            context.read<ReviewCubit>().createFolder(parentDirPath, name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              Navigator.of(dialogContext).pop();
              if (name.isEmpty) return;
              context.read<ReviewCubit>().createFolder(parentDirPath, name);
            },
            child: Text('Create', style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _commitRename() {
    if (!_renaming) return;
    final newName = _renameCtrl.text.trim();
    setState(() => _renaming = false);
    if (newName.isEmpty || newName == widget.node.name) return;
    final oldPath = widget.node.path;
    final parent = oldPath.substring(0, oldPath.lastIndexOf('/'));
    final newPath = '$parent/$newName';
    try {
      File(oldPath).renameSync(newPath);
      context.read<ReviewCubit>().refresh();
      // If the renamed file was open in editor, reopen at new path.
      try {
        context.read<FileEditorCubit>().openFile(newPath);
      } catch (_) {}
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e'), duration: const Duration(seconds: 3)),
      );
    }
  }

  void _showContextMenu(BuildContext context, Offset position) async {
    final node = widget.node;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        if (node.isDirectory) ...[
          PopupMenuItem(
            value: 'new_folder',
            height: 32,
            child: Row(children: [
              Icon(Icons.create_new_folder_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 8),
              const Text('New Folder', style: TextStyle(fontSize: 13)),
            ]),
          ),
          const PopupMenuDivider(height: 1),
        ],
        PopupMenuItem(
          value: 'copy_path',
          height: 32,
          child: Row(children: [
            Icon(Icons.copy_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            const Text('Copy path', style: TextStyle(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'copy_name',
          height: 32,
          child: Row(children: [
            Icon(Icons.text_snippet_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            const Text('Copy filename', style: TextStyle(fontSize: 13)),
          ]),
        ),
        if (!node.isDirectory) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'rename',
            height: 32,
            child: Row(children: [
              Icon(Icons.drive_file_rename_outline, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 8),
              const Text('Rename', style: TextStyle(fontSize: 13)),
            ]),
          ),
        ],
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'show_in_finder',
          height: 32,
          child: Row(children: [
            Icon(Icons.folder_open_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            const Text('Show in Finder', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ],
    );
    if (!mounted) return;
    switch (result) {
      case 'new_folder':
        _showNewFolderDialog(context, node.path);
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: node.path));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Path copied'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating),
          );
        }
      case 'copy_name':
        await Clipboard.setData(ClipboardData(text: node.name));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Filename copied'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating),
          );
        }
      case 'rename':
        _startRename();
      case 'show_in_finder':
        final target = node.isDirectory ? node.path : node.path;
        PlatformLauncher.instance.revealInFinder(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final node = widget.node;
    final isSelected = node.path == widget.selectedPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _renaming ? null : () {
              if (node.isDirectory) {
                context.read<ReviewCubit>().toggleNode(node.path);
              } else {
                context.read<ReviewCubit>().selectFile(node.path);
                try {
                  context.read<FileEditorCubit>().openFile(node.path);
                } catch (_) {}
              }
            },
            onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: EdgeInsets.only(
                left: 12.0 + widget.depth * 12.0,
                right: 8,
                top: 3,
                bottom: 3,
              ),
              color: isSelected
                  ? colors.primary.withAlpha(30)
                  : _hovering
                      ? colors.surfaceHighlight
                      : Colors.transparent,
              child: Row(
                children: [
                  if (node.isDirectory)
                    Icon(
                      node.isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 12,
                      color: AppColors.textMuted,
                    )
                  else
                    const SizedBox(width: 12),
                  const SizedBox(width: 4),
                  Builder(builder: (_) {
                    if (node.isDirectory) {
                      return Icon(
                        node.isExpanded ? Icons.folder_open : Icons.folder,
                        size: 12,
                        color: AppColors.neonBlue.withAlpha(180),
                      );
                    }
                    final ft = FileTypeUtils.forPath(node.path.isNotEmpty ? node.path : node.name);
                    return Icon(
                      ft.icon,
                      size: 12,
                      color: node.isModified ? AppColors.neonOrange : ft.color,
                    );
                  }),
                  const SizedBox(width: 5),
                  Expanded(
                    child: _renaming
                        ? TextField(
                            controller: _renameCtrl,
                            focusNode: _renameFocus,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(3),
                                borderSide: BorderSide(color: colors.primary, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(3),
                                borderSide: BorderSide(color: colors.primary, width: 1.5),
                              ),
                            ),
                            onSubmitted: (_) => _commitRename(),
                          )
                        : Text(
                            node.name,
                            style: TextStyle(
                              color: node.isModified
                                  ? AppColors.neonOrange
                                  : isSelected
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (node.isModified)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.neonOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (node.isDirectory && node.isExpanded)
          ...node.children.map((child) => _FileTreeNodeWidget(
                node: child,
                depth: widget.depth + 1,
                selectedPath: widget.selectedPath,
              )),
      ],
    );
  }
}

class _ChangedFileTile extends StatefulWidget {
  const _ChangedFileTile({required this.file, this.workspacePath});
  final FileChange file;
  /// Workspace root path for git diff lookups. When null, falls back to WorkspaceCubit.
  final String? workspacePath;

  @override
  State<_ChangedFileTile> createState() => _ChangedFileTileState();
}

class _ChangedFileTileState extends State<_ChangedFileTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final file = widget.file;
    final statusColor = switch (file.status) {
      FileChangeStatus.added => AppColors.neonGreen,
      FileChangeStatus.deleted => AppColors.neonRed,
      FileChangeStatus.modified => AppColors.neonOrange,
      _ => AppColors.textSecondary,
    };
    final statusLabel = switch (file.status) {
      FileChangeStatus.added => 'A',
      FileChangeStatus.deleted => 'D',
      FileChangeStatus.modified => 'M',
      FileChangeStatus.renamed => 'R',
      FileChangeStatus.untracked => 'U',
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () {
          // Resolve workspace path: prefer explicit param, fall back to WorkspaceCubit.
          final wsPath = widget.workspacePath ??
              (() {
                final wsState = context.read<WorkspaceCubit>().state;
                if (wsState is WorkspaceLoaded) return wsState.activeWorkspace?.path;
                return null;
              })();
          if (wsPath == null || wsPath.isEmpty) return;
          try {
            context.read<FileEditorCubit>().openDiff(
              widget.file.path,
              wsPath,
            );
          } catch (_) {}
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 100),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: _hovering ? colors.surfaceHighlight : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Center(
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.path,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (file.isStaged)
                const Icon(Icons.check_circle_outline, size: 10, color: AppColors.neonGreen),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrStatusSection extends StatelessWidget {
  const _PrStatusSection({required this.pr});
  final PrStatus pr;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'PR Status',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.more_horiz, size: 12, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'PR #${pr.prNumber}: ${pr.title}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Status: ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
              Text(
                pr.status,
                style: const TextStyle(color: AppColors.neonOrange, fontSize: 10),
              ),
              Text(
                '  ·  Reviewers: ${pr.reviewers} Pending',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              _PrButton(
                label: 'Create PR',
                color: colors.primary,
                onTap: () {},
              ),
              const SizedBox(width: 4),
              _PrButton(
                label: 'Merge',
                color: AppColors.neonGreen,
                onTap: () {},
              ),
              const SizedBox(width: 4),
              _PrButton(
                label: 'Close',
                color: AppColors.neonRed,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrButton extends StatelessWidget {
  const _PrButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Public standalone panels for embedding in mindmap cards ─────────────────

/// Shows only the file-tree tab (no diff, no runs).
class ReviewFileTreePanel extends StatelessWidget {
  const ReviewFileTreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewCubit, ReviewState>(
      builder: (context, state) {
        if (state is ReviewLoaded) {
          return Container(
            color: context.appColors.surface,
            child: _FileTreeSection(state: state),
          );
        }
        return _EmptyReview();
      },
    );
  }
}

/// Shows only the git-changes / diff tab (no file tree, no runs).
class ReviewDiffPanel extends StatelessWidget {
  const ReviewDiffPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReviewCubit, ReviewState>(
      builder: (context, state) {
        if (state is ReviewLoaded) {
          return Container(
            color: context.appColors.surface,
            child: _GitChangesSection(state: state),
          );
        }
        return _EmptyReview();
      },
    );
  }
}
