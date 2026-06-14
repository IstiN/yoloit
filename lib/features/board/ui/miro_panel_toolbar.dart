import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/ui/components/menus/miro_toolbar_primitives.dart';

class MiroPanelToolbar extends StatelessWidget {
  const MiroPanelToolbar({
    super.key,
    required this.maxWidth,
    required this.panel,
    required this.plugin,
    required this.canEdit,
    required this.onEdit,
    required this.onEditColor,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onDelete,
    required this.onToggleLocked,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onSettings,
    required this.onUpdateState,
  });

  final double maxWidth;
  final BoardPanelInstance panel;
  final BoardPanelPlugin? plugin;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback onEditColor;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onDelete;
  final VoidCallback onToggleLocked;
  final ValueChanged<DragStartDetails> onMoveStart;
  final ValueChanged<DragUpdateDetails>? onMoveUpdate;
  final VoidCallback onMoveEnd;
  final VoidCallback onSettings;
  final ValueChanged<Map<String, dynamic>>? onUpdateState;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: 42,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 6),
                  MiroToolbarDragIcon(
                    tooltip: panel.locked ? 'Panel is locked' : 'Move panel',
                    onStart: onMoveStart,
                    onUpdate: onMoveUpdate,
                    onEnd: onMoveEnd,
                    color: textColor,
                  ),
                  ..._buildPluginQuickControls(context, colors, textColor),
                  if (canEdit && onEdit != null)
                    MiroToolbarIcon(
                      tooltip:
                          plugin?.hasEditor == true ? 'Panel settings' : 'Edit',
                      icon:
                          plugin?.hasEditor == true
                              ? Icons.tune_rounded
                              : Icons.edit_outlined,
                      onTap: onEdit!,
                      color: textColor,
                    ),
                  MiroToolbarIcon(
                    tooltip: 'Panel color',
                    icon: Icons.format_color_fill_outlined,
                    onTap: onEditColor,
                    color: textColor,
                    swatch: panel.color,
                  ),
                  MiroToolbarDivider(colors: colors),
                  MiroToolbarIcon(
                    tooltip: panel.locked ? 'Unlock panel' : 'Lock panel',
                    icon:
                        panel.locked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                    onTap: onToggleLocked,
                    color: textColor,
                  ),
                  MiroToolbarIcon(
                    tooltip: 'Bring to front',
                    icon: Icons.flip_to_front_outlined,
                    onTap: onBringToFront,
                    color: textColor,
                  ),
                  MiroToolbarIcon(
                    tooltip: 'Send to back',
                    icon: Icons.flip_to_back_outlined,
                    onTap: onSendToBack,
                    color: textColor,
                  ),
                  MiroToolbarDivider(colors: colors),
                  MiroToolbarIcon(
                    tooltip: 'More panel settings',
                    icon: Icons.more_vert_rounded,
                    onTap: onSettings,
                    color: textColor,
                  ),
                  MiroToolbarIcon(
                    tooltip: 'Remove panel',
                    icon: Icons.close_rounded,
                    onTap: onDelete,
                    color: textColor,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPluginQuickControls(
    BuildContext context,
    AppColorScheme colors,
    Color textColor,
  ) {
    final update = onUpdateState;
    if (update == null) return const [];

    void updateState(Map<String, dynamic> patch) {
      update({...panel.state, ...patch});
    }

    if (panel.type == 'board.sticky') {
      final fontSize = (panel.state['fontSize'] as num?)?.round() ?? 18;
      final noteColor =
          parseHexColor(panel.state['color'] as String?) ??
          const Color(0xFFFEF08A);
      final stickyTextColor =
          parseHexColor(panel.state['textColor'] as String?) ??
          const Color(0xFF1F2937);
      return [
        MiroToolbarDivider(colors: colors),
        MiroToolbarIcon(
          tooltip: 'Sticky note',
          icon: Icons.sticky_note_2_outlined,
          onTap: onEdit ?? onSettings,
          color: textColor,
        ),
        MiroToolbarValueMenu<int>(
          tooltip: 'Text size',
          valueLabel: fontSize.toString(),
          values: const [14, 16, 18, 20, 24, 28, 32, 36],
          itemLabel: (value) => value.toString(),
          onSelected: (value) => updateState({'fontSize': value.toDouble()}),
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
          onSelected:
              (value) => updateState({'textColor': miroToolbarHex(value)}),
          onCustomSelected:
              (initial) => showMiroToolbarCustomColor(context, initial),
        ),
        MiroToolbarColorMenu(
          tooltip: 'Sticky color',
          icon: Icons.format_color_fill_outlined,
          selected: noteColor,
          colors: const [
            Color(0xFFFEF08A),
            Color(0xFFFDE68A),
            Color(0xFFFCA5A5),
            Color(0xFFF9A8D4),
            Color(0xFFC4B5FD),
            Color(0xFF93C5FD),
            Color(0xFF86EFAC),
            Color(0xFFFFFFFF),
          ],
          onSelected: (value) => updateState({'color': miroToolbarHex(value)}),
          onCustomSelected:
              (initial) => showMiroToolbarCustomColor(context, initial),
        ),
      ];
    }

    if (panel.type == 'board.shape') {
      final shape = panel.state['shape'] as String? ?? 'rectangle';
      final fontSize = (panel.state['fontSize'] as num?)?.round() ?? 18;
      final strokeWidth = (panel.state['strokeWidth'] as num?)?.round() ?? 3;
      final textHAlign = panel.state['textHAlign'] as String? ?? 'center';
      final textVAlign = panel.state['textVAlign'] as String? ?? 'center';
      final textOrientation =
          panel.state['textOrientation'] as String? ?? 'horizontal';
      final strokeColor =
          parseHexColor(panel.state['strokeColor'] as String?) ??
          const Color(0xFF93C5FD);
      final fillColor =
          parseHexColor(panel.state['fillColor'] as String?) ??
          Colors.transparent;
      return [
        MiroToolbarDivider(colors: colors),
        MiroToolbarShapeMenu(
          selectedShape: shape,
          onSelected: (value) => updateState({'shape': value}),
        ),
        MiroToolbarValueMenu<int>(
          tooltip: 'Text size',
          valueLabel: fontSize.toString(),
          values: const [12, 14, 16, 18, 20, 24, 28, 32, 36],
          itemLabel: (value) => value.toString(),
          onSelected: (value) => updateState({'fontSize': value.toDouble()}),
        ),
        MiroToolbarValueMenu<int>(
          tooltip: 'Stroke width',
          valueLabel: strokeWidth.toString(),
          values: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
          itemLabel: (value) => 'Stroke $value',
          onSelected: (value) => updateState({'strokeWidth': value.toDouble()}),
        ),
        MiroToolbarColorMenu(
          tooltip: 'Text and stroke color',
          icon: Icons.format_color_text_rounded,
          selected: strokeColor,
          colors: const [
            Color(0xFF111827),
            Color(0xFF93C5FD),
            Color(0xFFA78BFA),
            Color(0xFFF472B6),
            Color(0xFFFBBF24),
            Color(0xFF34D399),
            Color(0xFFF87171),
            Color(0xFFE2E8F0),
          ],
          onSelected:
              (value) => updateState({
                'strokeColor': miroToolbarHex(value),
                'textColor': miroToolbarHex(value),
              }),
          onCustomSelected:
              (initial) => showMiroToolbarCustomColor(context, initial),
        ),
        MiroToolbarColorMenu(
          tooltip: 'Fill color',
          icon: Icons.format_color_fill_outlined,
          selected: fillColor,
          colors: const [
            Colors.transparent,
            Color(0xFF93C5FD),
            Color(0xFFA78BFA),
            Color(0xFFF472B6),
            Color(0xFFFBBF24),
            Color(0xFF34D399),
            Color(0xFFF87171),
            Color(0xFFFFFFFF),
          ],
          onSelected:
              (value) => updateState({'fillColor': miroToolbarHex(value)}),
          onCustomSelected:
              (initial) => showMiroToolbarCustomColor(context, initial),
        ),
        MiroToolbarIconValueMenu<String>(
          tooltip: 'Horizontal text alignment',
          icon: miroToolbarHorizontalAlignIcon(textHAlign),
          values: const ['left', 'center', 'right'],
          itemLabel: miroToolbarHorizontalAlignLabel,
          itemIcon: miroToolbarHorizontalAlignIcon,
          onSelected: (value) => updateState({'textHAlign': value}),
        ),
        MiroToolbarIconValueMenu<String>(
          tooltip: 'Vertical text alignment',
          icon: miroToolbarVerticalAlignIcon(textVAlign),
          values: const ['top', 'center', 'bottom'],
          itemLabel: miroToolbarVerticalAlignLabel,
          itemIcon: miroToolbarVerticalAlignIcon,
          onSelected: (value) => updateState({'textVAlign': value}),
        ),
        MiroToolbarIconValueMenu<String>(
          tooltip: 'Text orientation',
          icon: miroToolbarTextOrientationIcon(textOrientation),
          values: const ['horizontal', 'vertical'],
          itemLabel: miroToolbarTextOrientationLabel,
          itemIcon: miroToolbarTextOrientationIcon,
          onSelected: (value) => updateState({'textOrientation': value}),
        ),
        MiroToolbarIcon(
          tooltip: 'Custom text settings',
          icon: Icons.text_fields_rounded,
          onTap: onEdit ?? onSettings,
          color: textColor,
        ),
      ];
    }

    return const [];
  }
}

