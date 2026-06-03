import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/core/hotkeys/hotkey_definition.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';
import 'package:yoloit/features/settings/data/tool_call_settings_service.dart';
import 'package:yoloit/features/settings/ui/cloud_providers_section.dart';
import 'package:yoloit/features/settings/ui/global_env_groups_section.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';
import 'package:yoloit/features/settings/ui/debug_ui/debug_ui_shell.dart';
import 'package:yoloit/ui/components/typography/caption.dart';
import 'package:yoloit/features/settings/ui/sync_section.dart';
import 'package:yoloit/features/settings/ui/widget_permissions_section.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/ui/skills_panel.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/updates/data/update_service.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

const _kCategories = [
  'Appearance',
  'AI & Models',
  'Prompts',
  'Environment',
  'Notifications',
  'Sessions',
  'Shortcuts',
  'Skills',
  'Sync',
  'Setup Guide',
  'Apps & Widgets',
  'Support',
  'About',
];

const _kDebugCategories = [..._kCategories, 'Debug UI'];

const _kSkillsCategoryIndex = 7;

/// Settings overlay shown as a modal dialog with sidebar navigation.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialCategory});

  final String? initialCategory;

  static Future<void> show(BuildContext context, {String? initialCategory}) {
    final wsCubit = context.read<WorkspaceCubit>();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder:
          (_) => BlocProvider(
            create: (_) => SkillsCubit(),
            child: BlocProvider.value(
              value: wsCubit,
              child:
                  useFullscreenDialogs(context)
                      ? Dialog.fullscreen(
                        child: SettingsPage(initialCategory: initialCategory),
                      )
                      : Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: const EdgeInsets.symmetric(
                          horizontal: 60,
                          vertical: 40,
                        ),
                        child: SettingsPage(initialCategory: initialCategory),
                      ),
            ),
          ),
    );
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedCategory = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial == null || initial.isEmpty) {
      return;
    }
    final index = _kCategories.indexOf(initial);
    if (index >= 0) {
      _selectedCategory = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fullscreen = useFullscreenDialogs(context);
    return Container(
      constraints:
          fullscreen
              ? null
              : const BoxConstraints(maxWidth: 900, maxHeight: 780),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(fullscreen ? 0 : 12),
        border: fullscreen ? null : Border.all(color: colors.border),
        boxShadow: [
          if (!fullscreen)
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(context),
                VerticalDivider(width: 1, color: colors.border),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: context.appColors.textMuted,
            ),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  List<String> get _categories => kDebugMode ? _kDebugCategories : _kCategories;

  Widget _buildSidebar(BuildContext context) {
    final colors = context.appColors;
    final cats = _categories;
    return SizedBox(
      width: 140,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cats.length,
        itemBuilder: (context, index) {
          final isActive = index == _selectedCategory;
          return InkWell(
            onTap: () => setState(() => _selectedCategory = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isActive ? colors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                cats[index],
                style: TextStyle(
                  color:
                      isActive
                          ? colors.primary
                          : Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    // Skills panel needs full height, not scrollable wrapper
    if (_selectedCategory == _kSkillsCategoryIndex) {
      return const SkillsPanel();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: switch (_selectedCategory) {
        0 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'Appearance'),
            const SizedBox(height: 12),
            _ThemeSelector(),
          ],
        ),
        1 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'Cloud Providers'),
            const SizedBox(height: 12),
            const CloudProvidersSection(),
            const SizedBox(height: 24),
            const _SectionHeader(title: 'AI Agents'),
            const SizedBox(height: 12),
            _AgentSettingsSection(),
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Ignored Tool Calls'),
            const SizedBox(height: 12),
            const _IgnoredToolCallsSection(),
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Chat Context'),
            const SizedBox(height: 12),
            const _ChatContextSection(),
          ],
        ),
        2 => const _PromptsSection(),
        3 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Environment'),
            SizedBox(height: 12),
            GlobalEnvGroupsSection(),
          ],
        ),
        4 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Notifications'),
            SizedBox(height: 12),
            _NotificationsSection(),
          ],
        ),
        5 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'Sessions'),
            const SizedBox(height: 12),
            _SessionSettings(),
          ],
        ),
        6 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'Keyboard Shortcuts'),
            const SizedBox(height: 12),
            _ShortcutsTable(),
          ],
        ),
        8 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Sync'),
            SizedBox(height: 12),
            SyncSection(),
          ],
        ),
        9 => const SetupGuideEmbedded(),
        10 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Terminal'),
            SizedBox(height: 12),
            _TerminalRendererSettings(),
            SizedBox(height: 24),
            _SectionHeader(title: 'Widget API Permissions'),
            SizedBox(height: 12),
            WidgetPermissionsSection(),
          ],
        ),
        11 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Support'),
            SizedBox(height: 12),
            _SupportSection(),
          ],
        ),
        12 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'About'),
            const SizedBox(height: 12),
            _AboutSection(),
          ],
        ),
        _ => kDebugMode ? const DebugUIShell() : const SizedBox.shrink(),
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Text(
      title,
      style: TextStyle(
        color: colors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

class _SupportSection extends StatefulWidget {
  const _SupportSection();

  @override
  State<_SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<_SupportSection> {
  bool _copying = false;
  String? _logPath;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.logPath.then((path) {
      if (mounted) setState(() => _logPath = path);
    });
  }

  Future<void> _copyLogs() async {
    setState(() => _copying = true);
    try {
      final payload = await SupportLogService.instance.buildCopyPayload();
      await Clipboard.setData(ClipboardData(text: payload));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Support logs copied')));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  void _clearRecentEvents() {
    SupportLogService.instance.clearMemoryLog();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recent support events cleared')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final recent = SupportLogService.instance.memoryLog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.support_outlined, size: 18, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Diagnostics',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _copying ? null : _copyLogs,
                    icon:
                        _copying
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.copy, size: 16),
                    label: Text(_copying ? 'Copying...' : 'Copy logs'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Board navigation diagnostics capture trackpad scroll, pan/zoom, canvas locks, and viewport interaction events.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Caption('App log: ${_logPath ?? 'loading...'}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Recent support events',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearRecentEvents,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear recent'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 180, maxHeight: 320),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              recent,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TerminalRendererSettings extends StatefulWidget {
  const _TerminalRendererSettings();

  @override
  State<_TerminalRendererSettings> createState() =>
      _TerminalRendererSettingsState();
}

class _TerminalRendererSettingsState extends State<_TerminalRendererSettings> {
  final _service = AgentConfigService.instance;
  final _tmux = TmuxService.instance;
  TerminalRenderEngine _engine = TerminalRenderEngine.xterm;
  TerminalBackendMode _backendMode = TerminalBackendMode.local;
  bool _tmuxOn = false;

  @override
  void initState() {
    super.initState();
    _engine = _service.terminalRenderEngine;
    _backendMode = _service.terminalBackendMode;
    _tmuxOn = _tmux.enabled;
    _service.load().then((_) {
      if (mounted) {
        setState(() {
          _engine = _service.terminalRenderEngine;
          _backendMode = _service.terminalBackendMode;
        });
      }
    });
  }

  Future<void> _setEngine(TerminalRenderEngine engine) async {
    setState(() => _engine = engine);
    await _service.setTerminalRenderEngine(engine);
  }

  Future<void> _setBackendMode(TerminalBackendMode mode) async {
    setState(() {
      _backendMode = mode;
      _tmuxOn = mode == TerminalBackendMode.tmux;
    });
    await _service.setTerminalBackendMode(mode);
    await _tmux.setEnabled(mode == TerminalBackendMode.tmux);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Terminal renderer',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Caption(
                      'Switches the embedded terminal emulator for board/app terminal panels.',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SegmentedButton<TerminalRenderEngine>(
                segments:
                    TerminalRenderEngine.values
                        .map(
                          (engine) => ButtonSegment(
                            value: engine,
                            label: Text(engine.label),
                            tooltip: engine.description,
                          ),
                        )
                        .toList(),
                selected: {_engine},
                onSelectionChanged: (selected) => _setEngine(selected.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          Divider(height: 24, color: colors.border),
          Row(
            children: [
              Icon(Icons.history_toggle_off, size: 18, color: colors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Terminal backend',
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    ),
                    Caption(
                      'Runtime is the default persistent backend. Local PTY remains available as a fallback.',
                    ),
                  ],
                ),
              ),
              SegmentedButton<TerminalBackendMode>(
                segments:
                    TerminalBackendMode.values
                        .map(
                          (mode) => ButtonSegment(
                            value: mode,
                            label: Text(mode.label),
                            tooltip: mode.description,
                            enabled:
                                mode != TerminalBackendMode.tmux ||
                                _tmux.available,
                          ),
                        )
                        .toList(),
                selected: {_backendMode},
                onSelectionChanged:
                    (selected) => _setBackendMode(selected.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_backendMode == TerminalBackendMode.runtime) ...[
            const SizedBox(height: 8),
            Text(
              'Runtime is dev MVP on macOS/Linux. Existing sessions stay in the backend process.',
              style: TextStyle(color: colors.statusWarning, fontSize: 11),
            ),
          ] else if (_tmuxOn && _tmux.available) ...[
            const SizedBox(height: 8),
            Text(
              'For scroll debugging, turn this off and start a new terminal session.',
              style: TextStyle(color: colors.statusWarning, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Prompts ─────────────────────────────────────────────────────────────────

class _PromptsSection extends StatefulWidget {
  const _PromptsSection();

  @override
  State<_PromptsSection> createState() => _PromptsSectionState();
}

class _PromptsSectionState extends State<_PromptsSection> {
  late Future<Map<String, String>> _promptsFuture;

  static const _yoloChatAsset = 'assets/prompts/yolo_chat_system_prompt.md';
  static const _cliGuidanceAsset = 'assets/prompts/cli_agent_guidance.md';

  @override
  void initState() {
    super.initState();
    _promptsFuture = _loadPrompts();
  }

  Future<Map<String, String>> _loadPrompts() async {
    final chat = await rootBundle.loadString(_yoloChatAsset);
    final guidance = await rootBundle.loadString(_cliGuidanceAsset);
    final help = await CliGuidanceService.instance.fetchHelp();
    return {
      'yolochat': chat.trim(),
      'agents': guidance.trim(),
      'help': help ?? '(yoloit binary not found or help unavailable)',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _promptsFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final prompts = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'YoloChat System Prompt'),
            const SizedBox(height: 4),
            const Text(
              'Injected as the system prompt for every YoloChat LLM session.',
              style: TextStyle(color: Color(0xFF8C8D9E), fontSize: 12),
            ),
            const SizedBox(height: 12),
            _PromptCard(
              label: 'assets/prompts/yolo_chat_system_prompt.md',
              content: prompts['yolochat']!,
            ),
            const SizedBox(height: 28),
            const _SectionHeader(title: 'CLI Agent Guidance'),
            const SizedBox(height: 4),
            const Text(
              'Prepended to every user message sent to Copilot, Cursor, and OpenCode agents.',
              style: TextStyle(color: Color(0xFF8C8D9E), fontSize: 12),
            ),
            const SizedBox(height: 12),
            _PromptCard(
              label: 'assets/prompts/cli_agent_guidance.md',
              content: prompts['agents']!,
            ),
            const SizedBox(height: 28),
            const _SectionHeader(title: 'YoLoIT CLI Help (injected)'),
            const SizedBox(height: 4),
            const Text(
              'Output of `yoloit help --format short` — appended to the first message in every agent session.',
              style: TextStyle(color: Color(0xFF8C8D9E), fontSize: 12),
            ),
            const SizedBox(height: 12),
            _PromptCard(
              label: 'yoloit help --format short',
              content: prompts['help']!,
            ),
          ],
        );
      },
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.label, required this.content});

  final String label;
  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar with filename + copy button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 15),
                  tooltip: 'Copy to clipboard',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    minimumSize: const Size(28, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colors.border.withValues(alpha: 0.25),
          ),
          // Scrollable content
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                content,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentSettingsSection extends StatefulWidget {
  @override
  State<_AgentSettingsSection> createState() => _AgentSettingsSectionState();
}

class _AgentSettingsSectionState extends State<_AgentSettingsSection> {
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
    if (mounted)
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

  String _defaultAsrLabel() {
    if (_defaultAsrMode != 'cloud') return 'Local';
    final cfg =
        _cloudConfigs
            .where((c) => c.id == _defaultAsrCloudConfigId)
            .firstOrNull;
    final modelName = _defaultAsrCloudModel ?? '—';
    final provName = cfg?.name ?? '—';
    return 'Cloud · $provName · $modelName';
  }

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
            style: TextStyle(
              color:
                  context.appColors.textMuted,
              fontSize: 11,
            ),
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
                  color:
                      context.appColors.textMuted,
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
                        (_) => _AsrPickerDialog(
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
                    return _AgentRow(
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

class _IgnoredToolCallsSection extends StatefulWidget {
  const _IgnoredToolCallsSection();

  @override
  State<_IgnoredToolCallsSection> createState() =>
      _IgnoredToolCallsSectionState();
}

class _IgnoredToolCallsSectionState extends State<_IgnoredToolCallsSection> {
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
            style: TextStyle(
              color:
                  context.appColors.textMuted,
              fontSize: 11,
            ),
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

// ─── Chat Context Settings ────────────────────────────────────────────────────

class _ChatContextSection extends StatefulWidget {
  const _ChatContextSection();

  @override
  State<_ChatContextSection> createState() => _ChatContextSectionState();
}

class _ChatContextSectionState extends State<_ChatContextSection> {
  bool _injectCliHelp = true;
  bool _boardSnapshot = false;

  @override
  void initState() {
    super.initState();
    SessionPrefs.isInjectCliHelpEnabled().then((v) {
      if (mounted) setState(() => _injectCliHelp = v);
    });
    SessionPrefs.isBoardSnapshotEnabled().then((v) {
      if (mounted) setState(() => _boardSnapshot = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          _ToggleRow(
            icon: Icons.integration_instructions_outlined,
            title: 'Inject CLI help on first message',
            subtitle:
                'Prepends yoloit command reference to the first Copilot message',
            value: _injectCliHelp,
            onChanged: (v) async {
              await SessionPrefs.saveInjectCliHelpEnabled(v);
              CliGuidanceService.instance.clearCache();
              if (mounted) setState(() => _injectCliHelp = v);
            },
          ),
          Divider(height: 1, color: colors.border),
          _ToggleRow(
            icon: Icons.screenshot_monitor_outlined,
            title: 'Attach board snapshot',
            subtitle:
                'Sends a compressed screenshot of the current board view with each message',
            value: _boardSnapshot,
            onChanged: (v) async {
              await SessionPrefs.saveBoardSnapshotEnabled(v);
              if (mounted) setState(() => _boardSnapshot = v);
            },
          ),
        ],
      ),
    );
  }
}

class _AgentRow extends StatefulWidget {
  const _AgentRow({
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
  State<_AgentRow> createState() => _AgentRowState();
}

class _AgentRowState extends State<_AgentRow> {
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
  void didUpdateWidget(_AgentRow old) {
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

  String _asrLabel() {
    final mode = widget.config.asrMode;
    if (mode == 'default') return 'Default';
    if (mode == 'local') return 'Local';
    final cfg =
        widget.cloudConfigs
            .where((c) => c.id == widget.config.asrCloudConfigId)
            .firstOrNull;
    final modelName = widget.config.asrCloudModel ?? '—';
    final provName = cfg?.name ?? '—';
    return 'Cloud · $provName · $modelName';
  }

  Future<void> _pickAsr(BuildContext context) async {
    // Reload cloud configs so any providers added since page load are visible.
    final freshConfigs = await CloudLlmSettingsService.instance.loadConfigs();
    if (!context.mounted) return;
    final result =
        await showDialog<({String mode, String? configId, String? model})>(
          context: context,
          builder:
              (_) => _AsrPickerDialog(
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
                activeColor: colors.primary,
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
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
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
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Name',
                    hintStyle: TextStyle(
                      color:
                          context.appColors.textMuted,
                      fontSize: 13,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
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
                    color:
                        context.appColors.textMuted,
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
                    color:
                        context.appColors.textMuted,
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
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
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
                  color:
                      context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cmdCtrl,
                  onChanged: (_) => _emit(),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    hintText: 'e.g. opencode or codemie-opencode',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
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
                  color:
                      context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: widget.config.passDefaultArgs,
                onChanged: (v) {
                  widget.onChanged(widget.config.copyWith(passDefaultArgs: v));
                },
                activeColor: colors.primary,
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
                  color:
                      context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: widget.config.disableModel,
                onChanged: (v) {
                  widget.onChanged(widget.config.copyWith(disableModel: v));
                },
                activeColor: colors.primary,
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
                    color:
                        context.appColors.textMuted,
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
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
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
                  color:
                      context.appColors.textMuted,
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

/// Dialog for picking ASR configuration (Default / Local / Cloud + Provider + Model).
class _AsrPickerDialog extends StatefulWidget {
  const _AsrPickerDialog({
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
  State<_AsrPickerDialog> createState() => _AsrPickerDialogState();
}

class _AsrPickerDialogState extends State<_AsrPickerDialog> {
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

    final inputDecoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.border),
      ),
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

// ─── Theme Selector ───────────────────────────────────────────────────────

class _ThemeSelector extends StatefulWidget {
  @override
  State<_ThemeSelector> createState() => _ThemeSelectorState();
}

class _ThemeSelectorState extends State<_ThemeSelector> {
  @override
  void initState() {
    super.initState();
    ThemeManager.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    ThemeManager.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _importTheme() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'icls', 'xml'],
      dialogTitle: 'Import Theme',
    );
    if (result == null || result.files.single.path == null) return;
    final id = await ThemeManager.instance.importThemeFile(
      result.files.single.path!,
    );
    await ThemeManager.instance.setCustomTheme(id);
  }

  Future<void> _pickColor(String slot, Color current) async {
    // Convert camelCase key to human-readable label
    final label = slot
        .replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]}')
        .trim()
        .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(title: label, initialColor: current),
    );
    if (picked != null) {
      await ThemeManager.instance.setColorOverride(slot, picked);
    }
  }

  Future<void> _savePreset() async {
    final tm = ThemeManager.instance;
    // Determine default name
    String defaultName;
    if (tm.activeCustomThemeId != null) {
      final custom =
          tm.customThemes
              .where((t) => t.id == tm.activeCustomThemeId)
              .firstOrNull;
      defaultName = '${custom?.name ?? "Custom"} Copy';
    } else {
      defaultName = '${tm.current.label} Custom';
    }

    final controller = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final colors = context.appColors;
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Save as Preset',
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Preset name',
              hintStyle: TextStyle(color: colors.textMuted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    // Do NOT dispose controller here — the dialog exit animation may still
    // reference it. Let GC handle cleanup.
    if (name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();
    // Wait for the dialog exit animation to fully complete before
    // notifyListeners() fires (which rebuilds the widget tree).
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await tm.saveCurrentAsPreset(trimmed);
  }

  Future<void> _exportTheme() async {
    final tm = ThemeManager.instance;
    final json = tm.exportCurrentAsJson();
    final dirPath = await BoardFilePicker.pickDirectory(
      context,
      title: 'Export Theme - Choose Folder',
    );
    if (dirPath == null) return;

    // Build a safe filename
    String themeName;
    if (tm.activeCustomThemeId != null) {
      final custom =
          tm.customThemes
              .where((t) => t.id == tm.activeCustomThemeId)
              .firstOrNull;
      themeName = custom?.name ?? 'custom_theme';
    } else {
      themeName = tm.current.label;
    }
    final safeName = themeName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+$'), '');
    final file = File(p.join(dirPath, '${safeName}_theme.json'));
    await file.writeAsString(json, flush: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Theme exported to ${file.path}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tm = ThemeManager.instance;
    final activeCustomId = tm.activeCustomThemeId;
    final hasOverrides = tm.hasOverrides;

    // Active theme label
    String activeLabel;
    if (activeCustomId != null) {
      final custom =
          tm.customThemes.where((t) => t.id == activeCustomId).firstOrNull;
      activeLabel = custom?.name ?? 'Custom';
    } else {
      activeLabel = tm.current.label;
    }
    if (hasOverrides) {
      activeLabel = '$activeLabel (customized)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preset strip ──
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...AppThemePreset.values.map((preset) {
              final isActive =
                  activeCustomId == null &&
                  preset == tm.current &&
                  !hasOverrides;
              return _PresetChip(
                label: preset.label,
                color: preset.color,
                brightness: preset.defaultBrightness,
                isActive: isActive,
                onTap: () {
                  tm.setTheme(preset);
                  tm.clearColorOverrides();
                },
              );
            }),
            ...tm.customThemes.map((custom) {
              final isActive = activeCustomId == custom.id && !hasOverrides;
              return _PresetChip(
                label: custom.name,
                color: custom.scheme.primary,
                brightness: custom.brightness,
                isActive: isActive,
                onTap: () {
                  tm.setCustomTheme(custom.id);
                  tm.clearColorOverrides();
                },
                onDelete: () => tm.deleteCustomTheme(custom.id),
              );
            }),
          ],
        ),
        const SizedBox(height: 10),
        // ── Actions row ──
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _SmallButton(
              icon: Icons.file_download_outlined,
              label: 'Import',
              onTap: _importTheme,
            ),
            _SmallButton(
              icon: Icons.file_upload_outlined,
              label: 'Export',
              onTap: _exportTheme,
            ),
            _SmallButton(
              icon: Icons.save_outlined,
              label: 'Save Preset',
              onTap: _savePreset,
            ),
            // Dark/Light toggle (only for themes without fixed brightness)
            if (!tm.hasFixedBrightness)
              _SmallButton(
                icon:
                    tm.isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                label: tm.isDark ? 'Light Mode' : 'Dark Mode',
                onTap: () => tm.toggleBrightness(),
              ),
            if (hasOverrides)
              _SmallButton(
                icon: Icons.restart_alt,
                label: 'Reset All',
                onTap: () => tm.clearColorOverrides(),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Supports JSON, JetBrains ICLS/XML, and VS Code themes',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 20),
        // ── Active theme label ──
        Text(
          activeLabel,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // ── YoLo Orb live preview ──
        _OrbColorPreview(onPick: _pickColor),
        const SizedBox(height: 16),
        // ── Color categories ──
        ...ThemeManager.colorCategories.entries.map((cat) {
          return _ColorCategoryRow(
            title: cat.key,
            slots: cat.value,
            onPick: _pickColor,
          );
        }),
      ],
    );
  }
}

// ─────────────────────────── orb color preview for appearance section ─────────

/// Inline YoLo orb preview shown inside the Appearance settings section.
///
/// Shows the animated orb beside its three customisable colour swatches so the
/// user can see live changes as they pick colours.
class _OrbColorPreview extends StatelessWidget {
  const _OrbColorPreview({required this.onPick});

  final Future<void> Function(String slot, Color current) onPick;

  static const _orbSlots = [
    (key: 'orbCyan', label: 'Cyan'),
    (key: 'orbPurple', label: 'Purple'),
    (key: 'orbPink', label: 'Pink'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tm = ThemeManager.instance;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Animated orb
          YoloOrbPreview(size: 80),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YoLo ORB',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children:
                      _orbSlots.map((slot) {
                        final currentColor = tm.colorForSlot(slot.key);
                        final isOverridden = tm.colorOverrides.containsKey(
                          slot.key,
                        );
                        return _ColorSwatch(
                          label: slot.label,
                          color: currentColor,
                          isOverridden: isOverridden,
                          onTap: () => onPick(slot.key, currentColor),
                          onReset:
                              isOverridden
                                  ? () => tm.removeColorOverride(slot.key)
                                  : null,
                        );
                      }).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Customise the YoLo assistant orb colours',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.color,
    this.brightness,
    required this.isActive,
    required this.onTap,
    this.onDelete,
  });

  final String label;
  final Color color;
  final Brightness? brightness;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = brightness == Brightness.light;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: isActive ? colors.primary.withAlpha(30) : colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? colors.primary : colors.border,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isLight ? Colors.black26 : Colors.white24,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    isActive
                        ? colors.primary
                        : context.appColors.textMuted,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.close, size: 12, color: colors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorCategoryRow extends StatelessWidget {
  const _ColorCategoryRow({
    required this.title,
    required this.slots,
    required this.onPick,
  });

  final String title;
  final List<({String key, String label})> slots;
  final Future<void> Function(String slot, Color current) onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tm = ThemeManager.instance;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                slots.map((slot) {
                  final currentColor = tm.colorForSlot(slot.key);
                  final isOverridden = tm.colorOverrides.containsKey(slot.key);
                  return _ColorSwatch(
                    label: slot.label,
                    color: currentColor,
                    isOverridden: isOverridden,
                    onTap: () => onPick(slot.key, currentColor),
                    onReset:
                        isOverridden
                            ? () => tm.removeColorOverride(slot.key)
                            : null,
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.label,
    required this.color,
    required this.isOverridden,
    required this.onTap,
    this.onReset,
  });

  final String label;
  final Color color;
  final bool isOverridden;
  final VoidCallback onTap;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isOverridden ? colors.primary : colors.border,
                    width: isOverridden ? 2 : 1,
                  ),
                ),
              ),
              if (isOverridden && onReset != null)
                Positioned(
                  right: -5,
                  top: -5,
                  child: GestureDetector(
                    onTap: onReset,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 7,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: colors.textMuted, fontSize: 9)),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// HSV-based color picker dialog.
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initialColor});

  final String title;
  final Color initialColor;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _colorToHex(_hsv.toColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) {
    return '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _updateFromHex(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return;
    try {
      final color = Color(int.parse('FF$h', radix: 16));
      setState(() {
        _hsv = HSVColor.fromColor(color);
      });
    } catch (_) {}
  }

  static const _presetColors = [
    Color(0xFF00FF9F),
    Color(0xFF00DD88),
    Color(0xFF00CC7A),
    Color(0xFF067D17),
    Color(0xFF2ECC71),
    Color(0xFF27AE60),
    Color(0xFF1ABC9C),
    Color(0xFF16A085),
    Color(0xFFFF4F6A),
    Color(0xFFFF6B6B),
    Color(0xFFE74C3C),
    Color(0xFFC0392B),
    Color(0xFFDE1B2E),
    Color(0xFFFF1744),
    Color(0xFFD50000),
    Color(0xFFB71C1C),
    Color(0xFF00B4FF),
    Color(0xFF3498DB),
    Color(0xFF2980B9),
    Color(0xFF0066CC),
    Color(0xFF548AF7),
    Color(0xFF2196F3),
    Color(0xFF1976D2),
    Color(0xFF0D47A1),
    Color(0xFFFF9500),
    Color(0xFFF39C12),
    Color(0xFFE67E22),
    Color(0xFFD35400),
    Color(0xFFCC7700),
    Color(0xFFFF6F00),
    Color(0xFFFF8F00),
    Color(0xFFFFAB00),
    Color(0xFF9B59B6),
    Color(0xFF8E44AD),
    Color(0xFF7C3AED),
    Color(0xFF6C3483),
    Color(0xFFE91E63),
    Color(0xFFF06292),
    Color(0xFFFFEB3B),
    Color(0xFFCDDC39),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pickedColor = _hsv.toColor();
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: pickedColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontFamily: 'SF Mono',
                      ),
                      decoration: InputDecoration(
                        labelText: 'Hex',
                        labelStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (v) {
                        _updateFromHex(v);
                        _hexController.text = _colorToHex(_hsv.toColor());
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _HsvSlider(
                label: 'Hue',
                value: _hsv.hue,
                max: 360,
                color: _hsv.toColor(),
                borderColor: colors.border,
                labelColor: colors.textMuted,
                onChanged:
                    (v) => setState(() {
                      _hsv = _hsv.withHue(v);
                      _hexController.text = _colorToHex(_hsv.toColor());
                    }),
              ),
              const SizedBox(height: 8),
              _HsvSlider(
                label: 'Saturation',
                value: _hsv.saturation,
                max: 1,
                color: _hsv.toColor(),
                borderColor: colors.border,
                labelColor: colors.textMuted,
                onChanged:
                    (v) => setState(() {
                      _hsv = _hsv.withSaturation(v);
                      _hexController.text = _colorToHex(_hsv.toColor());
                    }),
              ),
              const SizedBox(height: 8),
              _HsvSlider(
                label: 'Brightness',
                value: _hsv.value,
                max: 1,
                color: _hsv.toColor(),
                borderColor: colors.border,
                labelColor: colors.textMuted,
                onChanged:
                    (v) => setState(() {
                      _hsv = _hsv.withValue(v);
                      _hexController.text = _colorToHex(_hsv.toColor());
                    }),
              ),
              const SizedBox(height: 14),
              Text(
                'Presets',
                style: TextStyle(color: colors.textMuted, fontSize: 10),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children:
                    _presetColors.map((c) {
                      return GestureDetector(
                        onTap:
                            () => setState(() {
                              _hsv = HSVColor.fromColor(c);
                              _hexController.text = _colorToHex(c);
                            }),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color:
                                  c == pickedColor
                                      ? Colors.white
                                      : colors.border,
                              width: c == pickedColor ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(pickedColor),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HsvSlider extends StatelessWidget {
  const _HsvSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.borderColor,
    required this.labelColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final Color borderColor;
  final Color labelColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 10)),
        const SizedBox(height: 2),
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: color,
              inactiveTrackColor: borderColor,
              thumbColor: Colors.white,
            ),
            child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

// ─── Keyboard Shortcuts ───────────────────────────────────────────────────────

class _ShortcutsTable extends StatefulWidget {
  @override
  State<_ShortcutsTable> createState() => _ShortcutsTableState();
}

class _ShortcutsTableState extends State<_ShortcutsTable> {
  final _registry = HotkeyRegistry.instance;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_rebuild);
  }

  @override
  void dispose() {
    _registry.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Map<String, List<HotkeyDefinition>> get _grouped {
    final map = <String, List<HotkeyDefinition>>{};
    for (final d in _registry.definitions) {
      (map[d.category] ??= []).add(d);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final grouped = _grouped;
    final hasAny = _registry.definitions.any((d) => d.isOverridden);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...grouped.entries.map(
          (entry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  entry.key.toUpperCase(),
                  style: TextStyle(
                    color:
                        context.appColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children:
                      entry.value.indexed.map(((int, HotkeyDefinition) e) {
                        final (index, def) = e;
                        final isLast = index == entry.value.length - 1;
                        return _HotkeyRow(
                          definition: def,
                          isLast: isLast,
                          onEdit: () => _showKeyCapture(context, def),
                          onReset:
                              def.isOverridden
                                  ? () => _registry.resetBinding(def.id)
                                  : null,
                        );
                      }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (hasAny)
          TextButton.icon(
            onPressed: () => _registry.resetAll(),
            icon: const Icon(Icons.restart_alt, size: 14),
            label: const Text('Reset all to defaults'),
            style: TextButton.styleFrom(
              foregroundColor:
                  context.appColors.textMuted,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> _showKeyCapture(
    BuildContext context,
    HotkeyDefinition def,
  ) async {
    final result = await showDialog<SingleActivator>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _KeyCaptureDialog(definition: def),
    );
    if (result != null) {
      await _registry.setBinding(def.id, result);
    }
  }
}

class _HotkeyRow extends StatelessWidget {
  const _HotkeyRow({
    required this.definition,
    required this.isLast,
    required this.onEdit,
    required this.onReset,
  });

  final HotkeyDefinition definition;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border:
            isLast ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Description
          Expanded(
            child: Text(
              definition.description,
              style: TextStyle(
                color:
                    definition.isOverridden
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).textTheme.bodyMedium?.color ??
                            Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Key badge(s)
          _KeyBadge(activator: definition.currentActivator),
          if (definition.isOverridden) ...[
            const SizedBox(width: 6),
            Tooltip(
              message:
                  'Default: ${HotkeyDefinition.formatActivator(definition.defaultActivator)}',
              child: GestureDetector(
                onTap: onReset,
                child: Icon(
                  Icons.restart_alt,
                  size: 14,
                  color:
                      context.appColors.textMuted,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // Edit button
          Tooltip(
            message: 'Remap shortcut',
            child: GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: colors.primary.withAlpha(60)),
                ),
                child: Text(
                  'Edit',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyBadge extends StatelessWidget {
  const _KeyBadge({required this.activator});
  final SingleActivator activator;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        HotkeyDefinition.formatActivator(activator),
        style: TextStyle(
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// Dialog that captures the next key combo the user presses.
class _KeyCaptureDialog extends StatefulWidget {
  const _KeyCaptureDialog({required this.definition});
  final HotkeyDefinition definition;

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  final _focusNode = FocusNode();
  SingleActivator? _captured;
  String? _conflict;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    // Ignore pure modifier keys
    final modifiers = {
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
    };
    if (modifiers.contains(key)) return;

    // Escape = cancel
    if (key == LogicalKeyboardKey.escape &&
        !HardwareKeyboard.instance.isMetaPressed) {
      Navigator.of(context).pop();
      return;
    }

    final activator = SingleActivator(
      key,
      meta: HardwareKeyboard.instance.isMetaPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      control: HardwareKeyboard.instance.isControlPressed,
    );

    // Check for conflict
    final conflict =
        HotkeyRegistry.instance.definitions
            .where((d) => d.id != widget.definition.id)
            .where(
              (d) =>
                  d.currentActivator.trigger.keyId == key.keyId &&
                  d.currentActivator.meta == activator.meta &&
                  d.currentActivator.shift == activator.shift &&
                  d.currentActivator.alt == activator.alt &&
                  d.currentActivator.control == activator.control,
            )
            .firstOrNull;

    setState(() {
      _captured = activator;
      _conflict = conflict?.description;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remap: ${widget.definition.description}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              // Capture area
              GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: Container(
                  width: double.infinity,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _captured != null ? colors.primary : colors.border,
                      width: _captured != null ? 2 : 1,
                    ),
                  ),
                  child:
                      _captured == null
                          ? Text(
                            'Press a key combination…',
                            style: TextStyle(
                              color:
                                  context.appColors.textMuted,
                              fontSize: 14,
                            ),
                          )
                          : Text(
                            HotkeyDefinition.formatActivator(_captured!),
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                ),
              ),
              if (_conflict != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Conflicts with "$_conflict" — saving will override it',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        _captured == null
                            ? null
                            : () => Navigator.of(context).pop(_captured),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutSection extends StatefulWidget {
  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  bool _checking = false;
  bool _autoCheck = true;
  UpdateInfo? _updateInfo;
  String? _upToDateMsg;
  bool _installing = false;
  double? _installProgress;
  String _installStatus = '';

  @override
  void initState() {
    super.initState();
    SessionPrefs.isAutoUpdateCheckEnabled().then((v) {
      if (mounted) setState(() => _autoCheck = v);
    });
    // Eagerly load the real version from Info.plist so the UI shows it.
    UpdateService.getAppVersion().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _upToDateMsg = null;
      _updateInfo = null;
    });
    final info = await UpdateService.checkForUpdate(force: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateInfo = info;
      if (info == null)
        _upToDateMsg =
            'You are on the latest version (${UpdateService.currentVersion}).';
    });
  }

  Future<void> _installUpdate(UpdateInfo info) async {
    setState(() {
      _installing = true;
      _installProgress = null;
      _installStatus = 'Preparing…';
    });
    try {
      await UpdateService.downloadAndInstall(
        info,
        onProgress: (progress, status) {
          if (mounted)
            setState(() {
              _installProgress = progress;
              _installStatus = status;
            });
        },
      );
      // If we get here without exit(), the installer opened browser fallback.
    } catch (e) {
      if (mounted) {
        final colors = context.appColors;
        setState(() {
          _installing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: colors.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── App info ────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YoLoIT — AI Orchestrator',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'v${UpdateService.currentVersion}',
                              style: TextStyle(
                                color:
                                    context.appColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                            if (UpdateService.isDevBuild) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.accentOrange.withAlpha(30),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: colors.accentOrange.withAlpha(80),
                                  ),
                                ),
                                child: Text(
                                  'DEV',
                                  style: TextStyle(
                                    color: colors.accentOrange,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'A Flutter desktop app for orchestrating AI CLI tools (GitHub Copilot, Claude Code) with embedded PTY terminals and git workspace management.',
                style: TextStyle(
                  color:
                      context.appColors.textMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Platform: macOS (primary) • Windows (coming soon)',
                style: TextStyle(
                  color:
                      context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Update section ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Updates',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              // Auto-check toggle
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Auto-check for updates',
                      style: TextStyle(
                        color:
                            Theme.of(context).textTheme.bodyMedium?.color ??
                            Theme.of(context).colorScheme.onSurface,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Switch(
                    value: _autoCheck,
                    activeColor: colors.accentBlue,
                    onChanged: (v) {
                      setState(() => _autoCheck = v);
                      SessionPrefs.saveAutoUpdateCheckEnabled(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Checks GitHub releases once per day in release builds.',
                style: TextStyle(
                  color:
                      context.appColors.textMuted,
                  fontSize: 10,
                ),
              ),

              const SizedBox(height: 16),

              // Check now button
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _checking ? null : _checkNow,
                    icon:
                        _checking
                            ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.search, size: 14),
                    label: Text(
                      _checking ? 'Checking...' : 'Check for Updates',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.surfaceElevated,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      textStyle: const TextStyle(fontSize: 11),
                      side: BorderSide(color: colors.border),
                      elevation: 0,
                    ),
                  ),
                ],
              ),

              // Result
              if (_upToDateMsg != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: colors.accentGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _upToDateMsg!,
                      style: TextStyle(color: colors.accentGreen, fontSize: 11),
                    ),
                  ],
                ),
              ],

              if (_updateInfo != null) ...[
                const SizedBox(height: 10),
                if (_installing) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _installStatus,
                        style: TextStyle(
                          color:
                              Theme.of(context).textTheme.bodyMedium?.color ??
                              Theme.of(context).colorScheme.onSurface,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: _installProgress,
                        backgroundColor: colors.accentBlue.withAlpha(30),
                        color: colors.accentBlue,
                        minHeight: 3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'App will restart automatically after install.',
                        style: TextStyle(
                          color:
                              context.appColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ] else
                  _UpdateAvailableCard(
                    info: _updateInfo!,
                    onDownload: () => _installUpdate(_updateInfo!),
                    onSkip: () async {
                      await UpdateService.skipVersion(_updateInfo!.version);
                      if (mounted) setState(() => _updateInfo = null);
                    },
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdateAvailableCard extends StatelessWidget {
  const _UpdateAvailableCard({
    required this.info,
    required this.onDownload,
    required this.onSkip,
  });
  final UpdateInfo info;
  final VoidCallback onDownload;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.accentBlue.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.accentBlue.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 14,
                color: colors.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                '${info.tagName} is available!',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              info.releaseNotes.length > 200
                  ? '${info.releaseNotes.substring(0, 200)}...'
                  : info.releaseNotes,
              style: TextStyle(
                color:
                    context.appColors.textMuted,
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded, size: 14),
                label: const Text('Download'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentBlue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 11),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Skip this version',
                  style: TextStyle(
                    fontSize: 10,
                    color:
                        context.appColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Session Settings ─────────────────────────────────────────────────────────

class _SessionSettings extends StatefulWidget {
  @override
  State<_SessionSettings> createState() => _SessionSettingsState();
}

class _SessionSettingsState extends State<_SessionSettings> {
  final _tmux = TmuxService.instance;
  final _logging = LoggingService.instance;

  bool _loggingOn = false;
  bool _tmuxOn = false;
  bool _showLogs = false;
  List<LogFile> _logs = [];
  bool _logsLoading = false;

  bool _appLoggingOn = false;
  bool _showAppLog = false;
  String _appLogContent = '';
  bool _appLogLoading = false;

  @override
  void initState() {
    super.initState();
    _loggingOn = _logging.enabled;
    _tmuxOn = _tmux.enabled;
    _appLoggingOn = AppLogger.instance.enabled;
  }

  Future<void> _loadLogs() async {
    setState(() => _logsLoading = true);
    final logs = await _logging.listLogs();
    if (mounted)
      setState(() {
        _logs = logs;
        _logsLoading = false;
      });
  }

  Future<void> _deleteLog(String path) async {
    await _logging.deleteLog(path);
    await _loadLogs();
  }

  Future<void> _clearAll() async {
    await _logging.clearAll();
    await _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tmux toggle
          _ToggleRow(
            icon: Icons.terminal,
            title: 'Keep sessions alive after closing app',
            subtitle:
                _tmux.available
                    ? 'Uses tmux — sessions survive app restart'
                    : 'Requires tmux — install with: brew install tmux',
            value: _tmuxOn && _tmux.available,
            enabled: _tmux.available,
            onChanged: (v) async {
              await _tmux.setEnabled(v);
              if (mounted) setState(() => _tmuxOn = v);
            },
          ),
          Divider(height: 1, color: colors.border),
          // Terminal logging toggle
          _ToggleRow(
            icon: Icons.description_outlined,
            title: 'Log terminal output to files',
            subtitle: 'Saved to ~/.yoloit/logs/',
            value: _loggingOn,
            onChanged: (v) async {
              await _logging.setEnabled(v);
              if (mounted) {
                setState(() {
                  _loggingOn = v;
                  if (!v) _showLogs = false;
                });
              }
            },
          ),
          // Terminal logs viewer
          if (_loggingOn) ...[
            Divider(height: 1, color: colors.border),
            InkWell(
              onTap: () {
                setState(() => _showLogs = !_showLogs);
                if (!_showLogs) return;
                _loadLogs();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      _showLogs ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color:
                          context.appColors.textMuted,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'View log files',
                      style: TextStyle(color: colors.primary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_showLogs) _buildLogsSection(context),
          ],
          // App diagnostics logging
          Divider(height: 1, color: colors.border),
          _ToggleRow(
            icon: Icons.bug_report_outlined,
            title: 'Log app diagnostics to file',
            subtitle:
                'Saved to ~/Library/Logs/yoloit/app.log (max 5 MB, rotates)',
            value: _appLoggingOn,
            onChanged: (v) async {
              await AppLogger.instance.setEnabled(v);
              if (mounted)
                setState(() {
                  _appLoggingOn = v;
                  if (!v) _showAppLog = false;
                });
            },
          ),
          if (_appLoggingOn) ...[
            Divider(height: 1, color: colors.border),
            InkWell(
              onTap: () {
                setState(() => _showAppLog = !_showAppLog);
                if (_showAppLog) _loadAppLog();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      _showAppLog ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color:
                          context.appColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View app log',
                      style: TextStyle(color: colors.primary, fontSize: 13),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await AppLogger.instance.clearLog();
                        if (_showAppLog) _loadAppLog();
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showAppLog) _buildAppLogSection(context),
          ],
          Divider(height: 1, color: colors.border),
          _WorkspaceStorageRow(),
        ],
      ),
    );
  }

  Future<void> _loadAppLog() async {
    setState(() => _appLogLoading = true);
    final content = await AppLogger.instance.readLog();
    if (mounted)
      setState(() {
        _appLogContent = content;
        _appLogLoading = false;
      });
  }

  Widget _buildAppLogSection(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '~/.config/yoloit/app.log',
                  style: TextStyle(
                    color:
                        context.appColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await AppLogger.instance.clearLog();
                  _loadAppLog();
                },
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_appLogLoading)
            const Center(child: CircularProgressIndicator())
          else
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.border),
              ),
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  _appLogContent,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color:
                        context.appColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogsSection(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_logs.length} file(s)',
                style: TextStyle(
                  color:
                      context.appColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (_logs.isNotEmpty)
                TextButton(
                  onPressed: _clearAll,
                  child: const Text(
                    'Clear all',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _loadLogs,
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color:
                    context.appColors.textMuted,
              ),
            ],
          ),
          if (_logsLoading)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_logs.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No logs yet.',
                style: TextStyle(
                  color:
                      context.appColors.textMuted,
                  fontSize: 12,
                ),
              ),
            )
          else
            ...(_logs
                .take(10)
                .map(
                  (log) => _LogRow(
                    log: log,
                    onDelete: () => _deleteLog(log.path),
                    onView: () => _showLogContent(context, log),
                  ),
                )),
        ],
      ),
    );
  }

  void _showLogContent(BuildContext context, LogFile log) {
    final colors = context.appColors;
    showDialog<void>(
      context: context,
      builder:
          (_) => Dialog(
            backgroundColor: colors.surface,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: 40,
            ),
            child: _LogViewerDialog(log: log),
          ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color:
                context.appColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color:
                        enabled
                            ? Theme.of(context).colorScheme.onSurface
                            : context.appColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color:
                        context.appColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value && enabled,
            onChanged: enabled ? onChanged : null,
            activeColor: colors.primary,
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.log,
    required this.onDelete,
    required this.onView,
  });

  final LogFile log;
  final VoidCallback onDelete;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 14,
            color:
                context.appColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onView,
              child: Text(
                log.name,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Text(
            log.sizeLabel,
            style: TextStyle(
              color:
                  context.appColors.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Icon(
              Icons.close,
              size: 14,
              color:
                  context.appColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogViewerDialog extends StatefulWidget {
  const _LogViewerDialog({required this.log});
  final LogFile log;

  @override
  State<_LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<_LogViewerDialog> {
  String? _content;

  @override
  void initState() {
    super.initState();
    LoggingService.instance.readLog(widget.log.path).then((c) {
      if (mounted) setState(() => _content = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.log.name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  widget.log.sizeLabel,
                  style: TextStyle(
                    color:
                        context.appColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color:
                        context.appColors.textMuted,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child:
                _content == null
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _content!,
                        style: TextStyle(
                          color:
                              Theme.of(context).textTheme.bodyMedium?.color ??
                              Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace storage path row
// ---------------------------------------------------------------------------

// ignore: must_be_immutable
class _WorkspaceStorageRow extends StatefulWidget {
  @override
  State<_WorkspaceStorageRow> createState() => _WorkspaceStorageRowState();
}

class _WorkspaceStorageRowState extends State<_WorkspaceStorageRow> {
  late String _currentPath;

  @override
  void initState() {
    super.initState();
    _currentPath = AppConfig.instance.workspacesFilePath;
  }

  Future<void> _pickDirectory(BuildContext context) async {
    final result = await BoardFilePicker.pickDirectory(
      context,
      initialPath: p.dirname(_currentPath),
      title: 'Choose workspace storage folder',
    );
    if (result == null) return;
    final newPath = '$result/workspaces.json';
    await AppConfig.instance.setWorkspacesFilePath(newPath);
    if (mounted) {
      setState(() => _currentPath = newPath);
      if (context.mounted) await context.read<WorkspaceCubit>().load();
    }
  }

  Future<void> _resetPath(BuildContext context) async {
    await AppConfig.instance.resetWorkspacesFilePath();
    if (mounted) {
      setState(() => _currentPath = AppConfig.instance.workspacesFilePath);
      if (context.mounted) await context.read<WorkspaceCubit>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDefault = _currentPath == AppConfig.defaultWorkspacesFilePath;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.folder_open,
            size: 16,
            color:
                context.appColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workspace storage',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentPath,
                  style: TextStyle(
                    color:
                        context.appColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _pickDirectory(context),
            child: Text(
              'Change…',
              style: TextStyle(fontSize: 12, color: colors.primary),
            ),
          ),
          if (!isDefault)
            TextButton(
              onPressed: () => _resetPath(context),
              child: Text(
                'Reset',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).textTheme.bodyMedium?.color ??
                      Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Notifications Settings ───────────────────────────────────────────────────

class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection();

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  bool _agentSoundsEnabled = true;
  bool _approvalSoundEnabled = true;
  bool _completionSoundEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final agent = await SessionPrefs.isAgentSoundsEnabled();
    final approval = await SessionPrefs.isApprovalSoundEnabled();
    final completion = await SessionPrefs.isCompletionSoundEnabled();
    if (mounted) {
      setState(() {
        _agentSoundsEnabled = agent;
        _approvalSoundEnabled = approval;
        _completionSoundEnabled = completion;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sound alerts when AI agents change state.',
          style: TextStyle(
            color:
                context.appColors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 16),
        _SettingsToggle(
          title: 'Enable agent sounds',
          subtitle: 'Master switch — disables all agent sound alerts',
          value: _agentSoundsEnabled,
          onChanged: (v) {
            setState(() => _agentSoundsEnabled = v);
            SessionPrefs.saveAgentSoundsEnabled(v);
          },
        ),
        const SizedBox(height: 8),
        _SettingsToggle(
          title: 'Approval request sound (Sosumi)',
          subtitle: 'Plays when agent is waiting for tool approval',
          value: _approvalSoundEnabled && _agentSoundsEnabled,
          enabled: _agentSoundsEnabled,
          onChanged:
              _agentSoundsEnabled
                  ? (v) {
                    setState(() => _approvalSoundEnabled = v);
                    SessionPrefs.saveApprovalSoundEnabled(v);
                  }
                  : null,
        ),
        const SizedBox(height: 8),
        _SettingsToggle(
          title: 'Completion sound (Glass)',
          subtitle: 'Plays when agent finishes responding',
          value: _completionSoundEnabled && _agentSoundsEnabled,
          enabled: _agentSoundsEnabled,
          onChanged:
              _agentSoundsEnabled
                  ? (v) {
                    setState(() => _completionSoundEnabled = v);
                    SessionPrefs.saveCompletionSoundEnabled(v);
                  }
                  : null,
        ),
      ],
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color:
                        enabled
                            ? Theme.of(context).colorScheme.onSurface
                            : context.appColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color:
                        context.appColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: colors.primary,
          ),
        ],
      ),
    );
  }
}
