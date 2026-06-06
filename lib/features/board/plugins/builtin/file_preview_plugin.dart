import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/ui/file_editor_panel.dart';
import 'package:yoloit/features/editor/utils/editor_language_registry.dart';
import 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

final _filePreviewDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

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
  Color get accentColor => _filePreviewDefaultColors.primary;

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
  return const {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'bmp',
    'webp',
  }.contains(ext.toLowerCase());
}

bool _isSvgExt(String ext) => ext.toLowerCase() == 'svg';

bool _isPdfExt(String ext) => ext.toLowerCase() == 'pdf';

bool _isVideoExt(String ext) {
  return const {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'wmv',
    'flv',
  }.contains(ext.toLowerCase());
}

bool _isAudioExt(String ext) {
  return const {
    'mp3',
    'aac',
    'wav',
    'ogg',
    'flac',
    'm4a',
    'opus',
    'wma',
  }.contains(ext.toLowerCase());
}

bool _isMarkdownExt(String ext) =>
    const {'md', 'markdown'}.contains(ext.toLowerCase());

bool _isTextExt(String ext) {
  return const {
    'txt',
    'log',
    'csv',
    'tsv',
    'ini',
    'cfg',
    'conf',
    'env',
    'dart',
    'py',
    'js',
    'ts',
    'jsx',
    'tsx',
    'java',
    'kt',
    'swift',
    'go',
    'rs',
    'c',
    'cpp',
    'h',
    'hpp',
    'cs',
    'rb',
    'php',
    'sh',
    'bash',
    'zsh',
    'fish',
    'ps1',
    'bat',
    'cmd',
    'json',
    'yaml',
    'yml',
    'xml',
    'toml',
    'html',
    'css',
    'scss',
    'less',
    'sql',
    'graphql',
    'proto',
    'makefile',
    'dockerfile',
    'gitignore',
    'editorconfig',
    'properties',
    'gradle',
    'lock',
    'mjs',
    'cjs',
    'vue',
    'svelte',
    'astro',
  }.contains(ext.toLowerCase());
}

bool _isDotEnvPath(String path) {
  final name = p.basename(path).toLowerCase();
  return name == '.env' ||
      name.startsWith('.env.') ||
      p.extension(name) == '.env';
}

class _FilePreviewContent extends StatefulWidget {
  const _FilePreviewContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_FilePreviewContent> createState() => _FilePreviewContentState();
}

class _FilePreviewContentState extends State<_FilePreviewContent> {
  String get _path => widget.panel.state['path'] as String? ?? '';

