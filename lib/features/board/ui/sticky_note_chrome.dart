import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';
import 'package:yoloit/ui/components/buttons/header_icon_button.dart';
import 'package:yoloit/ui/components/menus/miro_toolbar_primitives.dart';
import 'package:yoloit/ui/components/menus/panel_overflow_menu.dart';

/// Compact floating chrome for sticky notes.
///
/// Appears above a sticky note when the note is selected, providing formatting
/// and panel-level actions without turning the note into a boxed panel.
class StickyNoteChrome extends StatelessWidget {
  const StickyNoteChrome({
    required this.panel,
    required this.locked,
    required this.onUpdateState,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDuplicate,
    required this.onToggleLocked,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onSettings,
    required this.onDelete,
    super.key,
  });

  final BoardPanelInstance panel;
  final bool locked;
  final ValueChanged<Map<String, dynamic>> onUpdateState;
  final ValueChanged<DragStartDetails> onDragStart;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final FutureOr<void> Function() onDragEnd;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleLocked;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onSettings;
  final VoidCallback onDelete;

  void _updateState(Map<String, dynamic> patch) {
    onUpdateState({...panel.state, ...patch});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final fontSize = (panel.state['fontSize'] as num?)?.round() ?? 18;
    final isShape = panel.type == ShapePlugin.kTypeId;
    final stickyTextColor =
        parseHexColor(panel.state['textColor'] as String?) ??
        (isShape ? const Color(0xFFE2E8F0) : const Color(0xFF1F2937));
    final surfaceColor =
        isShape
            ? (parseHexColor(panel.state['strokeColor'] as String?) ??
                const Color(0xFF93C5FD))
            : (parseHexColor(panel.state['color'] as String?) ??
                const Color(0xFFFEF08A));
    final surfaceTooltip = isShape ? 'Border color' : 'Sticky color';
    final surfaceColors =
        isShape
            ? const [
              Color(0xFF93C5FD),
              Color(0xFFA78BFA),
              Color(0xFFF472B6),
              Color(0xFFFBBF24),
              Color(0xFF34D399),
              Color(0xFFF87171),
              Color(0xFFE2E8F0),
            ]
            : const [
              Color(0xFFFEF08A),
              Color(0xFFFDE68A),
              Color(0xFFFCA5A5),
              Color(0xFFF9A8D4),
              Color(0xFFC4B5FD),
              Color(0xFF93C5FD),
              Color(0xFF86EFAC),
              Color(0xFFFFFFFF),
            ];
    final surfaceStateKey = isShape ? 'strokeColor' : 'color';

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          height: 38,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 4),
                MiroToolbarDragIcon(
                  tooltip:
                      locked
                          ? (isShape ? 'Shape is locked' : 'Sticky note is locked')
                          : (isShape ? 'Move shape' : 'Move sticky note'),
                  onStart: onDragStart,
                  onUpdate: onDragUpdate,
                  onEnd: onDragEnd,
                  color: textColor,
                ),
                MiroToolbarValueMenu<int>(
                  tooltip: 'Text size',
                  valueLabel: fontSize.toString(),
                  values: const [14, 16, 18, 20, 24, 28, 32, 36],
                  itemLabel: (value) => value.toString(),
                  onSelected: (value) => _updateState({'fontSize': value.toDouble()}),
                ),
                MiroToolbarColorMenu(
                  tooltip: 'Text color',
                  icon: Icons.format_color_text_rounded,
                  selected: stickyTextColor,
                  colors: const [
                    Color(0xFF111827),
                    Color(0xFF1F2937),
                    Color(0xFFFFFFFF),
                    Color(0xFF2563EB),
                    Color(0xFFF59E0B),
                    Color(0xFF10B981),
                    Color(0xFFEC4899),
                  ],
                  onSelected: (value) => _updateState({'textColor': miroToolbarHex(value)}),
                  onCustomSelected: (initial) => showMiroToolbarCustomColor(context, initial),
                ),
                MiroToolbarColorMenu(
                  tooltip: surfaceTooltip,
                  icon:
                      isShape
                          ? Icons.border_color_outlined
                          : Icons.format_color_fill_outlined,
                  selected: surfaceColor,
                  colors: surfaceColors,
                  onSelected:
                      (value) => _updateState({surfaceStateKey: miroToolbarHex(value)}),
                  onCustomSelected: (initial) => showMiroToolbarCustomColor(context, initial),
                ),
                MiroToolbarDivider(colors: colors),
                HeaderIconButton(
                  icon: Icons.copy,
                  tooltip:
                      isShape ? 'Duplicate shape' : 'Duplicate sticky note',
                  onPressed: onDuplicate,
                ),
                PanelOverflowMenu(
                  onToggleLocked: onToggleLocked,
                  locked: locked,
                  onBringToFront: onBringToFront,
                  onSendToBack: onSendToBack,
                  onSettings: onSettings,
                  onDelete: onDelete,
                ),
                HeaderIconButton(
                  icon: Icons.close,
                  tooltip: 'Remove',
                  onPressed: onDelete,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
