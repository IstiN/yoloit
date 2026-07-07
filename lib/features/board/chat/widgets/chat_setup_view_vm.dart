import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_session_naming.dart';
import 'package:yoloit/features/board/chat/provider_icon.dart';
import 'package:yoloit/features/board/chat/widgets/chat_provider_badge.dart';
import 'package:yoloit/features/board/chat/widgets/chat_setup_view_common.dart';
import 'package:yoloit/features/board/chat/widgets/model_search_dialog.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/data/models_dev_catalog_service.dart';
import 'package:yoloit/features/settings/data/opencode_auth_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';
import 'package:yoloit/features/settings/data/setup_check_service.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';

class ChatSetupView extends StatefulWidget {
  const ChatSetupView({
    required this.panelId,
    required this.config,
    required this.models,
    this.remoteInfo,
    required this.onStart,
  });

  final String panelId;
  final ChatSessionConfig config;
  final List<ChatModelInfo> models;
  final RemoteBoardInfo? remoteInfo;
  final ValueChanged<ChatSessionConfig> onStart;

  @override
  State<ChatSetupView> createState() => ChatSetupViewState();
}

class ChatSetupViewState extends State<ChatSetupView> {
  late TextEditingController _sessionCtrl;
  late TextEditingController _dirCtrl;
  late String _selectedProvider;
  late String _selectedModel;
  late List<String> _selectedEnvGroupIds;
  bool? _providerInstalled; // null = checking, true = ok, false = missing
  List<ChatModelInfo>? _opencodeModels; // loaded async from models.dev
  bool _cursorModelsLoading = false;
  bool _codexModelsLoading = false;
  bool? _cursorApiKeyConfigured; // null = unknown, true/false = checked

  String _providerLabel(String id) {
    final cfg = AgentConfigService.instance.configForAgent(id);
    if (cfg != null) return cfg.displayName;
    return id;
  }

  List<(String, String)> get _providers {
    return buildChatProviderOptions(AgentConfigService.instance.configs);
  }

  void _normalizeProviderSelection() {
    final provider = resolveChatProviderSelection(
      _selectedProvider,
      _providers,
    );
    if (provider != null && provider != _selectedProvider) {
      _selectedProvider = provider;
      final models = _modelsForProvider;
      if (models.isNotEmpty && !models.any((m) => m.id == _selectedModel)) {
        _selectedModel =
            models
                .firstWhere((m) => m.isDefault, orElse: () => models.first)
                .id;
      }
    }
  }

  List<ChatModelInfo> get _modelsForProvider {
    final catalog = ProviderModelCatalogService.instance;
    final catalogModels = catalog.modelsForProvider(_selectedProvider);
    if (catalogModels != null && catalogModels.isNotEmpty) {
      return catalogModels;
    }
    final cfg = AgentConfigService.instance.configForAgent(_selectedProvider);
    final adapter = cfg?.streamAdapter ?? _selectedProvider;
    // Fallback to hardcoded lists
    return switch (adapter) {
      'cursor' => kCursorModels,
      'codex' => kCodexModels,
      'kimi' => kKimiModels,
      'copilot' => kCopilotModels,
      'opencode' => _opencodeModels ?? kOpencodeModels,
      _ => kCopilotModels,
    };
  }

  List<String> _splitCommand(String command) {
    final parts = <String>[];
    final sb = StringBuffer();
    bool inDoubleQuotes = false;
    bool inSingleQuotes = false;
    for (int i = 0; i < command.length; i++) {
      final char = command[i];
      if (char == '"' && !inSingleQuotes) {
        inDoubleQuotes = !inDoubleQuotes;
      } else if (char == "'" && !inDoubleQuotes) {
        inSingleQuotes = !inSingleQuotes;
      } else if (char == ' ' && !inDoubleQuotes && !inSingleQuotes) {
        if (sb.isNotEmpty) {
          parts.add(sb.toString());
          sb.clear();
        }
      } else {
        sb.write(char);
      }
    }
    if (sb.isNotEmpty) {
      parts.add(sb.toString());
    }
    return parts;
  }

  @override
  void initState() {
    super.initState();
    _sessionCtrl = TextEditingController(text: widget.config.sessionName);
    _dirCtrl = TextEditingController(text: widget.config.workingDir);
    _selectedProvider = widget.config.provider;
    _selectedModel = widget.config.model;
    _selectedEnvGroupIds = List<String>.from(widget.config.envGroupIds);
    _normalizeProviderSelection();
    _checkProviderInstalled(_selectedProvider);
    final cfg = AgentConfigService.instance.configForAgent(_selectedProvider);
    final adapter = cfg?.streamAdapter ?? _selectedProvider;
    if (adapter == 'opencode') _loadOpencodeModels();
    if (_selectedProvider == 'cursor') _loadCursorModels();
    if (adapter == 'codex') _loadCodexModels();
  }

  void _pickDefaultModel(List<ChatModelInfo> models) {
    if (!models.any((m) => m.id == _selectedModel)) {
      _selectedModel =
          models
              .firstWhere((m) => m.isDefault, orElse: () => models.first)
              .id;
    }
  }

