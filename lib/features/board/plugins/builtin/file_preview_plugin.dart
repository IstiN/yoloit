import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/ui/file_editor_panel.dart';
import 'package:yoloit/features/preview/widgets/markdown_document_preview.dart';

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

  StreamSubscription<BoardFileModifiedEvent>? _fileSub;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _fileSub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(_onFileModified);
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

  Future<void> _editFile(String path) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _FilePreviewEditorDialog(path: path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;

    if (path.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.perm_media_outlined,
              size: 48,
              color: _accent.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No file selected',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('Pick File'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          path: path,
          onEdit: canEdit ? () => _editFile(path) : null,
          onOpen: () => PlatformLauncher.instance.revealInFinder(path),
          onChange: _pickFile,
        ),
        const Divider(height: 1, thickness: 0.5),
        Expanded(child: _buildPreview(path, ext)),
      ],
    );
  }

  Widget _buildPreview(String path, String ext) {
    // For binary/media types, _refreshKey forces full recreation on file change.
    // Text/markdown previews are stateful and subscribe to BoardEventBus
    // themselves, so they reload content while preserving scroll position.
    final mediaKey = ValueKey('$path:$_refreshKey');
    if (_isSvgExt(ext)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SvgPicture.file(File(path), key: mediaKey, fit: BoxFit.contain),
      );
    }
    if (_isImageExt(ext)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Image.file(File(path), key: mediaKey, fit: BoxFit.contain),
      );
    }
    if (_isVideoExt(ext)) {
      return _VideoPreview(key: mediaKey, path: path);
    }
    if (_isAudioExt(ext)) {
      return _AudioPreview(key: mediaKey, path: path);
    }
    if (_isMarkdownExt(ext)) {
      // No key change — stateful widget handles its own reload + scroll preservation.
      return _MarkdownPreview(key: ValueKey(path), path: path);
    }
    if (_isTextExt(ext) || _looksLikeTextFile(path)) {
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
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.insert_drive_file_outlined,
              size: 48,
              color: _accent,
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
              backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  bool _isEditableFile(String path, String ext) {
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
    _fileSub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(_onFileModified);
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
    if (_content.isEmpty) {
      return const Center(child: Text('File not found'));
    }
    return MarkdownDocumentPreview(content: _content);
  }
}

class _MermaidThemeOptions {
  const _MermaidThemeOptions({
    required this.renderOptions,
    required this.cacheToken,
    required this.canvasColor,
    required this.scrimColor,
  });

  final MermaidRenderOptions renderOptions;
  final String cacheToken;
  final Color canvasColor;
  final Color scrimColor;
}

