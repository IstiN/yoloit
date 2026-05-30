import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class StickyNotePlugin extends BoardPanelPlugin {
  const StickyNotePlugin();

  static const String kTypeId = 'board.sticky';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Sticky Note';

  @override
  IconData get icon => Icons.sticky_note_2_outlined;

  @override
  Color get accentColor => Colors.amber;

  @override
  Size get defaultSize => const Size(260, 220);

  @override
  Map<String, dynamic> get initialState => {
    'text': '',
    'color': '#FEF08A',
    'textColor': '#1F2937',
  };

  @override
  bool get usePanelChrome => false;

  @override
  bool get showHeader => false;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final colors = context.appColors;
    final color =
        _parseHex(panel.state['color'] as String?) ??
        colors.accentOrange.withValues(alpha: 0.85);
    final textColor =
        _parseHex(panel.state['textColor'] as String?) ??
        Theme.of(context).colorScheme.onSurface;
    return _StickyNoteContent(
      panel: panel,
      color: color,
      textColor: textColor,
      onChanged: (value) {
        renderContext.onUpdateState({...panel.state, 'text': value});
      },
    );
  }
}

class _StickyNoteContent extends StatefulWidget {
  const _StickyNoteContent({
    required this.panel,
    required this.color,
    required this.textColor,
    required this.onChanged,
  });

  final BoardPanelInstance panel;
  final Color color;
  final Color textColor;
  final ValueChanged<String> onChanged;

  @override
  State<_StickyNoteContent> createState() => _StickyNoteContentState();
}

class _StickyNoteContentState extends State<_StickyNoteContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textFromWidget());
  }

  @override
  void didUpdateWidget(covariant _StickyNoteContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _textFromWidget();
    if (nextText != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _textFromWidget() => widget.panel.state['text'] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: TextField(
          controller: _controller,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Sticky note',
            hintStyle: TextStyle(
              color: widget.textColor.withValues(alpha: 0.55),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            isCollapsed: true,
          ),
          cursorColor: widget.textColor,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

Color? _parseHex(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final cleaned = raw.trim().replaceFirst('#', '');
  if (cleaned.length != 6 && cleaned.length != 8) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  if (cleaned.length == 8) return Color(value);
  return Color.fromARGB(
    255,
    (value >> 16) & 255,
    (value >> 8) & 255,
    value & 255,
  );
}
