import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

/// Dialog for enabling / disabling local YoLoIT CLI tools exposed to the LLM.
class LocalToolsDialog extends StatefulWidget {
  const LocalToolsDialog({
    super.key,
    required this.disabledToolNames,
    required this.enabledCount,
    required this.onChanged,
  });

  final Set<String> disabledToolNames;
  final int enabledCount;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<LocalToolsDialog> createState() => _LocalToolsDialogState();
}

class _LocalToolsDialogState extends State<LocalToolsDialog> {
  late Set<String> _disabled;

  @override
  void initState() {
    super.initState();
    _disabled = {...widget.disabledToolNames};
  }

  void _persist(Set<String> next) {
    setState(() => _disabled = {...next});
    widget.onChanged(next);
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

    Widget buildToolTile(YoloitCliTool tool) {
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
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

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_input_component_outlined),
          const SizedBox(width: 8),
          const Expanded(child: Text('YoLo Chat tools')),
          Text(
            '${widget.enabledCount}/${tools.length}',
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
              'Checked tools are exposed to the local LLM. Unchecked tools are removed from the tool schema and blocked if the model still tries to call them.',
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
                    ...entry.value.map(buildToolTile),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _persist(<String>{}),
          child: const Text('Enable all'),
        ),
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
      ],
    );
  }
}