  StreamSubscription<BoardFileModifiedEvent>? _fileSub;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _fileSub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(
      _onFileModified,
    );
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    super.dispose();
  }

  void _onFileModified(BoardFileModifiedEvent event) {
    if (!mounted) return;
    final p = _path;
    if (p.isNotEmpty && p == event.path) {
      setState(() => _refreshKey++);
    }
  }

  Future<void> _pickFile() async {
    final file = await BoardFilePicker.pickFile(
      context,
      remoteInfo: widget.renderContext.remoteInfo,
      initialPath: _path.isEmpty ? null : p.dirname(_path),
      title: 'Select file',
    );
    if (file == null) return;
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'path': file.path,
      'title': file.name,
    });
  }

  Future<void> _editFile(String path) async {
    await showDialog<void>(
      context: context,
      barrierColor: context.appColors.background.withValues(alpha: 0.72),
      builder: (_) => _FilePreviewEditorDialog(path: path),
    );
  }

  void _openAsWebPage(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final fileUrl = Uri.file(path).toString();
    widget.renderContext.onCreateLinkedPanel?.call('board.webpage', {
      'url': fileUrl,
      'title': fileName,
    }, fileName);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final path = _path;

    if (path.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.perm_media_outlined,
              size: 48,
              color: colors.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No file selected',
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('Pick File'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final ext = path.contains('.') ? path.split('.').last : '';
    final canEdit = _isEditableFile(path, ext);

    final lowerExt = ext.toLowerCase();
    final isHtml = const {'html', 'htm'}.contains(lowerExt);
    final isPdf = _isPdfExt(lowerExt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          path: path,
          onEdit: canEdit ? () => _editFile(path) : null,
          onOpen: () => PlatformLauncher.instance.revealInFinder(path),
          onChange: _pickFile,
          onOpenAsWebPage:
              (isHtml || isPdf) ? () => _openAsWebPage(path) : null,
        ),
        const Divider(height: 1, thickness: 0.5),
        Expanded(child: _buildPreview(path, ext)),
      ],
    );
  }

  Widget _buildPreview(String path, String ext) {
    final colors = context.appColors;
    // For binary/media types, _refreshKey forces full recreation on file change.
    // Text/markdown previews are stateful and subscribe to BoardEventBus
    // themselves, so they reload content while preserving scroll position.
    final mediaKey = ValueKey('$path:$_refreshKey');
    if (_isSvgExt(ext)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: _SvgFilePreview(
          key: mediaKey,
          path: path,
          headless: widget.renderContext.isHeadlessPreview,
        ),
      );
    }
    if (_isImageExt(ext)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: _RasterImagePreview(
          key: mediaKey,
          path: path,
          onChange: _pickFile,
        ),
      );
    }
    if (_isVideoExt(ext)) {
      return _VideoPreview(key: mediaKey, path: path);
    }
    if (_isAudioExt(ext)) {
      return _AudioPreview(key: mediaKey, path: path);
    }
    if (_isPdfExt(ext)) {
      return _PdfPreview(
        path: path,
        onOpenAsWebPage: () => _openAsWebPage(path),
      );
    }
    if (_isMarkdownExt(ext)) {
      // No key change — stateful widget handles its own reload + scroll preservation.
      return _MarkdownPreview(key: ValueKey(path), path: path);
    }
    if (_isDotEnvPath(path) || _isTextExt(ext) || _looksLikeTextFile(path)) {
      return _CodePreview(key: ValueKey(path), path: path);
    }

    // Other file types (binary, etc.)
    final fileName = path.split(Platform.pathSeparator).last;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.insert_drive_file_outlined,
              size: 48,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Builder(
            builder:
                (ctx) => Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => PlatformLauncher.instance.openUrl(path),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in Editor'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  bool _isEditableFile(String path, String ext) {
    if (_isDotEnvPath(path)) return true;
    if (_isMarkdownExt(ext) || _isTextExt(ext)) return true;
    if (_isSvgExt(ext)) return true;
    return _looksLikeTextFile(path);
  }

  /// Heuristic: files without extension or with unknown extension — try reading
  /// first bytes to check if it's text.
  bool _looksLikeTextFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      final len = file.lengthSync();
      if (len > 2 * 1024 * 1024) return false; // Skip files > 2MB
      // Check for known no-extension text files
      final name = path.split(Platform.pathSeparator).last.toLowerCase();
      if (const {
        'makefile',
        'dockerfile',
        'jenkinsfile',
        'vagrantfile',
        'procfile',
        'gemfile',
        'rakefile',
        'license',
        'readme',
        'changelog',
        'authors',
        'contributors',
        'todo',
      }.contains(name)) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

class _RasterImagePreview extends StatefulWidget {
  const _RasterImagePreview({super.key, required this.path, this.onChange});

  final String path;
  final VoidCallback? onChange;

  @override
  State<_RasterImagePreview> createState() => _RasterImagePreviewState();
}

