import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/ui/components/input/labeled_text_field.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

/// Dialog for picking ASR configuration (Default / Local / Cloud + Provider + Model).
class AsrPickerDialog extends StatefulWidget {
  const AsrPickerDialog({
    super.key,
    required this.showDefaultOption,
    required this.initialMode,
    required this.initialConfigId,
    required this.initialModel,
    required this.cloudConfigs,
  });

  final bool showDefaultOption;
  final String initialMode;
  final String? initialConfigId;
  final String? initialModel;
  final List<CloudLlmConfig> cloudConfigs;

  @override
  State<AsrPickerDialog> createState() => AsrPickerDialogState();
}

class AsrPickerDialogState extends State<AsrPickerDialog> {
  late String _mode;
  String? _configId;
  String? _model;
  late TextEditingController _customModelCtrl;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _configId = widget.initialConfigId;
    _model = widget.initialModel;
    _customModelCtrl = TextEditingController(text: widget.initialModel ?? '');
  }

  @override
  void dispose() {
    _customModelCtrl.dispose();
    super.dispose();
  }

  List<({String id, String name})> get _catalogModels {
    if (_configId == null) return const [];
    final cfg = widget.cloudConfigs.where((c) => c.id == _configId).firstOrNull;
    if (cfg == null) return const [];
    return kCloudLlmPresets.where((p) => p.id == cfg.id).firstOrNull?.models ??
        const [];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isCloud = _mode == 'cloud';
    final catalog = _catalogModels;

    final inputDecoration = outlineInputDecoration(
      colors: colors,
      focused: false,
    );

    return AlertDialog(
      title: const Text('ASR Configuration', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode selector
            Text(
              'Mode',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                if (widget.showDefaultOption)
                  const ButtonSegment(value: 'default', label: Text('Default')),
                const ButtonSegment(value: 'local', label: Text('Local')),
                const ButtonSegment(value: 'cloud', label: Text('Cloud')),
              ],
              selected: {_mode},
              onSelectionChanged:
                  (v) => setState(() {
                    _mode = v.first;
                  }),
            ),
            if (isCloud) ...[
              const SizedBox(height: 16),
              // Provider
              Text(
                'Provider',
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value:
                    widget.cloudConfigs.any((c) => c.id == _configId)
                        ? _configId
                        : null,
                isExpanded: true,
                hint: Text(
                  'Select provider',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appColors.textMuted,
                  ),
                ),
                items:
                    widget.cloudConfigs
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.id,
                            child: Text(
                              c.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                onChanged:
                    (v) => setState(() {
                      _configId = v;
                      _model = null;
                      _customModelCtrl.clear();
                    }),
                dropdownColor: colors.surfaceElevated,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                ),
                decoration: inputDecoration,
              ),
              const SizedBox(height: 12),
              // Model
              Text(
                'Model',
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              if (catalog.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: catalog.any((m) => m.id == _model) ? _model : null,
                  isExpanded: true,
                  hint: Text(
                    'Select model',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appColors.textMuted,
                    ),
                  ),
                  items:
                      catalog
                          .map(
                            (m) => DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(
                                m.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged:
                      (v) => setState(() {
                        _model = v;
                        _customModelCtrl.text = v ?? '';
                      }),
                  dropdownColor: colors.surfaceElevated,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  decoration: inputDecoration,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customModelCtrl,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  decoration: inputDecoration.copyWith(
                    hintText: 'Custom model ID (overrides selection above)',
                  ),
                  onChanged: (v) => _model = v.trim().isEmpty ? null : v.trim(),
                ),
              ] else
                TextField(
                  controller: _customModelCtrl,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  decoration: inputDecoration.copyWith(
                    hintText: 'e.g. whisper-1',
                  ),
                  onChanged: (v) => _model = v.trim().isEmpty ? null : v.trim(),
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
        ElevatedButton(
          onPressed:
              () => Navigator.of(
                context,
              ).pop((mode: _mode, configId: _configId, model: _model)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