  Future<void> _loadOpencodeModels() async {
    try {
      final configuredProviders =
          await OpenCodeAuthService.instance.configuredProviderIds();
      final models = await ModelsDevCatalogService.instance
          .opencodeModelsWithAuth(configuredProviderIds: configuredProviders);
      if (models.isNotEmpty && mounted) {
        setState(() {
          _opencodeModels = models;
          _pickDefaultModel(models);
        });
      }
    } catch (e) {
      debugPrint('[ChatSetup] opencode models load failed: $e');
    }
  }

  Future<void> _loadCursorModels() async {
    if (_cursorModelsLoading) return;
    setState(() => _cursorModelsLoading = true);
    try {
      // Check if CURSOR_API_KEY is available in selected env groups.
      final envMap = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(_selectedEnvGroupIds);
      final hasKey =
          envMap.containsKey('CURSOR_API_KEY') ||
          Platform.environment.containsKey('CURSOR_API_KEY');
      if (mounted) setState(() => _cursorApiKeyConfigured = hasKey);
      if (!hasKey) {
        if (mounted) setState(() => _cursorModelsLoading = false);
        return;
      }
      final models = await ProviderModelCatalogService.instance
          .discoverCursorModels(envGroupIds: _selectedEnvGroupIds);
      if (models != null && models.isNotEmpty && mounted) {
        setState(() => _pickDefaultModel(models));
      }
    } catch (e) {
      debugPrint('[ChatSetup] cursor models load failed: $e');
    }
    if (mounted) setState(() => _cursorModelsLoading = false);
  }

  Future<void> _loadCodexModels() async {
    if (_codexModelsLoading) return;
    setState(() => _codexModelsLoading = true);
    try {
      final models =
          await ProviderModelCatalogService.instance.discoverCodexModels();
      if (models != null && models.isNotEmpty && mounted) {
        setState(() => _pickDefaultModel(models));
      }
    } catch (e) {
      debugPrint('[ChatSetup] codex models load failed: $e');
    }
    if (mounted) setState(() => _codexModelsLoading = false);
  }

  Future<void> _checkProviderInstalled(String provider) async {
    final cfg = AgentConfigService.instance.configForAgent(provider);
    final rawCommand = cfg?.launchCommand.trim() ?? '';
    if (rawCommand.isEmpty) {
      if (mounted) setState(() => _providerInstalled = true);
      return;
    }

    // Extract executable
    final parts = _splitCommand(rawCommand);
    final cmd = parts.isNotEmpty ? parts[0] : rawCommand;

    setState(() => _providerInstalled = null);
    try {
      final found = await SetupCheckService.isCommandAvailable(cmd);
      if (mounted) setState(() => _providerInstalled = found);
    } catch (_) {
      if (mounted) setState(() => _providerInstalled = false);
    }
  }

  @override
  void didUpdateWidget(covariant ChatSetupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When dynamic models arrive, reset selection to default if current is invalid.
    if (oldWidget.models != widget.models) {
      final models = _modelsForProvider;
      if (models.isNotEmpty && !models.any((m) => m.id == _selectedModel)) {
        setState(() {
          _selectedModel =
              models
                  .firstWhere((m) => m.isDefault, orElse: () => models.first)
                  .id;
        });
      }
    }
  }

  @override
  void dispose() {
    _sessionCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final dir = _dirCtrl.text.trim();
    if (dir.isEmpty) return;
    var sessionName = _sessionCtrl.text.trim();
    if (sessionName.isEmpty) {
      sessionName = 'chat-${DateTime.now().millisecondsSinceEpoch}';
    }
    final boardState = context.read<BoardCubit>().state;
    final board = boardState.activeBoard ?? boardState.boards.firstOrNull;
    if (board != null) {
      sessionName = makeUniqueChatSessionName(
        sessionName,
        board.panels
            .where(
              (panel) =>
                  panel.id != widget.panelId &&
                  panel.type == ChatPanelPlugin.kTypeId,
            )
            .map(
              (panel) =>
                  (panel.state['config'] is Map
                      ? (Map<String, dynamic>.from(
                            panel.state['config'] as Map,
                          ))['sessionName']
                          as String?
                      : null) ??
                  panel.title,
            ),
      );
    }
    // Ensure selected model is valid for the chosen provider
    final validModels = _modelsForProvider;
    final agentConfig = AgentConfigService.instance.configForAgent(
      _selectedProvider,
    );
    final disableModel = agentConfig?.disableModel ?? false;
    final model =
        disableModel
            ? ''
            : (validModels.any((m) => m.id == _selectedModel)
                ? _selectedModel
                : (validModels
                    .firstWhere(
                      (m) => m.isDefault,
                      orElse: () => validModels.first,
                    )
                    .id));
    widget.onStart(
      ChatSessionConfig(
        sessionName: sessionName,
        workingDir: dir,
        provider: _selectedProvider,
        model: model,
        envGroupIds: _selectedEnvGroupIds,
      ),
    );
  }