class _RasterImagePreviewState extends State<_RasterImagePreview> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(notify: false);
  }

  @override
  void didUpdateWidget(_RasterImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _load();
    }
  }

  void _load({bool notify = true}) {
    Uint8List? nextBytes;
    Object? nextError;
    try {
      final file = File(widget.path);
      if (!file.existsSync()) {
        nextError = 'File not found';
      } else {
        nextBytes = file.readAsBytesSync();
      }
    } catch (error) {
      nextError = error;
    }

    void apply() {
      _bytes = nextBytes;
      _error = nextError;
    }

    if (notify && mounted) {
      setState(() {
        apply();
      });
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return RepaintBoundary(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder:
              (context, error, stackTrace) => _FilePreviewError(
                title: 'Cannot decode image',
                details: error.toString(),
                path: widget.path,
                actionLabel: 'Change file',
                onAction: widget.onChange,
              ),
        ),
      );
    }

    return _FilePreviewError(
      title: _error?.toString() ?? 'Cannot load image',
      path: widget.path,
      actionLabel: 'Change file',
      onAction: widget.onChange,
    );
  }
}

class _FilePreviewError extends StatelessWidget {
  const _FilePreviewError({
    required this.title,
    required this.path,
    this.details,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String path;
  final String? details;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 42,
              color: colors.textMuted.withValues(alpha: 0.78),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              path,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (details != null && details!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Caption(details!, fontSize: 10, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.folder_open_outlined, size: 15),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SvgFilePreview extends StatefulWidget {
  const _SvgFilePreview({
    super.key,
    required this.path,
    required this.headless,
  });

  final String path;
  final bool headless;

  @override
  State<_SvgFilePreview> createState() => _SvgFilePreviewState();
}

class _SvgFilePreviewState extends State<_SvgFilePreview> {
  String? _svg;
  Object? _error;
  late String _taskKey;

  @override
  void initState() {
    super.initState();
    _taskKey = _headlessTaskKey();
    if (widget.headless) {
      HeadlessRenderRegistry.activeTasks.add(_taskKey);
    }
    _loadSvg();
  }

  @override
  void didUpdateWidget(_SvgFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.headless != widget.headless) {
      if (oldWidget.headless) {
        HeadlessRenderRegistry.activeTasks.remove(_taskKey);
      }
      _taskKey = _headlessTaskKey();
      if (widget.headless) {
        HeadlessRenderRegistry.activeTasks.add(_taskKey);
      }
      _loadSvg();
    }
  }

  @override
  void dispose() {
    HeadlessRenderRegistry.activeTasks.remove(_taskKey);
    super.dispose();
  }

  String _headlessTaskKey() =>
      'file_preview_svg:${widget.path.hashCode}:$hashCode';

  void _loadSvg() {
    try {
      final file = File(widget.path);
      _svg = file.existsSync() ? file.readAsStringSync() : null;
      _error = _svg == null ? 'File not found' : null;
    } catch (error) {
      _svg = null;
      _error = error;
    } finally {
      if (widget.headless) {
        scheduleMicrotask(() {
          HeadlessRenderRegistry.activeTasks.remove(_taskKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final svg = _svg;
    if (svg != null && svg.trim().isNotEmpty) {
      return SvgPicture.string(svg, fit: BoxFit.contain);
    }

    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 42,
        color: context.appColors.textMuted.withValues(alpha: 0.72),
        semanticLabel: _error?.toString(),
      ),
    );
  }
}

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({required this.path, required this.onOpenAsWebPage});

  final String path;
  final VoidCallback onOpenAsWebPage;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fileName = path.split(Platform.pathSeparator).last;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          color: colors.surfaceElevated,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 54,
                  color: colors.accentRed,
                ),
                const SizedBox(height: 12),
                Text(
                  fileName,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'PDF preview is available through a linked Web panel or the system PDF viewer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onOpenAsWebPage,
                      icon: const Icon(Icons.preview_outlined, size: 16),
                      label: const Text('Preview PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => PlatformLauncher.instance.openUrl(path),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Markdown Preview ─────────────────────────────────────────────────────────

// ─── Markdown Preview with Mermaid support ────────────────────────────────────

class _MarkdownPreview extends StatefulWidget {
  const _MarkdownPreview({super.key, required this.path});
  final String path;

  @override
  State<_MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<_MarkdownPreview> {
  late String _content;
  StreamSubscription<BoardFileModifiedEvent>? _fileSub;

  @override
  void initState() {
    super.initState();
    _content = _readFile();
    _fileSub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(
      _onFileModified,
    );
  }

  @override
  void didUpdateWidget(_MarkdownPreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _content = _readFile();
    }
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    super.dispose();
  }

  String _readFile() {
    try {
      final file = File(widget.path);
      return file.existsSync() ? file.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  void _onFileModified(BoardFileModifiedEvent event) {
    if (!mounted || event.path != widget.path) return;
    // Re-read file but let MarkdownDocumentPreview preserve its own scroll.
    setState(() => _content = _readFile());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_content.isEmpty) {
      return Center(
        child: Text(
          'File not found',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }
    return RepaintBoundary(child: MarkdownDocumentPreview(content: _content));
  }
}


// ─── Code / Text Preview ──────────────────────────────────────────────────────

class _CodePreview extends StatefulWidget {
  const _CodePreview({super.key, required this.path});
  final String path;

  @override
  State<_CodePreview> createState() => _CodePreviewState();
}

class _CodePreviewState extends State<_CodePreview> {
  static const int _kMaxPreviewLines = 5000;
  static const int _kMaxLineLength = 2000;
  static const int _kMaxPreviewBytes = 2 * 1024 * 1024;

  late List<String> _lines;
  late String _extension;
  late String _languageId;
  final _scrollCtrl = ScrollController();
  StreamSubscription<BoardFileModifiedEvent>? _fileSub;
  Timer? _fileChangeDebounce;
  bool _wasTruncated = false;
  String _truncateInfo = '';

  @override
  void initState() {
    super.initState();
    _extension = p.extension(widget.path).replaceFirst('.', '').toLowerCase();
    _languageId = EditorLanguageRegistry.forPath(widget.path).id;
    final result = _readLines();
    _lines = result.lines;
    _wasTruncated = result.wasTruncated;
    _truncateInfo = result.info;
    _fileSub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(
      _onFileModified,
    );
  }

  @override
  void didUpdateWidget(_CodePreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _extension = p.extension(widget.path).replaceFirst('.', '').toLowerCase();
      _languageId = EditorLanguageRegistry.forPath(widget.path).id;
      final result = _readLines();
      _lines = result.lines;
      _wasTruncated = result.wasTruncated;
      _truncateInfo = result.info;
    }
  }

  @override
  void dispose() {
    _fileChangeDebounce?.cancel();
    _fileSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  _ReadResult _readLines() {
    try {
      final file = File(widget.path);
      if (!file.existsSync()) return _ReadResult([]);

      final size = file.lengthSync();
      if (size == 0) return _ReadResult([]);

      String raw;
      bool truncated = false;
      String info = '';

      if (size > _kMaxPreviewBytes) {
        final bytes = file.readAsBytesSync().sublist(0, _kMaxPreviewBytes);
        raw = utf8.decode(bytes, allowMalformed: true);
        truncated = true;
        info =
            'Showing first ${(_kMaxPreviewBytes / 1024 / 1024).toStringAsFixed(1)} MB of ${(size / 1024 / 1024).toStringAsFixed(1)} MB. Open in editor for full file.';
      } else {
        raw = file.readAsStringSync();
      }

      var lines = raw.split('\n');
      final totalLines = lines.length;

      // Limit line count.
      if (lines.length > _kMaxPreviewLines) {
        lines = lines.sublist(0, _kMaxPreviewLines);
        truncated = true;
        info =
            'Showing first $_kMaxPreviewLines of $totalLines lines. Open in editor for full file.';
      }

      // Limit line length.
      var longLinesTruncated = false;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].length > _kMaxLineLength) {
          lines[i] = '${lines[i].substring(0, _kMaxLineLength)}…';
          longLinesTruncated = true;
        }
      }
      if (longLinesTruncated && info.isEmpty) {
        info =
            'Long lines truncated to $_kMaxLineLength chars. Open in editor for full file.';
      }

      return _ReadResult(lines, wasTruncated: truncated, info: info);
    } catch (_) {
      return _ReadResult([]);
    }
  }

  void _onFileModified(BoardFileModifiedEvent event) {
    if (!mounted || event.path != widget.path) return;
    _fileChangeDebounce?.cancel();
    _fileChangeDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
      final result = _readLines();
      setState(() {
        _lines = result.lines;
        _wasTruncated = result.wasTruncated;
        _truncateInfo = result.info;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final max = _scrollCtrl.position.maxScrollExtent;
        _scrollCtrl.jumpTo(offset.clamp(0.0, max));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return const Center(child: Text('File not found'));
    }
    final colors = context.appColors;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final lineNumColor = textColor.withValues(alpha: 0.35);

    // Use plain Text.rich for large files — SelectableText is very expensive
    // when there are thousands of lines because it sets up selection handles
    // and gesture detectors for every widget.
    final useSelectable = _lines.length <= 1000;

    Widget lineWidget(int i) {
      final span = TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: colors.terminalPrompt,
          height: 1.5,
        ),
        children: filePreviewCodeSyntaxSpans(
          _lines[i],
          extension: _extension,
          languageId: _languageId,
          colors: colors,
        ),
      );
      if (useSelectable) {
        return SelectableText.rich(span);
      }
      return Text.rich(span);
    }

    final listBody = ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _lines.length,
      itemBuilder: (_, i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: lineNumColor,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: lineWidget(i)),
            ],
          ),
        );
      },
    );

    if (!_wasTruncated) return Container(color: colors.terminalBackground, child: listBody);

    return Container(
      color: colors.terminalBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.accentOrange.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: colors.accentOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _truncateInfo,
                    style: TextStyle(fontSize: 11, color: colors.accentOrange),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: listBody),
        ],
      ),
    );
  }
}

