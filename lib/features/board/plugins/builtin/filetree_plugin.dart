import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class FileTreePlugin extends BoardPanelPlugin {
  const FileTreePlugin();

  static const String kTypeId = 'board.filetree';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'File Tree';

  @override
  IconData get icon => Icons.account_tree_outlined;

  @override
  Color get accentColor => const Color(0xFF64748B);

  @override
  Size get defaultSize => const Size(320, 500);

  @override
  Map<String, dynamic> get initialState => {
    'rootPath': '',
    'expandedDirs': <String>[],
    'selectedFile': '',
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _FileTreeContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

IconData _iconForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'dart' => Icons.code_outlined,
    'py' ||
    'js' ||
    'ts' ||
    'java' ||
    'kt' ||
    'swift' ||
    'go' ||
    'rs' ||
    'c' ||
    'cpp' ||
    'h' ||
    'cs' => Icons.code_outlined,
    'json' ||
    'yaml' ||
    'yml' ||
    'xml' ||
    'toml' ||
    'ini' => Icons.data_object_outlined,
    'md' || 'txt' || 'rtf' => Icons.article_outlined,
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'bmp' ||
    'svg' ||
    'webp' => Icons.image_outlined,
    'mp4' || 'mov' || 'avi' || 'mkv' => Icons.videocam_outlined,
    'mp3' || 'wav' || 'flac' || 'aac' => Icons.audiotrack_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'zip' || 'tar' || 'gz' || 'rar' || '7z' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

bool _isPreviewable(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', //
    'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v',
    'mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg',
  }.contains(ext);
}

// ─────────────────────────────────────────────────────────────────────────────

enum _TreeTab { files, diff }

class _FileTreeContent extends StatefulWidget {
  const _FileTreeContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_FileTreeContent> createState() => _FileTreeContentState();
}

class _FileTreeContentState extends State<_FileTreeContent> {
  static const Color _accent = Color(0xFF64748B);

  _TreeTab _activeTab = _TreeTab.files;

  String get _rootPath => widget.panel.state['rootPath'] as String? ?? '';

  Set<String> get _expandedDirs =>
      ((widget.panel.state['expandedDirs'] as List?) ?? <String>[])
          .whereType<String>()
          .toSet();

  String get _selectedFile =>
      widget.panel.state['selectedFile'] as String? ?? '';

  void _updateState(Map<String, dynamic> patch) {
    widget.renderContext.onUpdateState({...widget.panel.state, ...patch});
  }

  Future<void> _pickFolder() async {
    final dirPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select root folder',
    );
    if (dirPath == null) return;
    _updateState({
      'rootPath': dirPath,
      'expandedDirs': <String>[],
      'selectedFile': '',
    });
  }

  void _toggleDir(String dirPath) {
    final expanded = _expandedDirs;
    if (expanded.contains(dirPath)) {
      expanded.remove(dirPath);
    } else {
      expanded.add(dirPath);
    }
    _updateState({'expandedDirs': expanded.toList()});
  }

  void _selectFile(String filePath, String fileName) {
    _updateState({'selectedFile': filePath});
    if (_isPreviewable(fileName)) {
      widget.renderContext.onCreateLinkedPanel?.call('board.file.preview', {
        'path': filePath,
        'title': fileName,
      }, fileName);
    }
  }

  void _refresh() {
    // Trigger rebuild by touching state without changing rootPath.
    _updateState({'_refreshAt': DateTime.now().toIso8601String()});
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rootPath = _rootPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(rootPath),
        const Divider(height: 1, thickness: 0.5),
        _buildTabs(),
        const Divider(height: 1, thickness: 0.5),
        Expanded(
          child:
              _activeTab == _TreeTab.files
                  ? _buildFilesTab(rootPath)
                  : _buildDiffTab(),
        ),
      ],
    );
  }

  Widget _buildHeader(String rootPath) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rootPath.isEmpty ? 'No folder selected' : p.basename(rootPath),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    rootPath.isEmpty
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rootPath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              tooltip: 'Refresh',
              onPressed: _refresh,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: _accent,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 16),
            tooltip: 'Select Folder',
            onPressed: _pickFolder,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: _accent,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        for (final tab in _TreeTab.values)
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = tab),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _activeTab == tab ? _accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tab == _TreeTab.files ? 'FILES' : 'DIFF',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        _activeTab == tab ? _accent : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFilesTab(String rootPath) {
    if (rootPath.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree,
              size: 40,
              color: _accent.withOpacity(0.35),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a folder to browse',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text(
                'Select Folder',
                style: TextStyle(fontSize: 12),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 30),
              ),
            ),
          ],
        ),
      );
    }

    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      return const Center(
        child: Text(
          'Folder not found',
          style: TextStyle(color: Color(0xFFEF4444), fontSize: 13),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: _buildTreeEntries(rootDir, 0),
    );
  }

  List<Widget> _buildTreeEntries(Directory dir, int depth) {
    final entries = <Widget>[];
    try {
      final contents =
          dir.listSync()..sort((a, b) {
            final aIsDir = a is Directory;
            final bIsDir = b is Directory;
            if (aIsDir && !bIsDir) return -1;
            if (!aIsDir && bIsDir) return 1;
            return p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase());
          });

      for (final entity in contents) {
        final name = p.basename(entity.path);
        // Skip hidden files/directories.
        if (name.startsWith('.')) continue;

        if (entity is Directory) {
          final isExpanded = _expandedDirs.contains(entity.path);
          entries.add(_buildDirTile(entity, name, depth, isExpanded));
          if (isExpanded) {
            entries.addAll(_buildTreeEntries(entity, depth + 1));
          }
        } else if (entity is File) {
          entries.add(_buildFileTile(entity, name, depth));
        }
      }
    } on FileSystemException {
      entries.add(
        Padding(
          padding: EdgeInsets.only(left: 16.0 + depth * 16),
          child: const Text(
            'Permission denied',
            style: TextStyle(color: Color(0xFFEF4444), fontSize: 11),
          ),
        ),
      );
    }
    return entries;
  }

  Widget _buildDirTile(Directory dir, String name, int depth, bool isExpanded) {
    return InkWell(
      onTap: () => _toggleDir(dir.path),
      child: Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 16, right: 8),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              Icon(
                isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 16,
                color: const Color(0xFFFBBF24),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileTile(File file, String name, int depth) {
    final isSelected = _selectedFile == file.path;
    return InkWell(
      onTap: () => _selectFile(file.path, name),
      child: Container(
        padding: EdgeInsets.only(left: 28.0 + depth * 16, right: 8),
        color: isSelected ? _accent.withOpacity(0.1) : Colors.transparent,
        height: 28,
        child: Row(
          children: [
            Icon(_iconForFile(name), size: 16, color: _accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.difference_outlined,
            size: 40,
            color: _accent.withOpacity(0.35),
          ),
          const SizedBox(height: 8),
          const Text(
            'Diff view coming soon',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
