import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/tool_call_settings_service.dart';

class IgnoredToolCallsSection extends StatefulWidget {
  const IgnoredToolCallsSection({super.key});

  @override
  State<IgnoredToolCallsSection> createState() =>
      IgnoredToolCallsSectionState();
}

class IgnoredToolCallsSectionState extends State<IgnoredToolCallsSection> {
  final _service = ToolCallSettingsService.instance;
  final _controller = TextEditingController();
  Set<String> _ignored = const {'report_intent'};

  @override
  void initState() {
    super.initState();
    _service.load().then((_) {
      if (!mounted) return;
      setState(() => _ignored = _service.ignoredTools);
    });
    _service.ignoredToolsListenable.addListener(_onIgnoredChanged);
  }

  @override
  void dispose() {
    _service.ignoredToolsListenable.removeListener(_onIgnoredChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onIgnoredChanged() {
    if (!mounted) return;
    setState(() => _ignored = _service.ignoredTools);
  }

  Future<void> _addTool() async {
    final value = _controller.text.trim().toLowerCase();
    if (value.isEmpty) return;
    final next = {..._ignored, value};
    _controller.clear();
    await _service.setIgnoredTools(next);
  }

  Future<void> _removeTool(String toolName) async {
    final next = {..._ignored}..remove(toolName);
    await _service.setIgnoredTools(next);
  }

  Future<void> _resetDefault() async {
    await _service.setIgnoredTools({'report_intent'});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        color: colors.surfaceElevated.withAlpha(60),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tool calls in this list are hidden from chat results and running-status cards.',
            style: TextStyle(color: context.appColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                _ignored
                    .map(
                      (tool) => Chip(
                        label: Text(tool, style: const TextStyle(fontSize: 11)),
                        onDeleted: () => _removeTool(tool),
                        deleteIcon: const Icon(Icons.close, size: 14),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'tool name (e.g. report_intent)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addTool(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _addTool, child: const Text('Add')),
              TextButton(onPressed: _resetDefault, child: const Text('Reset')),
            ],
          ),
        ],
      ),
    );
  }
}
