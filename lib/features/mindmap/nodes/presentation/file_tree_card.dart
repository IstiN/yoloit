import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/ui/components/cards/mindmap_card_shell.dart';

/// Presentation file-tree card — renders a flat expandable tree from snapshot data.
class FileTreeCard extends StatelessWidget {
  const FileTreeCard({
    super.key,
    required this.props,
    this.onToggle,
    this.onSelect,
    this.onNewFolder,
    this.onCopyPath,
    this.onShowInFinder,
    this.onOpenInPanel,
    this.onRename,
    this.onCreateFile,
    this.onDelete,
  });
  final FileTreeCardProps props;
  final void Function(String path)? onToggle;
  final void Function(String path)? onSelect;
  final void Function(String path)? onNewFolder;
  final void Function(String path)? onCopyPath;
  final void Function(String path)? onShowInFinder;
  final void Function(String path)? onOpenInPanel;
  final void Function(String path, String newName)? onRename;
  final void Function(String dirPath)? onCreateFile;
  final void Function(String path)? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MindmapCardShell(
      borderColor: colors.accentGreen.withAlpha(112),
      headerIcon: Icons.account_tree_outlined,
      headerTitle:
          props.repoName != null ? 'Tree · ${props.repoName}' : 'File Tree',
      child:
          props.entries.isEmpty
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No files loaded',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.textMuted,
                      ),
                    ),
                    if (props.repoPath != null &&
                        props.repoPath!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 4,
                          left: 8,
                          right: 8,
                        ),
                        child: Text(
                          props.repoPath!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: props.entries.length,
                itemBuilder: (_, i) {
                  final entry = props.entries[i];
                  return _TreeRow(
                    entry: entry,
                    onToggle:
                        onToggle != null
                            ? () => onToggle!(entry.path)
                            : null,
                    onSelect:
                        onSelect != null
                            ? () => onSelect!(entry.path)
                            : null,
                    onNewFolder: onNewFolder,
                    onCopyPath: onCopyPath,
                    onShowInFinder: onShowInFinder,
                    onOpenInPanel: onOpenInPanel,
                    onRename: onRename,
                    onCreateFile: onCreateFile,
                    onDelete: onDelete,
                  );
                },
              ),
    );
  }
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.entry,
    this.onToggle,
    this.onSelect,
    this.onNewFolder,
    this.onCopyPath,
    this.onShowInFinder,
    this.onOpenInPanel,
    this.onRename,
    this.onCreateFile,
    this.onDelete,
  });
  final TreeEntry entry;
  final VoidCallback? onToggle;
  final VoidCallback? onSelect;
  final void Function(String path)? onNewFolder;
  final void Function(String path)? onCopyPath;
  final void Function(String path)? onShowInFinder;
  final void Function(String path)? onOpenInPanel;
  final void Function(String path, String newName)? onRename;
  final void Function(String dirPath)? onCreateFile;
  final void Function(String path)? onDelete;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hovered = false;

  Future<void> _showContextMenu(BuildContext context, Offset globalPos) async {
    final colors = context.appColors;
    final e = widget.entry;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      items: _menuItems(colors, e),
    );
    if (result == null) return;
    await _handleMenuResult(result, e);
  }

  List<PopupMenuEntry<String>> _menuItems(AppColorScheme colors, TreeEntry e) {
    return [
      if (e.isDir)
        PopupMenuItem(
          value: 'new_folder',
          child: Text(
            '📁 New Folder',
            style: TextStyle(fontSize: 12, color: colors.terminalText),
          ),
        ),
      if (e.isDir && widget.onCreateFile != null)
        PopupMenuItem(
          value: 'create_file',
          child: Text(
            '📄 New File',
            style: TextStyle(fontSize: 12, color: colors.terminalText),
          ),
        ),
      PopupMenuItem(
        value: 'rename',
        child: Text(
          '✏️ Rename',
          style: TextStyle(fontSize: 12, color: colors.terminalText),
        ),
      ),
      PopupMenuItem(
        value: 'copy_path',
        child: Text(
          '📋 Copy path',
          style: TextStyle(fontSize: 12, color: colors.terminalText),
        ),
      ),
      PopupMenuItem(
        value: 'copy_name',
        child: Text(
          '📄 Copy filename',
          style: TextStyle(fontSize: 12, color: colors.terminalText),
        ),
      ),
      PopupMenuItem(
        value: 'show_finder',
        child: Text(
          '📂 Show in Finder',
          style: TextStyle(fontSize: 12, color: colors.terminalText),
        ),
      ),
      if (!e.isDir && widget.onOpenInPanel != null)
        PopupMenuItem(
          value: 'open_panel',
          child: Text(
            '⬡ Open in panel',
            style: TextStyle(fontSize: 12, color: colors.terminalText),
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        child: Text(
          '🗑️ Delete',
          style: TextStyle(fontSize: 12, color: colors.accentRed),
        ),
      ),
    ];
  }

  Future<void> _handleMenuResult(String result, TreeEntry e) {
    final handler = _menuHandlers[result];
    if (handler == null) return Future.value();
    return handler(e);
  }

  Map<String, Future<void> Function(TreeEntry)> get _menuHandlers => {
    'new_folder': _onMenuNewFolder,
    'create_file': _onMenuCreateFile,
    'rename': _onMenuRename,
    'copy_path': _onMenuCopyPath,
    'copy_name': _onMenuCopyName,
    'show_finder': _onMenuShowFinder,
    'open_panel': _onMenuOpenPanel,
    'delete': _onMenuDelete,
  };

  Future<void> _onMenuNewFolder(TreeEntry e) async =>
      widget.onNewFolder?.call(e.path);

  Future<void> _onMenuCreateFile(TreeEntry e) async =>
      widget.onCreateFile?.call(e.path);

  Future<void> _onMenuRename(TreeEntry e) async =>
      widget.onRename?.call(e.path, e.name);

  Future<void> _onMenuCopyPath(TreeEntry e) => copyToClipboard(e.path);

  Future<void> _onMenuCopyName(TreeEntry e) => copyToClipboard(e.name);

  Future<void> _onMenuShowFinder(TreeEntry e) =>
      PlatformLauncher.instance.revealInFinder(e.path);

  Future<void> _onMenuOpenPanel(TreeEntry e) async =>
      widget.onOpenInPanel?.call(e.path);

  Future<void> _onMenuDelete(TreeEntry e) async =>
      widget.onDelete?.call(e.path);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final e = widget.entry;
    final indent = 12.0 + e.depth * 16.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
        onTap: e.isDir ? widget.onToggle : widget.onSelect,
        child: Container(
          color: _hovered ? colors.surfaceHighlight : Colors.transparent,
          padding: EdgeInsets.only(left: indent, right: 8, top: 3, bottom: 3),
          child: Row(
            children: [
              if (e.isDir)
                Icon(
                  e.isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: colors.textSecondary,
                )
              else
                const SizedBox(width: 14),
              const SizedBox(width: 4),
              Icon(
                e.isDir
                    ? (e.isExpanded ? Icons.folder_open : Icons.folder)
                    : _fileIcon(e.name),
                size: 13,
                color: e.isDir ? colors.accentGreen : colors.accentBlue,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  e.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: _hovered ? colors.textPrimary : colors.terminalText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'dart' => Icons.code,
      'yaml' || 'yml' => Icons.settings,
      'json' => Icons.data_object,
      'md' => Icons.description,
      'py' => Icons.code,
      'ts' || 'tsx' || 'js' || 'jsx' => Icons.javascript,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' => Icons.image,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}
