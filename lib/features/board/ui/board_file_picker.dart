import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as native;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';

enum BoardFilePickerMode { directory, file, files }

class BoardFileSelection {
  const BoardFileSelection({required this.path, required this.name});

  final String path;
  final String name;
}

class BoardFilePicker {
  const BoardFilePicker._();

  static Future<String?> pickDirectory(
    BuildContext context, {
    RemoteBoardInfo? remoteInfo,
    String? initialPath,
    String title = 'Choose folder',
  }) {
    if (remoteInfo == null) {
      return native.FilePicker.getDirectoryPath(
        dialogTitle: title,
        initialDirectory: _nativeInitialDirectory(initialPath),
      );
    }
    return showDialog<String>(
      context: context,
      builder:
          (_) => _BoardFilePickerDialog(
            title: title,
            mode: BoardFilePickerMode.directory,
            remoteInfo: remoteInfo,
            initialPath: initialPath,
          ),
    );
  }

  static Future<BoardFileSelection?> pickFile(
    BuildContext context, {
    RemoteBoardInfo? remoteInfo,
    String? initialPath,
    String title = 'Choose file',
  }) {
    if (remoteInfo == null) {
      return _pickNativeFile(initialPath: initialPath, title: title);
    }
    return showDialog<BoardFileSelection>(
      context: context,
      builder:
          (_) => _BoardFilePickerDialog(
            title: title,
            mode: BoardFilePickerMode.file,
            remoteInfo: remoteInfo,
            initialPath: initialPath,
          ),
    );
  }

  static Future<List<BoardFileSelection>?> pickFiles(
    BuildContext context, {
    RemoteBoardInfo? remoteInfo,
    String? initialPath,
    String title = 'Choose files',
  }) {
    if (remoteInfo == null) {
      return _pickNativeFiles(initialPath: initialPath, title: title);
    }
    return showDialog<List<BoardFileSelection>>(
      context: context,
      builder:
          (_) => _BoardFilePickerDialog(
            title: title,
            mode: BoardFilePickerMode.files,
            remoteInfo: remoteInfo,
            initialPath: initialPath,
          ),
    );
  }

  static Future<BoardFileSelection?> _pickNativeFile({
    required String? initialPath,
    required String title,
  }) async {
    final result = await native.FilePicker.pickFiles(
      dialogTitle: title,
      initialDirectory: _nativeInitialDirectory(initialPath),
      allowMultiple: false,
      withData: false,
      withReadStream: false,
    );
    final file = result?.files.firstOrNull;
    final path = file?.path;
    if (path == null || path.trim().isEmpty) return null;
    return BoardFileSelection(path: path, name: file?.name ?? p.basename(path));
  }

  static Future<List<BoardFileSelection>?> _pickNativeFiles({
    required String? initialPath,
    required String title,
  }) async {
    final result = await native.FilePicker.pickFiles(
      dialogTitle: title,
      initialDirectory: _nativeInitialDirectory(initialPath),
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    final files = result?.files
        .where((file) => file.path != null && file.path!.trim().isNotEmpty)
        .map(
          (file) => BoardFileSelection(
            path: file.path!,
            name: file.name.isEmpty ? p.basename(file.path!) : file.name,
          ),
        )
        .toList(growable: false);
    return files == null || files.isEmpty ? null : files;
  }

  static String? _nativeInitialDirectory(String? initialPath) {
    final value = initialPath?.trim();
    if (value == null || value.isEmpty) return null;
    final expanded = _expandLocalPathForNative(value);
    final type = FileSystemEntity.typeSync(expanded, followLinks: false);
    if (type == FileSystemEntityType.directory) return expanded;
    if (type == FileSystemEntityType.file) return p.dirname(expanded);
    return null;
  }

  static String _expandLocalPathForNative(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed == '~') return _localHomePathForNative() ?? trimmed;
    if (trimmed.startsWith('~/')) {
      final home = _localHomePathForNative();
      if (home != null) return p.join(home, trimmed.substring(2));
    }
    return trimmed;
  }

  static String? _localHomePathForNative() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final trimmed = home?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _BoardFilePickerDialog extends StatefulWidget {
  const _BoardFilePickerDialog({
    required this.title,
    required this.mode,
    required this.remoteInfo,
    required this.initialPath,
  });

  final String title;
  final BoardFilePickerMode mode;
  final RemoteBoardInfo? remoteInfo;
  final String? initialPath;

  @override
  State<_BoardFilePickerDialog> createState() => _BoardFilePickerDialogState();
}

class _BoardFilePickerDialogState extends State<_BoardFilePickerDialog> {
  _DirectoryListing? _listing;
  Object? _error;
  bool _loading = false;
  late String _path;
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  String _query = '';
  final Set<String> _selectedFiles = <String>{};

