import 'package:flutter/material.dart';

import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

/// Settings section for managing cloud LLM provider configs.
///
/// Users can add providers from presets (OpenRouter, Gemini, OpenAI) or
/// create fully custom endpoints. Each config stores a base URL, API key,
/// and model selection.
class CloudProvidersSection extends StatefulWidget {
  const CloudProvidersSection({super.key});

  @override
  State<CloudProvidersSection> createState() => _CloudProvidersSectionState();
}

class _CloudProvidersSectionState extends State<CloudProvidersSection> {
  List<CloudLlmConfig> _configs = [];
  String? _activeConfigId;
  String _assistantProviderType = 'local';
  VoiceSettings _voiceSettings = const VoiceSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configs = await CloudLlmSettingsService.instance.loadConfigs();
    final activeId =
        await CloudLlmSettingsService.instance.loadActiveConfigId();
    final providerType =
        await CloudLlmSettingsService.instance.loadAssistantProviderType();
    final vs = await CloudLlmSettingsService.instance.loadVoiceSettings();
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _activeConfigId = activeId;
      _assistantProviderType = providerType;
      _voiceSettings = vs;
      _loading = false;
    });
  }

  Future<void> _setAssistantProviderType(String type) async {
    await CloudLlmSettingsService.instance.saveAssistantProviderType(type);
    if (!mounted) return;
    setState(() => _assistantProviderType = type);
  }

  Future<void> _setActiveConfig(String? id) async {
    await CloudLlmSettingsService.instance.saveActiveConfigId(id);
    if (!mounted) return;
    setState(() => _activeConfigId = id);
  }

  Future<void> _setVoiceSettings(VoiceSettings s) async {
    await CloudLlmSettingsService.instance.saveVoiceSettings(s);
    if (!mounted) return;
    setState(() => _voiceSettings = s);
  }

  Future<void> _deleteConfig(String id) async {
    await CloudLlmSettingsService.instance.removeConfig(id);
    if (id == _activeConfigId) {
      await CloudLlmSettingsService.instance.saveActiveConfigId(null);
    }
    await _load();
  }

  void _showAddPresetDialog() {
    // Only show presets not already configured.
    final existingIds = _configs.map((c) => c.id).toSet();
    final available =
        kCloudLlmPresets.where((p) => !existingIds.contains(p.id)).toList();

    if (available.isEmpty) {
      _showEditConfigDialog(null);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Cloud Provider'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final preset in available)
                  ListTile(
                    title: Text(preset.name),
                    subtitle: Text(
                      preset.defaultModel,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.add, size: 18),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showEditConfigDialog(preset.toConfig(''));
                    },
                  ),
                const Divider(),
                ListTile(
                  title: const Text('Custom endpoint'),
                  subtitle: const Text(
                    'Any OpenAI-compatible API',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showEditConfigDialog(null);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showEditConfigDialog(CloudLlmConfig? initial) {
    final isNew = initial == null || initial.apiKey.isEmpty;
    final idCtrl = TextEditingController(text: initial?.id ?? '');
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final urlCtrl = TextEditingController(text: initial?.baseUrl ?? '');
    final keyCtrl = TextEditingController(text: initial?.apiKey ?? '');
    final modelCtrl = TextEditingController(text: initial?.model ?? '');
    final initialName = initial?.name ?? '';

    // Find preset for model dropdown.
    final preset =
        initial != null
            ? kCloudLlmPresets.where((p) => p.id == initial.id).firstOrNull
            : null;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(isNew ? 'Add Cloud Provider' : 'Edit $initialName'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (preset == null) ...[
                        _field('ID', idCtrl, hint: 'my-provider'),
                        const SizedBox(height: 12),
                        _field('Name', nameCtrl, hint: 'My Provider'),
                        const SizedBox(height: 12),
                        _field(
                          'Base URL',
                          urlCtrl,
                          hint: 'https://api.example.com/v1',
                        ),
                        const SizedBox(height: 12),
                      ],
                      _field('API Key', keyCtrl, hint: 'sk-...', obscure: true),
                      const SizedBox(height: 12),
                      if (preset != null && preset.models.isNotEmpty) ...[
                        const Text(
                          'Model',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          value:
                              preset.models.any((m) => m.id == modelCtrl.text)
                                  ? modelCtrl.text
                                  : null,
                          hint: const Text(
                            'Select preset model…',
                            style: TextStyle(fontSize: 13),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items:
                              preset.models
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m.id,
                                      child: Text(
                                        m.name,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => modelCtrl.text = v);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        _field(
                          'Custom model ID (overrides selection above)',
                          modelCtrl,
                          hint: 'e.g. google/gemini-2.5-pro',
                        ),
                      ] else
                        _field('Model', modelCtrl, hint: 'model-name'),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final config = CloudLlmConfig(
                      id: preset?.id ?? idCtrl.text.trim(),
                      name: preset?.name ?? nameCtrl.text.trim(),
                      baseUrl: preset?.baseUrl ?? urlCtrl.text.trim(),
                      apiKey: keyCtrl.text.trim(),
                      model: modelCtrl.text.trim(),
                      extraHeaders: preset?.extraHeaders ?? const {},
                    );
                    if (config.id.isEmpty || config.apiKey.isEmpty) return;
                    await CloudLlmSettingsService.instance.upsertConfig(config);
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    _load();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Assistant provider toggle
        Text(
          'Assistant Provider',
          style: textStyle?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'local', label: Text('Local Model')),
            ButtonSegment(value: 'cloud', label: Text('Cloud API')),
          ],
          selected: {_assistantProviderType},
          onSelectionChanged: (v) => _setAssistantProviderType(v.first),
        ),
        const SizedBox(height: 20),

        // Cloud providers list
        Row(
          children: [
            Text(
              'Cloud Providers',
              style: textStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: 'Add provider',
              onPressed: _showAddPresetDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_configs.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outline.withAlpha(40)),
            ),
            child: Text(
              'No cloud providers configured.\n'
              'Tap + to add OpenRouter, Google Gemini, OpenAI, or a custom endpoint.',
              style: textStyle?.copyWith(
                fontSize: 12,
                color: colors.onSurface.withAlpha(160),
              ),
            ),
          )
        else
          ...List.generate(_configs.length, (i) {
            final config = _configs[i];
            final isActive = config.id == _activeConfigId;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isActive ? colors.primary.withAlpha(16) : colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isActive
                          ? colors.primary.withAlpha(100)
                          : colors.outline.withAlpha(40),
                ),
              ),
              child: ListTile(
                dense: true,
                leading: Radio<String>(
                  value: config.id,
                  groupValue: _activeConfigId,
                  onChanged: (v) => _setActiveConfig(v),
                ),
                title: Text(
                  config.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${config.model} • ${config.apiKey.isNotEmpty ? "key ✓" : "no key"}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withAlpha(160),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      tooltip: 'Edit',
                      onPressed: () => _showEditConfigDialog(config),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, size: 16, color: colors.error),
                      tooltip: 'Remove',
                      onPressed: () => _deleteConfig(config.id),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 24),
        Text(
          'Voice / ASR Settings',
          style: textStyle?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Use cloud LLM for voice transcription',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            'Sends audio directly to the active cloud LLM model instead of local Whisper. Requires a multimodal model that accepts audio (e.g. Voxtral, Gemini).',
            style: TextStyle(fontSize: 11),
          ),
          value: _voiceSettings.useCloudAsr,
          onChanged:
              (v) => _setVoiceSettings(
                _voiceSettings.copyWith(useCloudAsr: v ?? false),
              ),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Convert WAV → MP3 before sending',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            'Requires ffmpeg on PATH. Reduces file size (may lower token cost for cloud ASR). Falls back to WAV if conversion fails.',
            style: TextStyle(fontSize: 11),
          ),
          value: _voiceSettings.convertWavToMp3,
          onChanged:
              (v) => _setVoiceSettings(
                _voiceSettings.copyWith(convertWavToMp3: v ?? false),
              ),
        ),
      ],
    );
  }
}
