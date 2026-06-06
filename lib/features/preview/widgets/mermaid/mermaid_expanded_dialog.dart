import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Full-screen zoomable dialog for inspecting a Mermaid diagram.
class MermaidExpandedDialog extends StatefulWidget {
  const MermaidExpandedDialog({
    super.key,
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
  State<MermaidExpandedDialog> createState() => _MermaidExpandedDialogState();
}

class _MermaidExpandedDialogState extends State<MermaidExpandedDialog> {
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
    if (widget.svg == null || widget.targetWidth <= 900) {
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
    final colors = context.appColors;
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
                                child: RepaintBoundary(
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
                      ),
                      if (_refineError != null)
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 24,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.accentRed.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: colors.accentRed.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                'Failed to render higher resolution preview: $_refineError',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.accentRed,
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
