import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/runs/ui/run_config_dialog.dart';

class RunPanel extends StatelessWidget {
  const RunPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RunCubit, RunState>(
      builder: (context, state) {
        return _RunPanelView(state: state);
      },
    );
  }
}

class _RunPanelView extends StatefulWidget {
  const _RunPanelView({required this.state});
  final RunState state;

  @override
  State<_RunPanelView> createState() => _RunPanelViewState();
}

class _RunPanelViewState extends State<_RunPanelView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_RunPanelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSession = oldWidget.state.activeSession;
    final newSession = widget.state.activeSession;
    if (newSession != null &&
        newSession.output.length != (oldSession?.output.length ?? 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = widget.state;

    return Container(
      color: colors.terminalBackground,
      child: Row(
        children: [
          // Left: configurations list (always visible)
          _ConfigList(state: state),
          Container(width: 1, color: colors.divider),
          // Right: session tabs + console output
          Expanded(
            child: Column(
              children: [
                _ConsoleHeader(state: state),
                Expanded(
                  child: _Console(
                    state: state,
                    scrollController: _scrollController,
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

// ── Console Header (tabs + action buttons, shown inside the right area) ──────

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({required this.state});
  final RunState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<RunCubit>();
    final activeSession = state.activeSession;
    final isRunning = activeSession?.status == RunStatus.running;
    final isFlutter = activeSession?.config.isFlutterRun ?? false;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Session tabs
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...state.sessions.map((s) => _SessionTab(
                      session: s,
                      isActive: s.id == state.activeSessionId,
                      onTap: () => cubit.setActiveSession(s.id),
                      onClose: () => cubit.removeSession(s.id),
                    )),
              ],
            ),
          ),
          // Action buttons
          if (activeSession != null) ...[
            if (isRunning && isFlutter) ...[
              _HeaderButton(
                tooltip: 'Hot Reload (r)',
                label: '🔥',
                onTap: () => cubit.sendHotReload(activeSession.id),
              ),
              _HeaderButton(
                tooltip: 'Hot Restart (R)',
                label: 'R',
                onTap: () => cubit.sendHotRestart(activeSession.id),
                textStyle: const TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (isRunning)
              _HeaderButton(
                tooltip: 'Stop',
                icon: Icons.stop_rounded,
                iconColor: AppColors.neonRed,
                onTap: () => cubit.stopRun(activeSession.id),
              )
            else
              _HeaderButton(
                tooltip: 'Re-run',
                icon: Icons.play_arrow_rounded,
                iconColor: AppColors.neonGreen,
                onTap: () => cubit.startRun(activeSession.config),
              ),
            _HeaderButton(
              tooltip: 'Clear output',
              icon: Icons.clear_all_rounded,
              iconColor: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              onTap: () => cubit.clearOutput(activeSession.id),
            ),
          ],
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _SessionTab extends StatelessWidget {
  const _SessionTab({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  final RunSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isRunning = session.status == RunStatus.running;
    final dotColor = session.config.color ??
        (isRunning ? AppColors.neonGreen : Theme.of(context).colorScheme.onSurface.withAlpha(120));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? colors.tabActiveBg : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? colors.tabBorder : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRunning)
              SizedBox(
                width: 8,
                height: 8,
                child: _PulsingDot(color: dotColor),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session.status == RunStatus.failed
                      ? AppColors.neonRed
                      : dotColor,
                ),
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                session.config.name,
                style: TextStyle(
                  color: isActive
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 11,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClose,
              child: Icon(
                Icons.close,
                size: 10,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    this.icon,
    this.iconColor,
    this.label,
    this.textStyle,
    required this.onTap,
  });

  final String tooltip;
  final IconData? icon;
  final Color? iconColor;
  final String? label;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: 14, color: iconColor)
              : Text(
                  label ?? '',
                  style: textStyle ??
                      TextStyle(
                          color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
                ),
        ),
      ),
    );
  }
}

// ── Config List ──────────────────────────────────────────────────────────────

class _ConfigList extends StatelessWidget {
  const _ConfigList({required this.state});
  final RunState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<RunCubit>();

    return SizedBox(
      width: 180,
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              'CONFIGURATIONS',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 4),
              children: [
                ...state.configs.map((c) {
                  final runningSession = state.sessions
                      .where((s) =>
                          s.config.id == c.id &&
                          s.status == RunStatus.running)
                      .firstOrNull;
                  return _ConfigItem(
                    config: c,
                    isRunning: runningSession != null,
                    onRun: () {
                      if (runningSession != null) {
                        // Already running — hot reload if flutter, else focus
                        if (c.isFlutterRun) {
                          cubit.sendHotReload(runningSession.id);
                        }
                        cubit.setActiveSession(runningSession.id);
                      } else {
                        cubit.startRun(c);
                      }
                    },
                    onEdit: () async {
                      final updated =
                          await RunConfigDialog.show(context, initial: c);
                      if (updated != null) cubit.updateConfig(updated);
                    },
                    onDelete: () => cubit.removeConfig(c.id),
                  );
                }),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: InkWell(
                    onTap: () async {
                      final config =
                          await RunConfigDialog.show(context);
                      if (config != null) cubit.addConfig(config);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 12, color: colors.primary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Add Configuration',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: colors.primary, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _ConfigItem extends StatefulWidget {
  const _ConfigItem({
    required this.config,
    required this.isRunning,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  final RunConfig config;
  final bool isRunning;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ConfigItem> createState() => _ConfigItemState();
}

class _ConfigItemState extends State<_ConfigItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dotColor =
        widget.config.color ?? Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: _hovering ? colors.surfaceHighlight : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.config.name,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Always reserve space for buttons; show/hide via Opacity to
            // prevent layout jump on hover.
            Opacity(
              opacity: widget.isRunning ? 1.0 : 0.0,
              child: const _SmallIconButton(
                icon: Icons.fiber_manual_record,
                color: AppColors.neonGreen,
                tooltip: 'Running',
                onTap: null,
              ),
            ),
            Opacity(
              opacity: (_hovering || widget.isRunning) ? 1.0 : 0.0,
              child: _SmallIconButton(
                icon: Icons.play_arrow_rounded,
                color: AppColors.neonGreen,
                tooltip: 'Run',
                onTap: (_hovering || widget.isRunning) ? widget.onRun : null,
              ),
            ),
            Opacity(
              opacity: (_hovering || widget.isRunning) ? 1.0 : 0.0,
              child: _SmallIconButton(
                icon: Icons.more_vert,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                tooltip: 'Options',
                onTap: (_hovering || widget.isRunning)
                    ? () => _showMenu(context)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + box.size.width,
        offset.dy,
        offset.dx + box.size.width + 160,
        offset.dy + 100,
      ),
      color: context.appColors.surfaceElevated,
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 32,
          child: Text('Edit',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, fontSize: 12)),
        ),
        const PopupMenuItem(
          value: 'delete',
          height: 32,
          child: Text('Delete',
              style: TextStyle(color: AppColors.neonRed, fontSize: 12)),
        ),
      ],
    ).then((value) {
      if (value == 'edit') widget.onEdit();
      if (value == 'delete') widget.onDelete();
    });
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 28,
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }
}

// ── Console Output ───────────────────────────────────────────────────────────

class _Console extends StatefulWidget {
  const _Console({required this.state, required this.scrollController});
  final RunState state;
  final ScrollController scrollController;

  @override
  State<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<_Console> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _copyAll() {
    final session = widget.state.activeSession;
    if (session == null) return;
    final text = session.output.map((l) => l.text).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Output copied to clipboard'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final session = widget.state.activeSession;

    if (session == null) {
      return _EmptyConsole(
        hasWorkspace: widget.state.workspacePath != null,
        configs: widget.state.configs,
      );
    }

    final output = session.output;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyA) {
          _copyAll();
        }
      },
      child: GestureDetector(
        onTap: _focusNode.requestFocus,
        child: Container(
          color: colors.terminalBackground,
          child: Column(
            children: [
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: colors.surface,
                child: ClipRect(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '> ${session.config.command}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (session.startedAt != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(session.startedAt!),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(120), fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Copy all (⌘A)',
                        child: InkWell(
                          onTap: _copyAll,
                          child: Icon(Icons.copy_outlined,
                              size: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(120)),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: output.isEmpty
                    ? Center(
                        child: Text(
                          'No output yet…',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(120), fontSize: 12),
                        ),
                      )
                    : _FullLogView(
                        output: output,
                        scrollController: widget.scrollController,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// Renders all output lines as a single selectable block.
/// Ctrl+A / ⌘A selects everything; ⌘C copies the selection.
class _FullLogView extends StatelessWidget {
  const _FullLogView({
    required this.output,
    required this.scrollController,
  });

  final List<RunOutputLine> output;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    // Build a TextSpan that colours error lines red / orange.
    final spans = <TextSpan>[];
    for (final line in output) {
      final t = line.text;
      final Color color;
      if (t.startsWith('\n[Process exited')) {
        color = const Color(0xFF44446A);
      } else if (t.startsWith('Reloaded') || t.contains('🔥')) {
        color = AppColors.neonGreen;
      } else if (line.isError) {
        color = AppColors.neonRed;
      } else if (t.toLowerCase().contains('error')) {
        color = AppColors.neonOrange;
      } else {
        color = AppColors.terminalText;
      }
      spans.add(TextSpan(text: '$t\n', style: TextStyle(color: color)));
    }

    return Scrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SelectableText.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            children: spans,
          ),
          // Let the OS handle Ctrl+A / ⌘A for select-all within this widget.
          contextMenuBuilder: (context, editableTextState) =>
              AdaptiveTextSelectionToolbar.editableText(
            editableTextState: editableTextState,
          ),
        ),
      ),
    );
  }
}

class _EmptyConsole extends StatelessWidget {
  const _EmptyConsole({
    required this.hasWorkspace,
    required this.configs,
  });

  final bool hasWorkspace;
  final List<RunConfig> configs;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cubit = context.read<RunCubit>();

    return Container(
      color: colors.terminalBackground,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primary.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.play_circle_outline,
                  size: 32, color: colors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Run Configurations',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasWorkspace
                  ? 'Select a configuration from the left panel to run it'
                  : 'Open a workspace to get started',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(120), fontSize: 12),
            ),
            if (hasWorkspace && configs.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: configs
                    .take(3)
                    .map(
                      (c) => _RunQuickButton(
                        config: c,
                        onTap: () => cubit.startRun(c),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

class _RunQuickButton extends StatelessWidget {
  const _RunQuickButton({required this.config, required this.onTap});
  final RunConfig config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dotColor = config.color ?? colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 12, color: dotColor),
            const SizedBox(width: 4),
            Text(config.name,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Pulsing dot animation ────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withAlpha((_anim.value * 255).round()),
        ),
      ),
    );
  }
}
