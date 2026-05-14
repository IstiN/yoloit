import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:yoloit/core/theme/app_color_scheme.dart';

class MarkdownDocumentPreview extends StatefulWidget {
  const MarkdownDocumentPreview({super.key, required this.content});

  final String content;

  @override
  State<MarkdownDocumentPreview> createState() =>
      _MarkdownDocumentPreviewState();
}

class _MarkdownDocumentPreviewState extends State<MarkdownDocumentPreview> {
  final MermaidRenderer _renderer = MermaidRenderer();
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    _renderer
        .init()
        .then((_) {
          if (mounted) setState(() => _rendererReady = true);
        })
        .catchError((Object e) {
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
    final colors = AppColorScheme.of(context);
    final mermaidTheme = _buildMermaidThemeOptions(context, colors);
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
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
    );
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: MarkdownBody(
          key: ValueKey(_rendererReady),
          data: widget.content,
          softLineBreak: true,
          builders: {
            'pre': _MermaidBlockBuilder(
              renderer: _rendererReady ? _renderer : null,
              colors: colors,
              mermaidTheme: mermaidTheme,
            ),
          },
          styleSheet: styleSheet,
        ),
      ),
    );
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
      _entries[key] = existing;
      return existing;
    }

    final future = () async {
      final svg = await renderer.renderToSvg(code, options: options);
      final png = await MermaidRenderer.svgToPng(
        svg,
        width: width,
        backgroundColor: options.backgroundColor,
      );
      final aspectRatio = _MermaidDiagramState.parseAspectRatio(svg);
      final imageProvider = MemoryImage(png);
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
    }
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          final removed = _entries.remove(key);
          if (removed != null) {
            _resolved.remove(key);
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

  Uint8List? _png;
  String? _svg;
  String? _error;
  bool _loading = true;
  double _aspectRatio = 16 / 9;
  MemoryImage? _imageProvider;

  @override
  void initState() {
    super.initState();
    _hydrateFromCacheIfAvailable();
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
      final hydrated = _hydrateFromCacheIfAvailable();
      if (!hydrated) {
        _render();
      }
    }
  }

  Future<void> _render() async {
    if (widget.renderer == null) {
      return;
    }
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
      if (!mounted) return;
      final imageProvider = diagram.imageProvider;
      await precacheImage(imageProvider, context);
      if (mounted) {
        setState(() {
          _svg = diagram.svg;
          _png = diagram.png;
          _imageProvider = imageProvider;
          _aspectRatio = diagram.aspectRatio;
          _loading = false;
        });
      }
    } catch (e) {
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

  bool _hydrateFromCacheIfAvailable() {
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

  Future<void> _copySource() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Mermaid source copied'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MermaidOverlayActionChip(
                        icon: Icons.content_copy_rounded,
                        label: 'Copy',
                        onTap: _copySource,
                      ),
                      const SizedBox(width: 8),
                      _MermaidOverlayActionChip(
                        icon: Icons.open_in_full_rounded,
                        label: 'Open',
                        onTap: _openExpandedPreview,
                      ),
                    ],
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

class _MermaidOverlayActionChip extends StatelessWidget {
  const _MermaidOverlayActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ],
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