  void _showModelSearch(
    BuildContext context,
    Color inputFill,
    ColorScheme colorScheme,
  ) {
    final allModels = _modelsForProvider;
    showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return ModelSearchDialog(
          models: allModels,
          selectedId: _selectedModel,
          inputFill: inputFill,
        );
      },
    ).then((selected) {
      if (!mounted) return;
      if (selected != null) {
        setState(() => _selectedModel = selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final styles = ChatSetupStyles(context);
    final agentConfig = AgentConfigService.instance.configForAgent(
      _selectedProvider,
    );
    final disableModel = agentConfig?.disableModel ?? false;
    final inputFill = styles.colors.surfaceElevated;
    final dropdownFill = styles.colors.surface;
    final providers = _providers;
    final selectedProvider = resolveChatProviderSelection(
      _selectedProvider,
      providers,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Provider type selector
          Text('Provider', style: styles.labelStyle),
          const SizedBox(height: 4),
          ChatSetupDropdown<String>(
            value: selectedProvider,
            fillColor: inputFill,
            dropdownColor: dropdownFill,
            style: styles.inputTextStyle,
            items:
                providers
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.$1,
                        child: Row(
                          children: [
                            ChatProviderIcon(provider: p.$1, size: 16),
                            const SizedBox(width: 8),
                            Text(p.$2),
                          ],
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _selectedProvider = v;
                // Reset model to default for the new provider
                final models = _modelsForProvider;
                _selectedModel =
                    models
                        .firstWhere(
                          (m) => m.isDefault,
                          orElse: () => models.first,
                        )
                        .id;
              });
              _checkProviderInstalled(v);
              final cfg = AgentConfigService.instance.configForAgent(v);
              final adapter = cfg?.streamAdapter ?? v;
              if (adapter == 'opencode') _loadOpencodeModels();
              if (adapter == 'cursor') _loadCursorModels();
              if (adapter == 'codex') _loadCodexModels();
            },
          ),
          // ── Not-installed banner ──────────────────────────────────────────
          if (_providerInstalled == false) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_providerLabel(_selectedProvider)} is not installed',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => SetupGuidePage.show(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      foregroundColor: Colors.orange,
                    ),
                    child: const Text(
                      'Install',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_providerInstalled == null) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 14),
          EnvGroupSelectionField(
            selectedGroupIds: _selectedEnvGroupIds,
            onChanged: (value) {
              setState(() => _selectedEnvGroupIds = value);
              if (_selectedProvider == 'cursor') _loadCursorModels();
            },
          ),
          // Show hint when cursor is selected but CURSOR_API_KEY is missing.
          if (_selectedProvider == 'cursor' &&
              _cursorApiKeyConfigured == false) ...[
            const SizedBox(height: 4),
            Text(
              'Add CURSOR_API_KEY to an env group above to authenticate.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade300),
            ),
          ],
          if (_cursorModelsLoading) ...[
            const SizedBox(height: 4),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_codexModelsLoading) ...[
            const SizedBox(height: 4),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 14),

          // Working directory
          Text('Working Directory', style: styles.labelStyle),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final dir = await BoardFilePicker.pickDirectory(
                      context,
                      remoteInfo: widget.remoteInfo,
                      initialPath: _dirCtrl.text,
                      title: 'Select working directory',
                    );
                    if (!mounted) return;
                    if (dir != null) {
                      setState(() => _dirCtrl.text = dir);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: inputFill,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 16,
                          color: context.appColors.statusActive,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dirCtrl.text.isEmpty
                                ? 'Select folder…'
                                : _dirCtrl.text.split('/').last,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  _dirCtrl.text.isEmpty
                                      ? styles.colorScheme.onSurface.withAlpha(120)
                                      : styles.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Session name
          Text('Session Name', style: styles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _sessionCtrl,
            style: styles.inputTextStyle,
            decoration: InputDecoration(
              hintText: 'auto-generated if empty',
              hintStyle: styles.hintStyle,
              filled: true,
              fillColor: inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),

          // Model selector
          if (!disableModel) ...[
            Text('Model', style: styles.labelStyle),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _showModelSearch(context, inputFill, styles.colorScheme),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: inputFill,
                ),
                child: Row(
                  children: [
                    () {
                      final m = _modelsForProvider
                          .cast<ChatModelInfo?>()
                          .firstWhere(
                            (m) => m!.id == _selectedModel,
                            orElse: () => null,
                          );
                      if (m != null && m.providerGroup != null) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: buildProviderBadge(context, m.providerGroup!),
                        );
                      }
                      return const SizedBox.shrink();
                    }(),
                    Expanded(
                      child: Text(
                        _modelsForProvider
                                .cast<ChatModelInfo?>()
                                .firstWhere(
                                  (m) => m!.id == _selectedModel,
                                  orElse: () => null,
                                )
                                ?.displayName ??
                            _selectedModel,
                        style: styles.inputTextStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.unfold_more,
                      size: 16,
                      color: styles.colorScheme.onSurface.withAlpha(128),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Spacer(),

          FilledButton(
            onPressed:
                (_dirCtrl.text.trim().isEmpty || _providerInstalled == false)
                    ? null
                    : _start,
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.statusActive,
              foregroundColor: context.appColors.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _providerInstalled == false
                  ? 'Install provider first'
                  : 'Start Chat',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
