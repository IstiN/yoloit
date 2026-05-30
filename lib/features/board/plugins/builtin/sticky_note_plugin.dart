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
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final text = panel.state['text'] as String? ?? '';
    final colors = context.appColors;
    final color =
        _parseHex(panel.state['color'] as String?) ??
        colors.accentOrange.withValues(alpha: 0.85);
    final textColor =
        _parseHex(panel.state['textColor'] as String?) ??
        Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: color,
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
        child: SingleChildScrollView(
          child: Text(
            text.trim().isEmpty ? 'Sticky note' : text,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
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