class _ReadResult {
  _ReadResult(this.lines, {this.wasTruncated = false, this.info = ''});
  final List<String> lines;
  final bool wasTruncated;
  final String info;
}

@visibleForTesting
List<TextSpan> filePreviewCodeSyntaxSpans(
  String line, {
  required String extension,
  required AppColorScheme colors,
  String? languageId,
}) {
  final language = languageId ?? _languageIdForExtension(extension);
  return switch (language) {
    'json' => _jsonSyntaxSpans(line, colors),
    'xml' => _xmlSyntaxSpans(line, colors),
    'dotenv' => _dotenvSyntaxSpans(line, colors),
    _ => [TextSpan(text: line)],
  };
}

String _languageIdForExtension(String extension) {
  final ext = extension.toLowerCase();
  if (ext == 'env') return 'dotenv';
  if (ext == 'json' || ext == 'jsonc') return 'json';
  if (const {'html', 'htm', 'xml', 'svg'}.contains(ext)) return 'xml';
  return ext;
}

List<TextSpan> _jsonSyntaxSpans(String line, AppColorScheme colors) {
  final spans = <TextSpan>[];
  final tokenRe = RegExp(
    r'"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false|null)\b|[{}\[\]:,]',
  );
  var cursor = 0;
  for (final match in tokenRe.allMatches(line)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: line.substring(cursor, match.start)));
    }
    final token = match.group(0)!;
    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(color: _jsonTokenColor(token, line, match, colors)),
      ),
    );
    cursor = match.end;
  }
  if (cursor < line.length) {
    spans.add(TextSpan(text: line.substring(cursor)));
  }
  return spans.isEmpty ? [TextSpan(text: line)] : spans;
}

