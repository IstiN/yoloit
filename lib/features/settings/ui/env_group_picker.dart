import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/env_group_search.dart';
import 'package:yoloit/ui/components/input/labeled_text_field.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

export 'env_group_selection_field.dart';

Future<List<String>?> showEnvGroupPickerDialog(
  BuildContext context, {
  required List<String> initialSelected,
  VoidCallback? onOpenSettings,
}) {
  return showDialog<List<String>>(
    context: context,
    builder:
        (_) => _EnvGroupPickerDialog(
          initialSelected: initialSelected,
          onOpenSettings: onOpenSettings,
        ),
  );
}

class _EnvGroupPickerDialog extends StatefulWidget {
  const _EnvGroupPickerDialog({
    required this.initialSelected,
    this.onOpenSettings,
  });

  final List<String> initialSelected;

  /// When provided, the empty state shows an "Open Settings" button. Kept as
  /// a callback so this file does not depend on the settings page (and its
  /// heavy import graph).
  final VoidCallback? onOpenSettings;

  @override
  State<_EnvGroupPickerDialog> createState() => _EnvGroupPickerDialogState();
}

class _EnvGroupPickerDialogState extends State<_EnvGroupPickerDialog> {
  final _service = GlobalEnvGroupsService.instance;
  bool _loading = true;
  List<GlobalEnvGroup> _groups = const [];
  late List<String> _selectedIds;
  bool _showInlineAdd = false;
  final _newGroupNameCtrl = TextEditingController(text: 'New Group');
  final List<_KvEntry> _newKvEntries = [_KvEntry()];
  bool _saving = false;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  final Set<String> _expandedPreviewIds = {};

  @override
  void initState() {
    super.initState();
    _selectedIds = List<String>.from(widget.initialSelected);
    _load();
  }

