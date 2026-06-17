import 'dart:async';

import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_widgets.dart';

class MarkdownDocumentPreview extends StatefulWidget {
  const MarkdownDocumentPreview({
    super.key,
    required this.content,
    this.scrollController,
    this.onContentLayoutChanged,
  });

  final String content;
  final ScrollController? scrollController;
  final VoidCallback? onContentLayoutChanged;

  @override
  State<MarkdownDocumentPreview> createState() =>
      _MarkdownDocumentPreviewState();
}

class _MarkdownDocumentPreviewState extends State<MarkdownDocumentPreview> {
  static final MermaidRenderer _sharedRenderer = MermaidRenderer();
  static Future<void>? _initFuture;
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    final taskKey = 'mermaid_init:${_sharedRenderer.hashCode}';
    HeadlessRenderRegistry.activeTasks.add(taskKey);
    _initFuture ??= _sharedRenderer.init();
    _initFuture!
        .then((_) {
          if (!mounted) return;
          setState(() => _rendererReady = true);
          widget.onContentLayoutChanged?.call();
        })
        .catchError((Object e) {
          assert(() { debugPrint('[Mermaid] init() FAILED: $e'); return true; }());
        })
        .whenComplete(() {
          HeadlessRenderRegistry.activeTasks.remove(taskKey);
        });
  }

  @override
  void dispose() {
    HeadlessRenderRegistry.activeTasks.remove(
      'mermaid_init:${_sharedRenderer.hashCode}',
    );
    // Do NOT dispose the static shared renderer, as it persists for the
    // process lifetime!
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mermaidTheme = buildMermaidThemeOptions(context, colors);
    final styleSheet = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).copyWith(
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
    final Widget mdBody = SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(12),
      child: MarkdownBody(
        key: ValueKey(_rendererReady),
        data: widget.content,
        softLineBreak: true,
        builders: {
          'pre': MermaidBlockBuilder(
            renderer: _rendererReady ? _sharedRenderer : null,
            colors: colors,
            mermaidTheme: mermaidTheme,
          ),
        },
        styleSheet: styleSheet,
      ),
    );

    if (View.maybeOf(context) == null) {
      // Headless context: bypass SelectionArea to avoid View.of() crashes
      return mdBody;
    }

    return RepaintBoundary(child: SelectionArea(child: mdBody));
  }
}
