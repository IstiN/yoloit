import 'dart:math' as math;

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_cache.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_expanded_dialog.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_preview_frame.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_theme.dart';

/// Renders a single Mermaid diagram asynchronously with inline preview
/// and expandable full-screen dialog.
class MermaidDiagram extends StatefulWidget {
  const MermaidDiagram({
    super.key,
    required this.code,
    required this.renderer,
    required this.colors,
    required this.mermaidTheme,
  });

  final String code;
  final MermaidRenderer? renderer;
  final AppColorScheme colors;
  final MermaidThemeOptions mermaidTheme;

  @override
  State<MermaidDiagram> createState() => MermaidDiagramState();
}

class MermaidDiagramState extends State<MermaidDiagram> {
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
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.renderer != widget.renderer ||
        oldWidget.mermaidTheme.cacheToken != widget.mermaidTheme.cacheToken) {
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
    final taskKey = 'mermaid:${widget.code.hashCode}';
    HeadlessRenderRegistry.activeTasks.add(taskKey);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diagram = await MermaidRasterizedDiagramCache.load(
        renderer: widget.renderer!,
        code: widget.code,
        width: _inlineRenderWidth,
        options: widget.mermaidTheme.renderOptions,
        variant: widget.mermaidTheme.cacheToken,
      );
      if (!mounted) return;
      final imageProvider = diagram.imageProvider;
      if (View.maybeOf(context) != null) {
        await precacheImage(imageProvider, context);
      }
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
    } finally {
      HeadlessRenderRegistry.activeTasks.remove(taskKey);
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
    final cached = MermaidRasterizedDiagramCache.peek(
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
    final colors = context.appColors;
    await showDialog<void>(
      context: context,
      barrierColor: colors.background.withValues(alpha: 0.72),
      builder:
          (_) => MermaidExpandedDialog(
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
    final colors = context.appColors;
    if (_png == null && (_loading || widget.renderer == null)) {
      return MermaidPreviewFrame(
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
      return MermaidPreviewFrame(
        height: _previewHeight,
        colors: widget.colors,
        borderColor: colors.accentRed.withValues(alpha: 0.3),
        backgroundColor: widget.mermaidTheme.canvasColor,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Mermaid error: $_error',
            style: TextStyle(fontSize: 12, color: colors.accentRed),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: MermaidPreviewFrame(
        height: _previewHeight,
        colors: widget.colors,
        backgroundColor: widget.mermaidTheme.canvasColor,
        child: Material(
          color: colors.surface.withValues(alpha: 0),
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
    final colors = context.appColors;
    return Material(
      color: colors.background.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colors.textPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