  @override
  void dispose() {
    _newGroupNameCtrl.dispose();
    for (final e in _newKvEntries) {
      e.dispose();
    }
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  void _togglePreview(String id) {
    setState(() {
      if (_expandedPreviewIds.remove(id)) return;
      _expandedPreviewIds.add(id);
    });
  }

  Future<void> _load() async {
    final groups = await _service.loadAll();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _selectedIds =
          _selectedIds.where((id) => groups.any((g) => g.id == id)).toList();
      _loading = false;
    });
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.remove(id);
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _moveSelected(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _selectedIds.length) return;
    setState(() {
      final value = _selectedIds.removeAt(index);
      _selectedIds.insert(next, value);
    });
  }

  Future<void> _saveNewGroup() async {
    final name = _newGroupNameCtrl.text.trim();
    if (name.isEmpty) return;
    final values = <String, String>{};
    for (final e in _newKvEntries) {
      final k = e.keyCtrl.text.trim();
      final v = e.valueCtrl.text.trim();
      if (k.isNotEmpty && v.isNotEmpty) values[k] = v;
    }
    if (values.isEmpty) return;

    setState(() => _saving = true);
    try {
      final id = 'group_${DateTime.now().millisecondsSinceEpoch}';
      final group = GlobalEnvGroup(id: id, name: name, values: values);
      // Load existing groups, append, and save all
      final existing = await _service.loadAll();
      existing.add(group);
      await _service.saveAll(existing);
      if (!mounted) return;
      setState(() {
        _groups = existing;
        _selectedIds.add(id);
        _showInlineAdd = false;
        _saving = false;
        _newGroupNameCtrl.text = 'New Group';
        for (final e in _newKvEntries) {
          e.dispose();
        }
        _newKvEntries
          ..clear()
          ..add(_KvEntry());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectedGroups =
        _selectedIds
            .map((id) {
              for (final group in _groups) {
                if (group.id == id) return group;
              }
              return null;
            })
            .whereType<GlobalEnvGroup>()
            .toList();
    return Dialog(
      backgroundColor: colors.surfaceElevated,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Env Groups',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Caption('Later groups override earlier groups when the same key appears multiple times.'),
              const SizedBox(height: 14),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (selectedGroups.isNotEmpty) ...[
                  Text(
                    'Selected order',
                    style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  ...selectedGroups.indexed.map((entry) {
                    final index = entry.$1;
                    final group = entry.$2;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.accentGreen.withAlpha(32),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.accentGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${group.name} • ${group.values.length} vars',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed:
                                index == 0
                                    ? null
                                    : () => _moveSelected(index, -1),
                            icon: const Icon(Icons.arrow_upward, size: 14),
                            color: context.appColors.textMuted,
                            splashRadius: 14,
                          ),
                          IconButton(
                            onPressed:
                                index == selectedGroups.length - 1
                                    ? null
                                    : () => _moveSelected(index, 1),
                            icon: const Icon(Icons.arrow_downward, size: 14),
                            color: context.appColors.textMuted,
                            splashRadius: 14,
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                ],
                Text(
                  'Available groups',
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 11),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textPrimary,
                  ),
                  decoration: outlineInputDecoration(
                    colors: colors,
                    hintText: 'Quick search: group or key name…',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      maxWidth: 32,
                      maxHeight: 32,
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchCtrl,
                      builder: (context, value, _) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return IconButton(
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close, size: 14),
                          splashRadius: 14,
                          color: colors.textMuted,
                        );
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Inline add form
                if (_showInlineAdd) ...[
                  _buildInlineAddForm(colors),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child:
                      _groups.isEmpty
                          ? Center(
                           child: Column(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               Icon(
                                 Icons.key_outlined,
                                 size: 36,
                                 color: colors.accentGreen.withValues(alpha: 0.4),
                               ),
                               const SizedBox(height: 10),
                               Text(
                                 'No global env groups yet',
                                 style: TextStyle(
                                   color: Theme.of(context).colorScheme.onSurface,
                                   fontSize: 13,
                                   fontWeight: FontWeight.w600,
                                 ),
                               ),
                               const SizedBox(height: 4),
                               Text(
                                 'Create env groups in Settings → Environment',
                                 style: TextStyle(
                                   color: context.appColors.textMuted,
                                   fontSize: 12,
                                 ),
                               ),
                               const SizedBox(height: 14),
                               if (widget.onOpenSettings != null)
                                 FilledButton.icon(
                                   onPressed: () {
                                     Navigator.pop(context);
                                     widget.onOpenSettings!();
                                   },
                                   icon: const Icon(Icons.settings, size: 16),
                                   label: const Text('Open Settings'),
                                   style: FilledButton.styleFrom(
                                     backgroundColor: colors.accentGreen,
                                     foregroundColor: colors.background,
                                     textStyle: const TextStyle(fontSize: 12),
                                   ),
                                 ),
                             ],
                           ),
                          )
                          : _buildAvailableGroupsList(colors, context),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_showInlineAdd)
                    TextButton.icon(
                      onPressed: () => setState(() => _showInlineAdd = true),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New Group'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.accentGreen,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selectedIds),
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

  /// Filtered, expandable list of available groups. While a quick search is
  /// active only groups whose name or keys match are shown, with the
  /// matching keys highlighted; rows can be expanded to preview keys
  /// (values are never shown in the picker).
  Widget _buildAvailableGroupsList(AppColorScheme colors, BuildContext context) {
    final results = EnvGroupSearch.filter(_groups, _searchQuery);
    if (results.isEmpty) {
      return Center(
        child: Caption(
          'No groups or keys match "$_searchQuery".',
          fontSize: 12,
        ),
      );
    }
    final searching = _searchQuery.trim().isNotEmpty;
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final group = result.group;
        final selected = _selectedIds.contains(group.id);
        final expanded = _expandedPreviewIds.contains(group.id);
        final searching = _searchQuery.trim().isNotEmpty;
        final needle = _searchQuery.trim().toLowerCase();
        final subtitle = searching
            ? '${result.entries.length}/${group.values.length} keys shown'
            : '${group.values.length} variables';
        return Column(
          children: [
            CheckboxListTile(
              value: selected,
              onChanged: (value) => _toggle(group.id, value ?? false),
              activeColor: colors.accentGreen,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                group.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              secondary: IconButton(
                onPressed: () => _togglePreview(group.id),
                tooltip: expanded ? 'Hide keys' : 'Show keys',
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                color: context.appColors.textMuted,
                splashRadius: 14,
              ),
            ),
            if (expanded)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8, left: 32),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in result.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (searching &&
                                  entry.key.toLowerCase().contains(needle))
                              ? colors.accentGreen.withAlpha(32)
                              : colors.background,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color:
                                (searching &&
                                    entry.key.toLowerCase().contains(needle))
                                ? colors.accentGreen
                                : colors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInlineAddForm(AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.accentGreen.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle_outline, size: 16, color: colors.accentGreen),
              const SizedBox(width: 8),
              Text(
                'New Env Group',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _showInlineAdd = false),
                icon: const Icon(Icons.close, size: 16),
                splashRadius: 14,
                color: colors.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LabeledTextField(
            controller: _newGroupNameCtrl,
            hint: 'Group name',
          ),
          const SizedBox(height: 8),
          ..._newKvEntries.indexed.map((entry) {
            final i = entry.$1;
            final kv = entry.$2;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildKvTextField(
                      controller: kv.keyCtrl,
                      hint: 'KEY',
                      colors: colors,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '=',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _buildKvTextField(
                      controller: kv.valueCtrl,
                      hint: 'value',
                      colors: colors,
                      obscure: true,
                    ),
                  ),
                  if (_newKvEntries.length > 1)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _newKvEntries[i].dispose();
                          _newKvEntries.removeAt(i);
                        });
                      },
                      icon: Icon(Icons.remove_circle_outline, size: 16, color: colors.accentRed),
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        maxWidth: 24,
                        maxHeight: 24,
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() => _newKvEntries.add(_KvEntry()));
                },
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add variable'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  textStyle: const TextStyle(fontSize: 11),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const Spacer(),
              if (_saving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton(
                  onPressed: _saveNewGroup,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accentGreen,
                    foregroundColor: colors.background,
                    textStyle: const TextStyle(fontSize: 11),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Save & Select'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKvTextField({
    required TextEditingController controller,
    required String hint,
    required AppColorScheme colors,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(
        fontSize: 11,
        color: colors.textPrimary,
        fontFamily: 'monospace',
      ),
      decoration: outlineInputDecoration(
        colors: colors,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 11, color: colors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        focused: false,
      ),
    );
  }
}

class _KvEntry {
  final keyCtrl = TextEditingController();
  final valueCtrl = TextEditingController();

  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
  }
}