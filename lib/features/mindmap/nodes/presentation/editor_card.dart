import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';

/// Presentation editor card — shared shell for both macOS and web.
///
/// [onContentUpdate] is called when the user edits text inside the card.
/// This is only used on web; on macOS the [body] override takes over.
class EditorCard extends StatefulWidget {
  const EditorCard({
    super.key,
    required this.props,
    this.immersive = false,
    this.body,
    this.onSwitchTab,
    this.onSave,
    this.onToggleImmersive,
    this.onContentUpdate,
  });
  final EditorCardProps props;
  final bool immersive;
  final Widget? body;
  final void Function(int tabIndex)? onSwitchTab;
  final VoidCallback? onSave;
  final VoidCallback? onToggleImmersive;

  /// Called with new content when user edits text (web only).
  final void Function(String content)? onContentUpdate;

  @override
  State<EditorCard> createState() => _EditorCardState();
}

class _EditorCardState extends State<EditorCard> {
  bool _isPreview = false;
  bool _isEditing = false;
  late TextEditingController _editCtrl;
  late FocusNode _focusNode;

  bool get _isMarkdown =>
      widget.props.language.toLowerCase() == 'markdown' ||
      widget.props.filePath.toLowerCase().endsWith('.md');

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.props.content);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(EditorCard old) {
    super.didUpdateWidget(old);
    if (!_isEditing && old.props.content != widget.props.content) {
      _editCtrl.text = widget.props.content;
    }
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitEdit() {
    if (_isEditing) {
      widget.onContentUpdate?.call(_editCtrl.text);
      setState(() => _isEditing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final props = widget.props;
    final lines = props.content.split('\n').take(200).toList();

    Widget editorBody;
    if (props.isImage) {
      editorBody = _ImageBody(
        base64: props.imageBase64!,
        filePath: props.filePath,
      );
    } else if (_isEditing && widget.onContentUpdate != null) {
      editorBody = KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (ev) {
          if (ev is KeyDownEvent &&
              ev.logicalKey == LogicalKeyboardKey.keyS &&
              HardwareKeyboard.instance.isControlPressed) {
            _commitEdit();
          }
        },
        child: TextField(
          controller: _editCtrl,
          focusNode: _focusNode,
          maxLines: null,
          expands: true,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: colors.terminalText,
            height: 1.5,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            fillColor: colors.terminalBackground,
            filled: true,
          ),
        ),
      );
    } else if (_isPreview && _isMarkdown) {
      editorBody = Container(
        color: colors.terminalBackground,
        padding: const EdgeInsets.all(12),
        child: Markdown(
          data: props.content,
          shrinkWrap: false,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(color: colors.terminalText, fontSize: 11),
            h1: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            h2: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: colors.accentBlue,
              backgroundColor: colors.surfaceHighlight,
            ),
          ),
        ),
      );
    } else {
      editorBody = Container(
        color: colors.terminalBackground,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: RepaintBoundary(
          child: SelectionArea(
            child: ListView.builder(
              itemCount: lines.length,
              itemBuilder:
                  (_, i) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                      width: 32,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: colors.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lines[i],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: colors.terminalText,
                          height: 1.5,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color:
              widget.immersive
                  ? colors.accentBlue
                  : colors.accentBlue.withAlpha(89),
          width: widget.immersive ? 2 : 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color:
                widget.immersive
                    ? colors.background.withAlpha(204)
                    : colors.background.withAlpha(144),
            blurRadius: widget.immersive ? 32 : 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.immersive &&
                widget.body == null &&
                props.tabs.length > 1)
              Container(
                height: 28,
                decoration: BoxDecoration(
                  color: colors.background,
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: [
                    for (var i = 0; i < props.tabs.length; i++)
                      _TabChip(
                        name: p.basename(props.tabs[i].path),
                        isActive: props.tabs[i].isActive,
                        onTap: () => widget.onSwitchTab?.call(i),
                      ),
                  ],
                ),
              ),
            if (!widget.immersive && widget.body == null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.code, size: 12, color: colors.accentBlue),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        p.basename(props.filePath),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      props.language,
                      style: TextStyle(fontSize: 9, color: colors.textMuted),
                    ),
                    if (_isMarkdown &&
                        !props.isImage &&
                        widget.body == null) ...[
                      const SizedBox(width: 6),
                      _HeaderButton(
                        label: _isPreview ? 'Code' : 'Preview',
                        icon: _isPreview ? Icons.code : Icons.preview,
                        onTap: () {
                          if (_isEditing) _commitEdit();
                          setState(() => _isPreview = !_isPreview);
                        },
                      ),
                    ],
                    if (widget.onContentUpdate != null && !props.isImage) ...[
                      const SizedBox(width: 6),
                      _HeaderButton(
                        label: _isEditing ? 'Save' : 'Edit',
                        icon: _isEditing ? Icons.save : Icons.edit,
                        onTap: () {
                          if (_isEditing) {
                            _commitEdit();
                          } else {
                            _editCtrl.text = props.content;
                            setState(() {
                              _isEditing = true;
                              _isPreview = false;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _focusNode.requestFocus();
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(child: widget.body ?? editorBody),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.name, required this.isActive, this.onTap});
  final String name;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? colors.tabActiveBg : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? colors.tabBorder : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: isActive ? colors.textPrimary : colors.textSecondary,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.tabActiveBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.tabBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: colors.accentBlue),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: colors.accentBlue,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageBody extends StatelessWidget {
  const _ImageBody({required this.base64, required this.filePath});
  final String base64;
  final String filePath;

  bool get _isSvg => filePath.toLowerCase().endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    try {
      final bytes = base64Decode(base64);
      return Container(
        color: colors.terminalBackground,
        child: Center(
          child:
              _isSvg
                  ? SvgPicture.memory(bytes, fit: BoxFit.contain)
                  : RepaintBoundary(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, __, ___) => Center(
                            child: Text(
                              'Image error',
                              style: TextStyle(
                                color: colors.accentBlue,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ),
                  ),
        ),
      );
    } catch (_) {
      return Center(
        child: Text(
          'Invalid image data',
          style: TextStyle(color: colors.accentBlue, fontSize: 10),
        ),
      );
    }
  }
}
