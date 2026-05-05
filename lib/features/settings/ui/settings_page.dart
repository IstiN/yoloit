import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/hotkeys/hotkey_definition.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/ui/skills_panel.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/updates/data/update_service.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

const _kCategories = [
  'Appearance',
  'AI Agents',
  'Notifications',
  'Sessions',
  'Shortcuts',
  'Skills',
  'Setup Guide',
  'About',
];

/// Settings overlay shown as a modal dialog with sidebar navigation.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static Future<void> show(BuildContext context) {
    final wsCubit = context.read<WorkspaceCubit>();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (_) => BlocProvider(
        create: (_) => SkillsCubit(),
        child: BlocProvider.value(
          value: wsCubit,
          child: const Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(horizontal: 60, vertical: 40),
            child: SettingsPage(),
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
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
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
          const Text(
            'Settings',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: 140,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _kCategories.length,
        itemBuilder: (context, index) {
          final isActive = index == _selectedCategory;
          return InkWell(
            onTap: () => setState(() => _selectedCategory = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isActive ? colors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                _kCategories[index],
                style: TextStyle(
                  color: isActive ? colors.primary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
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
    if (_selectedCategory == 5) {
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
              const _SectionHeader(title: 'AI Agents'),
              const SizedBox(height: 12),
              _AgentSettingsSection(),
            ],
          ),
        2 => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(title: 'Notifications'),
              const SizedBox(height: 12),
              const _NotificationsSection(),
            ],
          ),
        3 => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(title: 'Sessions'),
              const SizedBox(height: 12),
              _SessionSettings(),
            ],
          ),
        4 => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(title: 'Keyboard Shortcuts'),
              const SizedBox(height: 12),
              _ShortcutsTable(),
            ],
          ),
        6 => const SetupGuideEmbedded(),
        _ => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(title: 'About'),
              const SizedBox(height: 12),
              _AboutSection(),
            ],
          ),
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

// ─── AI Agents Settings ───────────────────────────────────────────────────────

class _AgentSettingsSection extends StatefulWidget {
  @override
  State<_AgentSettingsSection> createState() => _AgentSettingsSectionState();
}

