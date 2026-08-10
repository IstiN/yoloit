import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/files_plugin_base.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/ui/widgets/hover_listener.dart';

class FilesPlugin extends FilesPluginBase {
  const FilesPlugin();

  /// Test-only hook replacing the platform file picker, which cannot run
  /// inside widget tests.
  @visibleForTesting
  static Future<List<BoardFileSelection>?> Function(BuildContext context)?
  debugPickFiles;

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
  'dart' ||
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
  'zip' || 'tar' || 'gz' || 'rar' || '7z' => Icons.folder_zip_outlined,
  '' => Icons.folder_outlined,
  _ => Icons.insert_drive_file_outlined,
};

bool _isPreviewable(String ext) => const {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'webp',
  'svg',
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  'm4v',
  'mp3',
  'wav',
  'flac',
  'aac',
  'm4a',
  'ogg',
}.contains(ext.toLowerCase());

class _FilesContent extends StatefulWidget {
  const _FilesContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_FilesContent> createState() => _FilesContentState();
}

class _FilesContentState extends State<_FilesContent> {
  List<Map<String, dynamic>> get _files =>
      (widget.panel.state['files'] as List?)
          ?.whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  void _save(List<Map<String, dynamic>> files) {
    widget.renderContext.onUpdateState({...widget.panel.state, 'files': files});
  }

  Future<void> _addFiles() async {
    final picker = FilesPlugin.debugPickFiles;
    final result = await (picker?.call(context) ??
        BoardFilePicker.pickFiles(
          context,
          remoteInfo: widget.renderContext.remoteInfo,
          title: 'Add files',
        ));
    if (result == null || result.isEmpty) return;

    final current = _files;
    final existingPaths = current.map((f) => f['path'] as String?).toSet();

    final newEntries =
        result
            .where((f) => !existingPaths.contains(f.path))
            .map(
              (f) => {
                'id': DateTime.now().millisecondsSinceEpoch.toString() + f.name,
                'path': f.path,
                'name': f.name,
                'addedAt': DateTime.now().toIso8601String(),
              },
            )
            .toList();

    if (newEntries.isEmpty) return;
    _save([...current, ...newEntries]);
  }

  void _removeFile(String id) {
    _save(_files.where((f) => f['id'] != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addFiles,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Files', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // Files list
        Expanded(
          child:
              files.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.attach_file,
                          size: 40,
                          color: colors.primary.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No files added yet',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: files.length,
                    separatorBuilder:
                        (context, index) => const Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 52,
                        ),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final id = file['id'] as String;
                      final name = file['name'] as String? ?? '';
                      final path = file['path'] as String? ?? '';
                      final ext =
                          name.contains('.') ? name.split('.').last : '';

                      return _FileTile(
                        name: name,
                        path: path,
                        icon: _iconForExtension(ext),
                        onReveal:
                            () =>
                                PlatformLauncher.instance.revealInFinder(path),
                        onDelete: () => _removeFile(id),
                        onOpenAsPanel:
                            _isPreviewable(ext)
                                ? () async {
                                  await widget.renderContext.onCreateLinkedPanel
                                      ?.call('board.file.preview', {
                                        'path': file['path'] as String,
                                        'title': file['name'] as String,
                                      }, file['name'] as String);
                                }
                                : null,
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
    this.onOpenAsPanel,
  });

  final String name;
  final String path;
  final IconData icon;
  final VoidCallback onReveal;
  final VoidCallback onDelete;
  final VoidCallback? onOpenAsPanel;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return HoverListener(
      builder: (context, hovered) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color:
              hovered
                  ? colors.textPrimary.withValues(alpha: 0.03)
                  : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(widget.icon, size: 18, color: colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.path,
                      style: TextStyle(fontSize: 10, color: colors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (hovered) ...[
                if (widget.onOpenAsPanel != null)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    tooltip: 'Open as preview panel',
                    onPressed: widget.onOpenAsPanel,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    color: colors.primaryLight,
                  ),
                IconButton(
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  tooltip: 'Reveal in Finder',
                  onPressed: widget.onReveal,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: colors.textMuted,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: 'Remove',
                  onPressed: widget.onDelete,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: colors.accentRed,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
