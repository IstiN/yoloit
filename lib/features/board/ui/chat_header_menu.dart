import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/ui/chat_session_history_dialog.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';

class ChatHeaderMenu extends StatelessWidget {
  const ChatHeaderMenu({
    required this.panel,
    required this.onEditColor,
    this.onUpdateState,
  });

  final BoardPanelInstance panel;
  final VoidCallback onEditColor;
  final ValueChanged<Map<String, dynamic>>? onUpdateState;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        context.appColors.textMuted;
    final secondaryColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, size: 16, color: mutedColor),
        splashRadius: 14,
        padding: EdgeInsets.zero,
        iconSize: 16,
        color: colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        itemBuilder:
            (menuCtx) => [
              PopupMenuItem(
                value: 'rename',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 14, color: secondaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Rename session',
                      style: TextStyle(fontSize: 12, color: onSurface),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 14, color: secondaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'CLI settings',
                      style: TextStyle(fontSize: 12, color: onSurface),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'history',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.history, size: 14, color: secondaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Session history',
                      style: TextStyle(fontSize: 12, color: onSurface),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'color',
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      size: 14,
                      color: secondaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Change color',
                      style: TextStyle(fontSize: 12, color: onSurface),
                    ),
                  ],
                ),
              ),
            ],
        onSelected: (value) {
          switch (value) {
            case 'rename':
              _showRenameDialog(context);
            case 'settings':
              _showSettingsDialog(context);
            case 'history':
              _showSessionHistory(context);
            case 'color':
              onEditColor();
          }
        },
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final config = panel.state['config'] as Map<String, dynamic>?;
    final currentName = config?['sessionName'] as String? ?? panel.title;
    final ctrl = TextEditingController(text: currentName);
    // Capture the cubit from the parent context (not the dialog's context)
    final cubit = context.read<BoardCubit>();

    showDialog(
      context: context,
      builder: (ctx) {
        final colors = ctx.appColors;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final mutedColor =
            ctx.appColors.textMuted;
        return AlertDialog(
          backgroundColor: colors.surfaceElevated,
          title: Text('Rename session', style: TextStyle(color: onSurface)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              hintText: 'Session name',
              hintStyle: TextStyle(color: mutedColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: (_) {
              _applyRename(ctx, ctrl.text, cubit);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _applyRename(ctx, ctrl.text, cubit),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  void _applyRename(BuildContext ctx, String newName, BoardCubit cubit) {
    final name = newName.trim();
    if (name.isEmpty) return;
    Navigator.pop(ctx);

    final config = Map<String, dynamic>.from(
      panel.state['config'] as Map<String, dynamic>? ?? {},
    );
    config['sessionName'] = name;

    cubit.updatePanelTitle(panel.id, name);
    onUpdateState?.call({...panel.state, 'config': config});
  }

  void _showSessionHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => ChatSessionHistoryDialog(panelId: panel.id),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final config = ChatSessionConfig.fromJson(
      Map<String, dynamic>.from(panel.state['config'] as Map? ?? {}),
    );
    final customArgsCtrl = TextEditingController(
      text: config.customArgs.join(' '),
    );
    final maxContinuesCtrl = TextEditingController(
      text: '${config.maxAutopilotContinues}',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        final colors = ctx.appColors;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final secondaryColor =
            Theme.of(ctx).textTheme.bodyMedium?.color ??
            Theme.of(ctx).colorScheme.onSurface;
        final mutedColor =
            ctx.appColors.textMuted;
        var mode = config.mode;
        var reasoningEffort = config.reasoningEffort;
        var envGroupIds = List<String>.from(config.envGroupIds);
        return StatefulBuilder(
          builder:
              (ctx, setDialogState) => AlertDialog(
                backgroundColor: colors.surfaceElevated,
                title: Text(
                  'CLI Settings',
                  style: TextStyle(color: onSurface, fontSize: 14),
                ),
                content: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agent Mode',
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      DropdownButton<String?>(
                        value: mode,
                        isExpanded: true,
                        dropdownColor: colors.surfaceElevated,
                        style: TextStyle(color: onSurface, fontSize: 12),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Default (interactive)'),
                          ),
                          DropdownMenuItem(
                            value: 'interactive',
                            child: Text('Interactive'),
                          ),
                          DropdownMenuItem(value: 'plan', child: Text('Plan')),
                          DropdownMenuItem(
                            value: 'autopilot',
                            child: Text('Autopilot'),
                          ),
                        ],
                        onChanged: (v) => setDialogState(() => mode = v),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Reasoning effort',
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      DropdownButton<String?>(
                        value: reasoningEffort,
                        isExpanded: true,
                        dropdownColor: colors.surfaceElevated,
                        style: TextStyle(color: onSurface, fontSize: 12),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Default')),
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                          DropdownMenuItem(
                            value: 'medium',
                            child: Text('Medium'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                          DropdownMenuItem(
                            value: 'xhigh',
                            child: Text('XHigh'),
                          ),
                        ],
                        onChanged:
                            (v) => setDialogState(() => reasoningEffort = v),
                      ),
                      const SizedBox(height: 12),
                      EnvGroupSelectionField(
                        selectedGroupIds: envGroupIds,
                        onChanged:
                            (value) =>
                                setDialogState(() => envGroupIds = value),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Max autopilot continues',
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: maxContinuesCtrl,
                        style: TextStyle(color: onSurface, fontSize: 12),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '99',
                          hintStyle: TextStyle(color: mutedColor),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Custom args',
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: customArgsCtrl,
                        style: TextStyle(color: onSurface, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: '--flag value ...',
                          hintStyle: TextStyle(color: mutedColor),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final argsText = customArgsCtrl.text.trim();
                      final customArgs =
                          argsText.isEmpty
                              ? <String>[]
                              : argsText.split(RegExp(r'\s+'));
                      final maxCont =
                          int.tryParse(maxContinuesCtrl.text.trim()) ?? 99;
                      final updatedConfig = config.copyWith(
                        mode: () => mode,
                        reasoningEffort: () => reasoningEffort,
                        envGroupIds: envGroupIds,
                        maxAutopilotContinues: maxCont,
                        customArgs: customArgs,
                      );
                      onUpdateState?.call({
                        ...panel.state,
                        'config': updatedConfig.toJson(),
                      });
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
        );
      },
    );
  }
}
