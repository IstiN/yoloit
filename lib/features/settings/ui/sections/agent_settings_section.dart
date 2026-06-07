import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';
import 'package:yoloit/features/settings/ui/dialogs/asr_picker_dialog.dart';

String _formatAsrLabel(
  String mode,
  List<CloudLlmConfig> configs,
  String? configId,
  String? model,
) {
  if (mode == 'default') return 'Default';
  if (mode == 'local') return 'Local';
  final cfg = configs.where((c) => c.id == configId).firstOrNull;
  final modelName = model ?? '—';
  final provName = cfg?.name ?? '—';
  return 'Cloud · $provName · $modelName';
}

InputDecoration _outlineDecoration({
  required Color borderColor,
  String? hint,
  EdgeInsets contentPadding = const EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
  ),
}) =>
    InputDecoration(
      isDense: true,
      hintText: hint,
      contentPadding: contentPadding,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: borderColor),
      ),
    );

class AgentSettingsSection extends StatefulWidget {
  const AgentSettingsSection({super.key});

  @override
  State<AgentSettingsSection> createState() => AgentSettingsSectionState();
}

class AgentSettingsSectionState extends State<AgentSettingsSection> {
  final _service = AgentConfigService.instance;
  final _catalogService = ProviderModelCatalogService.instance;
  List<AgentConfig>? _configs;
  bool _loading = true;
  String? _defaultAgentId;
  static const _boardChatAgentIds = {'copilot', 'cursor', 'opencode'};

  // Global default ASR state.
  String _defaultAsrMode = 'local';
  String? _defaultAsrCloudConfigId;
  String? _defaultAsrCloudModel;
  List<CloudLlmConfig> _cloudConfigs = [];

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    await _catalogService.load();
    final configs = await _service.load();
    final cloudCfgs = await CloudLlmSettingsService.instance.loadConfigs();
    if (mounted) {
      setState(() {
        _configs = configs;
        _defaultAgentId = _service.defaultAgentId;
        _defaultAsrMode = _service.defaultAsrMode;
        _defaultAsrCloudConfigId = _service.defaultAsrCloudConfigId;
        _defaultAsrCloudModel = _service.defaultAsrCloudModel;
        _cloudConfigs = cloudCfgs;
        _loading = false;
      });
    }
  }

  Future<void> _saveConfigs() async {
    if (_configs != null) await _service.save(_configs!);
  }

  void _updateConfig(int index, AgentConfig updated) {
    setState(() => _configs![index] = updated);
    _saveConfigs();
  }

  Future<void> _setDefault(String? id) async {
    setState(() => _defaultAgentId = id);
    await _service.setDefaultAgentId(id);
  }

  Future<void> _saveDefaultAsr({
    required String mode,
    String? configId,
    String? model,
  }) async {
    setState(() {
      _defaultAsrMode = mode;
      _defaultAsrCloudConfigId = configId;
      _defaultAsrCloudModel = model;
    });
    await _service.saveDefaultAsr(mode: mode, configId: configId, model: model);
  }

  String _defaultAsrLabel() => _formatAsrLabel(
    _defaultAsrMode,
    _cloudConfigs,
    _defaultAsrCloudConfigId,
    _defaultAsrCloudModel,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = context.appColors;
    final configs = _configs!;
    final visibleEntries = <({int index, AgentConfig config})>[
      for (var i = 0; i < configs.length; i++)
        if (configs[i].streamAdapter != null) (index: i, config: configs[i]),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Use only board-chat agents below, pick their models, and mark one as favorite (★).',
            style: TextStyle(color: context.appColors.textMuted, fontSize: 11),
          ),
        ),
        // Global default ASR row
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                'Default ASR:',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  // Reload cloud configs so newly-added providers appear.
                  final freshConfigs =
                      await CloudLlmSettingsService.instance.loadConfigs();
                  if (mounted) setState(() => _cloudConfigs = freshConfigs);
                  if (!context.mounted) return;
                  final result = await showDialog<
                    ({String mode, String? configId, String? model})
                  >(
                    context: context,
                    builder:
                        (_) => AsrPickerDialog(
                          showDefaultOption: false,
                          initialMode: _defaultAsrMode,
                          initialConfigId: _defaultAsrCloudConfigId,
                          initialModel: _defaultAsrCloudModel,
                          cloudConfigs: freshConfigs,
                        ),
                  );
                  if (result != null) {
                    await _saveDefaultAsr(
                      mode: result.mode,
                      configId: result.configId,
                      model: result.model,
                    );
                  }
                },
                icon: const Icon(Icons.mic, size: 14),
                label: Text(
                  _defaultAsrLabel(),
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (
                var visibleIndex = 0;
                visibleIndex < visibleEntries.length;
                visibleIndex++
              ) ...[
                Builder(
                  builder: (context) {
                    final visibleEntry = visibleEntries[visibleIndex];
                    final index = visibleEntry.index;
                    final config = visibleEntry.config;
                    final isDefault = config.id == _defaultAgentId;
                    return AgentRow(
                      config: config,
                      isDefault: isDefault,
                      cloudConfigs: _cloudConfigs,
                      onChanged: (updated) => _updateConfig(index, updated),
                      onSetDefault:
                          () => _setDefault(isDefault ? null : config.id),
                      onDelete:
                          config.isBuiltIn
                              ? null
                              : () {
                                setState(() {
                                  _configs!.removeAt(index);
                                });
                                _saveConfigs();
                              },
                    );
                  },
                ),
                if (visibleIndex != visibleEntries.length - 1)
                  Divider(height: 1, color: colors.border),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
            final newAgent = AgentConfig(
              id: id,
              displayName: 'Custom Agent',
              iconLabel: 'CA',
              launchCommand: '',
              visible: true,
              isBuiltIn: false,
              streamAdapter: 'opencode',
            );
            setState(() {
              _configs!.add(newAgent);
            });
            _saveConfigs();
          },
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Add Custom Agent', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }
}