  bool get _isRemote => widget.remoteInfo != null;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController()..addListener(() {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(
            const Duration(milliseconds: 150),
            () => setState(() => _query = _searchController.text.trim()),
          );
        });
    _path = _initialPath();
    unawaited(_load(_path));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _initialPath() {
    final explicit = widget.initialPath?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (_isRemote) return '';
    return _localHomePath() ?? Directory.current.path;
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing =
          _isRemote
              ? await _loadRemote(path)
              : await _loadLocal(path.isEmpty ? Directory.current.path : path);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _path = listing.path;
        _searchController.clear();
        _selectedFiles.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_DirectoryListing> _loadRemote(String path) async {
    final remote = widget.remoteInfo!;
    final listing = await YoloitRemoteClient(
      baseUrl: remote.url,
      token: remote.token,
    ).listDirectory(path);
    return _DirectoryListing(
      path: listing.path,
      parent: listing.parent,
      roots:
          listing.roots
              .map(
                (entry) => _FileEntry(
                  name: entry.name,
                  path: entry.path,
                  isDirectory: true,
                ),
              )
              .toList(),
      entries:
          listing.entries
              .map(
                (entry) => _FileEntry(
                  name: entry.name,
                  path: entry.path,
                  isDirectory: entry.isDirectory,
                ),
              )
              .toList(),
    );
  }

  Future<_DirectoryListing> _loadLocal(String rawPath) async {
    final directory = Directory(_expandLocalPath(rawPath));
    if (!await directory.exists()) {
      throw FileSystemException('Directory not found', directory.path);
    }
    final entries = <_FileEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.directory &&
          stat.type != FileSystemEntityType.file) {
        continue;
      }
      entries.add(
        _FileEntry(
          name: p.basename(entity.path),
          path: entity.path,
          isDirectory: stat.type == FileSystemEntityType.directory,
        ),
      );
    }
    entries.sort(_compareEntries);
    return _DirectoryListing(
      path: directory.path,
      parent:
          directory.parent.path == directory.path
              ? null
              : directory.parent.path,
      roots: _localRoots(),
      entries: entries,
    );
  }

  List<_FileEntry> _localRoots() {
    final roots = <_FileEntry>[];
    final seen = <String>{};
    void addRoot(String name, String? path) {
      final value = path?.trim();
      if (value == null || value.isEmpty || !seen.add(value)) return;
      roots.add(_FileEntry(name: name, path: value, isDirectory: true));
    }

    addRoot('Home', _localHomePath());
    addRoot('Current', Directory.current.path);
    addRoot('Root', Platform.pathSeparator);
    return roots.toList();
  }

