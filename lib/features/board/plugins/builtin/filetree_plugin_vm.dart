import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/filetree_plugin_base.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

class FileTreePlugin extends FileTreePluginBase {
  const FileTreePlugin();

  static const String kTypeId = FileTreePluginBase.kTypeId;

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
  _TreeTab _activeTab = _TreeTab.files;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;
  bool _showHidden = true;
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  bool _searchLoading = false;
  List<FileSystemEntity> _searchResults = const <FileSystemEntity>[];
  String? _searchError;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchGeneration++;
    _searchController.dispose();
    super.dispose();
  }

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
    final dirPath = await BoardFilePicker.pickDirectory(
      context,
      remoteInfo: widget.renderContext.remoteInfo,
      initialPath: _rootPath,
      title: 'Select root folder',
    );
    if (dirPath == null) return;
    _clearSearch();
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
    // Open file preview as linked panel for any file
    widget.renderContext.onCreateLinkedPanel?.call('board.file.preview', {
      'path': filePath,
      'title': fileName,
    }, fileName);
  }

  void _refresh() {
    if (_searchQuery.isNotEmpty) {
      _scheduleSearch(immediate: true);
    }
    // Trigger rebuild by touching state without changing rootPath.
    _updateState({'_refreshAt': DateTime.now().toIso8601String()});
  }

  void _setShowHidden(bool value) {
    setState(() => _showHidden = value);
    if (_searchQuery.isNotEmpty) {
      _scheduleSearch(immediate: true);
    }
  }

  void _setSearchQuery(String value) {
    final next = value.trim().toLowerCase();
    setState(() => _searchQuery = next);
    _scheduleSearch();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchGeneration++;
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchLoading = false;
      _searchResults = const <FileSystemEntity>[];
      _searchError = null;
    });
  }

  void _scheduleSearch({bool immediate = false}) {
    _searchDebounce?.cancel();
    final query = _searchQuery;
    if (query.isEmpty || _rootPath.isEmpty) {
      _searchGeneration++;
      setState(() {
        _searchLoading = false;
        _searchResults = const <FileSystemEntity>[];
        _searchError = null;
      });
      return;
    }
    if (immediate) {
      unawaited(_runSearch(query, _rootPath, _showHidden));
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(query, _rootPath, _showHidden));
    });
  }

  Future<void> _runSearch(
    String query,
    String rootPath,
    bool showHidden,
  ) async {
    final generation = ++_searchGeneration;
    setState(() {
      _searchLoading = true;
      _searchError = null;
      _searchResults = const <FileSystemEntity>[];
    });
    try {
      final results = await _collectMatchingEntriesAsync(
        Directory(rootPath),
        query: query,
        showHidden: showHidden,
        generation: generation,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchError = error.toString();
        _searchLoading = false;
      });
    }
  }

  // ── Context menu ──────────────────────────────────────────────────────────

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPos,
    FileSystemEntity entity,
  ) async {
    final isDir = entity is Directory;
    final colors = context.appColors;
    final name = p.basename(entity.path);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      color: colors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      items: [
        if (isDir)
          PopupMenuItem(
            value: 'new_folder',
            child: Text(
              '📁 New Folder',
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
            ),
          ),
        if (isDir)
          PopupMenuItem(
            value: 'new_file',
            child: Text(
              '📄 New File',
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
            ),
          ),
        PopupMenuItem(
          value: 'rename',
          child: Text(
            '✏️ Rename',
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
          ),
        ),
        PopupMenuItem(
          value: 'copy_path',
          child: Text(
            '📋 Copy path',
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
          ),
        ),
        PopupMenuItem(
          value: 'copy_name',
          child: Text(
            '📄 Copy filename',
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
          ),
        ),
        PopupMenuItem(
          value: 'show_finder',
          child: Text(
            '📂 Show in Finder',
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
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
      ],
    );
    if (result == null || !mounted) return;
    switch (result) {
      case 'new_folder':
        await _promptNewFolder(entity.path);
      case 'new_file':
        await _promptNewFile(entity.path);
      case 'rename':
        await _promptRename(entity.path, name);
      case 'copy_path':
        await copyToClipboard(entity.path);
      case 'copy_name':
        await copyToClipboard(name);
      case 'show_finder':
        await PlatformLauncher.instance.revealInFinder(entity.path);
      case 'delete':
        await _confirmDelete(entity, name);
    }
  }

  Future<void> _promptNewFolder(String parentDir) async {
    final name = await _showInputDialog('New Folder', 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    final dir = Directory(p.join(parentDir, name.trim()));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _refresh();
  }

  Future<void> _promptNewFile(String parentDir) async {
    final name = await _showInputDialog('New File', 'File name');
    if (name == null || name.trim().isEmpty) return;
    final file = File(p.join(parentDir, name.trim()));
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    _refresh();
  }

  Future<void> _promptRename(String entityPath, String currentName) async {
    final newName = await _showInputDialog('Rename', 'New name', currentName);
    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == currentName) {
      return;
    }
    final parent = p.dirname(entityPath);
    final newPath = p.join(parent, newName.trim());
    try {
      final entity =
          FileSystemEntity.typeSync(entityPath) ==
                  FileSystemEntityType.directory
              ? Directory(entityPath)
              : File(entityPath) as FileSystemEntity;
      await entity.rename(newPath);
    } catch (_) {}
    _refresh();
  }

  Future<void> _confirmDelete(FileSystemEntity entity, String name) async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: colors.background,
            title: const Text('Delete', style: TextStyle(fontSize: 14)),
            content: Text(
              'Delete "$name"? This cannot be undone.',
              style: const TextStyle(fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: colors.accentRed),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else {
        await entity.delete();
      }
    } catch (_) {}
    _refresh();
  }

  Future<String?> _showInputDialog(
    String title,
    String hint, [
    String initialValue = '',
  ]) async {
    final colors = context.appColors;
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: colors.background,
            title: Text(title, style: const TextStyle(fontSize: 14)),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
                isDense: true,
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('OK'),
              ),
            ],
          ),
    );
    controller.dispose();
    return result;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rootPath = _rootPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(rootPath),
        Divider(color: colors.border, height: 1, thickness: 0.5),
        _buildTabs(),
        Divider(color: colors.border, height: 1, thickness: 0.5),
        if (_showSearch && _activeTab == _TreeTab.files) _buildSearchBar(),
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
    final colors = context.appColors;
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
                    rootPath.isEmpty ? colors.textMuted : colors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rootPath.isNotEmpty)
            IconButton(
              icon: Icon(
                _showHidden ? Icons.visibility : Icons.visibility_off,
                size: 16,
              ),
              tooltip: _showHidden ? 'Hide dotfiles' : 'Show dotfiles',
              onPressed: () => _setShowHidden(!_showHidden),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: _showHidden ? colors.textPrimary : colors.textSecondary,
            ),
          if (rootPath.isNotEmpty)
            IconButton(
              icon: Icon(
                _showSearch ? Icons.search_off : Icons.search,
                size: 16,
              ),
              tooltip: 'Search files',
              onPressed: () {
                final next = !_showSearch;
                if (!next) {
                  _clearSearch();
                }
                setState(() => _showSearch = next);
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: _showSearch ? colors.textPrimary : colors.textSecondary,
            ),
          if (rootPath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              tooltip: 'Refresh',
              onPressed: _refresh,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: colors.textSecondary,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 16),
            tooltip: 'Select Folder',
            onPressed: _pickFolder,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: colors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final colors = context.appColors;
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
                      color:
                          _activeTab == tab
                              ? colors.textSecondary
                              : Colors.transparent,
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
                        _activeTab == tab
                            ? colors.textSecondary
                            : colors.textMuted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Filter files…',
          hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
          prefixIcon: Icon(Icons.search, size: 14, color: colors.textMuted),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 0,
          ),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(Icons.close, size: 14, color: colors.textMuted),
                  )
                  : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 0,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: colors.textSecondary.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: colors.textSecondary.withValues(alpha: 0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.textSecondary),
          ),
        ),
        onChanged: _setSearchQuery,
      ),
    );
  }

  Widget _buildFilesTab(String rootPath) {
    final colors = context.appColors;
    if (rootPath.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree,
              size: 40,
              color: colors.textSecondary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 8),
            const Caption('Select a folder to browse', fontSize: 13),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text(
                'Select Folder',
                style: TextStyle(fontSize: 12),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: colors.textSecondary,
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
      return Center(
        child: Text(
          'Folder not found',
          style: TextStyle(color: colors.accentRed, fontSize: 13),
        ),
      );
    }

    if (_searchQuery.isNotEmpty) {
      return _buildSearchResults(rootDir);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: _buildTreeEntries(rootDir, 0),
    );
  }

  Widget _buildSearchResults(Directory rootDir) {
    final colors = context.appColors;
    if (_searchLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 10),
            Caption('Searching...', fontSize: 12),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Search failed: $_searchError',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.accentRed, fontSize: 12),
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Caption('No matching files', fontSize: 12),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final colors = context.appColors;
        final entity = _searchResults[index];
        final name = p.basename(entity.path);
        final relPath = p.relative(entity.path, from: _rootPath);
        final isDir = entity is Directory;
        return GestureDetector(
          onSecondaryTapDown:
              (d) => _showContextMenu(context, d.globalPosition, entity),
          child: InkWell(
            onTap:
                isDir
                    ? () {
                      final expanded = _expandedDirs;
                      expanded.add(entity.path);
                      // Also expand parents so the folder is visible in tree
                      var parent = entity.parent;
                      while (parent.path != _rootPath &&
                          parent.path.startsWith(_rootPath)) {
                        expanded.add(parent.path);
                        parent = parent.parent;
                      }
                      _updateState({'expandedDirs': expanded.toList()});
                      setState(() {
                        _showSearch = false;
                      });
                      _clearSearch();
                    }
                    : () => _selectFile(entity.path, name),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 28,
                child: Row(
                  children: [
                    Icon(
                      isDir ? Icons.folder_outlined : _iconForFile(name),
                      size: 15,
                      color: isDir ? colors.accentOrange : colors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        relPath,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              _selectedFile == entity.path
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<FileSystemEntity>> _collectMatchingEntriesAsync(
    Directory rootDir, {
    required String query,
    required bool showHidden,
    required int generation,
    int maxResults = 200,
    int maxVisited = 12000,
  }) async {
    final results = <FileSystemEntity>[];
    final queue = <Directory>[rootDir];
    var visited = 0;

    while (queue.isNotEmpty &&
        results.length < maxResults &&
        visited < maxVisited) {
      if (generation != _searchGeneration) return results;
      final dir = queue.removeAt(0);
      final contents = await _listSortedContents(dir);
      if (contents == null) continue;

      for (final entity in contents) {
        if (generation != _searchGeneration ||
            results.length >= maxResults ||
            visited >= maxVisited) {
          return results;
        }
        visited++;
        _collectMatchingEntry(
          entity,
          query: query,
          showHidden: showHidden,
          results: results,
          queue: queue,
        );
      }
      if (visited % 400 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return results;
  }

  /// Lists [dir] contents sorted with directories first, then by name.
  /// Returns null when the directory cannot be listed (skipped by the walk).
  Future<List<FileSystemEntity>?> _listSortedContents(Directory dir) async {
    final List<FileSystemEntity> contents;
    try {
      contents = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return null;
    }
    contents.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase());
    });
    return contents;
  }

  /// Adds [entity] to [results] when it matches, and enqueues directories.
  void _collectMatchingEntry(
    FileSystemEntity entity, {
    required String query,
    required bool showHidden,
    required List<FileSystemEntity> results,
    required List<Directory> queue,
  }) {
    final name = p.basename(entity.path);
    if (!showHidden && name.startsWith('.')) return;
    final matches = name.toLowerCase().contains(query);
    if (entity is Directory) {
      if (matches) results.add(entity);
      queue.add(entity);
    } else if (entity is File && matches) {
      results.add(entity);
    }
  }

  List<Widget> _buildTreeEntries(Directory dir, int depth) {
    final colors = context.appColors;
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
        // Skip hidden files/directories unless _showHidden is enabled.
        if (!_showHidden && name.startsWith('.')) continue;

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
          child: Text(
            'Permission denied',
            style: TextStyle(color: colors.accentRed, fontSize: 11),
          ),
        ),
      );
    }
    return entries;
  }

  Widget _buildDirTile(Directory dir, String name, int depth, bool isExpanded) {
    final colors = context.appColors;
    return GestureDetector(
      onSecondaryTapDown:
          (d) => _showContextMenu(context, d.globalPosition, dir),
      child: InkWell(
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
                  color: colors.textMuted,
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.folder_open_outlined
                      : Icons.folder_outlined,
                  size: 16,
                  color: colors.accentOrange,
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
      ),
    );
  }

  Widget _buildFileTile(File file, String name, int depth) {
    final colors = context.appColors;
    final isSelected = _selectedFile == file.path;
    return GestureDetector(
      onSecondaryTapDown:
          (d) => _showContextMenu(context, d.globalPosition, file),
      child: InkWell(
        onTap: () => _selectFile(file.path, name),
        child: Container(
          padding: EdgeInsets.only(left: 28.0 + depth * 16, right: 8),
          color:
              isSelected
                  ? colors.textSecondary.withValues(alpha: 0.1)
                  : Colors.transparent,
          height: 28,
          child: Row(
            children: [
              Icon(_iconForFile(name), size: 16, color: colors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildDiffTab() {
    final colors = context.appColors;
    final rootPath = _rootPath;
    if (rootPath.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.difference_outlined,
              size: 40,
              color: colors.textSecondary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 8),
            const Caption('Select a folder to see changes', fontSize: 13),
          ],
        ),
      );
    }
    return _GitDiffView(
      rootPath: rootPath,
      onOpenDiff: (filePath, root) {
        final fileName = filePath.split('/').last;
        widget.renderContext.onCreateLinkedPanel?.call('board.diff.preview', {
          'filePath': filePath,
          'rootPath': root,
          'title': fileName,
        }, 'Diff: $fileName');
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Git Diff View
// ─────────────────────────────────────────────────────────────────────────────

class _GitDiffView extends StatefulWidget {
  const _GitDiffView({required this.rootPath, this.onOpenDiff});
  final String rootPath;
  final void Function(String filePath, String rootPath)? onOpenDiff;

  @override
  State<_GitDiffView> createState() => _GitDiffViewState();
}

class _GitDiffViewState extends State<_GitDiffView> {
  List<_DiffEntry>? _entries;
  bool _loading = true;
  String? _error;
  final Set<String> _expandedDirs = {};
  String? _selectedFile;

  @override
  void initState() {
    super.initState();
    _loadDiff();
  }

  @override
  void didUpdateWidget(covariant _GitDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) _loadDiff();
  }

  Future<void> _loadDiff() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Process.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: widget.rootPath);
      if (result.exitCode != 0) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Not a git repository';
        });
        return;
      }
      final lines = (result.stdout as String)
          .split('\n')
          .where((l) => l.trim().isNotEmpty);
      final entries = <_DiffEntry>[];
      for (final line in lines) {
        if (line.length < 4) continue;
        final status = line.substring(0, 2).trim();
        final filePath = line.substring(3).trim();
        entries.add(_DiffEntry(status: status, filePath: filePath));
      }
      if (!mounted) return;
      // Auto-expand all directories
      final dirs = <String>{};
      for (final e in entries) {
        final parts = e.filePath.split('/');
        for (int i = 1; i < parts.length; i++) {
          dirs.add(parts.sublist(0, i).join('/'));
        }
      }
      setState(() {
        _entries = entries;
        _expandedDirs.addAll(dirs);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to get git status';
      });
    }
  }

  Color _statusColor(String status) {
    final c = context.appColors;
    return switch (status) {
      'M' => c.accentOrange,
      'A' => c.accentGreen,
      'D' => c.accentRed,
      'R' => c.accentBlue,
      _ => c.textMuted,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'M' => 'M',
      'A' => 'A',
      'D' => 'D',
      'R' => 'R',
      '?' || '??' => '?',
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Caption(_error!, fontSize: 13),
      );
    }
    final entries = _entries ?? [];
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 40,
              color: colors.accentGreen.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            const Caption('Working tree clean', fontSize: 13),
          ],
        ),
      );
    }

    // Build tree structure
    final treeNodes = _buildTree(entries);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Caption('${entries.length} changed file${entries.length == 1 ? '' : 's'}',),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 14),
                onPressed: _loadDiff,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                color: colors.textMuted,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: treeNodes,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTree(List<_DiffEntry> entries) {
    final colors = context.appColors;
    // Group files by directory path into a tree
    final tree = <String, List<_DiffEntry>>{};
    final topLevel = <_DiffEntry>[];

    for (final e in entries) {
      final slashIdx = e.filePath.lastIndexOf('/');
      if (slashIdx < 0) {
        topLevel.add(e);
      } else {
        final dir = e.filePath.substring(0, slashIdx);
        tree.putIfAbsent(dir, () => []).add(e);
      }
    }

    // Collect all unique directory prefixes, sorted
    final allDirs = tree.keys.toList()..sort();
    final widgets = <Widget>[];

    // Render directories with their files
    for (final dir in allDirs) {
      final depth = dir.split('/').length - 1;
      final isExpanded = _expandedDirs.contains(dir);
      final dirName = dir.split('/').last;
      final fileCount = tree[dir]!.length;

      widgets.add(
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedDirs.remove(dir);
              } else {
                _expandedDirs.add(dir);
              }
            });
          },
          child: Padding(
            padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 8),
            child: SizedBox(
              height: 26,
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.folder_open_outlined
                        : Icons.folder_outlined,
                    size: 14,
                    color: colors.accentOrange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dirName,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Caption('$fileCount', fontSize: 10),
                ],
              ),
            ),
          ),
        ),
      );

      if (isExpanded) {
        for (final e in tree[dir]!) {
          widgets.add(_buildFileRow(e, depth + 1));
        }
      }
    }

    // Top-level files (no directory)
    for (final e in topLevel) {
      widgets.add(_buildFileRow(e, 0));
    }

    return widgets;
  }

  Widget _buildFileRow(_DiffEntry entry, int depth) {
    final colors = context.appColors;
    final fileName = entry.filePath.split('/').last;
    final statusColor = _statusColor(entry.status);
    final isSelected = _selectedFile == entry.filePath;

    return InkWell(
      onTap: () {
        setState(() => _selectedFile = entry.filePath);
        widget.onOpenDiff?.call(entry.filePath, widget.rootPath);
      },
      child: Container(
        color: isSelected ? colors.surfaceElevated : Colors.transparent,
        padding: EdgeInsets.only(left: 22.0 + depth * 14, right: 8),
        height: 26,
        child: Row(
          children: [
            Container(
              width: 16,
              alignment: Alignment.center,
              child: Text(
                _statusLabel(entry.status),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(_iconForFile(fileName), size: 14, color: colors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                fileName,
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
}

class _DiffEntry {
  const _DiffEntry({required this.status, required this.filePath});
  final String status;
  final String filePath;
}
