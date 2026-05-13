import 'dart:async';
import 'dart:io';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
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

bool _isVideoExt(String ext) {
  return const {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv'}
      .contains(ext.toLowerCase());
}

bool _isAudioExt(String ext) {
  return const {'mp3', 'aac', 'wav', 'ogg', 'flac', 'm4a', 'opus', 'wma'}
      .contains(ext.toLowerCase());
}

bool _isMarkdownExt(String ext) =>
    const {'md', 'markdown'}.contains(ext.toLowerCase());

bool _isTextExt(String ext) {
  return const {
    'txt', 'log', 'csv', 'tsv', 'ini', 'cfg', 'conf', 'env',
    'dart', 'py', 'js', 'ts', 'jsx', 'tsx', 'java', 'kt', 'swift',
    'go', 'rs', 'c', 'cpp', 'h', 'hpp', 'cs', 'rb', 'php', 'sh',
    'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd',
    'json', 'yaml', 'yml', 'xml', 'toml', 'html', 'css', 'scss',
    'less', 'sql', 'graphql', 'proto', 'makefile', 'dockerfile',
    'gitignore', 'editorconfig', 'properties', 'gradle', 'lock',
    'mjs', 'cjs', 'vue', 'svelte', 'astro',
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
            Icon(Icons.perm_media_outlined, size: 48, color: _accent.withOpacity(0.4)),
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
    if (_isVideoExt(ext)) {
      return _VideoPreview(key: ValueKey(path), path: path);
    }
    if (_isAudioExt(ext)) {
      return _AudioPreview(key: ValueKey(path), path: path);
    }
    if (_isMarkdownExt(ext)) {
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
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.insert_drive_file_outlined, size: 48, color: _accent),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (ctx) => Text(
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
        'makefile', 'dockerfile', 'jenkinsfile', 'vagrantfile',
        'procfile', 'gemfile', 'rakefile', 'license', 'readme',
        'changelog', 'authors', 'contributors', 'todo',
      }.contains(name)) return true;
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
  final MermaidRenderer _renderer = MermaidRenderer();
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Mermaid] init() starting for ${widget.path}');
    _renderer.init().then((_) {
      debugPrint('[Mermaid] init() complete, renderer ready');
      if (mounted) setState(() => _rendererReady = true);
    }).catchError((e) {
      debugPrint('[Mermaid] init() FAILED: $e');
    });
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.path);
    if (!file.existsSync()) {
      return const Center(child: Text('File not found'));
    }
    try {
      final content = file.readAsStringSync();
      final colors = AppColorScheme.of(context);
      return Markdown(
        key: ValueKey(_rendererReady), // force rebuild when renderer becomes ready
        data: content,
        selectable: true,
        padding: const EdgeInsets.all(12),
        builders: {
          'pre': _MermaidBlockBuilder(
            renderer: _rendererReady ? _renderer : null,
            colors: colors,
            context: context,
          ),
        },
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          codeblockDecoration: BoxDecoration(
            color: colors.terminalBackground,
            borderRadius: BorderRadius.circular(6),
          ),
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface,
            backgroundColor: colors.terminalBackground,
          ),
        ),
      );
    } catch (e) {
      return Center(child: Text('Error reading file: $e'));
    }
  }
}

/// Custom markdown builder that intercepts ```mermaid code blocks and renders
/// them with [MermaidRenderer]. All other code blocks fall back to default.
class _MermaidBlockBuilder extends MarkdownElementBuilder {
  _MermaidBlockBuilder({
    required this.renderer,
    required this.colors,
    required this.context,
  });

  final MermaidRenderer? renderer;
  final AppColorScheme colors;
  final BuildContext context;

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

    final lang = (codeEl.attributes['class'] ?? '').replaceFirst('language-', '');
    if (lang != 'mermaid') return null;

    final code = codeEl.textContent.trim();
    return _MermaidDiagram(code: code, renderer: renderer, colors: colors);
  }
}

/// Widget that renders a single Mermaid diagram asynchronously.
class _MermaidDiagram extends StatefulWidget {
  const _MermaidDiagram({
    required this.code,
    required this.renderer,
    required this.colors,
  });

  final String code;
  final MermaidRenderer? renderer;
  final AppColorScheme colors;

  @override
  State<_MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<_MermaidDiagram> {
  String? _svg;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(_MermaidDiagram old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.renderer != widget.renderer) {
      _render();
    }
  }

  Future<void> _render() async {
    if (widget.renderer == null) {
      debugPrint('[Mermaid] _render() skipped — renderer not ready yet');
      return;
    }
    debugPrint('[Mermaid] _render() start, code length=${widget.code.length}');
    setState(() { _loading = true; _error = null; });
    try {
      final svg = await widget.renderer!.renderToSvg(widget.code);
      debugPrint('[Mermaid] _render() success, svg length=${svg.length}');
      if (mounted) setState(() { _svg = svg; _loading = false; });
    } catch (e) {
      debugPrint('[Mermaid] _render() ERROR: $e');
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || widget.renderer == null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.colors.terminalBackground,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Rendering diagram…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(
          'Mermaid error: $_error',
          style: const TextStyle(fontSize: 12, color: Colors.red),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.colors.border),
      ),
      child: SvgPicture.string(
        _svg!,
        fit: BoxFit.contain,
      ),
    );
  }
}

// ─── Code / Text Preview ──────────────────────────────────────────────────────

class _CodePreview extends StatelessWidget {
  const _CodePreview({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return const Center(child: Text('File not found'));
    }
    try {
      final content = file.readAsStringSync();
      final lines = content.split('\n');
      final colors = AppColorScheme.of(context);
      final textColor = Theme.of(context).colorScheme.onSurface;
      final lineNumColor = textColor.withValues(alpha: 0.35);

      return Container(
        color: colors.terminalBackground,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: lines.length,
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
                      lines[i],
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
    } catch (e) {
      return Center(child: Text('Error reading file: $e'));
    }
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
    return Video(
      controller: _controller,
      controls: AdaptiveVideoControls,
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
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _isPlaying = v);
    }));
    _subs.add(_player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.stream.duration.listen((d) {
      if (mounted) setState(() => _total = d);
    }));
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
    final progress = _total.inMilliseconds > 0
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
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.music_note_rounded, size: 48, color: _accent),
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
              overlayColor: _accent.withOpacity(0.15),
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
                onPressed: () => _player.seek(
                  Duration(milliseconds: (_position.inMilliseconds - 10000).clamp(0, _total.inMilliseconds)),
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
                onPressed: () => _player.seek(
                  Duration(milliseconds: (_position.inMilliseconds + 10000).clamp(0, _total.inMilliseconds)),
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
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
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

