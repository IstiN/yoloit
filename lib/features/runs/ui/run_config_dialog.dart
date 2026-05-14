import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

enum _RunPreset { custom, flutterApp }

class RunConfigDialog extends StatefulWidget {
  const RunConfigDialog({super.key, this.initial});

  final RunConfig? initial;

  static Future<RunConfig?> show(BuildContext context, {RunConfig? initial}) {
    return showDialog<RunConfig>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => RunConfigDialog(initial: initial),
    );
  }

  @override
  State<RunConfigDialog> createState() => _RunConfigDialogState();
}

class _RunConfigDialogState extends State<RunConfigDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _commandCtrl;
  late final TextEditingController _workingDirCtrl;
  late bool _isFlutterRun;
  late _RunPreset _preset;
  Color? _selectedColor;
  late List<_QuickActionDraft> _quickActions;

  static const _colorChips = [
    Color(0xFF54C5F8),
    Color(0xFF00FF9F),
    Color(0xFFFFD700),
    Color(0xFFFF4F6A),
    Color(0xFF9D4EDD),
    Color(0xFFFF9500),
    Color(0xFFFF69B4),
    Color(0xFF00B4FF),
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _commandCtrl = TextEditingController(text: c?.command ?? '');
    _workingDirCtrl = TextEditingController(text: c?.workingDir ?? '');
    _isFlutterRun = c?.isFlutterRun ?? false;
    _preset = _isFlutterRun ? _RunPreset.flutterApp : _RunPreset.custom;
    _selectedColor = c?.color;
    _quickActions =
        (c?.quickActions ?? const [])
            .map((action) => _QuickActionDraft.fromAction(action))
            .toList();
    if (_preset == _RunPreset.flutterApp) {
      _ensureFlutterQuickActions();
    }
  }

  void _applyPreset(_RunPreset preset) {
    _preset = preset;
    if (preset == _RunPreset.flutterApp) {
      _isFlutterRun = true;
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = 'Flutter Run';
      }
      if (_commandCtrl.text.trim().isEmpty) {
        _commandCtrl.text = 'flutter run -d macos --debug';
      }
      _ensureFlutterQuickActions();
    } else {
      _isFlutterRun = false;
      _clearFlutterPresetActions();
    }
  }

  void _ensureFlutterQuickActions() {
    final hasReload = _quickActions.any(
      (action) =>
          action.commandCtrl.text.trim() == 'r' ||
          action.labelCtrl.text.trim().toLowerCase() == 'hot reload',
    );
    final hasRestart = _quickActions.any(
      (action) =>
          action.commandCtrl.text.trim() == 'R' ||
          action.labelCtrl.text.trim().toLowerCase() == 'hot restart',
    );
    if (!hasReload) {
      _quickActions.add(
        _QuickActionDraft(
          id: 'flutter_hot_reload',
          labelCtrl: TextEditingController(text: 'Hot Reload'),
          iconCtrl: TextEditingController(text: 'local_fire_department'),
          commandCtrl: TextEditingController(text: 'r'),
          appendNewline: false,
        ),
      );
    }
    if (!hasRestart) {
      _quickActions.add(
        _QuickActionDraft(
          id: 'flutter_hot_restart',
          labelCtrl: TextEditingController(text: 'Hot Restart'),
          iconCtrl: TextEditingController(text: 'restart_alt'),
          commandCtrl: TextEditingController(text: 'R'),
          appendNewline: false,
        ),
      );
    }
  }

  void _clearFlutterPresetActions() {
    bool isPresetAction(_QuickActionDraft action) {
      final id = action.id.trim().toLowerCase();
      final label = action.labelCtrl.text.trim().toLowerCase();
      final command = action.commandCtrl.text.trim();
      return id == 'flutter_hot_reload' ||
          id == 'flutter_hot_restart' ||
          label == 'hot reload' ||
          label == 'hot restart' ||
          command == 'r' ||
          command == 'R';
    }

    final kept = <_QuickActionDraft>[];
    for (final action in _quickActions) {
      if (isPresetAction(action)) {
        action.dispose();
      } else {
        kept.add(action);
      }
    }
    _quickActions = kept;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _commandCtrl.dispose();
    _workingDirCtrl.dispose();
    for (final action in _quickActions) {
      action.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final command = _commandCtrl.text.trim();
    if (name.isEmpty || command.isEmpty) return;

    final existing = widget.initial;
    final quickActions =
        _quickActions
            .map((draft) => draft.toAction())
            .where((action) => action != null)
            .cast<RunQuickAction>()
            .toList();
    final config = RunConfig(
      id: existing?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      command: command,
      workingDir:
          _workingDirCtrl.text.trim().isEmpty
              ? null
              : _workingDirCtrl.text.trim(),
      env: existing?.env ?? {},
      color: _selectedColor,
      isFlutterRun: _isFlutterRun,
      quickActions: quickActions,
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                widget.initial == null
                    ? 'New Run Configuration'
                    : 'Edit Run Configuration',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _Field(
                label: 'Name',
                controller: _nameCtrl,
                hint: 'e.g. Flutter Run',
              ),
              const SizedBox(height: 12),
              _Field(
                label: 'Command',
                controller: _commandCtrl,
                hint: 'e.g. flutter run -d macos',
                fontFamily: 'monospace',
              ),
              const SizedBox(height: 12),
              _WorkingDirField(controller: _workingDirCtrl),
              const SizedBox(height: 16),
              const Text(
                'Preset',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<_RunPreset>(
                initialValue: _preset,
                dropdownColor: colors.surfaceElevated,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _RunPreset.custom,
                    child: Text('No preset'),
                  ),
                  DropdownMenuItem(
                    value: _RunPreset.flutterApp,
                    child: Text('Flutter App (Hot Reload / Restart preset)'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _applyPreset(value));
                },
              ),
              const SizedBox(height: 16),
              _QuickActionsEditor(
                actions: _quickActions,
                onChanged: () => setState(() {}),
                onAdd: () {
                  setState(() {
                    _quickActions.add(_QuickActionDraft.empty());
                  });
                },
                onRemove: (index) {
                  setState(() {
                    final removed = _quickActions.removeAt(index);
                    removed.dispose();
                  });
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Color',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _selectedColor = null),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                        border: Border.all(
                          color:
                              _selectedColor == null
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                          width: _selectedColor == null ? 2 : 1,
                        ),
                      ),
                      child:
                          _selectedColor == null
                              ? const Icon(
                                Icons.close,
                                size: 10,
                                color: AppColors.textPrimary,
                              )
                              : null,
                    ),
                  ),
                  ..._colorChips.map(
                    (c) => GestureDetector(
                      onTap: () => setState(() => _selectedColor = c),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c,
                          border:
                              _selectedColor?.toARGB32() == c.toARGB32()
                                  ? Border.all(
                                    color: AppColors.textPrimary,
                                    width: 2,
                                  )
                                  : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionDraft {
  _QuickActionDraft({
    required this.id,
    required this.labelCtrl,
    required this.iconCtrl,
    required this.commandCtrl,
    required this.appendNewline,
  });

  factory _QuickActionDraft.fromAction(RunQuickAction action) {
    return _QuickActionDraft(
      id: action.id,
      labelCtrl: TextEditingController(text: action.label),
      iconCtrl: TextEditingController(text: action.icon),
      commandCtrl: TextEditingController(text: action.command),
      appendNewline: action.appendNewline,
    );
  }

  factory _QuickActionDraft.empty() {
    return _QuickActionDraft(
      id: 'qa_${DateTime.now().millisecondsSinceEpoch}',
      labelCtrl: TextEditingController(),
      iconCtrl: TextEditingController(text: 'bolt'),
      commandCtrl: TextEditingController(),
      appendNewline: false,
    );
  }

  final String id;
  final TextEditingController labelCtrl;
  final TextEditingController iconCtrl;
  final TextEditingController commandCtrl;
  bool appendNewline;

  RunQuickAction? toAction() {
    final label = labelCtrl.text.trim();
    final command = commandCtrl.text;
    if (label.isEmpty || command.trim().isEmpty) return null;
    return RunQuickAction(
      id: id,
      label: label,
      icon: iconCtrl.text.trim().isEmpty ? 'bolt' : iconCtrl.text.trim(),
      command: command,
      appendNewline: appendNewline,
    );
  }

  void dispose() {
    labelCtrl.dispose();
    iconCtrl.dispose();
    commandCtrl.dispose();
  }
}

class _QuickActionsEditor extends StatelessWidget {
  const _QuickActionsEditor({
    required this.actions,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_QuickActionDraft> actions;
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  static const _iconOptions = <_QuickActionIconOption>[
    _QuickActionIconOption('bolt', Icons.bolt_rounded),
    _QuickActionIconOption(
      'local_fire_department',
      Icons.local_fire_department_rounded,
    ),
    _QuickActionIconOption('restart_alt', Icons.restart_alt_rounded),
    _QuickActionIconOption('play_arrow', Icons.play_arrow_rounded),
    _QuickActionIconOption('pause', Icons.pause_rounded),
    _QuickActionIconOption('stop', Icons.stop_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Shown in Run header while session is running (stdin commands).',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(130),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        ...actions.asMap().entries.map((entry) {
          final index = entry.key;
          final action = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Label',
                          controller: action.labelCtrl,
                          hint: 'Hot Reload',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Field(
                          label: 'Icon',
                          controller: action.iconCtrl,
                          hint: 'bolt / restart_alt / local_fire_department',
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: action.iconCtrl,
                        builder: (context, value, _) {
                          final icon = _iconFromName(value.text);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Preview',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap:
                                    () => _pickIcon(
                                      context,
                                      action,
                                      colors: colors,
                                    ),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: colors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: colors.border),
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 16,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _Field(
                    label: 'Command',
                    controller: action.commandCtrl,
                    hint: 'r',
                    fontFamily: 'monospace',
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: action.appendNewline,
                          onChanged: (value) {
                            action.appendNewline = value ?? false;
                            onChanged();
                          },
                          activeColor: colors.primary,
                          side: const BorderSide(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Append Enter (\\n)',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => onRemove(index),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.neonRed,
                        ),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add quick action'),
            style: TextButton.styleFrom(foregroundColor: colors.primary),
          ),
        ),
      ],
    );
  }

  static IconData _iconFromName(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'local_fire_department':
      case 'fire':
      case 'hot_reload':
        return Icons.local_fire_department_rounded;
      case 'restart_alt':
      case 'restart':
      case 'hot_restart':
        return Icons.restart_alt_rounded;
      case 'play':
      case 'play_arrow':
        return Icons.play_arrow_rounded;
      case 'pause':
        return Icons.pause_rounded;
      case 'stop':
        return Icons.stop_rounded;
      case 'bolt':
      default:
        return Icons.bolt_rounded;
    }
  }

  Future<void> _pickIcon(
    BuildContext context,
    _QuickActionDraft action, {
    required AppColorScheme colors,
  }) async {
    final selected = await showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Pick icon'),
            backgroundColor: colors.surfaceElevated,
            content: SizedBox(
              width: 360,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _iconOptions
                        .map(
                          (opt) => InkWell(
                            onTap: () => Navigator.of(context).pop(opt.name),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 104,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colors.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    opt.icon,
                                    size: 14,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      opt.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
    );
    if (selected == null || selected.trim().isEmpty) return;
    action.iconCtrl.text = selected;
    onChanged();
  }
}

class _QuickActionIconOption {
  const _QuickActionIconOption(this.name, this.icon);
  final String name;
  final IconData icon;
}

class _WorkingDirField extends StatefulWidget {
  const _WorkingDirField({required this.controller});

  final TextEditingController controller;

  @override
  State<_WorkingDirField> createState() => _WorkingDirFieldState();
}

class _WorkingDirFieldState extends State<_WorkingDirField> {
  TextEditingController get controller => widget.controller;

  Future<void> _browse() async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Working Directory',
    );
    if (dir != null && mounted) controller.text = dir;
  }

  List<String> _workspacePaths(BuildContext context) {
    final state = context.read<WorkspaceCubit>().state;
    if (state is! WorkspaceLoaded) return [];
    final active = state.activeWorkspace;
    return active?.paths ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final paths = _workspacePaths(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Working Directory',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'Leave empty to use workspace root',
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Browse for directory',
              child: InkWell(
                onTap: _browse,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (paths.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children:
                paths.map((path) {
                  final label = p.basename(path);
                  final isSelected = controller.text == path;
                  return GestureDetector(
                    onTap: () => controller.text = path,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? colors.primary.withAlpha(30)
                                : colors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected ? colors.primary : colors.border,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              isSelected ? colors.primary : AppColors.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.fontFamily,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontFamily: fontFamily,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
            filled: true,
            fillColor: colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