  String? _localHomePath() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final trimmed = home?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _expandLocalPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed == '~') return _localHomePath() ?? trimmed;
    if (trimmed.startsWith('~/')) {
      final home = _localHomePath();
      if (home != null) return p.join(home, trimmed.substring(2));
    }
    return trimmed.isEmpty
        ? _localHomePath() ?? Directory.current.path
        : trimmed;
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('New folder'),
            content: TextField(
              key: const Key('board-file-picker-new-folder-name'),
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Folder name'),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('board-file-picker-create-folder-confirm'),
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Create'),
              ),
            ],
          ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    try {
      if (_isRemote) {
        final remote = widget.remoteInfo!;
        final listing = await YoloitRemoteClient(
          baseUrl: remote.url,
          token: remote.token,
        ).createDirectory(parentPath: _path, name: trimmed);
        if (!mounted) return;
        setState(() {
          _listing = _DirectoryListing.fromRemote(listing);
          _path = listing.path;
        });
      } else {
        await Directory(p.join(_path, trimmed)).create();
        await _load(_path);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create folder: $error')),
      );
    }
  }

  void _confirm() {
    if (widget.mode == BoardFilePickerMode.directory) {
      Navigator.of(context).pop(_path);
      return;
    }
    final listing = _listing;
    if (listing == null) return;
    final selected =
        listing.entries
            .where((entry) => _selectedFiles.contains(entry.path))
            .map(
              (entry) => BoardFileSelection(path: entry.path, name: entry.name),
            )
            .toList();
    if (widget.mode == BoardFilePickerMode.file) {
      if (selected.isEmpty) return;
      Navigator.of(context).pop(selected.first);
    } else {
      Navigator.of(context).pop(selected);
    }
  }

  void _submitSearch(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (trimmed == '~') {
      String? home;
      for (final entry in _listing?.roots ?? const <_FileEntry>[]) {
        if (entry.name.toLowerCase() == 'home') {
          home = entry.path;
          break;
        }
      }
      if (home != null) unawaited(_load(home));
      return;
    }
    if (_looksLikePath(trimmed)) {
      unawaited(_load(trimmed));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    return AdaptiveDialogScaffold(
      title: widget.title,
      icon: Icon(_isRemote ? Icons.cloud_queue : Icons.folder_open_outlined),
      maxWidth: 680,
      maxHeight: 520,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Parent folder',
                onPressed:
                    listing?.parent == null
                        ? null
                        : () => _load(listing!.parent!),
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: Text(
                  listing?.path ?? _path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('board-file-picker-new-folder'),
                tooltip: 'New folder',
                onPressed: listing == null ? null : _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => _load(_path),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if ((listing?.roots ?? const <_FileEntry>[]).isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final root = listing.roots[index];
                  return ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                    label: Text(root.name),
                    onPressed: () => _load(root.path),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemCount: listing!.roots.length,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const Key('board-file-picker-search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _query.isEmpty
                      ? null
                      : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
              hintText: 'Quick search or paste a path...',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: _submitSearch,
          ),
          const Divider(height: 24),
          Expanded(child: _buildEntries(listing)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('board-file-picker-confirm'),
          onPressed:
              widget.mode == BoardFilePickerMode.directory ||
                      _selectedFiles.isNotEmpty
                  ? _confirm
                  : null,
          child: Text(
            widget.mode == BoardFilePickerMode.directory ? 'Choose' : 'Open',
          ),
        ),
      ],
    );
  }

  Widget _buildEntries(_DirectoryListing? listing) {
    if (_loading && listing == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Could not load folder: $_error'));
    }
    if (listing == null) return const SizedBox.shrink();
    if (listing.entries.isEmpty) {
      return const Center(child: Text('No files here yet.'));
    }
    final entries = _filteredEntries(listing);
    if (entries.isEmpty) {
      return const Center(child: Text('No matches in this folder.'));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = _selectedFiles.contains(entry.path);
        final canSelectFile =
            !entry.isDirectory && widget.mode != BoardFilePickerMode.directory;
        return ListTile(
          key: Key('board-file-picker-entry-${entry.path}'),
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: selected,
          trailing:
              widget.mode == BoardFilePickerMode.files && canSelectFile
                  ? Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleFile(entry),
                  )
                  : null,
          onTap: () {
            if (entry.isDirectory) {
              unawaited(_load(entry.path));
              return;
            }
            if (canSelectFile) _toggleFile(entry);
          },
        );
      },
    );
  }

  void _toggleFile(_FileEntry entry) {
    setState(() {
      if (widget.mode == BoardFilePickerMode.file) {
        _selectedFiles
          ..clear()
          ..add(entry.path);
      } else if (!_selectedFiles.add(entry.path)) {
        _selectedFiles.remove(entry.path);
      }
    });
  }

  List<_FileEntry> _filteredEntries(_DirectoryListing listing) {
    final query = _query.toLowerCase();
    if (query.isEmpty || _looksLikePath(_query)) {
      return listing.entries;
    }
    return listing.entries
        .where((entry) {
          return entry.name.toLowerCase().contains(query) ||
              entry.path.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  bool _looksLikePath(String value) {
    return value.startsWith('/') ||
        value.startsWith('~/') ||
        value.startsWith('~\\') ||
        p.isAbsolute(value) ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
  }
}

class _DirectoryListing {
  const _DirectoryListing({
    required this.path,
    required this.parent,
    required this.roots,
    required this.entries,
  });

  factory _DirectoryListing.fromRemote(RemoteDirectoryListing listing) {
    return _DirectoryListing(
      path: listing.path,
      parent: listing.parent,
      roots:
          listing.roots
              .map(
                (entry) => _FileEntry(
                  name: entry.name,
                  path: entry.path,
                  isDirectory: true,
                ),
              )
              .toList(),
      entries:
          listing.entries
              .map(
                (entry) => _FileEntry(
                  name: entry.name,
                  path: entry.path,
                  isDirectory: entry.isDirectory,
                ),
              )
              .toList(),
    );
  }

  final String path;
  final String? parent;
  final List<_FileEntry> roots;
  final List<_FileEntry> entries;
}

class _FileEntry {
  const _FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
}

int _compareEntries(_FileEntry a, _FileEntry b) {
  if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
