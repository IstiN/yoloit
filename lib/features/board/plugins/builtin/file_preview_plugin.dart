import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class FilePreviewPlugin extends BoardPanelPlugin {
  const FilePreviewPlugin();

  static const String kTypeId = 'board.file.preview';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'File Preview';

  @override
  IconData get icon => Icons.image_outlined;

  @override
  Color get accentColor => const Color(0xFF8B5CF6);

  @override
  Size get defaultSize => const Size(460, 380);

  @override
  Map<String, dynamic> get initialState => {'path': '', 'title': ''};

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _FilePreviewContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

bool _isImageExt(String ext) {
  return const {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'}
      .contains(ext.toLowerCase());
}

bool _isSvgExt(String ext) => ext.toLowerCase() == 'svg';

class _FilePreviewContent extends StatefulWidget {
  const _FilePreviewContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_FilePreviewContent> createState() => _FilePreviewContentState();
}

class _FilePreviewContentState extends State<_FilePreviewContent> {
  static const Color _accent = Color(0xFF8B5CF6);

  String get _path => widget.panel.state['path'] as String? ?? '';

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'path': file.path!,
      'title': file.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;

    if (path.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 48, color: _accent.withOpacity(0.4)),
            const SizedBox(height: 12),
            const Text(
              'No file selected',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('Pick File'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      );
    }

    final ext = path.contains('.') ? path.split('.').last : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          path: path,
          onOpen: () => PlatformLauncher.instance.revealInFinder(path),
          onChange: _pickFile,
        ),
        const Divider(height: 1, thickness: 0.5),
        Expanded(child: _buildPreview(path, ext)),
      ],
    );
  }

  Widget _buildPreview(String path, String ext) {
    if (_isSvgExt(ext)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SvgPicture.file(File(path), fit: BoxFit.contain),
      );
    }
    if (_isImageExt(ext)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Image.file(File(path), fit: BoxFit.contain),
      );
    }

    // Other file types
    final fileName = path.split(Platform.pathSeparator).last;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.insert_drive_file_outlined, size: 48, color: _accent),
          ),
          const SizedBox(height: 12),
          Text(
            fileName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE2E8F0),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => PlatformLauncher.instance.openUrl(path),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in Editor'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.path,
    required this.onOpen,
    required this.onChange,
  });

  final String path;
  final VoidCallback onOpen;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final fileName = path.split(Platform.pathSeparator).last;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              fileName,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open_outlined, size: 14),
            label: const Text('Open', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
          ),
          TextButton.icon(
            onPressed: onChange,
            icon: const Icon(Icons.swap_horiz, size: 14),
            label: const Text('Change', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF94A3B8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
          ),
        ],
      ),
    );
  }
}
