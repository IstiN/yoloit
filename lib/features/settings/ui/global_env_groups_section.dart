import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/dialogs/env_group_text_editor_dialog.dart';
import 'package:yoloit/features/settings/ui/env_group_search.dart';
import 'package:yoloit/ui/components/cards/settings_card.dart';
import 'package:yoloit/ui/components/input/labeled_text_field.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

class GlobalEnvGroupsSection extends StatefulWidget {
  const GlobalEnvGroupsSection({super.key});

  @override
  State<GlobalEnvGroupsSection> createState() => _GlobalEnvGroupsSectionState();
}

class _GlobalEnvGroupsSectionState extends State<GlobalEnvGroupsSection> {
  final _service = GlobalEnvGroupsService.instance;
  bool _loading = true;
  bool _saving = false;
  List<GlobalEnvGroup> _groups = [];
  final Set<String> _revealedKeys = {};

  /// Groups the user expanded. Groups start collapsed to keep the section
  /// compact; the quick search still reveals matches regardless of this.
  final Set<String> _expandedGroupIds = {};
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() => _searchQuery = '');
  }

  void _toggleCollapsed(String groupId) {
    setState(() {
      if (_expandedGroupIds.remove(groupId)) return;
      _expandedGroupIds.add(groupId);
    });
  }

  /// Reveals a collapsed group (e.g. right before mutating its variables).
  void _ensureExpanded(String groupId) {
    _expandedGroupIds.add(groupId);
  }

  Future<void> _load() async {
    try {
      final groups = await _service.loadAll();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to load env groups: $error')),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveAll(_normalizedGroups());
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Env groups saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to save env groups: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  List<GlobalEnvGroup> _normalizedGroups() {
    return _groups
        .map(
          (group) => group.copyWith(
            name:
                group.name.trim().isEmpty
                    ? 'Untitled Group'
                    : group.name.trim(),
            values: Map<String, String>.fromEntries(
              group.values.entries
                  .where(
                    (e) =>
                        e.key.trim().isNotEmpty &&
                        !_isDraftEnvKey(e.key),
                  )
                  .map((e) => MapEntry(e.key.trim(), e.value)),
            ),
          ),
        )
        .toList();
  }

  void _addGroup() {
    final id = 'group_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _groups.insert(0, GlobalEnvGroup(id: id, name: 'New Group', values: const {}));
      _ensureExpanded(id);
    });
  }

  Future<void> _importAsNewGroup() async {
    final path = await FilePicker.pickFiles(
      dialogTitle: 'Import .env file',
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['env', 'txt'],
    );
    final filePath = path?.files.single.path;
    if (filePath == null) return;
    final imported = await _service.importEnvFileAsGroup(filePath);
    if (!mounted) return;
    setState(() {
      _groups.insert(0, imported);
      _ensureExpanded(imported.id);
    });
  }

  Future<void> _importIntoGroup(int groupIndex) async {
    if (!PlatformCapabilities.current.has(PlatformCapability.processes)) return;
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Import .env file',
      allowMultiple: false,
      type: FileType.any,
    );
    final filePath = result?.files.single.path;
    if (filePath == null) return;
    final group = await _service.importEnvFileAsGroup(filePath);
    if (!mounted) return;
    final mergedId = _groups[groupIndex].id;
    setState(() {
      _groups[groupIndex] = _groups[groupIndex].copyWith(
        values: {..._groups[groupIndex].values, ...group.values},
      );
      _ensureExpanded(mergedId);
    });
  }

  /// Opens the full-screen `.env` text editor for a group and, when the user
  /// applies, replaces the group's values with the parsed result and saves.
  Future<void> _editAsEnvFile(int groupIndex) async {
    final group = _groups[groupIndex];
    // Draft rows (empty keys) cannot be represented in .env text.
    final values = Map<String, String>.fromEntries(
      group.values.entries.where((e) => !_isDraftEnvKey(e.key)),
    );
    final result = await showEnvGroupTextEditor(
      context,
      group: group.copyWith(values: values),
    );
    if (result == null || !mounted) return;
    final editedId = _groups[groupIndex].id;
    setState(() {
      _groups[groupIndex] = _groups[groupIndex].copyWith(values: result);
      _ensureExpanded(editedId);
    });
    await _save();
  }

  void _renameGroup(int index, String value) {
    setState(() {
      _groups[index] = _groups[index].copyWith(name: value);
    });
  }

  void _deleteGroup(int index) {
    final groupId = _groups[index].id;
    setState(() {
      _groups.removeAt(index);
    });
    _service.deleteGroupSecrets(groupId);
  }

  static bool _isDraftEnvKey(String key) => key.startsWith('__draft_');

  String _nextDraftEnvKey(Map<String, String> values) {
    var draftKey = '__draft_${DateTime.now().microsecondsSinceEpoch}';
    while (values.containsKey(draftKey)) {
      draftKey = '__draft_${DateTime.now().microsecondsSinceEpoch}';
    }
    return draftKey;
  }

  void _addVariable(int index) {
    final values = Map<String, String>.from(_groups[index].values);
    values[_nextDraftEnvKey(values)] = '';
    setState(() {
      _groups[index] = _groups[index].copyWith(values: values);
      _ensureExpanded(_groups[index].id);
    });
  }

  void _renameVariable(int groupIndex, String oldKey, String newKey) {
    final values = Map<String, String>.from(_groups[groupIndex].values);
    final current = values.remove(oldKey) ?? '';
    values[newKey] = current;
    setState(() {
      _groups[groupIndex] = _groups[groupIndex].copyWith(values: values);
    });
  }

  void _updateVariableValue(int groupIndex, String key, String value) {
    final values = Map<String, String>.from(_groups[groupIndex].values);
    values[key] = value;
    setState(() {
      _groups[groupIndex] = _groups[groupIndex].copyWith(values: values);
    });
  }

  void _deleteVariable(int groupIndex, String key) {
    final values = Map<String, String>.from(_groups[groupIndex].values);
    values.remove(key);
    setState(() {
      _groups[groupIndex] = _groups[groupIndex].copyWith(values: values);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manage global env variable groups. They are stored securely and can be attached to board chats and board terminals. If multiple selected groups contain the same key, the last selected group wins.',
          style: TextStyle(
            color: context.appColors.textMuted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: _addGroup,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Group'),
              style: TextButton.styleFrom(foregroundColor: colors.primary),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _importAsNewGroup,
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Import .env'),
              style: TextButton.styleFrom(foregroundColor: colors.primary),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 12,
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
                  onPressed: _clearSearch,
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 14),
                  splashRadius: 14,
                  color: colors.textMuted,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Caption('No env groups yet. Create one or import a .env file.', fontSize: 12),
          )
        else if (_searchResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Caption(
              'No groups or keys match "$_searchQuery".',
              fontSize: 12,
            ),
          )
        else
          ..._searchResults.map((result) {
            final groupIndex = _groups.indexOf(result.group);
            final group = result.group;
            final searching = _searchQuery.trim().isNotEmpty;
            final collapsed =
                !searching && !_expandedGroupIds.contains(group.id);
            final vars =
                (searching ? result.entries : group.values.entries).toList();
            return SettingsCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: IconButton(
                            onPressed: () => _toggleCollapsed(group.id),
                            tooltip:
                                collapsed ? 'Expand group' : 'Collapse group',
                            icon: Icon(
                              collapsed ? Icons.expand_more : Icons.expand_less,
                              size: 20,
                            ),
                            color: colors.textMuted,
                            splashRadius: 14,
                            padding: const EdgeInsets.only(right: 4),
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _EnvField(
                            initialValue: group.name,
                            hint: 'Group name',
                            onChanged:
                                (value) => _renameGroup(groupIndex, value),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${group.values.length} vars',
                          style: TextStyle(
                            color: context.appColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _importIntoGroup(groupIndex),
                          tooltip: 'Import into group',
                          icon: const Icon(
                            Icons.file_upload_outlined,
                            size: 18,
                          ),
                          color: colors.primary,
                        ),
                        IconButton(
                          onPressed: () => _editAsEnvFile(groupIndex),
                          tooltip: 'Edit as .env file',
                          icon: const Icon(Icons.edit_note, size: 20),
                          color: colors.primary,
                        ),
                        IconButton(
                          onPressed: () => _deleteGroup(groupIndex),
                          tooltip: 'Delete group',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: colors.accentRed,
                        ),
                      ],
                    ),
                    if (!collapsed) ...[
                      const SizedBox(height: 10),
                      if (vars.isEmpty)
                        Text(
                          'No variables yet.',
                          style: TextStyle(
                            color: context.appColors.textMuted,
                            fontSize: 11,
                          ),
                        )
                      else
                        ...vars.map((entry) {
                          final key = entry.key;
                          final value = entry.value;
                          final revealKey = '${group.id}::$key';
                          final revealed = _revealedKeys.contains(revealKey);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _EnvField(
                                    initialValue:
                                        _isDraftEnvKey(key) ? '' : key,
                                    hint: 'KEY',
                                    onChanged:
                                        (newKey) => _renameVariable(
                                          groupIndex,
                                          key,
                                          newKey,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: _EnvField(
                                    initialValue: value,
                                    hint: 'VALUE',
                                    obscure: !revealed,
                                    onChanged:
                                        (newValue) => _updateVariableValue(
                                          groupIndex,
                                          key,
                                          newValue,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      if (revealed) {
                                        _revealedKeys.remove(revealKey);
                                      } else {
                                        _revealedKeys.add(revealKey);
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    revealed
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 16,
                                  ),
                                  color: context.appColors.textMuted,
                                  splashRadius: 14,
                                ),
                                IconButton(
                                  onPressed:
                                      () => _deleteVariable(groupIndex, key),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                  ),
                                  color: colors.accentRed,
                                  splashRadius: 14,
                                ),
                              ],
                            ),
                          );
                        }),
                      TextButton.icon(
                        onPressed: () => _addVariable(groupIndex),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add Variable'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
            );
          }),
      ],
    );
  }

  /// Filtered view of [_groups] for the current quick-search query. Kept as
  /// a getter so the build method stays declarative.
  List<EnvGroupSearchResult> get _searchResults =>
      EnvGroupSearch.filter(_groups, _searchQuery, isDraftKey: _isDraftEnvKey);
}

class _EnvField extends StatefulWidget {
  const _EnvField({
    required this.initialValue,
    required this.hint,
    required this.onChanged,
    this.obscure = false,
    this.style,
  });

  final String initialValue;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final TextStyle? style;

  @override
  State<_EnvField> createState() => _EnvFieldState();
}

class _EnvFieldState extends State<_EnvField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _EnvField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: _controller,
      obscureText: widget.obscure,
      onChanged: widget.onChanged,
      style: widget.style ??
          TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
      decoration: outlineInputDecoration(
        colors: colors,
        hintText: widget.hint,
      ),
    );
  }
}