Color _jsonTokenColor(
  String token,
  String line,
  RegExpMatch match,
  AppColorScheme colors,
) {
  if (token.startsWith('"')) {
    final rest = line.substring(match.end).trimLeft();
    return rest.startsWith(':') ? colors.primaryLight : colors.accentGreen;
  }
  if (token == 'true' || token == 'false') return colors.accentBlue;
  if (token == 'null') return colors.textMuted;
  if (RegExp(r'^-?\d').hasMatch(token)) return colors.accentOrange;
  return colors.textMuted;
}

List<TextSpan> _xmlSyntaxSpans(String line, AppColorScheme colors) {
  final spans = <TextSpan>[];
  final tokenRe = RegExp(
    r"""<!--.*?-->|</?[A-Za-z_][\w:.-]*|[A-Za-z_:][\w:.-]*(?=\s*=)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[</>=]""",
  );
  var cursor = 0;
  for (final match in tokenRe.allMatches(line)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: line.substring(cursor, match.start)));
    }
    final token = match.group(0)!;
    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(color: _xmlTokenColor(token, colors)),
      ),
    );
    cursor = match.end;
  }
  if (cursor < line.length) {
    spans.add(TextSpan(text: line.substring(cursor)));
  }
  return spans.isEmpty ? [TextSpan(text: line)] : spans;
}

