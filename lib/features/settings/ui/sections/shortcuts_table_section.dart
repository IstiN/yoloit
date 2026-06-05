import 'package:flutter/material.dart';
import 'package:yoloit/core/hotkeys/hotkey_definition.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/ui/dialogs/key_capture_dialog.dart';

class ShortcutsTable extends StatefulWidget {
  const ShortcutsTable({super.key});

  @override
  State<ShortcutsTable> createState() => ShortcutsTableState();
}

class ShortcutsTableState extends State<ShortcutsTable> {
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
                        return HotkeyRow(
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

class HotkeyRow extends StatelessWidget {
  const HotkeyRow({
    super.key,
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
          KeyBadge(activator: definition.currentActivator),
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

class KeyBadge extends StatelessWidget {
  const KeyBadge({super.key, required this.activator});

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
