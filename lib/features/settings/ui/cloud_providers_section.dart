import 'package:flutter/material.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/ui/components/typography/label.dart';

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
    var providerType =
        await CloudLlmSettingsService.instance.loadAssistantProviderType();
    if (providerType == 'local') {
      providerType = 'cloud';
      await CloudLlmSettingsService.instance.saveAssistantProviderType(
        'cloud',
      );
    }
    final vs = await CloudLlmSettingsService.instance.loadVoiceSettings();
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _activeConfigId = activeId;
      _voiceSettings = vs;
      _loading = false;
    });
  }

  Future<void> _setActiveConfig(String? id) async {
    await CloudLlmSettingsService.instance.saveActiveConfigId(id);
    await CloudLlmSettingsService.instance.saveAssistantProviderType('cloud');
    if (!mounted) return;
    setState(() => _activeConfigId = id);
  }

  Future<void> _setChatProvider(String providerId) async {
    await _setActiveConfig(providerId);
  }

  Future<void> _setProviderModel(String configId, String modelId) async {
    final config = _configById(configId);
    if (config == null) return;
    final updated = config.copyWith(model: modelId);
    await CloudLlmSettingsService.instance.upsertConfig(updated);
    await _load();
  }

  Future<void> _setVoiceSettings(VoiceSettings s) async {
    await CloudLlmSettingsService.instance.saveVoiceSettings(s);
    if (!mounted) return;
    setState(() => _voiceSettings = s);
  }

  CloudLlmConfig? _configById(String? id) {
    if (id == null || id.isEmpty) return null;
    return _configs.where((c) => c.id == id).firstOrNull;
  }

  CloudLlmPreset? _presetById(String? id) {
    if (id == null || id.isEmpty) return null;
    return kCloudLlmPresets.where((p) => p.id == id).firstOrNull;
  }

  String? _effectiveAsrConfigId() {
    final fromVoice = _voiceSettings.cloudAsrConfigId;
    if (_configById(fromVoice) != null) return fromVoice;
    if (_configById(_activeConfigId) != null) return _activeConfigId;
    return _configs.isNotEmpty ? _configs.first.id : null;
  }

  List<({String id, String label})> _modelOptionsForConfig(String? configId) {
    final cfg = _configById(configId);
    if (cfg == null) return const [];
    final preset = _presetById(cfg.id);
    final byId = <String, String>{};
    byId[cfg.model] = cfg.model;
    if (preset != null) {
      for (final model in preset.models) {
        byId[model.id] = model.name;
      }
    }
    return byId.entries.map((e) => (id: e.key, label: e.value)).toList();
  }

  Future<void> _deleteConfig(String id) async {
    await CloudLlmSettingsService.instance.removeConfig(id);
    if (id == _activeConfigId) {
      await CloudLlmSettingsService.instance.saveActiveConfigId(null);
      await CloudLlmSettingsService.instance.saveAssistantProviderType('cloud');
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
                          initialValue:
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
        Label(label, fontSize: 13),
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
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      tooltip: 'Provider settings',
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
          'Model Routing',
          style: textStyle?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...(() {
          final chatProviderId =
              _configById(_activeConfigId)?.id ??
              (_configs.isNotEmpty ? _configs.first.id : null);
          final chatConfig = _configById(chatProviderId);
          final chatModelOptions = _modelOptionsForConfig(chatProviderId);
          final chatModelValue =
              chatModelOptions.any((m) => m.id == chatConfig?.model)
                  ? chatConfig?.model
                  : null;
          return <Widget>[
            _providerDropdown(
              value: chatProviderId,
              labelText: 'Chat provider',
              onChanged: (v) {
                if (v == null) return;
                _setChatProvider(v);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: chatModelValue,
                    hint: const Text('Select chat model'),
                    decoration: const InputDecoration(
                      labelText: 'Chat model',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _modelItems(chatModelOptions),
                    onChanged: (v) {
                      if (v == null || chatProviderId == null) return;
                      _setProviderModel(chatProviderId, v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  tooltip: 'Chat provider settings',
                  onPressed:
                      chatConfig == null
                          ? null
                          : () => _showEditConfigDialog(chatConfig),
                ),
              ],
            ),
          ];
        })(),
        const SizedBox(height: 12),
        Text(
          'Voice / ASR Settings',
          style: textStyle?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        // "Use same as chat" checkbox comes first so users see it before the
        // provider/model dropdowns that are irrelevant when it is enabled.
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Use the same provider/model as chat',
            style: TextStyle(fontSize: 13),
          ),
          value: _voiceSettings.useChatModelForCloudAsr,
          onChanged:
              (v) => _setVoiceSettings(
                _voiceSettings.copyWith(useChatModelForCloudAsr: v ?? true),
              ),
        ),
        if (_voiceSettings.useChatModelForCloudAsr) ...[
          const SizedBox(height: 4),
          Text(
            'Audio will be sent directly to the chat model as a voice attachment.',
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurface.withAlpha(160),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (!_voiceSettings.useChatModelForCloudAsr) ...[
          ...(() {
            final asrConfigId = _effectiveAsrConfigId();
            final asrOptions = _modelOptionsForConfig(asrConfigId);
            final asrOptionsWithSelected = <({String id, String label})>[
              ...asrOptions,
              if (_voiceSettings.cloudAsrModel != null &&
                  _voiceSettings.cloudAsrModel!.trim().isNotEmpty &&
                  !asrOptions.any((m) => m.id == _voiceSettings.cloudAsrModel))
                (
                  id: _voiceSettings.cloudAsrModel!.trim(),
                  label: _voiceSettings.cloudAsrModel!.trim(),
                ),
            ];
            final asrValue =
                asrOptionsWithSelected.any(
                      (m) => m.id == _voiceSettings.cloudAsrModel,
                    )
                    ? _voiceSettings.cloudAsrModel
                    : null;
            return <Widget>[
              _providerDropdown(
                value: asrConfigId,
                labelText: 'ASR provider',
                onChanged: (v) {
                  if (v == null) return;
                  _setVoiceSettings(
                    _voiceSettings.copyWith(
                      useCloudAsr: true,
                      useChatModelForCloudAsr: false,
                      cloudAsrConfigId: v,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: asrValue,
                hint: const Text(
                  'Select ASR model',
                  style: TextStyle(fontSize: 13),
                ),
                decoration: const InputDecoration(
                  labelText: 'ASR model',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _modelItems(asrOptionsWithSelected),
                onChanged:
                    (v) => _setVoiceSettings(
                      _voiceSettings.copyWith(cloudAsrModel: v),
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'ASR uses the provider/model selected above.',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurface.withAlpha(160),
                ),
              ),
            ];
          })(),
        ],
        if (_voiceSettings.useCloudAsr) ...[
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Convert WAV → MP3 before sending',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'Requires ffmpeg on PATH. Reduces file size.',
              style: TextStyle(fontSize: 11),
            ),
            value: _voiceSettings.convertWavToMp3,
            onChanged:
                (v) => _setVoiceSettings(
                  _voiceSettings.copyWith(convertWavToMp3: v ?? false),
                ),
          ),
        ],
      ],
    );
  }

  DropdownButtonFormField<String> _providerDropdown({
    required String? value,
    required String labelText,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: labelText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: _configs
          .map(
            (c) => DropdownMenuItem<String>(
              value: c.id,
              child: Text(c.name, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  List<DropdownMenuItem<String>> _modelItems(
    List<({String id, String label})> options,
  ) {
    return options
        .map(
          (m) => DropdownMenuItem<String>(
            value: m.id,
            child: Text(
              m.label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        )
        .toList();
  }
}
