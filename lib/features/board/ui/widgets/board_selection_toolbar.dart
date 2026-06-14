import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Floating toolbar shown when one or more panels are selected.
class BoardSelectionToolbar extends StatelessWidget {
  const BoardSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.onAddToGroup,
    required this.onClear,
  });

  final int selectedCount;
  final VoidCallback onAddToGroup;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : colors.surfaceElevated;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withAlpha(0xF2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withAlpha(180)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isLight ? 18 : 70),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$selectedCount selected',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.folder_copy_outlined, size: 16),
            label: const Text('Add to group'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: onAddToGroup,
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            tooltip: 'Clear selection',
            onPressed: onClear,
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Dialog that lets the user create a new group from the current selection
/// or add the selected panels to an existing group.
class BoardSelectionGroupDialog extends StatefulWidget {
  const BoardSelectionGroupDialog({
    super.key,
    required this.groups,
    this.initialName = 'New Group',
  });

  final List<BoardPanelGroup> groups;
  final String initialName;

  @override
  State<BoardSelectionGroupDialog> createState() =>
      _BoardSelectionGroupDialogState();
}

class _BoardSelectionGroupDialogState
    extends State<BoardSelectionGroupDialog> {
  late final TextEditingController _nameController;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = _nameController.text.trim();
    final existingSelected = _selectedGroupId != null;
    final canSubmit = existingSelected || name.isNotEmpty;

    return AlertDialog(
      title: const Text('Add selection to group'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'New group name',
                hintText: 'Enter group name',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.groups.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Or add to existing group',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in widget.groups)
                    ChoiceChip(
                      label: Text(group.name),
                      selected: _selectedGroupId == group.id,
                      onSelected: (selected) {
                        setState(() {
                          _selectedGroupId = selected ? group.id : null;
                        });
                      },
                    ),
                ],
              ),
            ],
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
              canSubmit
                  ? () {
                    Navigator.of(context).pop<
                      ({String? groupId, String? newName})?>(
                      (
                        groupId: _selectedGroupId,
                        newName: existingSelected ? null : name,
                      ),
                    );
                  }
                  : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
