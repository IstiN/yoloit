import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Built-in plugin that renders a Markdown note panel.
class MarkdownNotePlugin extends BoardPanelPlugin {
  const MarkdownNotePlugin();

  static const String kTypeId = 'board.note.markdown';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Markdown Note';

  @override
  IconData get icon => Icons.sticky_note_2_outlined;

  @override
  Color get accentColor => const Color(0xFFB46CFF);

  @override
  Size get defaultSize => const Size(360, 220);

  @override
  Map<String, dynamic> get initialState => {
    'markdown': '',
    'autoHeight': false,
    'autoScroll': false,
  };

  @override
  bool get hasEditor => true;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final markdown = panel.state['markdown'] as String? ?? '';
    final autoHeight = panel.state['autoHeight'] as bool? ?? false;
    final autoScroll = panel.state['autoScroll'] as bool? ?? false;

    if (autoHeight) {
      return _AutoHeightNoteContent(
        markdown: markdown,
        panel: panel,
        renderContext: renderContext,
      );
    }

    return _ScrollableNoteContent(
      markdown: markdown,
      autoScroll: autoScroll,
    );
  }

  @override
  Future<bool> showEditor(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onSave,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _MarkdownNoteEditorDialog(panel: panel),
    );
    if (result == null) return false;
    onSave(result);
    return true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scrollable content with optional auto-scroll and copy button
// ─────────────────────────────────────────────────────────────────────────────

/// Renders the markdown body in a scrollable view.
/// When [autoScroll] is true (e.g. for live agent log panels), the scroll
/// position is animated to the bottom whenever the content changes.
/// A copy button appears on hover in the top-right corner.
class _ScrollableNoteContent extends StatefulWidget {
  const _ScrollableNoteContent({
    required this.markdown,
    this.autoScroll = false,
  });

  final String markdown;
  final bool autoScroll;

  @override
  State<_ScrollableNoteContent> createState() => _ScrollableNoteContentState();
}

class _ScrollableNoteContentState extends State<_ScrollableNoteContent> {
  final _scrollCtrl = ScrollController();
  bool _isHovered = false;
  bool _copied = false;

