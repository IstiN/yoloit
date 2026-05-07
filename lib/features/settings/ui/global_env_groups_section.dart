import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load env groups: $error')),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final backend = await _service.saveAll(_normalizedGroups());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            backend == GlobalEnvStorageBackend.secureStorage
                ? 'Env groups saved.'
                : 'Env groups saved to local app storage because secure storage is unavailable.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
                  .where((e) => e.key.trim().isNotEmpty)
                  .map((e) => MapEntry(e.key.trim(), e.value)),
            ),
          ),
        )
        .toList();
  }

  void _addGroup() {
    setState(() {
      _groups.add(
        GlobalEnvGroup(
          id: 'env_group_${DateTime.now().millisecondsSinceEpoch}',
          name: 'New Group',
          values: const {},
        ),
      );
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
    setState(() => _groups.add(imported));
  }

  Future<void> _importIntoGroup(int groupIndex) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Import .env file',
      allowMultiple: false,
      type: FileType.any,
    );
    final filePath = result?.files.single.path;
    if (filePath == null) return;
    final content = await File(filePath).readAsString();
    final parsed = _service.parseEnvContent(content);
    if (!mounted) return;
    setState(() {
      _groups[groupIndex] = _groups[groupIndex].copyWith(
        values: {..._groups[groupIndex].values, ...parsed},
      );
    });
  }

  void _renameGroup(int index, String value) {
    setState(() {
      _groups[index] = _groups[index].copyWith(name: value);
    });
  }

  void _deleteGroup(int index) {
    setState(() {
      _groups.removeAt(index);
    });
  }

  void _addVariable(int index) {
    final values = Map<String, String>.from(_groups[index].values);
    values[''] = '';
    setState(() {
      _groups[index] = _groups[index].copyWith(values: values);
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
        const Text(
          'Manage global env variable groups. They are stored securely and can be attached to board chats and board terminals. If multiple selected groups contain the same key, the last selected group wins.',
          style: TextStyle(
            color: AppColors.textMuted,
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
        if (_groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No env groups yet. Create one or import a .env file.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          )
        else
          ..._groups.indexed.map((entry) {
            final groupIndex = entry.$1;
            final group = entry.$2;
            final vars = group.values.entries.toList();
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(text: group.name),
                            onChanged:
                                (value) => _renameGroup(groupIndex, value),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Group name',
                              hintStyle: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: colors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: colors.border),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                          onPressed: () => _deleteGroup(groupIndex),
                          tooltip: 'Delete group',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: AppColors.neonRed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (vars.isEmpty)
                      const Text(
                        'No variables yet.',
                        style: TextStyle(
                          color: AppColors.textMuted,
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
                                  initialValue: key,
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
                                color: AppColors.textMuted,
                                splashRadius: 14,
                              ),
                              IconButton(
                                onPressed:
                                    () => _deleteVariable(groupIndex, key),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                color: AppColors.neonRed,
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
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _EnvField extends StatefulWidget {
  const _EnvField({
    required this.initialValue,
    required this.hint,
    required this.onChanged,
    this.obscure = false,
  });

  final String initialValue;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool obscure;

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
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}
