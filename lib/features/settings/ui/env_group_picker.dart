import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

class EnvGroupSelectionField extends StatefulWidget {
  const EnvGroupSelectionField({
    super.key,
    required this.selectedGroupIds,
    required this.onChanged,
    this.label = 'Env Groups',
  });

  final List<String> selectedGroupIds;
  final ValueChanged<List<String>> onChanged;
  final String label;

  @override
  State<EnvGroupSelectionField> createState() => _EnvGroupSelectionFieldState();
}

class _EnvGroupSelectionFieldState extends State<EnvGroupSelectionField> {
  late Future<List<String>> _namesFuture;

  @override
  void initState() {
    super.initState();
    _namesFuture = GlobalEnvGroupsService.instance.resolveSelectedGroupNames(
      widget.selectedGroupIds,
    );
  }

  @override
  void didUpdateWidget(covariant EnvGroupSelectionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedGroupIds.join('\u0000') !=
        widget.selectedGroupIds.join('\u0000')) {
      _namesFuture = GlobalEnvGroupsService.instance.resolveSelectedGroupNames(
        widget.selectedGroupIds,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 4),
        FutureBuilder<List<String>>(
          future: _namesFuture,
          builder: (context, snapshot) {
            final names = snapshot.data ?? const <String>[];
            return InkWell(
              onTap: () async {
                final selected = await showEnvGroupPickerDialog(
                  context,
                  initialSelected: widget.selectedGroupIds,
                );
                if (selected != null) {
                  widget.onChanged(selected);
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF1A2030),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.key_outlined,
                      size: 16,
                      color: Color(0xFF34D399),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        names.isEmpty
                            ? 'No groups selected'
                            : names.join('  •  '),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              names.isEmpty
                                  ? const Color(0xFF475569)
                                  : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    Text(
                      '${widget.selectedGroupIds.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.tune, size: 14, color: Color(0xFF64748B)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

Future<List<String>?> showEnvGroupPickerDialog(
  BuildContext context, {
  required List<String> initialSelected,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _EnvGroupPickerDialog(initialSelected: initialSelected),
  );
}

class _EnvGroupPickerDialog extends StatefulWidget {
  const _EnvGroupPickerDialog({required this.initialSelected});

  final List<String> initialSelected;

  @override
  State<_EnvGroupPickerDialog> createState() => _EnvGroupPickerDialogState();
}

class _EnvGroupPickerDialogState extends State<_EnvGroupPickerDialog> {
  final _service = GlobalEnvGroupsService.instance;
  bool _loading = true;
  List<GlobalEnvGroup> _groups = const [];
  late List<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = List<String>.from(widget.initialSelected);
    _load();
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

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: const Color(0xFF16163A),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Env Groups',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Later groups override earlier groups when the same key appears multiple times.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (selectedGroups.isNotEmpty) ...[
                  const Text(
                    'Selected order',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
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
                        color: const Color(0xFF0F1219),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0x2034D399),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF34D399),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${group.name} • ${group.values.length} vars',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
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
                            color: AppColors.textMuted,
                            splashRadius: 14,
                          ),
                          IconButton(
                            onPressed:
                                index == selectedGroups.length - 1
                                    ? null
                                    : () => _moveSelected(index, 1),
                            icon: const Icon(Icons.arrow_downward, size: 14),
                            color: AppColors.textMuted,
                            splashRadius: 14,
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                ],
                const Text(
                  'Available groups',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child:
                      _groups.isEmpty
                          ? const Center(
                            child: Text(
                              'No global env groups yet.\nCreate them in Settings → Environment.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          )
                          : ListView.builder(
                            itemCount: _groups.length,
                            itemBuilder: (context, index) {
                              final group = _groups[index];
                              final selected = _selectedIds.contains(group.id);
                              return CheckboxListTile(
                                value: selected,
                                onChanged:
                                    (value) =>
                                        _toggle(group.id, value ?? false),
                                activeColor: const Color(0xFF34D399),
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  group.name,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  '${group.values.length} variables',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              );
                            },
                          ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
}