  @override
  void didUpdateWidget(_ScrollableNoteContent old) {
    super.didUpdateWidget(old);
    if (widget.autoScroll && old.markdown != widget.markdown) {
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _copyContent() async {
    await Clipboard.setData(ClipboardData(text: widget.markdown));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        children: [
          ClipRect(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: MarkdownBody(
                  data: widget.markdown.isEmpty ? '*Empty note*' : widget.markdown,
                ),
              ),
            ),
          ),
          // Copy button — shown on hover
          AnimatedOpacity(
            opacity: _isHovered ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 120),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Tooltip(
                  message: _copied ? 'Copied!' : 'Copy content',
                  child: InkWell(
                    onTap: _isHovered ? _copyContent : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.copy_outlined,
                            size: 12,
                            color: _copied
                                ? Colors.green
                                : Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Copied' : 'Copy',
                            style: TextStyle(
                              fontSize: 11,
                              color: _copied
                                  ? Colors.green
                                  : Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-height content widget
// ─────────────────────────────────────────────────────────────────────────────

/// Renders the markdown body and, after each layout, resizes the panel height
/// to exactly fit the rendered content (plus padding).
/// Width stays at its current value — only height is adjusted.
class _AutoHeightNoteContent extends StatefulWidget {
  const _AutoHeightNoteContent({
    required this.markdown,
    required this.panel,
    required this.renderContext,
  });

  final String markdown;
  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_AutoHeightNoteContent> createState() => _AutoHeightNoteContentState();
}

class _AutoHeightNoteContentState extends State<_AutoHeightNoteContent> {
  final _contentKey = GlobalKey();
  static const double _innerPadding = 16.0;
  static const double _panelHeaderHeight = 44.0;
  static const double _panelContentPadding = 12.0;

  @override
  void initState() {
    super.initState();
    _scheduleResize();
  }

  @override
  void didUpdateWidget(_AutoHeightNoteContent old) {
    super.didUpdateWidget(old);
    final oldAutoHeight = old.panel.state['autoHeight'] as bool? ?? false;
    final newAutoHeight = widget.panel.state['autoHeight'] as bool? ?? false;
    if (old.markdown != widget.markdown ||
        oldAutoHeight != newAutoHeight ||
        old.panel.bounds.width != widget.panel.bounds.width) {
      _scheduleResize();
    }
  }

  void _scheduleResize() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final contentH = box.size.height;
      final newH = contentH + _panelHeaderHeight + _panelContentPadding * 2;
      final currentH = widget.panel.bounds.height;
      debugPrint('[NoteAutoHeight] ${widget.panel.title}: content=$contentH current=$currentH target=$newH');
      // Only resize if difference is more than 4px to avoid jitter.
      if ((newH - currentH).abs() > 4) {
        widget.renderContext.onResize?.call(widget.panel.bounds.width, newH);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        key: _contentKey,
        padding: const EdgeInsets.all(_innerPadding),
        child: MarkdownBody(
          data: widget.markdown.isEmpty ? '*Empty note*' : widget.markdown,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal editor dialog
// ─────────────────────────────────────────────────────────────────────────────

class _MarkdownNoteEditorDialog extends StatefulWidget {
  const _MarkdownNoteEditorDialog({required this.panel});

  final BoardPanelInstance panel;

  @override
  State<_MarkdownNoteEditorDialog> createState() =>
      _MarkdownNoteEditorDialogState();
}

class _MarkdownNoteEditorDialogState extends State<_MarkdownNoteEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _mdCtrl;
  Color? _selectedColor;
  bool _isPreview = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.panel.title);
    _mdCtrl = TextEditingController(
      text: widget.panel.state['markdown'] as String? ?? '',
    );
    _selectedColor = widget.panel.color;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _mdCtrl.dispose();
    super.dispose();
  }

  void _wrapSelection(String before, String after, String placeholder) {
    final value = _mdCtrl.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    final selected = start < end ? value.text.substring(start, end) : '';
    final replacement =
        '$before${selected.isEmpty ? placeholder : selected}$after';
    final updated = value.text.replaceRange(start, end, replacement);
    setState(() {
      _mdCtrl.value = value.copyWith(
        text: updated,
        selection: TextSelection.collapsed(offset: start + replacement.length),
      );
    });
  }

  void _prefixLines(String prefix) {
    final value = _mdCtrl.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    final block = start < end ? value.text.substring(start, end) : '';
    final source = block.isEmpty ? 'item' : block;
    final replacement = source
        .split('\n')
        .map((line) => line.isEmpty ? prefix.trimRight() : '$prefix$line')
        .join('\n');
    final updated = value.text.replaceRange(start, end, replacement);
    setState(() {
      _mdCtrl.value = value.copyWith(
        text: updated,
        selection: TextSelection.collapsed(offset: start + replacement.length),
      );
    });
  }

  Future<void> _pickColor() async {
    Color picked = _selectedColor ?? const Color(0xFFB46CFF);
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Panel color'),
            content: ColorPicker(
              pickerColor: picked,
              onColorChanged: (c) => picked = c,
              enableAlpha: false,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() => _selectedColor = picked);
                  Navigator.of(ctx).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.panel.id.isEmpty
            ? 'Add markdown note'
            : 'Edit markdown note',
      ),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            // ── Toolbar ─────────────────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToolBtn(
                    icon: Icons.title,
                    tooltip: 'Heading',
                    onTap: () => _prefixLines('# '),
                  ),
                  _ToolBtn(
                    icon: Icons.format_bold,
                    tooltip: 'Bold',
                    onTap: () => _wrapSelection('**', '**', 'bold'),
                  ),
                  _ToolBtn(
                    icon: Icons.format_italic,
                    tooltip: 'Italic',
                    onTap: () => _wrapSelection('*', '*', 'italic'),
                  ),
                  _ToolBtn(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Bullet list',
                    onTap: () => _prefixLines('- '),
                  ),
                  _ToolBtn(
                    icon: Icons.check_box_outlined,
                    tooltip: 'Checklist',
                    onTap: () => _prefixLines('- [ ] '),
                  ),
                  _ToolBtn(
                    icon: Icons.link,
                    tooltip: 'Link',
                    onTap:
                        () =>
                            _wrapSelection('[', '](https://)', 'text'),
                  ),
                  _ToolBtn(
                    icon: Icons.code,
                    tooltip: 'Code block',
                    onTap:
                        () =>
                            _wrapSelection('```\n', '\n```', 'code'),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _pickColor,
                    borderRadius: BorderRadius.circular(999),
                    child: Tooltip(
                      message: 'Panel color',
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              _selectedColor ??
                              const Color(0xFFB46CFF),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withAlpha(90),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.edit_outlined),
                        label: Text('Write'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.preview_outlined),
                        label: Text('Preview'),
                      ),
                    ],
                    selected: {_isPreview},
                    onSelectionChanged: (sel) =>
                        setState(() => _isPreview = sel.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── Editor / Preview ────────────────────────────────────────────
            Container(
              height: 360,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  _isPreview
                      ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: MarkdownBody(
                          data:
                              _mdCtrl.text.isEmpty
                                  ? '*Empty note*'
                                  : _mdCtrl.text,
                        ),
                      )
                      : TextField(
                        controller: _mdCtrl,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                          hintText: 'Write your markdown note here…',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.of(context).pop({
                '_title': _titleCtrl.text.trim(),
                '_color': _selectedColor?.toARGB32(),
                'markdown': _mdCtrl.text,
              }),
          child: Text(
            widget.panel.id.isEmpty ? 'Add' : 'Save',
          ),
        ),
      ],
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
    );
  }
}