class _AgentSettingsSectionState extends State<_AgentSettingsSection> {
  final _service = AgentConfigService.instance;
  List<AgentConfig>? _configs;
  bool _loading = true;
  String? _defaultAgentId;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final configs = await _service.load();
    if (mounted) setState(() {
      _configs = configs;
      _defaultAgentId = _service.defaultAgentId;
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

  void _deleteConfig(int index) {
    setState(() => _configs!.removeAt(index));
    _saveConfigs();
  }

  Future<void> _setDefault(String? id) async {
    setState(() => _defaultAgentId = id);
    await _service.setDefaultAgentId(id);
  }

  void _addCustomAgent() {
    final newConfig = AgentConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      displayName: 'Custom Agent',
      iconLabel: '◈',
      launchCommand: '',
      visible: true,
      isBuiltIn: false,
    );
    setState(() => _configs!.add(newConfig));
    _saveConfigs();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = context.appColors;
    final configs = _configs!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Star (★) an agent to make it open automatically for new workspaces.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: configs.indexed.map(((int, AgentConfig) e) {
              final (index, config) = e;
              final isLast = index == configs.length - 1;
              final isDefault = config.id == _defaultAgentId;
              return Column(
                children: [
                  _AgentRow(
                    config: config,
                    isDefault: isDefault,
                    onChanged: (updated) => _updateConfig(index, updated),
                    onDelete: config.isBuiltIn ? null : () => _deleteConfig(index),
                    onSetDefault: () => _setDefault(isDefault ? null : config.id),
                  ),
                  if (!isLast) Divider(height: 1, color: colors.border),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _addCustomAgent,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Custom Agent'),
          style: TextButton.styleFrom(
            foregroundColor: colors.primary,
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _AgentRow extends StatefulWidget {
  const _AgentRow({
    required this.config,
    required this.isDefault,
    required this.onChanged,
    required this.onDelete,
    required this.onSetDefault,
  });

  final AgentConfig config;
  final bool isDefault;
  final ValueChanged<AgentConfig> onChanged;
  final VoidCallback? onDelete;
  final VoidCallback onSetDefault;

  @override
  State<_AgentRow> createState() => _AgentRowState();
}

class _AgentRowState extends State<_AgentRow> {
  late TextEditingController _nameCtrl;
  late TextEditingController _iconCtrl;
  late TextEditingController _cmdCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.config.displayName);
    _iconCtrl = TextEditingController(text: widget.config.iconLabel);
    _cmdCtrl = TextEditingController(text: widget.config.launchCommand);
  }

  @override
  void didUpdateWidget(_AgentRow old) {
    super.didUpdateWidget(old);
    if (old.config.id != widget.config.id) {
      _nameCtrl.text = widget.config.displayName;
      _iconCtrl.text = widget.config.iconLabel;
      _cmdCtrl.text = widget.config.launchCommand;
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
    widget.onChanged(widget.config.copyWith(
      displayName: _nameCtrl.text,
      iconLabel: _iconCtrl.text,
      launchCommand: _cmdCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Visibility toggle
          Switch(
            value: widget.config.visible,
            onChanged: (v) =>
                widget.onChanged(widget.config.copyWith(visible: v)),
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
                color: AppColors.textPrimary,
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
              onChanged: (_) => _emit(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Name',
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
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
          // Launch command
          Expanded(
            child: TextField(
              controller: _cmdCtrl,
              onChanged: (_) => _emit(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'launch command (empty = plain shell)',
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
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
          // Default star button
          const SizedBox(width: 4),
          Tooltip(
            message: widget.isDefault ? 'Default agent (click to unset)' : 'Set as default agent',
            child: GestureDetector(
              onTap: widget.onSetDefault,
              child: Icon(
                widget.isDefault ? Icons.star : Icons.star_border,
                size: 18,
                color: widget.isDefault ? Colors.amber : AppColors.textMuted,
              ),
            ),
          ),
          // Delete button (custom only)
          if (widget.onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.textMuted,
              ),
              onPressed: widget.onDelete,
              tooltip: 'Delete agent',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ] else
            const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatefulWidget {
  @override
  State<_ThemeSelector> createState() => _ThemeSelectorState();
}

class _ThemeSelectorState extends State<_ThemeSelector> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final current = ThemeManager.instance.current;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AppThemePreset.values.map((preset) {
        final isActive = preset == current;
        return GestureDetector(
          onTap: () {
            ThemeManager.instance.setTheme(preset);
            setState(() {});
          },
          child: Container(
            width: 100,
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? colors.primary.withAlpha(30)
                  : colors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? colors.primary : colors.border,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: preset.theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  preset.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? colors.primary : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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
        ...grouped.entries.map((entry) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.textMuted,
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
                    children: entry.value.indexed.map(((int, HotkeyDefinition) e) {
                      final (index, def) = e;
                      final isLast = index == entry.value.length - 1;
                      return _HotkeyRow(
                        definition: def,
                        isLast: isLast,
                        onEdit: () => _showKeyCapture(context, def),
                        onReset: def.isOverridden
                            ? () => _registry.resetBinding(def.id)
                            : null,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            )),
        if (hasAny)
          TextButton.icon(
            onPressed: () => _registry.resetAll(),
            icon: const Icon(Icons.restart_alt, size: 14),
            label: const Text('Reset all to defaults'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> _showKeyCapture(BuildContext context, HotkeyDefinition def) async {
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
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Description
          Expanded(
            child: Text(
              definition.description,
              style: TextStyle(
                color: definition.isOverridden
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
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
              message: 'Default: ${HotkeyDefinition.formatActivator(definition.defaultActivator)}',
              child: GestureDetector(
                onTap: onReset,
                child: Icon(
                  Icons.restart_alt,
                  size: 14,
                  color: AppColors.textMuted,
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
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
    if (key == LogicalKeyboardKey.escape && !HardwareKeyboard.instance.isMetaPressed) {
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
    final conflict = HotkeyRegistry.instance.definitions
        .where((d) => d.id != widget.definition.id)
        .where((d) =>
            d.currentActivator.trigger.keyId == key.keyId &&
            d.currentActivator.meta == activator.meta &&
            d.currentActivator.shift == activator.shift &&
            d.currentActivator.alt == activator.alt &&
            d.currentActivator.control == activator.control)
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
                style: const TextStyle(
                  color: AppColors.textPrimary,
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
                  child: _captured == null
                      ? Text(
                          'Press a key combination…',
                          style: TextStyle(
                            color: AppColors.textMuted,
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
                    const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
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
                    onPressed: _captured == null
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
    SessionPrefs.isAutoUpdateCheckEnabled()
        .then((v) { if (mounted) setState(() => _autoCheck = v); });
    // Eagerly load the real version from Info.plist so the UI shows it.
    UpdateService.getAppVersion().then((_) { if (mounted) setState(() {}); });
  }

  Future<void> _checkNow() async {
    setState(() { _checking = true; _upToDateMsg = null; _updateInfo = null; });
    final info = await UpdateService.checkForUpdate(force: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateInfo = info;
      if (info == null) _upToDateMsg = 'You are on the latest version (${UpdateService.currentVersion}).';
    });
  }

  Future<void> _installUpdate(UpdateInfo info) async {
    setState(() { _installing = true; _installProgress = null; _installStatus = 'Preparing…'; });
    try {
      await UpdateService.downloadAndInstall(
        info,
        onProgress: (progress, status) {
          if (mounted) setState(() { _installProgress = progress; _installStatus = status; });
        },
      );
      // If we get here without exit(), the installer opened browser fallback.
    } catch (e) {
      if (mounted) {
        setState(() { _installing = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.neonRed),
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
                        const Text('YoLoIT — AI Orchestrator',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text('v${UpdateService.currentVersion}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            if (UpdateService.isDevBuild) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.neonOrange.withAlpha(30),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: AppColors.neonOrange.withAlpha(80)),
                                ),
                                child: const Text('DEV',
                                    style: TextStyle(color: AppColors.neonOrange, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
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
              const Text(
                'A Flutter desktop app for orchestrating AI CLI tools (GitHub Copilot, Claude Code) with embedded PTY terminals and git workspace management.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 6),
              const Text('Platform: macOS (primary) • Windows (coming soon)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
              const Text('Updates',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),

              // Auto-check toggle
              Row(
                children: [
                  const Expanded(
                    child: Text('Auto-check for updates',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  Switch(
                    value: _autoCheck,
                    activeColor: AppColors.neonBlue,
                    onChanged: (v) {
                      setState(() => _autoCheck = v);
                      SessionPrefs.saveAutoUpdateCheckEnabled(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Checks GitHub releases once per day in release builds.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10)),

              const SizedBox(height: 16),

              // Check now button
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _checking ? null : _checkNow,
                    icon: _checking
                        ? const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                          )
                        : const Icon(Icons.search, size: 14),
                    label: Text(_checking ? 'Checking...' : 'Check for Updates'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.surfaceElevated,
                      foregroundColor: AppColors.textPrimary,
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
                Row(children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: AppColors.neonGreen),
                  const SizedBox(width: 6),
                  Text(_upToDateMsg!, style: const TextStyle(color: AppColors.neonGreen, fontSize: 11)),
                ]),
              ],

              if (_updateInfo != null) ...[
                const SizedBox(height: 10),
                if (_installing) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_installStatus,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: _installProgress,
                        backgroundColor: AppColors.neonBlue.withAlpha(30),
                        color: AppColors.neonBlue,
                        minHeight: 3,
                      ),
                      const SizedBox(height: 4),
                      const Text('App will restart automatically after install.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
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
  const _UpdateAvailableCard({required this.info, required this.onDownload, required this.onSkip});
  final UpdateInfo info;
  final VoidCallback onDownload;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neonBlue.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.neonBlue.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt_rounded, size: 14, color: AppColors.neonBlue),
              const SizedBox(width: 8),
              Text('${info.tagName} is available!',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              info.releaseNotes.length > 200
                  ? '${info.releaseNotes.substring(0, 200)}...'
                  : info.releaseNotes,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.5),
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
                  backgroundColor: AppColors.neonBlue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 11),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSkip,
                child: const Text('Skip this version',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
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
    if (mounted) setState(() { _logs = logs; _logsLoading = false; });
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
            subtitle: _tmux.available
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
                setState(() { _loggingOn = v; if (!v) _showLogs = false; });
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _showLogs ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: AppColors.textMuted,
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
            subtitle: 'Saved to ~/Library/Logs/yoloit/app.log (max 5 MB, rotates)',
            value: _appLoggingOn,
            onChanged: (v) async {
              await AppLogger.instance.setEnabled(v);
              if (mounted) setState(() { _appLoggingOn = v; if (!v) _showAppLog = false; });
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _showAppLog ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: AppColors.textMuted,
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
                      child: const Text('Clear', style: TextStyle(fontSize: 12)),
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
    if (mounted) setState(() { _appLogContent = content; _appLogLoading = false; });
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
                child: Text('~/.config/yoloit/app.log',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11,
                        fontFamily: 'monospace')),
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
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textMuted,
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
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const Spacer(),
              if (_logs.isNotEmpty)
                TextButton(
                  onPressed: _clearAll,
                  child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _loadLogs,
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: AppColors.textMuted,
              ),
            ],
          ),
          if (_logsLoading)
            const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No logs yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            )
          else
            ...(_logs.take(10).map(
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
      builder: (_) => Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
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
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
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
          const Icon(Icons.insert_drive_file_outlined, size: 14, color: AppColors.textMuted),
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
          Text(log.sizeLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
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
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(widget.log.sizeLabel,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: _content == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _content!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
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
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose workspace storage folder',
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
          Icon(Icons.folder_open, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Workspace storage',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentPath,
                  style: const TextStyle(
                    color: AppColors.textMuted,
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
            child: Text('Change…', style: TextStyle(fontSize: 12, color: colors.primary)),
          ),
          if (!isDefault)
            TextButton(
              onPressed: () => _resetPath(context),
              child: const Text(
                'Reset',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    if (_loading) return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sound alerts when AI agents change state.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
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
          onChanged: _agentSoundsEnabled
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
          onChanged: _agentSoundsEnabled
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
                    color: enabled ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
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
