import 'package:dmtools_mermaid_renderer/dmtools_mermaid_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_cache.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_renderer_widget.dart';
import 'package:yoloit/features/preview/widgets/mermaid/mermaid_theme.dart';

/// Custom [MarkdownElementBuilder] that intercepts ` ```mermaid ` code blocks
/// and renders them with [MermaidDiagram].
class MermaidBlockBuilder extends MarkdownElementBuilder {
  MermaidBlockBuilder({
    required this.renderer,
    required this.colors,
    required this.mermaidTheme,
  });

  final MermaidRenderer? renderer;
  final AppColorScheme colors;
  final MermaidThemeOptions mermaidTheme;

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
    return MermaidDiagram(
      key: ValueKey(
        MermaidRasterizedDiagramCache.keyFor(
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
