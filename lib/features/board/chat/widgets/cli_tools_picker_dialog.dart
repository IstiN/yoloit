import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

/// Shared dialog for enabling / disabling YoLoIT CLI tools.
///
/// Used by both the assistant panel ([ToolsDialog] wrapper) and the chat
/// panel ([LocalToolsDialog] wrapper).
class CliToolsPickerDialog extends StatefulWidget {
  const CliToolsPickerDialog({
    super.key,
    required this.initialDisabled,
    required this.onPersist,
    this.title = 'YoLo tools',
    this.description,
    this.showEnableAll = true,
    this.showDisableAll = true,
    this.showDisableDestructive = true,
    this.enabledCount,
  });

  final Set<String> initialDisabled;
  final ValueChanged<Set<String>> onPersist;
  final String title;
  final String? description;
  final bool showEnableAll;
  final bool showDisableAll;
  final bool showDisableDestructive;

  /// Pre-computed enabled count. When `null` the dialog computes
  /// `total - disabled.length` internally.
  final int? enabledCount;

  @override
  State<CliToolsPickerDialog> createState() => _CliToolsPickerDialogState();
}

class _CliToolsPickerDialogState extends State<CliToolsPickerDialog> {
  late Set<String> _disabled;

  @override
  void initState() {
    super.initState();
    _disabled = {...widget.initialDisabled};
  }

  void _persist(Set<String> next) {
    setState(() => _disabled = {...next});
    widget.onPersist(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = colors.textMuted.withAlpha(153);
    final tools = [...YoloitCliToolCatalog.tools]..sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      return byGroup == 0 ? a.command.compareTo(b.command) : byGroup;
    });

    final grouped = <String, List<YoloitCliTool>>{};
    for (final tool in tools) {
      grouped.putIfAbsent(tool.group, () => []).add(tool);
    }

    final countText = widget.enabledCount != null
        ? '${widget.enabledCount}/${tools.length}'
        : '${tools.length - _disabled.length}/${tools.length}';

    Widget buildTile(YoloitCliTool tool) {
      final enabled = !_disabled.contains(tool.functionName);
      return CheckboxListTile(
        dense: true,
        value: enabled,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        onChanged: (value) {
          final next = {..._disabled};
          if (value == true) {
            next.remove(tool.functionName);
          } else {
            next.add(tool.functionName);
          }
          _persist(next);
        },
        title: Row(
          children: [
            Expanded(
              child: Text(
                'yoloit ${tool.command}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (tool.destructive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withAlpha(31),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'destructive',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${tool.functionName}\n${tool.description}',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      );
    }

    final actions = <Widget>[
      if (widget.showEnableAll)
        TextButton(
          onPressed: () => _persist(<String>{}),
          child: const Text('Enable all'),
        ),
      if (widget.showDisableAll)
        TextButton(
          onPressed: () {
            final next = {
              for (final tool in tools) tool.functionName,
            };
            _persist(next);
          },
          child: const Text('Disable all'),
        ),
      if (widget.showDisableDestructive)
        TextButton(
          onPressed: () {
            final next = {
              for (final tool in tools)
                if (tool.destructive) tool.functionName,
            };
            _persist(next);
          },
          child: const Text('Disable destructive'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      ),
    ];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_input_component_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
          Text(
            countText,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.description ??
                  'Checked tools are available to YoLo Chat. '
                  'Unchecked tools are hidden from the local LLM and blocked '
                  'at runtime.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  for (final entry in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    ...entry.value.map(buildTile),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: actions,
    );
  }
}