Color _xmlTokenColor(String token, AppColorScheme colors) {
  if (token.startsWith('<!--')) return colors.textMuted;
  if (token.startsWith('<')) return colors.accentBlue;
  if (token.startsWith('"') || token.startsWith("'")) return colors.accentGreen;
  if (token == '=' || token == '>' || token == '/' || token == '<') {
    return colors.textMuted;
  }
  return colors.accentOrange;
}

List<TextSpan> _dotenvSyntaxSpans(String line, AppColorScheme colors) {
  if (line.trimLeft().startsWith('#')) {
    return [TextSpan(text: line, style: TextStyle(color: colors.textMuted))];
  }

  final match = RegExp(
    r'^(\s*)(export\s+)?([A-Za-z_][A-Za-z0-9_]*)(\s*=\s*)(.*)$',
  ).firstMatch(line);
  if (match == null) return [TextSpan(text: line)];

  return [
    TextSpan(text: match.group(1)),
    if (match.group(2) != null)
      TextSpan(
        text: match.group(2),
        style: TextStyle(color: colors.accentOrange),
      ),
    TextSpan(
      text: match.group(3),
      style: TextStyle(color: colors.primaryLight),
    ),
    TextSpan(text: match.group(4), style: TextStyle(color: colors.textMuted)),
    ..._dotenvValueSpans(match.group(5) ?? '', colors),
  ];
}

List<TextSpan> _dotenvValueSpans(String value, AppColorScheme colors) {
  final commentStart = _dotenvInlineCommentStart(value);
  final rawValue =
      commentStart == -1 ? value : value.substring(0, commentStart);
  final comment = commentStart == -1 ? '' : value.substring(commentStart);
  return [
    TextSpan(text: rawValue, style: TextStyle(color: colors.accentGreen)),
    if (comment.isNotEmpty)
      TextSpan(text: comment, style: TextStyle(color: colors.textMuted)),
  ];
}

int _dotenvInlineCommentStart(String value) {
  var quoted = false;
  String? quote;
  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    if ((ch == '"' || ch == "'") && (i == 0 || value[i - 1] != '\\')) {
      if (!quoted) {
        quoted = true;
        quote = ch;
      } else if (quote == ch) {
        quoted = false;
        quote = null;
      }
      continue;
    }
    if (!quoted && ch == '#' && (i == 0 || value[i - 1].trim().isEmpty)) {
      return i;
    }
  }
  return -1;
}

// ─── Video Player ─────────────────────────────────────────────────────────────

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({super.key, required this.path});
  final String path;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.path), play: false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ColoredBox(
      color: colors.background,
      child: Video(controller: _controller, controls: AdaptiveVideoControls),
    );
  }
}

