import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

/// A compact, copyable ID chip with an inline edit action.
class PanelIdChip extends StatelessWidget {
  const PanelIdChip({
    required this.id,
    required this.onEdit,
    required this.onCopy,
    this.label = 'ID',
    super.key,
  });

  final String id;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: '$label: $id\nTap to copy, ✎ to edit',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: onCopy,
            icon: Icon(Icons.fingerprint, size: 12, color: colors.textMuted),
            label: Text(
              id.length > 14 ? '${id.substring(0, 14)}...' : id,
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.edit, size: 12, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
