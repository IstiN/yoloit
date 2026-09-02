import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

/// Inline field that opens the env group picker and shows the selected
/// groups' names. Kept in its own file (without the settings page import)
/// so lightweight hosts — e.g. the board settings dialog — don't pull the
/// whole settings feature graph into their compilation.
class EnvGroupSelectionField extends StatefulWidget {
  const EnvGroupSelectionField({
    super.key,
    required this.selectedGroupIds,
    required this.onChanged,
    this.label = 'Env Groups',
    this.onOpenSettings,
  });

  final List<String> selectedGroupIds;
  final ValueChanged<List<String>> onChanged;
  final String label;

  /// Forwarded to the picker dialog's empty state ("Open Settings" button).
  final VoidCallback? onOpenSettings;

  @override
  State<EnvGroupSelectionField> createState() => _EnvGroupSelectionFieldState();
}

class _EnvGroupSelectionFieldState extends State<EnvGroupSelectionField> {
  late Future<List<String>> _namesFuture;

  @override
  void initState() {
    super.initState();
    _namesFuture = GlobalEnvGroupsService.instance.resolveSelectedGroupNames(
      widget.selectedGroupIds,
    );
  }

  @override
  void didUpdateWidget(covariant EnvGroupSelectionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedGroupIds.join('\u0000') !=
        widget.selectedGroupIds.join('\u0000')) {
      _namesFuture = GlobalEnvGroupsService.instance.resolveSelectedGroupNames(
        widget.selectedGroupIds,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Caption(widget.label),
        const SizedBox(height: 4),
        FutureBuilder<List<String>>(
          future: _namesFuture,
          builder: (context, snapshot) {
            final names = snapshot.data ?? const <String>[];
            return InkWell(
              onTap: () async {
                final selected = await showEnvGroupPickerDialog(
                  context,
                  initialSelected: widget.selectedGroupIds,
                  onOpenSettings: widget.onOpenSettings,
                );
                if (selected != null) {
                  widget.onChanged(selected);
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: colors.surfaceElevated,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.key_outlined,
                      size: 16,
                      color: colors.accentGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        names.isEmpty
                            ? 'No groups selected'
                            : names.join('  •  '),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              names.isEmpty
                                  ? (context.appColors.textMuted)
                                  : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.selectedGroupIds.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.tune, size: 14, color: context.appColors.textMuted),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
