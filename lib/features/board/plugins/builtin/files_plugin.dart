import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class FilesPlugin extends BoardPanelPlugin {
  const FilesPlugin();

  static const String kTypeId = 'board.files';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Files';

  @override
  IconData get icon => Icons.attach_file_outlined;

  @override
  Color get accentColor => const Color(0xFFEC4899);

  @override
  Size get defaultSize => const Size(360, 320);

  @override
  Map<String, dynamic> get initialState => {'files': <Map<String, dynamic>>[]};

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _FilesContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

IconData _iconForExtension(String ext) => switch (ext.toLowerCase()) {
  'png' || 'jpg' || 'jpeg' || 'gif' || 'bmp' || 'svg' || 'webp' => Icons.image_outlined,
  'mp4' || 'mov' || 'avi' || 'mkv' => Icons.videocam_outlined,
  'mp3' || 'wav' || 'flac' || 'aac' => Icons.audiotrack_outlined,
  'pdf' => Icons.picture_as_pdf_outlined,
  'dart' || 'py' || 'js' || 'ts' || 'java' || 'kt' || 'swift' ||
  'go' || 'rs' || 'c' || 'cpp' || 'h' || 'cs' => Icons.code_outlined,
  'json' || 'yaml' || 'yml' || 'xml' || 'toml' || 'ini' => Icons.data_object_outlined,
  'md' || 'txt' || 'rtf' => Icons.article_outlined,
  'zip' || 'tar' || 'gz' || 'rar' || '7z' => Icons.folder_zip_outlined,
  '' => Icons.folder_outlined,
  _ => Icons.insert_drive_file_outlined,
};

class _FilesContent extends StatefulWidget {
  const _FilesContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_FilesContent> createState() => _FilesContentState();
}

class _FilesContentState extends State<_FilesContent> {
  static const Color _accent = Color(0xFFEC4899);

  List<Map<String, dynamic>> get _files =>
      (widget.panel.state['files'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  void _save(List<Map<String, dynamic>> files) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'files': files,
    });
  }

  Future<void> _addFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final current = _files;
    final existingPaths = current.map((f) => f['path'] as String?).toSet();

    final newEntries = result.files
        .where((f) => f.path != null && !existingPaths.contains(f.path))
        .map((f) => {
              'id': DateTime.now().millisecondsSinceEpoch.toString() +
                  f.name,
              'path': f.path!,
              'name': f.name,
              'addedAt': DateTime.now().toIso8601String(),
            })
        .toList();

    if (newEntries.isEmpty) return;
    _save([...current, ...newEntries]);
  }

  void _removeFile(String id) {
    _save(_files.where((f) => f['id'] != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header / add button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Text(
                '${files.length} file${files.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEC4899),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addFiles,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Files', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // Files list
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.attach_file,
                        size: 40,
                        color: _accent.withOpacity(0.35),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No files added yet',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: files.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, thickness: 0.5, indent: 52),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final id = file['id'] as String;
                    final name = file['name'] as String? ?? '';
                    final path = file['path'] as String? ?? '';
                    final ext = name.contains('.')
                        ? name.split('.').last
                        : '';

                    return _FileTile(
                      name: name,
                      path: path,
                      icon: _iconForExtension(ext),
                      onReveal: () =>
                          PlatformLauncher.instance.revealInFinder(path),
                      onDelete: () => _removeFile(id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({
    required this.name,
    required this.path,
    required this.icon,
    required this.onReveal,
    required this.onDelete,
  });

  final String name;
  final String path;
  final IconData icon;
  final VoidCallback onReveal;
  final VoidCallback onDelete;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: _hovered ? Colors.white.withOpacity(0.03) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFEC4899).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(widget.icon, size: 18, color: const Color(0xFFEC4899)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.path,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (_hovered) ...[
              IconButton(
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                tooltip: 'Reveal in Finder',
                onPressed: widget.onReveal,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: const Color(0xFF94A3B8),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Remove',
                onPressed: widget.onDelete,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: Colors.redAccent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