class PanelSettingsDialog extends StatelessWidget {
  const PanelSettingsDialog({
    super.key,
    required this.panel,
    required this.plugin,
    required this.onEditColor,
    required this.onBringToFront,
    required this.onSendToBack,
    this.onEditPanel,
  });

  final BoardPanelInstance panel;
  final BoardPanelPlugin? plugin;
  final VoidCallback onEditColor;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback? onEditPanel;

  @override
  Widget build(BuildContext context) {
    final board = context.read<BoardCubit>().state.activeBoard;
    BoardPanelGroup? currentGroup;
    if (board != null) {
      for (final group in board.groups) {
        if (group.panelIds.contains(panel.id)) {
          currentGroup = group;
          break;
        }
      }
    }
    final otherGroups = <BoardPanelGroup>[];
    if (board != null) {
      for (final group in board.groups) {
        if (group.id != currentGroup?.id) {
          otherGroups.add(group);
        }
      }
    }

    return AdaptiveDialogScaffold(
      title: 'Panel settings',
      icon: Icon(plugin?.icon ?? Icons.dashboard_customize_outlined),
      maxWidth: 460,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelSettingsSection(
              title: 'Panel',
              children: [
                PanelSettingsInfoRow(label: 'Title', value: panel.title),
                PanelSettingsInfoRow(
                  label: 'Type',
                  value: plugin?.displayName ?? panel.type,
                ),
                PanelSettingsInfoRow(
                  label: 'Depth',
                  value: 'zIndex ${panel.zIndex}',
                ),
              ],
            ),
            const SizedBox(height: 18),
            PanelSettingsSection(
              title: 'Appearance',
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onEditColor,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('Panel color'),
                    ),
                    if (onEditPanel != null)
                      OutlinedButton.icon(
                        onPressed: onEditPanel,
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: Text(
                          plugin?.hasEditor == true
                              ? '${plugin?.displayName ?? 'Content'} settings'
                              : 'Edit content',
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            PanelSettingsSection(
              title: 'Arrange',
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onBringToFront,
                      icon: const Icon(Icons.flip_to_front_outlined, size: 18),
                      label: const Text('Bring to front'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onSendToBack,
                      icon: const Icon(Icons.flip_to_back_outlined, size: 18),
                      label: const Text('Send to back'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            PanelSettingsSection(
              title: 'Group',
              children: [
                if (currentGroup != null)
                  Builder(
                    builder: (context) {
                      final group = currentGroup!;
                      return Row(
                        children: [
                          Expanded(
                            child: PanelSettingsInfoRow(
                              label: 'In group',
                              value: group.name,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              final cubit = context.read<BoardCubit>();
                              final boardId = board?.id;
                              if (boardId == null) return;
                              cubit.removePanelsFromGroup(
                                boardId,
                                group.id,
                                [panel.id],
                              );
                              Navigator.of(context).maybePop();
                            },
                            icon: const Icon(Icons.link_off_outlined, size: 18),
                            label: const Text('Remove'),
                          ),
                        ],
                      );
                    },
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              final cubit = context.read<BoardCubit>();
                              final boardId = board?.id;
                              final name = await _showGroupNameDialog(context);
                              if (name == null || name.isEmpty) return;
                              if (boardId == null) return;
                              await cubit.createGroup(
                                boardId,
                                name: name,
                                panelIds: [panel.id],
                              );
                              navigator.maybePop();
                            },
                            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                            label: const Text('New group'),
                          ),
                          if (otherGroups.isNotEmpty)
                            _ExistingGroupDropdown(
                              groups: otherGroups,
                              onSelected: (groupId) {
                                final cubit = context.read<BoardCubit>();
                                final boardId = board?.id;
                                if (boardId == null) return;
                                cubit.addPanelsToGroup(
                                  boardId,
                                  groupId,
                                  [panel.id],
                                );
                                Navigator.of(context).maybePop();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<String?> _showGroupNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showAdaptiveYoloDialog<String?>(
      context: context,
      builder:
          (dialogContext) => AdaptiveDialogScaffold(
            title: 'New group',
            icon: const Icon(Icons.create_new_folder_outlined),
            maxWidth: 360,
            body: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.of(dialogContext).pop(
                      controller.text.trim(),
                    ),
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }
}

class _ExistingGroupDropdown extends StatelessWidget {
  const _ExistingGroupDropdown({required this.groups, required this.onSelected});

  final List<BoardPanelGroup> groups;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        hint: const Text('Add to group'),
        items:
            groups.map((group) {
              return DropdownMenuItem<String>(
                value: group.id,
                child: Text(group.name),
              );
            }).toList(),
        onChanged: (value) {
          if (value != null) onSelected(value);
        },
      ),
    );
  }
}

class PanelSettingsSection extends StatelessWidget {
  const PanelSettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class PanelSettingsInfoRow extends StatelessWidget {
  const PanelSettingsInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: textTheme.labelMedium)),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
