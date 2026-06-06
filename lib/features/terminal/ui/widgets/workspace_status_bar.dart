import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

class WorkspaceStatusBar extends StatelessWidget {
  const WorkspaceStatusBar({this.session});
  final AgentSession? session;

  void _showColorPicker(BuildContext context, Workspace ws, Color current) {
    showDialog<void>(
      context: context,
      builder:
          (_) => WorkspaceColorPickerDialog(
            workspace: ws,
            initial: ws.color ?? current,
            onSave:
                (c) =>
                    context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, c),
            onReset:
                () => context.read<WorkspaceCubit>().setWorkspaceColor(
                  ws.id,
                  null,
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (session == null) return const SizedBox();
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, wsState) {
        final ws = wsState is WorkspaceLoaded ? wsState.activeWorkspace : null;
        final accentColor = ws?.color ?? colors.primary;
        final wsName = ws?.name ?? 'No workspace';

        return Tooltip(
          message: 'Click to change workspace colour',
          child: GestureDetector(
            onTap:
                ws != null
                    ? () => _showColorPicker(context, ws, accentColor)
                    : null,
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                border: Border(
                  top: BorderSide(color: accentColor.withAlpha(180), width: 2),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            wsName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accentColor.withAlpha(220),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        if (ws?.gitBranch != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.alt_route,
                            size: 10,
                            color: colors.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              ws!.gitBranch!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.palette_outlined,
                    size: 10,
                    color: accentColor.withAlpha(120),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class WorkspaceColorPickerDialog extends StatefulWidget {
  const WorkspaceColorPickerDialog({
    required this.workspace,
    required this.initial,
    required this.onSave,
    required this.onReset,
  });

  final Workspace workspace;
  final Color initial;
  final ValueChanged<Color> onSave;
  final VoidCallback onReset;

  @override
  State<WorkspaceColorPickerDialog> createState() =>
      _WorkspaceColorPickerDialogState();
}

class _WorkspaceColorPickerDialogState
    extends State<WorkspaceColorPickerDialog> {
  late Color _current;
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _hexCtrl = TextEditingController(text: _toHex(_current));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  String _toHex(Color c) =>
      '#${c.r.toInt().toRadixString(16).padLeft(2, '0')}'
              '${c.g.toInt().toRadixString(16).padLeft(2, '0')}'
              '${c.b.toInt().toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  void _setColor(Color c) {
    setState(() {
      _current = c;
      _hexCtrl.text = _toHex(c);
    });
  }

  void _onHexSubmit(String value) {
    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final v = int.tryParse('FF$cleaned', radix: 16);
      if (v != null) _setColor(Color(v));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final presets = {
      colors.primary,
      colors.accentBlue,
      colors.accentGreen,
      colors.accentOrange,
      colors.accentRed,
      colors.terminalPrompt,
      colors.primaryLight,
      colors.statusActive,
      colors.primaryDark,
      colors.statusWarning,
      colors.sidebarGlow,
      colors.primaryGlow,
      colors.accentGreenDim,
      colors.accentRedDim,
    }.toList();
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _current,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Colour — ${widget.workspace.name}',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: colors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ColorPicker(
                pickerColor: _current,
                onColorChanged: _setColor,
                pickerAreaHeightPercent: 0.5,
                enableAlpha: false,
                displayThumbColor: true,
                labelTypes: const [],
                hexInputBar: false,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'HEX',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _hexCtrl,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _current.withAlpha(80)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: _onHexSubmit,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _current,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'PRESETS',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    presets.map((c) {
                      final isSelected = _current.toARGB32() == c.toARGB32();
                      return GestureDetector(
                        onTap: () => _setColor(c),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  isSelected
                                      ? colors.textPrimary
                                      : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow:
                                isSelected
                                    ? [
                                      BoxShadow(
                                        color: c.withAlpha(180),
                                        blurRadius: 6,
                                      ),
                                    ]
                                    : null,
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      widget.onReset();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Reset to theme'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.onSave(_current);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _current,
                      foregroundColor: colors.textPrimary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
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
