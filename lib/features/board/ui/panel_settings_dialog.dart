import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

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
                            icon: const Icon(
                              Icons.create_new_folder_outlined,
                              size: 18,
                            ),
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
  const PanelSettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

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
  const PanelSettingsInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: textTheme.labelMedium),
          ),
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
