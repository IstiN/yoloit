import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Web implementation of [MarkdownDocumentPreview].
///
/// Uses [flutter_markdown_plus] directly. Mermaid diagrams are rendered as
/// plain code blocks because the native mermaid renderer is not available on
/// web.
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
  @override
  void initState() {
    super.initState();
    // Notify layout listeners on the next frame so headless consumers can
    // measure the widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onContentLayoutChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
    final mdBody = SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(12),
      child: MarkdownBody(
        data: widget.content,
        softLineBreak: true,
        styleSheet: styleSheet,
      ),
    );

    if (View.maybeOf(context) == null) {
      return mdBody;
    }

    return RepaintBoundary(child: SelectionArea(child: mdBody));
  }
}