class AgentRow extends StatefulWidget {
  const AgentRow({
    required this.config,
    required this.isDefault,
    required this.cloudConfigs,
    required this.onChanged,
    required this.onSetDefault,
    this.onDelete,
  });

  final AgentConfig config;
  final bool isDefault;
  final List<CloudLlmConfig> cloudConfigs;
  final ValueChanged<AgentConfig> onChanged;
  final VoidCallback onSetDefault;
  final VoidCallback? onDelete;

  @override
  State<AgentRow> createState() => AgentRowState();
}

class AgentRowState extends State<AgentRow> {
  late TextEditingController _nameCtrl;
  late TextEditingController _iconCtrl;
  late TextEditingController _cmdCtrl;

  String _effectiveLaunchCommand(AgentConfig cfg) {
    final cmd = cfg.launchCommand.trim();
    if (cfg.streamAdapter != null &&
        (cmd.isEmpty ||
            cmd == 'opencode' ||
            cmd == 'cursor-agent' ||
            cmd == 'copilot' ||
            cmd == 'copilot --allow-all')) {
      return AgentConfigService.defaultBoardChatCommand(cfg.streamAdapter!);
    }
    return cmd;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.config.displayName);
    _iconCtrl = TextEditingController(text: widget.config.iconLabel);
    _cmdCtrl = TextEditingController(
      text: _effectiveLaunchCommand(widget.config),
    );
  }

  @override
  void didUpdateWidget(AgentRow old) {
    super.didUpdateWidget(old);
    if (old.config.id != widget.config.id) {
      _nameCtrl.text = widget.config.displayName;
      _iconCtrl.text = widget.config.iconLabel;
      _cmdCtrl.text = _effectiveLaunchCommand(widget.config);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.config.copyWith(
        displayName: _nameCtrl.text,
        iconLabel: _iconCtrl.text,
        launchCommand: _cmdCtrl.text,
      ),
    );
  }

  String _asrLabel() => _formatAsrLabel(
    widget.config.asrMode,
    widget.cloudConfigs,
    widget.config.asrCloudConfigId,
    widget.config.asrCloudModel,
  );

  Future<void> _pickAsr(BuildContext context) async {
    // Reload cloud configs so any providers added since page load are visible.
    final freshConfigs = await CloudLlmSettingsService.instance.loadConfigs();
    if (!context.mounted) return;
    final result =
        await showDialog<({String mode, String? configId, String? model})>(
          context: context,
          builder:
              (_) => AsrPickerDialog(
                showDefaultOption: true,
                initialMode: widget.config.asrMode,
                initialConfigId: widget.config.asrCloudConfigId,
                initialModel: widget.config.asrCloudModel,
                cloudConfigs: freshConfigs,
              ),
        );
    if (result != null) {
      widget.onChanged(
        widget.config.copyWith(
          asrMode: result.mode,
          asrCloudConfigId: result.configId,
          asrCloudModel: result.model,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Providers that have a remote model catalog.
    final catalogModels = ProviderModelCatalogService.instance
        .modelsForProvider(widget.config.id);
    final hasCatalog = catalogModels != null && catalogModels.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Visibility toggle
              Switch(
                value: widget.config.visible,
                onChanged:
                    (v) => widget.onChanged(widget.config.copyWith(visible: v)),
                activeThumbColor: colors.primary,
              ),
              const SizedBox(width: 8),
              // Icon label
              SizedBox(
                width: 48,
                child: TextField(
                  controller: _iconCtrl,
                  readOnly: widget.config.isBuiltIn,
                  onChanged: (_) => _emit(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontFamily: 'monospace',
                  ),
                  decoration: _outlineDecoration(
                    borderColor: colors.border,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Name
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _nameCtrl,
                  readOnly: widget.config.isBuiltIn,
                  onChanged: (_) => _emit(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  decoration: _outlineDecoration(
                    borderColor: colors.border,
                    hint: 'Name',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              // Default star button
              const SizedBox(width: 4),
              Tooltip(
                message:
                    widget.isDefault
                        ? 'Favorite agent (click to unset)'
                        : 'Set as favorite agent',
                child: GestureDetector(
                  onTap: widget.onSetDefault,
                  child: Icon(
                    widget.isDefault ? Icons.star : Icons.star_border,
                    size: 18,
                    color:
                        widget.isDefault
                            ? Colors.amber
                            : context.appColors.textMuted,
                  ),
                ),
              ),
              if (!widget.config.isBuiltIn && widget.onDelete != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Delete custom agent',
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Tooltip(
                message: 'Reset to defaults',
                child: GestureDetector(
                  onTap: () {
                    if (widget.config.isBuiltIn) {
                      final def = AgentConfigService.instance
                          .defaultConfigForId(widget.config.id);
                      if (def != null) {
                        widget.onChanged(def);
                        _nameCtrl.text = def.displayName;
                        _iconCtrl.text = def.iconLabel;
                        _cmdCtrl.text = _effectiveLaunchCommand(def);
                      }
                    } else {
                      final adapter = widget.config.streamAdapter ?? 'opencode';
                      final defaultCmd =
                          AgentConfigService.defaultBoardChatCommand(adapter);
                      final updated = widget.config.copyWith(
                        launchCommand: defaultCmd,
                        passDefaultArgs: true,
                        disableModel: false,
                      );
                      widget.onChanged(updated);
                      _cmdCtrl.text = defaultCmd;
                    }
                  },
                  child: Icon(
                    Icons.settings_backup_restore,
                    size: 18,
                    color: context.appColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          // Model picker for catalog-backed providers (copilot, cursor, opencode).
          if (hasCatalog) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 8),
                Text(
                  'Default model:',
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value:
                        catalogModels.any(
                              (m) => m.id == widget.config.defaultModel,
                            )
                            ? widget.config.defaultModel
                            : null,
                    hint: Text(
                      catalogModels
                          .firstWhere(
                            (m) => m.isDefault,
                            orElse: () => catalogModels.first,
                          )
                          .displayName,
                      style: TextStyle(
                        color: context.appColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    items:
                        catalogModels
                            .map(
                              (m) => DropdownMenuItem<String>(
                                value: m.id,
                                child: Text(
                                  m.displayName,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged:
                        (v) => widget.onChanged(
                          widget.config.copyWith(defaultModel: v),
                        ),
                    dropdownColor: colors.surfaceElevated,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                    ),
                    decoration: _outlineDecoration(borderColor: colors.border),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ],
          // ── Launch Command override ───────────────────────────────────────
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 8),
              Text(
                'Launch command:',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cmdCtrl,
                  onChanged: (_) => _emit(),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  decoration: _outlineDecoration(
                    borderColor: colors.border,
                    hint: 'e.g. opencode or codemie-opencode',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
          // ── Pass default flags override ───────────────────────────────────
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 8),
              Text(
                'Pass default flags:',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: widget.config.passDefaultArgs,
                onChanged: (v) {
                  widget.onChanged(widget.config.copyWith(passDefaultArgs: v));
                },
                activeThumbColor: colors.primary,
              ),
              const Spacer(),
            ],
          ),
          // ── Disable model selection ──────────────────────────────────────
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 8),
              Text(
                'Disable model selection:',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: widget.config.disableModel,
                onChanged: (v) {
                  widget.onChanged(widget.config.copyWith(disableModel: v));
                },
                activeThumbColor: colors.primary,
              ),
              const Spacer(),
            ],
          ),
          // ── Stream Adapter ───────────────────────────────────────────────
          if (!widget.config.isBuiltIn) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 8),
                Text(
                  'Stream Adapter:',
                  style: TextStyle(
                    color: context.appColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: widget.config.streamAdapter,
                    items: const [
                      DropdownMenuItem(
                        value: 'opencode',
                        child: Text('OpenCode', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'cursor',
                        child: Text('Cursor', style: TextStyle(fontSize: 12)),
                      ),
                      DropdownMenuItem(
                        value: 'copilot',
                        child: Text('Copilot', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        widget.onChanged(
                          widget.config.copyWith(streamAdapter: v),
                        );
                      }
                    },
                    dropdownColor: colors.surfaceElevated,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                    ),
                    decoration: _outlineDecoration(borderColor: colors.border),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ],
          // ── ASR (transcription) picker ────────────────────────────────────
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 8),
              Text(
                'ASR:',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickAsr(context),
                icon: const Icon(Icons.mic, size: 13),
                label: Text(_asrLabel(), style: const TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