_MermaidThemeOptions _buildMermaidThemeOptions(
  BuildContext context,
  AppColorScheme colors,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final onSurface = theme.colorScheme.onSurface;
  final canvasColor =
      isDark
          ? Color.lerp(colors.background, colors.surface, 0.55)!
          : Color.lerp(Colors.white, colors.background, 0.45)!;
  final clusterFill =
      isDark
          ? Color.lerp(colors.surfaceElevated, colors.primary, 0.18)!
          : Color.lerp(colors.surfaceElevated, colors.primary, 0.10)!;
  final nodeFill =
      isDark
          ? Color.lerp(clusterFill, Colors.white, 0.07)!
          : Color.lerp(Colors.white, colors.primary, 0.08)!;
  final secondaryFill =
      isDark
          ? Color.lerp(nodeFill, colors.primaryLight, 0.10)!
          : Color.lerp(nodeFill, colors.primary, 0.06)!;
  final tertiaryFill =
      isDark
          ? Color.lerp(clusterFill, colors.surfaceHighlight, 0.45)!
          : Color.lerp(colors.surfaceHighlight, Colors.white, 0.18)!;
  final noteFill =
      isDark
          ? Color.lerp(nodeFill, colors.primary, 0.12)!
          : Color.lerp(Colors.white, colors.primary, 0.14)!;
  final borderColor =
      isDark
          ? Color.lerp(colors.border, colors.primaryLight, 0.42)!
          : Color.lerp(colors.border, colors.primaryDark, 0.16)!;
  final lineColor =
      Color.lerp(onSurface, colors.primary, isDark ? 0.48 : 0.24)!;
  final edgeLabelBackground =
      isDark
          ? Color.lerp(canvasColor, Colors.black, 0.16)!
          : Color.lerp(canvasColor, Colors.white, 0.78)!;
  final backgroundHex = _hexColor(canvasColor);
  final textHex = _hexColor(onSurface);
  final borderHex = _hexColor(borderColor);
  final lineHex = _hexColor(lineColor);
  final renderOptions = MermaidRenderOptions(
    backgroundColor: backgroundHex,
    config: <String, Object?>{
      'theme': 'base',
      'darkMode': isDark,
      'themeVariables': <String, Object?>{
        'background': backgroundHex,
        'textColor': textHex,
        'lineColor': lineHex,
        'mainBkg': _hexColor(nodeFill),
        'secondBkg': _hexColor(clusterFill),
        'tertiaryBkg': _hexColor(tertiaryFill),
        'primaryColor': _hexColor(nodeFill),
        'primaryBorderColor': borderHex,
        'primaryTextColor': textHex,
        'secondaryColor': _hexColor(secondaryFill),
        'secondaryBorderColor': borderHex,
        'secondaryTextColor': textHex,
        'tertiaryColor': _hexColor(tertiaryFill),
        'tertiaryBorderColor': borderHex,
        'tertiaryTextColor': textHex,
        'clusterBkg': _hexColor(clusterFill),
        'clusterBorder': borderHex,
        'nodeBorder': borderHex,
        'edgeLabelBackground': _hexColor(edgeLabelBackground),
        'labelBoxBkgColor': _hexColor(edgeLabelBackground),
        'labelTextColor': textHex,
        'actorBkg': _hexColor(nodeFill),
        'actorBorder': borderHex,
        'actorTextColor': textHex,
        'activationBorderColor': _hexColor(colors.primary),
        'activationBkgColor': _hexColor(secondaryFill),
        'sequenceNumberColor': textHex,
        'signalColor': lineHex,
        'signalTextColor': textHex,
        'noteBkgColor': _hexColor(noteFill),
        'noteBorderColor': borderHex,
        'noteTextColor': textHex,
      },
    },
  );
  return _MermaidThemeOptions(
    renderOptions: renderOptions,
    cacheToken:
        '${isDark ? 'dark' : 'light'}:${_hexColor(colors.primary)}:$backgroundHex:$textHex',
    canvasColor: canvasColor,
    scrimColor: canvasColor.withValues(alpha: isDark ? 0.62 : 0.52),
  );
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0x00FFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Custom markdown builder that intercepts ```mermaid code blocks and renders
/// them with [MermaidRenderer]. All other code blocks fall back to default.
class _MermaidBlockBuilder extends MarkdownElementBuilder {
  _MermaidBlockBuilder({
    required this.renderer,
    required this.colors,
    required this.mermaidTheme,
  });

  final MermaidRenderer? renderer;
  final AppColorScheme colors;
  final _MermaidThemeOptions mermaidTheme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // element is <pre>; look for a <code class="language-mermaid"> child
    final children = element.children;
    if (children == null || children.isEmpty) return null;

    final codeEl = children.whereType<md.Element>().firstWhere(
      (e) => e.tag == 'code',
      orElse: () => md.Element('code', []),
    );

    final lang = (codeEl.attributes['class'] ?? '').replaceFirst(
      'language-',
      '',
    );
    if (lang != 'mermaid') return null;

    final code = codeEl.textContent.trim();
    return _MermaidDiagram(
      key: ValueKey(
        _MermaidRasterizedDiagramCache.keyFor(
          code,
          900,
          variant: mermaidTheme.cacheToken,
        ),
      ),
      code: code,
      renderer: renderer,
      colors: colors,
      mermaidTheme: mermaidTheme,
    );
  }
}

/// Widget that renders a single Mermaid diagram asynchronously.
class _MermaidDiagram extends StatefulWidget {
  const _MermaidDiagram({
    super.key,
    required this.code,
    required this.renderer,
    required this.colors,
    required this.mermaidTheme,
  });

  final String code;
  final MermaidRenderer? renderer;
  final AppColorScheme colors;
  final _MermaidThemeOptions mermaidTheme;

  @override
  State<_MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidRasterizedDiagram {
  const _MermaidRasterizedDiagram({
    required this.svg,
    required this.png,
    required this.aspectRatio,
    required this.imageProvider,
  });

  final String svg;
  final Uint8List png;
  final double aspectRatio;
  final MemoryImage imageProvider;
}

class _MermaidRasterizedDiagramCache {
  static const int _maxEntries = 24;
  static final LinkedHashMap<String, Future<_MermaidRasterizedDiagram>>
  _entries = LinkedHashMap<String, Future<_MermaidRasterizedDiagram>>();
  static final LinkedHashMap<String, _MermaidRasterizedDiagram> _resolved =
      LinkedHashMap<String, _MermaidRasterizedDiagram>();

  static String keyFor(String code, double width, {String variant = ''}) =>
      '${width.round()}:$variant:${code.length}:${code.hashCode}';

  static bool contains(String key) => _entries.containsKey(key);

  static _MermaidRasterizedDiagram? peek(
    String code,
    double width, {
    String variant = '',
  }) {
    final key = keyFor(code, width, variant: variant);
    final existing = _resolved.remove(key);
    if (existing == null) return null;
    _resolved[key] = existing;
    return existing;
  }

  static Future<_MermaidRasterizedDiagram> load({
    required MermaidRenderer renderer,
    required String code,
    required double width,
    required MermaidRenderOptions options,
    String variant = '',
  }) {
    final key = keyFor(code, width, variant: variant);
    final existing = _entries.remove(key);
    if (existing != null) {
      debugPrint('[MermaidCache] HIT key=$key entries=${_entries.length + 1}');
      _entries[key] = existing;
      return existing;
    }

    debugPrint('[MermaidCache] MISS key=$key entries=${_entries.length}');
    final stopwatch = Stopwatch()..start();
    final future = () async {
      final svg = await renderer.renderToSvg(code, options: options);
      final png = await MermaidRenderer.svgToPng(
        svg,
        width: width,
        backgroundColor: options.backgroundColor,
      );
      final aspectRatio = _MermaidDiagramState.parseAspectRatio(svg);
      final imageProvider = MemoryImage(png);
      stopwatch.stop();
      debugPrint(
        '[MermaidCache] STORE key=$key ms=${stopwatch.elapsedMilliseconds} pngBytes=${png.length}',
      );
      final diagram = _MermaidRasterizedDiagram(
        svg: svg,
        png: png,
        aspectRatio: aspectRatio,
        imageProvider: imageProvider,
      );
      _resolved[key] = diagram;
      _entries[key] = SynchronousFuture<_MermaidRasterizedDiagram>(diagram);
      return diagram;
    }();

    _entries[key] = future;
    while (_entries.length > _maxEntries) {
      final eldestKey = _entries.keys.first;
      _entries.remove(eldestKey);
      _resolved.remove(eldestKey);
      debugPrint(
        '[MermaidCache] EVICT key=$eldestKey entries=${_entries.length}',
      );
    }
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          final removed = _entries.remove(key);
          if (removed != null) {
            _resolved.remove(key);
            debugPrint('[MermaidCache] DROP FAILED key=$key error=$error');
          }
        },
      ),
    );
    return future;
  }
}

class _MermaidDiagramState extends State<_MermaidDiagram> {
  static const double _previewHeight = 260;
  static const double _inlineRenderWidth = 900;
  static const double _expandedRenderWidth = 2200;
  static int _nextInstanceId = 1;

  Uint8List? _png;
  String? _svg;
  String? _error;
  bool _loading = true;
  double _aspectRatio = 16 / 9;
  MemoryImage? _imageProvider;
  late final int _instanceId;
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    _instanceId = _nextInstanceId++;
    _hydrateFromCacheIfAvailable(logPrefix: 'initState');
    debugPrint(
      '[Mermaid#$_instanceId] initState key=${_MermaidRasterizedDiagramCache.keyFor(widget.code, _inlineRenderWidth, variant: widget.mermaidTheme.cacheToken)} rendererReady=${widget.renderer != null}',
    );
    if (_png == null) {
      _render();
    }
  }

  @override
  void didUpdateWidget(_MermaidDiagram old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code ||
        old.renderer != widget.renderer ||
        old.mermaidTheme.cacheToken != widget.mermaidTheme.cacheToken) {
      debugPrint(
        '[Mermaid#$_instanceId] didUpdateWidget codeChanged=${old.code != widget.code} rendererChanged=${old.renderer != widget.renderer} themeChanged=${old.mermaidTheme.cacheToken != widget.mermaidTheme.cacheToken}',
      );
      final hydrated = _hydrateFromCacheIfAvailable(
        logPrefix: 'didUpdateWidget',
      );
      if (!hydrated) {
        _render();
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[Mermaid#$_instanceId] dispose builds=$_buildCount');
    super.dispose();
  }

  Future<void> _render() async {
    if (widget.renderer == null) {
      debugPrint('[Mermaid#$_instanceId] _render skipped: renderer not ready');
      return;
    }
    final cacheKey = _MermaidRasterizedDiagramCache.keyFor(
      widget.code,
      _inlineRenderWidth,
      variant: widget.mermaidTheme.cacheToken,
    );
    debugPrint(
      '[Mermaid#$_instanceId] _render start cacheKey=$cacheKey hadProvider=${_imageProvider != null} cacheContains=${_MermaidRasterizedDiagramCache.contains(cacheKey)}',
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diagram = await _MermaidRasterizedDiagramCache.load(
        renderer: widget.renderer!,
        code: widget.code,
        width: _inlineRenderWidth,
        options: widget.mermaidTheme.renderOptions,
        variant: widget.mermaidTheme.cacheToken,
      );
      if (!mounted) {
        debugPrint('[Mermaid#$_instanceId] _render completed after dispose');
        return;
      }
      final imageProvider = diagram.imageProvider;
      final imageCache = PaintingBinding.instance.imageCache;
      debugPrint(
        '[Mermaid#$_instanceId] imageCache before precache contains=${imageCache.containsKey(imageProvider)} entries=${imageCache.currentSize} bytes=${imageCache.currentSizeBytes}',
      );
      await precacheImage(imageProvider, context);
      debugPrint(
        '[Mermaid#$_instanceId] imageCache after precache contains=${imageCache.containsKey(imageProvider)} entries=${imageCache.currentSize} bytes=${imageCache.currentSizeBytes}',
      );
      if (mounted) {
        setState(() {
          _svg = diagram.svg;
          _png = diagram.png;
          _imageProvider = imageProvider;
          _aspectRatio = diagram.aspectRatio;
          _loading = false;
        });
        debugPrint(
          '[Mermaid#$_instanceId] _render done pngBytes=${diagram.png.length} providerHash=${imageProvider.hashCode}',
        );
      }
    } catch (e, st) {
      debugPrint('[Mermaid#$_instanceId] _render ERROR: $e');
      debugPrintStack(
        label: '[Mermaid#$_instanceId] stacktrace',
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  static double parseAspectRatio(String svg) {
    final match = RegExp(r'viewBox="([^"]+)"').firstMatch(svg);
    if (match != null) {
      final parts = match.group(1)!.trim().split(RegExp(r'[\s,]+'));
      if (parts.length == 4) {
        final width = double.tryParse(parts[2]);
        final height = double.tryParse(parts[3]);
        if (width != null && height != null && width > 0 && height > 0) {
          return width / height;
        }
      }
    }
    return 16 / 9;
  }

  bool _hydrateFromCacheIfAvailable({required String logPrefix}) {
    final cached = _MermaidRasterizedDiagramCache.peek(
      widget.code,
      _inlineRenderWidth,
      variant: widget.mermaidTheme.cacheToken,
    );
    if (cached == null) return false;
    _svg = cached.svg;
    _png = cached.png;
    _imageProvider = cached.imageProvider;
    _aspectRatio = cached.aspectRatio;
    _loading = false;
    _error = null;
    debugPrint(
      '[Mermaid#$_instanceId] $logPrefix hydrated from cache pngBytes=${cached.png.length}',
    );
    return true;
  }

  Future<void> _openExpandedPreview() async {
    if (_png == null) return;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final targetWidth = math.min(
      _expandedRenderWidth,
      math.max(_inlineRenderWidth, screenWidth * dpr),
    );
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder:
          (_) => _MermaidExpandedDialog(
            initialPng: _png!,
            svg: _svg,
            targetWidth: targetWidth,
            aspectRatio: _aspectRatio,
            colors: widget.colors,
            backgroundColor: widget.mermaidTheme.canvasColor,
            backgroundColorHex:
                widget.mermaidTheme.renderOptions.backgroundColor,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    if (_buildCount <= 5 || _buildCount % 20 == 0) {
      debugPrint(
        '[Mermaid#$_instanceId] build #$_buildCount loading=$_loading hasPng=${_png != null} hasProvider=${_imageProvider != null}',
      );
    }
    if (_png == null && (_loading || widget.renderer == null)) {
      return _MermaidPreviewFrame(
        height: _previewHeight,
        colors: widget.colors,
        backgroundColor: widget.mermaidTheme.canvasColor,
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Rendering diagram…', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return _MermaidPreviewFrame(
        height: _previewHeight,
        colors: widget.colors,
        borderColor: Colors.red.withValues(alpha: 0.3),
        backgroundColor: widget.mermaidTheme.canvasColor,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Mermaid error: $_error',
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: _MermaidPreviewFrame(
        height: _previewHeight,
        colors: widget.colors,
        backgroundColor: widget.mermaidTheme.canvasColor,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openExpandedPreview,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _png == null ? 0 : 1,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      child: Image(
                        image: _imageProvider!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.mermaidTheme.scrimColor,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_full_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Open',
                            style: TextStyle(fontSize: 11, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MermaidPreviewFrame extends StatelessWidget {
  const _MermaidPreviewFrame({
    required this.height,
    required this.colors,
    required this.child,
    this.borderColor,
    this.backgroundColor,
  });

  final double height;
  final AppColorScheme colors;
  final Widget child;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? colors.border),
      ),
      child: child,
    );
  }
}

class _MermaidExpandedDialog extends StatefulWidget {
  const _MermaidExpandedDialog({
    required this.initialPng,
    required this.svg,
    required this.targetWidth,
    required this.aspectRatio,
    required this.colors,
    required this.backgroundColor,
    required this.backgroundColorHex,
  });

  final Uint8List initialPng;
  final String? svg;
  final double targetWidth;
  final double aspectRatio;
  final AppColorScheme colors;
  final Color backgroundColor;
  final String? backgroundColorHex;

  @override
  State<_MermaidExpandedDialog> createState() => _MermaidExpandedDialogState();
}

class _MermaidExpandedDialogState extends State<_MermaidExpandedDialog> {
  late Uint8List _png;
  bool _refining = false;
  String? _refineError;

  @override
  void initState() {
    super.initState();
    _png = widget.initialPng;
    _renderHighResIfNeeded();
  }

  Future<void> _renderHighResIfNeeded() async {
    if (widget.svg == null ||
        widget.targetWidth <= _MermaidDiagramState._inlineRenderWidth) {
      return;
    }
    setState(() {
      _refining = true;
      _refineError = null;
    });
    try {
      final png = await MermaidRenderer.svgToPng(
        widget.svg!,
        width: widget.targetWidth,
        backgroundColor: widget.backgroundColorHex,
      );
      if (!mounted) return;
      setState(() {
        _png = png;
        _refining = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _refining = false;
        _refineError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: widget.colors.surfaceElevated,
      child: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width - 40, 1400),
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Diagram preview',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (_refining)
                    Text('Refining...', style: theme.textTheme.bodySmall),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fittedSize = _containSize(
                    Size(
                      math.max(1, constraints.maxWidth - 32),
                      math.max(1, constraints.maxHeight - 32),
                    ),
                    widget.aspectRatio,
                  );
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.backgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: widget.colors.border),
                          ),
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 6,
                            boundaryMargin: const EdgeInsets.all(48),
                            child: Center(
                              child: SizedBox(
                                width: fittedSize.width,
                                height: fittedSize.height,
                                child: Image.memory(
                                  _png,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_refineError != null)
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 24,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                'Failed to render higher resolution preview: $_refineError',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Size _containSize(Size bounds, double aspectRatio) {
    final boundedHeight = bounds.width / aspectRatio;
    if (boundedHeight <= bounds.height) {
      return Size(bounds.width, boundedHeight);
    }
    return Size(bounds.height * aspectRatio, bounds.height);
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
  late List<String> _lines;
  final _scrollCtrl = ScrollController();
  StreamSubscription<BoardFileModifiedEvent>? _fileSub;

  @override
  void initState() {
    super.initState();
    _lines = _readLines();
    _fileSub = BoardEventBus.instance.on<BoardFileModifiedEvent>().listen(_onFileModified);
  }

  @override
  void didUpdateWidget(_CodePreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _lines = _readLines();
    }
  }

  @override
  void dispose() {
    _fileSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<String> _readLines() {
    try {
      final file = File(widget.path);
      if (!file.existsSync()) return [];
      return file.readAsStringSync().split('\n');
    } catch (_) {
      return [];
    }
  }

  void _onFileModified(BoardFileModifiedEvent event) {
    if (!mounted || event.path != widget.path) return;
    // Capture scroll offset before rebuild so we can restore it after.
    final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    setState(() => _lines = _readLines());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      _scrollCtrl.jumpTo(offset.clamp(0.0, max));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return const Center(child: Text('File not found'));
    }
    final colors = AppColorScheme.of(context);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final lineNumColor = textColor.withValues(alpha: 0.35);

    return Container(
      color: colors.terminalBackground,
      child: ListView.builder(
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
                Expanded(
                  child: SelectableText(
                    _lines[i],
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: colors.terminalPrompt,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
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
    return Video(controller: _controller, controls: AdaptiveVideoControls);
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
  static const Color _accent = Color(0xFF8B5CF6);

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
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              size: 48,
              color: _accent,
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
              activeTrackColor: _accent,
              inactiveTrackColor: colors.border,
              thumbColor: _accent,
              overlayColor: _accent.withValues(alpha: 0.15),
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
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                Text(
                  _fmt(_total),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color,
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
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
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
  });

  final String path;
  final VoidCallback? onEdit;
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
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
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
                foregroundColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
            ),
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
