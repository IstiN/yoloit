import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        border: Border.all(color: const Color(0x7034D399), width: 1.5),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
              color: Color(0x90000000), blurRadius: 20, offset: Offset(0, 6))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF0F1218),
                border:
                    Border(bottom: BorderSide(color: Color(0xFF1E2330))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined,
                      size: 12, color: Color(0xFF34D399)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      props.repoName != null
                          ? 'Tree · ${props.repoName}'
                          : 'File Tree',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8E8FF)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: props.entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No files loaded',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFF475569))),
                          if (props.repoPath != null &&
                              props.repoPath!.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 4, left: 8, right: 8),
                              child: Text(props.repoPath!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 9, color: Color(0xFF334155))),
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
                          onToggle: onToggle != null
                              ? () => onToggle!(entry.path)
                              : null,
                          onSelect: onSelect != null
                              ? () => onSelect!(entry.path)
                              : null,
                          onNewFolder: onNewFolder,
                          onCopyPath: onCopyPath,
                          onShowInFinder: onShowInFinder,
                          onOpenInPanel: onOpenInPanel,
                          onRename: onRename,
                          onCreateFile: onCreateFile,
                        );
                      },
                    ),
            ),
          ],
        ),
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

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hovered = false;

  Future<void> _showContextMenu(BuildContext context, Offset globalPos) async {
    final e = widget.entry;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
      color: const Color(0xFF12151C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2A3040)),
      ),
      items: [
        if (e.isDir)
          const PopupMenuItem(value: 'new_folder', child: Text('📁 New Folder',
              style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE)))),
        if (e.isDir && widget.onCreateFile != null)
          const PopupMenuItem(value: 'create_file', child: Text('📄 New File',
              style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE)))),
        const PopupMenuItem(value: 'rename', child: Text('✏️ Rename',
            style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE)))),
        const PopupMenuItem(value: 'copy_path', child: Text('📋 Copy path',
            style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE)))),
        const PopupMenuItem(value: 'copy_name', child: Text('📄 Copy filename',
            style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE)))),
        const PopupMenuItem(value: 'show_finder', child: Text('📂 Show in Finder',
            style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE)))),
        if (!e.isDir && widget.onOpenInPanel != null)
          const PopupMenuItem(value: 'open_panel', child: Text('⬡ Open in panel',
              style: TextStyle(fontSize: 12, color: Color(0xFFCECEEE)))),
      ],
    );
    if (result == null) return;
    switch (result) {
      case 'new_folder':
        widget.onNewFolder?.call(e.path);
      case 'create_file':
        widget.onCreateFile?.call(e.path);
      case 'rename':
        widget.onRename?.call(e.path, e.name);
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: e.path));
      case 'copy_name':
        await Clipboard.setData(ClipboardData(text: e.name));
      case 'show_finder':
        await PlatformLauncher.instance.revealInFinder(e.path);
      case 'open_panel':
        widget.onOpenInPanel?.call(e.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final indent = 12.0 + e.depth * 16.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
        onTap: e.isDir ? widget.onToggle : widget.onSelect,
        child: Container(
          color: _hovered ? const Color(0xFF1A1E2A) : Colors.transparent,
          padding: EdgeInsets.only(
              left: indent, right: 8, top: 3, bottom: 3),
          child: Row(
            children: [
              if (e.isDir)
                Icon(
                  e.isExpanded
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 14,
                  color: const Color(0xFF6B7898),
                )
              else
                const SizedBox(width: 14),
              const SizedBox(width: 4),
              Icon(
                e.isDir
                    ? (e.isExpanded
                        ? Icons.folder_open
                        : Icons.folder)
                    : _fileIcon(e.name),
                size: 13,
                color: e.isDir
                    ? const Color(0xFF34D399)
                    : const Color(0xFF60A5FA),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  e.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: _hovered
                        ? const Color(0xFFE8E8FF)
                        : const Color(0xFFCECEEE),
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
