import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/settings/ui/cloud_providers_section.dart';
import 'package:yoloit/features/settings/ui/debug_ui/debug_ui_shell.dart';
import 'package:yoloit/features/settings/ui/dialogs/color_picker_dialog.dart';
import 'package:yoloit/features/settings/ui/global_env_groups_section.dart';
import 'package:yoloit/features/settings/ui/sections/about_section.dart';
import 'package:yoloit/features/settings/ui/sections/agent_settings_section.dart';
import 'package:yoloit/features/settings/ui/sections/chat_context_section.dart';
import 'package:yoloit/features/settings/ui/sections/ignored_tool_calls_section.dart';
import 'package:yoloit/features/settings/ui/sections/notifications_section.dart';
import 'package:yoloit/features/settings/ui/sections/prompts_section.dart';
import 'package:yoloit/features/settings/ui/sections/section_header.dart';
import 'package:yoloit/features/settings/ui/sections/session_settings_section.dart';
import 'package:yoloit/features/settings/ui/sections/shortcuts_table_section.dart';
import 'package:yoloit/features/settings/ui/sections/support_section.dart';
import 'package:yoloit/features/settings/ui/sections/terminal_renderer_settings.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';
import 'package:yoloit/features/settings/ui/sync_section.dart';
import 'package:yoloit/features/settings/ui/widget_permissions_section.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/ui/skills_panel.dart';
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
            NotificationsSection(),
          ],
        ),
        5 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Sessions'),
            SizedBox(height: 12),
            SessionSettings(),
          ],
        ),
        6 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Keyboard Shortcuts'),
            SizedBox(height: 12),
            ShortcutsTable(),
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
        12 => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'About'),
            SizedBox(height: 12),
            AboutSection(),
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

