import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

class ToolsDialog extends StatelessWidget {
  const ToolsDialog({
    super.key,
    required this.initialDisabled,
    required this.onPersist,
  });

  final Set<String> initialDisabled;
  final ValueChanged<Set<String>> onPersist;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = colors.textMuted.withAlpha(153);
    final tools = [...YoloitCliToolCatalog.tools]..sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      return byGroup == 0 ? a.command.compareTo(b.command) : byGroup;
    });

    return _ToolsDialogContent(
      tools: tools,
      initialDisabled: initialDisabled,
      muted: muted,
      colors: colors,
      onPersist: onPersist,
    );
  }
}

class _ToolsDialogContent extends StatefulWidget {
  const _ToolsDialogContent({
    required this.tools,
    required this.initialDisabled,
    required this.muted,
    required this.colors,
    required this.onPersist,
  });

  final List<YoloitCliTool> tools;
  final Set<String> initialDisabled;
  final Color muted;
  final AppColorScheme colors;
  final ValueChanged<Set<String>> onPersist;

  @override
  State<_ToolsDialogContent> createState() => _ToolsDialogContentState();
}

class _ToolsDialogContentState extends State<_ToolsDialogContent> {
  late Set<String> _disabled;

  @override
  void initState() {
    super.initState();
    _disabled = {...widget.initialDisabled};
  }

  void _persist(Set<String> next) {
    setState(() => _disabled = {...next});
    widget.onPersist(_disabled);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<YoloitCliTool>>{};
    for (final tool in widget.tools) {
      grouped.putIfAbsent(tool.group, () => []).add(tool);
    }

    Widget tile(YoloitCliTool tool) {
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
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (tool.destructive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withAlpha(28),
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
          style: TextStyle(fontSize: 11, color: widget.muted),
        ),
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_input_component_outlined),
          const SizedBox(width: 8),
          const Expanded(child: Text('YoLo tools')),
          Text(
            '${widget.tools.length - _disabled.length}/${widget.tools.length}',
            style: TextStyle(fontSize: 12, color: widget.muted),
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
              'Checked tools are available to YoLo Chat. Unchecked tools are hidden from the local LLM and blocked at runtime.',
              style: TextStyle(fontSize: 12, color: widget.muted),
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
                          color: widget.colors.primary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    ...entry.value.map(tile),
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
              for (final tool in widget.tools) tool.functionName,
            };
            _persist(next);
          },
          child: const Text('Disable all'),
        ),
        TextButton(
          onPressed: () {
            final next = {
              for (final tool in widget.tools)
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
