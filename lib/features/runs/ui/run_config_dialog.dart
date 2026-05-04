import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

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
  Color? _selectedColor;

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
    _selectedColor = c?.color;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _commandCtrl.dispose();
    _workingDirCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final command = _commandCtrl.text.trim();
    if (name.isEmpty || command.isEmpty) return;

    final existing = widget.initial;
    final config = RunConfig(
      id: existing?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      command: command,
      workingDir: _workingDirCtrl.text.trim().isEmpty
          ? null
          : _workingDirCtrl.text.trim(),
      env: existing?.env ?? {},
      color: _selectedColor,
      isFlutterRun: _isFlutterRun,
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
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
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
              _Field(label: 'Name', controller: _nameCtrl, hint: 'e.g. Flutter Run'),
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
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _isFlutterRun,
                      onChanged: (v) =>
                          setState(() => _isFlutterRun = v ?? false),
                      activeColor: colors.primary,
                      side: const BorderSide(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Flutter Run mode (enables Hot Reload / Restart buttons)',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Color',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
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
                          color: _selectedColor == null
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          width: _selectedColor == null ? 2 : 1,
                        ),
                      ),
                      child: _selectedColor == null
                          ? const Icon(Icons.close,
                              size: 10, color: AppColors.textPrimary)
                          : null,
                    ),
                  ),
                  ..._colorChips.map((c) => GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c,
                            border: _selectedColor?.toARGB32() == c.toARGB32()
                                ? Border.all(
                                    color: AppColors.textPrimary, width: 2)
                                : null,
                          ),
                        ),
                      )),
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
                          horizontal: 16, vertical: 8),
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
    );
  }
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
              fontWeight: FontWeight.w500),
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
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  child: Icon(Icons.folder_open_rounded,
                      size: 16, color: colors.primary),
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
            children: paths.map((path) {
              final label = p.basename(path);
              final isSelected = controller.text == path;
              return GestureDetector(
                onTap: () => controller.text = path,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected
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
                      color: isSelected ? colors.primary : AppColors.textMuted,
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
              fontWeight: FontWeight.w500),
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
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
