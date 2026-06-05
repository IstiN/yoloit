import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/hotkeys/hotkey_definition.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/services/app_logger.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/settings/ui/cloud_providers_section.dart';
import 'package:yoloit/features/settings/ui/debug_ui/debug_ui_shell.dart';
import 'package:yoloit/features/settings/ui/dialogs/color_picker_dialog.dart';
import 'package:yoloit/features/settings/ui/dialogs/key_capture_dialog.dart';
import 'package:yoloit/features/settings/ui/dialogs/log_viewer_dialog.dart';
import 'package:yoloit/features/settings/ui/global_env_groups_section.dart';
import 'package:yoloit/features/settings/ui/sections/agent_settings_section.dart';
import 'package:yoloit/features/settings/ui/sections/chat_context_section.dart';
import 'package:yoloit/features/settings/ui/sections/ignored_tool_calls_section.dart';
import 'package:yoloit/features/settings/ui/sections/prompts_section.dart';
import 'package:yoloit/features/settings/ui/sections/section_header.dart';
import 'package:yoloit/features/settings/ui/sections/support_section.dart';
import 'package:yoloit/features/settings/ui/sections/terminal_renderer_settings.dart';
import 'package:yoloit/features/settings/ui/sections/toggle_row.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';
import 'package:yoloit/features/settings/ui/sync_section.dart';
import 'package:yoloit/features/settings/ui/widget_permissions_section.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/ui/skills_panel.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
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
            const SectionHeader(title: 'Appearance'),
            const SizedBox(height: 12),
            _ThemeSelector(),
          ],
        ),
        1 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Cloud Providers'),
            SizedBox(height: 12),
            CloudProvidersSection(),
            SizedBox(height: 24),
            SectionHeader(title: 'AI Agents'),
            SizedBox(height: 12),
            AgentSettingsSection(),
            SizedBox(height: 20),
            SectionHeader(title: 'Ignored Tool Calls'),
            SizedBox(height: 12),
            IgnoredToolCallsSection(),
            SizedBox(height: 20),
            SectionHeader(title: 'Chat Context'),
            SizedBox(height: 12),
            ChatContextSection(),
          ],
        ),
        2 => const PromptsSection(),
        3 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Environment'),
            SizedBox(height: 12),
            GlobalEnvGroupsSection(),
          ],
        ),
        4 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Notifications'),
            SizedBox(height: 12),
            _NotificationsSection(),
          ],
        ),
        5 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Sessions'),
            const SizedBox(height: 12),
            _SessionSettings(),
          ],
        ),
        6 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Keyboard Shortcuts'),
            const SizedBox(height: 12),
            _ShortcutsTable(),
          ],
        ),
        8 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Sync'),
            SizedBox(height: 12),
            SyncSection(),
          ],
        ),
        9 => const SetupGuideEmbedded(),
        10 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Terminal'),
            SizedBox(height: 12),
            TerminalRendererSettings(),
            SizedBox(height: 24),
            SectionHeader(title: 'Widget API Permissions'),
            SizedBox(height: 12),
            WidgetPermissionsSection(),
          ],
        ),
        11 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Support'),
            SizedBox(height: 12),
            SupportSection(),
          ],
        ),
        12 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'About'),
            const SizedBox(height: 12),
            _AboutSection(),
          ],
        ),
        _ => kDebugMode ? const DebugUIShell() : const SizedBox.shrink(),
      },
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
      builder: (ctx) => ColorPickerDialog(title: label, initialColor: current),
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
          const YoloOrbPreview(size: 80),
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
                color: isActive ? colors.primary : context.appColors.textMuted,
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
                    color: context.appColors.textMuted,
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
              foregroundColor: context.appColors.textMuted,
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
      builder: (_) => KeyCaptureDialog(definition: def),
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
                  color: context.appColors.textMuted,
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
      if (info == null) {
        _upToDateMsg =
            'You are on the latest version (${UpdateService.currentVersion}).';
      }
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
          if (mounted) {
            setState(() {
              _installProgress = progress;
              _installStatus = status;
            });
          }
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
                                color: context.appColors.textMuted,
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
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Platform: macOS (primary) • Windows (coming soon)',
                style: TextStyle(
                  color: context.appColors.textMuted,
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
                    activeThumbColor: colors.accentBlue,
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
                  color: context.appColors.textMuted,
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
                          color: context.appColors.textMuted,
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
                color: context.appColors.textMuted,
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
                    color: context.appColors.textMuted,
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
    if (mounted) {
      setState(() {
        _logs = logs;
        _logsLoading = false;
      });
    }
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
          ToggleRow(
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
          ToggleRow(
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
                      color: context.appColors.textMuted,
                    ),
                    const SizedBox(width: 8),
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
          ToggleRow(
            icon: Icons.bug_report_outlined,
            title: 'Log app diagnostics to file',
            subtitle:
                'Saved to ~/Library/Logs/yoloit/app.log (max 5 MB, rotates)',
            value: _appLoggingOn,
            onChanged: (v) async {
              await AppLogger.instance.setEnabled(v);
              if (mounted) {
                setState(() {
                  _appLoggingOn = v;
                  if (!v) _showAppLog = false;
                });
              }
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
                      color: context.appColors.textMuted,
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
    if (mounted) {
      setState(() {
        _appLogContent = content;
        _appLogLoading = false;
      });
    }
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
                    color: context.appColors.textMuted,
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
                    color: context.appColors.textMuted,
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
                  color: context.appColors.textMuted,
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
                color: context.appColors.textMuted,
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No logs yet.',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                ),
              ),
            )
          else
            ...(_logs
                .take(10)
                .map(
                  (log) => LogRow(
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
            child: LogViewerDialog(log: log),
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
          Icon(Icons.folder_open, size: 16, color: context.appColors.textMuted),
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
                    color: context.appColors.textMuted,
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
    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sound alerts when AI agents change state.',
          style: TextStyle(color: context.appColors.textMuted, fontSize: 11),
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
                    color: context.appColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.primary,
          ),
        ],
      ),
    );
  }
}