// ─── Audio Player ─────────────────────────────────────────────────────────────

class _AudioPreview extends StatefulWidget {
  const _AudioPreview({super.key, required this.path});
  final String path;

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  late final Player _player;
  Duration _total = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _subs.add(
      _player.stream.playing.listen((v) {
        if (mounted) setState(() => _isPlaying = v);
      }),
    );
    _subs.add(
      _player.stream.position.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((d) {
        if (mounted) setState(() => _total = d);
      }),
    );
    _player.open(Media(widget.path), play: false);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isPlaying = _isPlaying;
    final fileName = widget.path.split(Platform.pathSeparator).last;
    final progress =
        _total.inMilliseconds > 0
            ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Album art placeholder
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 48,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),

          // File name
          Text(
            fileName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // Progress bar
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.border,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.15),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: progress,
              onChanged: (v) {
                final target = Duration(
                  milliseconds: (v * _total.inMilliseconds).round(),
                );
                _player.seek(target);
              },
            ),
          ),

          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(_position),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appColors.textMuted,
                  ),
                ),
                Text(
                  _fmt(_total),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind 10s
              IconButton(
                icon: const Icon(Icons.replay_10_rounded),
                iconSize: 28,
                color: Theme.of(context).colorScheme.onSurface,
                onPressed:
                    () => _player.seek(
                      Duration(
                        milliseconds: (_position.inMilliseconds - 10000).clamp(
                          0,
                          _total.inMilliseconds,
                        ),
                      ),
                    ),
              ),
              const SizedBox(width: 8),
              // Play/Pause
              GestureDetector(
                onTap: () {
                  if (isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: colors.textPrimary,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Forward 10s
              IconButton(
                icon: const Icon(Icons.forward_10_rounded),
                iconSize: 28,
                color: Theme.of(context).colorScheme.onSurface,
                onPressed:
                    () => _player.seek(
                      Duration(
                        milliseconds: (_position.inMilliseconds + 10000).clamp(
                          0,
                          _total.inMilliseconds,
                        ),
                      ),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Toolbar ──────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.path,
    required this.onEdit,
    required this.onOpen,
    required this.onChange,
    this.onOpenAsWebPage,
  });

  final String path;
  final VoidCallback? onEdit;
  final VoidCallback onOpen;
  final VoidCallback onChange;
  final VoidCallback? onOpenAsWebPage;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fileName = path.split(Platform.pathSeparator).last;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              fileName,
              style: TextStyle(
                fontSize: 11,
                color: context.appColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const Spacer(),
          if (onEdit != null)
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Edit', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
            ),
          if (onOpenAsWebPage != null)
            TextButton.icon(
              onPressed: onOpenAsWebPage,
              icon: const Icon(Icons.language_outlined, size: 14),
              label: const Text('Web', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: colors.accentBlue,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
            ),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open_outlined, size: 14),
            label: const Text('Open', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
          ),
          TextButton.icon(
            onPressed: onChange,
            icon: const Icon(Icons.swap_horiz, size: 14),
            label: const Text('Change', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: colors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePreviewEditorDialog extends StatefulWidget {
  const _FilePreviewEditorDialog({required this.path});

  final String path;

  @override
  State<_FilePreviewEditorDialog> createState() =>
      _FilePreviewEditorDialogState();
}

class _FilePreviewEditorDialogState extends State<_FilePreviewEditorDialog> {
  late final FileEditorCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FileEditorCubit();
    unawaited(_cubit.openFile(widget.path));
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    final fileName = widget.path.split(Platform.pathSeparator).last;
    return BlocProvider<FileEditorCubit>.value(
      value: _cubit,
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: colors.surfaceElevated,
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width - 40, 1480),
          height: MediaQuery.sizeOf(context).height * 0.9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _cubit.saveFile(),
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Save'),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Expanded(child: FileEditorPanel(hideTabBar: true)),
            ],
          ),
        ),
      ),
    );
  }
}
