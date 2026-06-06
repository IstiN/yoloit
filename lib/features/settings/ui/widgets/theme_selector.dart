import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/settings/ui/dialogs/color_picker_dialog.dart';

class ThemeSelector extends StatefulWidget {
  const ThemeSelector({super.key});

  @override
  State<ThemeSelector> createState() => ThemeSelectorState();
}

class ThemeSelectorState extends State<ThemeSelector> {
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
              return PresetChip(
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
              return PresetChip(
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
            SmallButton(
              icon: Icons.file_download_outlined,
              label: 'Import',
              onTap: _importTheme,
            ),
            SmallButton(
              icon: Icons.file_upload_outlined,
              label: 'Export',
              onTap: _exportTheme,
            ),
            SmallButton(
              icon: Icons.save_outlined,
              label: 'Save Preset',
              onTap: _savePreset,
            ),
            // Dark/Light toggle (only for themes without fixed brightness)
            if (!tm.hasFixedBrightness)
              SmallButton(
                icon:
                    tm.isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                label: tm.isDark ? 'Light Mode' : 'Dark Mode',
                onTap: () => tm.toggleBrightness(),
              ),
            if (hasOverrides)
              SmallButton(
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
        OrbColorPreview(onPick: _pickColor),
        const SizedBox(height: 16),
        // ── Color categories ──
        ...ThemeManager.colorCategories.entries.map((cat) {
          return ColorCategoryRow(
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
class OrbColorPreview extends StatelessWidget {
  const OrbColorPreview({super.key, required this.onPick});

  final Future<void> Function(String slot, Color current) onPick;

  static const _orbSlots = [
    (key: 'orbCyan', label: 'Cyan'),
    (key: 'orbPurple', label: 'Purple'),
    (key: 'orbPink', label: 'Pink'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
                ColorCategoryRow(
                  title: 'YoLo ORB',
                  slots: _orbSlots,
                  onPick: onPick,
                  uppercaseTitle: false,
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

class PresetChip extends StatelessWidget {
  const PresetChip({
    super.key,
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

class ColorCategoryRow extends StatelessWidget {
  const ColorCategoryRow({
    super.key,
    required this.title,
    required this.slots,
    required this.onPick,
    this.uppercaseTitle = true,
  });

  final String title;
  final List<({String key, String label})> slots;
  final Future<void> Function(String slot, Color current) onPick;
  final bool uppercaseTitle;

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
            uppercaseTitle ? title.toUpperCase() : title,
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
                  return ColorSwatch(
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

class ColorSwatch extends StatelessWidget {
  const ColorSwatch({
    super.key,
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

class SmallButton extends StatelessWidget {
  const SmallButton({
    super.key,
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
