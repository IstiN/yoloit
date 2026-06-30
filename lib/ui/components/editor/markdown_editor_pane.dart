import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/ui/widgets/text_editing_utils.dart';
import 'package:yoloit/ui/components/buttons/markdown_tool_button.dart';

/// Markdown write/preview editor with a formatting toolbar.
class MarkdownEditorPane extends StatefulWidget {
  const MarkdownEditorPane({
    required this.controller,
    super.key,
    this.focusNode,
    this.hintText = 'Write markdown here…',
    this.onPaste,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final Future<void> Function()? onPaste;

  @override
  State<MarkdownEditorPane> createState() => _MarkdownEditorPaneState();
}

class _MarkdownEditorPaneState extends State<MarkdownEditorPane> {
  bool _isPreview = false;

  void _refresh() => setState(() {});

  void _setPreview(bool preview) {
    if (_isPreview == preview) return;
    if (preview) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() => _isPreview = preview);
    if (!preview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          (widget.focusNode ?? FocusScope.of(context)).requestFocus();
        }
      });
    }
  }

  KeyEventResult _handlePasteShortcut(FocusNode node, KeyEvent event) {
    if (widget.onPaste == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isPaste =
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (!isPaste) return KeyEventResult.ignored;
    widget.onPaste!();
    return KeyEventResult.handled;
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
      h1: theme.textTheme.headlineSmall?.copyWith(color: colors.textPrimary),
      h2: theme.textTheme.titleLarge?.copyWith(color: colors.textPrimary),
      h3: theme.textTheme.titleMedium?.copyWith(color: colors.textPrimary),
      listBullet: theme.textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: colors.textPrimary,
        backgroundColor: colors.terminalBackground,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.terminalBackground,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final markdown =
        widget.controller.text.trim().isEmpty
            ? '*Empty*'
            : widget.controller.text;
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(
          data: markdown,
          softLineBreak: true,
          selectable: true,
          styleSheet: _styleSheet(context),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return Focus(
      onKeyEvent: _handlePasteShortcut,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(color: context.appColors.textPrimary),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          hintText: widget.hintText,
        ),
        onChanged: (_) => _refresh(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final controller = widget.controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    MarkdownToolButton(
                      icon: Icons.title,
                      tooltip: 'Heading',
                      onTap: () {
                        prefixSelectedLines(controller, '# ');
                        _refresh();
                      },
                    ),
                    MarkdownToolButton(
                      icon: Icons.format_bold,
                      tooltip: 'Bold',
                      onTap: () {
                        wrapSelection(
                          controller,
                          before: '**',
                          after: '**',
                          placeholder: 'bold',
                        );
                        _refresh();
                      },
                    ),
                    MarkdownToolButton(
                      icon: Icons.format_italic,
                      tooltip: 'Italic',
                      onTap: () {
                        wrapSelection(
                          controller,
                          before: '*',
                          after: '*',
                          placeholder: 'italic',
                        );
                        _refresh();
                      },
                    ),
                    MarkdownToolButton(
                      icon: Icons.format_list_bulleted,
                      tooltip: 'Bullet list',
                      onTap: () {
                        prefixSelectedLines(controller, '- ');
                        _refresh();
                      },
                    ),
                    MarkdownToolButton(
                      icon: Icons.check_box_outlined,
                      tooltip: 'Checkbox',
                      onTap: () {
                        prefixSelectedLines(controller, '- [ ] ');
                        _refresh();
                      },
                    ),
                    MarkdownToolButton(
                      icon: Icons.link,
                      tooltip: 'Link',
                      onTap: () {
                        wrapSelection(
                          controller,
                          before: '[',
                          after: '](https://)',
                          placeholder: 'text',
                        );
                        _refresh();
                      },
                    ),
                    MarkdownToolButton(
                      icon: Icons.code,
                      tooltip: 'Code block',
                      onTap: () {
                        wrapSelection(
                          controller,
                          before: '```\n',
                          after: '\n```',
                          placeholder: 'code',
                        );
                        _refresh();
                      },
                    ),
                    MarkdownToolButton(
                      icon: Icons.format_quote,
                      tooltip: 'Quote',
                      onTap: () {
                        prefixSelectedLines(controller, '> ');
                        _refresh();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.edit_outlined, size: 16),
                  label: Text('Write'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.preview_outlined, size: 16),
                  label: Text('Preview'),
                ),
              ],
              selected: {_isPreview},
              onSelectionChanged: (sel) => _setPreview(sel.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(10),
              color: colors.surfaceElevated,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.topLeft,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child:
                    _isPreview
                        ? KeyedSubtree(
                          key: const ValueKey('markdown_preview'),
                          child: _buildPreview(context),
                        )
                        : KeyedSubtree(
                          key: const ValueKey('markdown_write'),
                          child: _buildEditor(context),
                        ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
