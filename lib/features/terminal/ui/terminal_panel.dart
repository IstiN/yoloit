import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:xterm/src/core/buffer/line.dart' as xterm_buffer;
import 'package:xterm/src/core/cell.dart' as xterm_core;
import 'package:xterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/hotkeys/hotkeys.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_shortcuts.dart';
import 'package:yoloit/features/terminal/ui/widgets/workspace_status_bar.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/features/workspaces/ui/new_agent_session_dialog.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

class TerminalPanel extends StatelessWidget {
  const TerminalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TerminalCubit, TerminalState>(
      builder: (context, state) {
        if (state is TerminalLoaded && state.sessions.isNotEmpty) {
          return _TerminalView(state: state);
        }
        return _EmptyTerminal();
      },
    );
  }
}

class _EmptyTerminal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final remote = _remoteInfoForTerminal(context);
    return _buildContent(context, remote: remote);
  }

  RemoteBoardInfo? _remoteInfoForTerminal(BuildContext context) {
    try {
      final board = context.read<BoardCubit>().state.activeBoard;
      if (board == null) return null;
      return remoteInfoForBoard(board);
    } catch (_) {
      return null;
    }
  }

  Widget _buildContent(
    BuildContext context, {
    required RemoteBoardInfo? remote,
  }) {
    final colors = context.appColors;
    return Container(
      color: colors.terminalBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TerminalHeader(sessions: [], activeIndex: 0),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.primary.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.terminal_outlined,
                      size: 32,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    remote != null ? 'Remote Terminal' : 'AI Agents',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Caption(
                    remote != null
                        ? 'Start a shell on the connected Mac'
                        : 'Open a workspace and start an AI agent to begin',
                    fontSize: 13,
                  ),
                  const SizedBox(height: 24),
                  if (remote != null)
                    _RemoteTerminalButton(remote: remote)
                  else
                    const _AgentLaunchButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteTerminalButton extends StatelessWidget {
  const _RemoteTerminalButton({required this.remote});

  final RemoteBoardInfo remote;

  @override
  Widget build(BuildContext context) {
    final board = context.read<BoardCubit>().state.activeBoard;
    final cwd = board?.defaultFolder ?? '';
    return FilledButton.icon(
      onPressed: () {
        context.read<TerminalCubit>().createRemoteSession(
          remoteInfo: remote,
          cwd: cwd.isEmpty ? '/' : cwd,
        );
      },
      icon: const Icon(Icons.terminal, size: 18),
      label: const Text('Start remote terminal'),
    );
  }
}

class _AgentLaunchButtons extends StatelessWidget {
  const _AgentLaunchButtons();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, wsState) {
        final hasActive =
            wsState is WorkspaceLoaded && wsState.activeWorkspace != null;
        if (!hasActive) {
          return Text(
            'Select a workspace from the left panel first',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children:
                AgentType.values.map((type) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _AgentLaunchButton(
                      type: type,
                      workspacePath: wsState.activeWorkspace!.workspaceDir,
                      workspaceId: wsState.activeWorkspace!.id,
                    ),
                  );
                }).toList(),
          ),
        );
      },
    );
  }
}

class _TerminalView extends StatefulWidget {
  const _TerminalView({required this.state});
  final TerminalLoaded state;

  @override
  State<_TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<_TerminalView> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sessions = widget.state.sessions;
    final activeIndex = widget.state.activeIndex.clamp(
      0,
      sessions.isEmpty ? 0 : sessions.length - 1,
    );
    final activeSession = widget.state.activeSession;

    return Container(
      color: colors.terminalBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TerminalHeader(sessions: sessions, activeIndex: activeIndex),
          if (activeSession != null) _SessionInfoBar(session: activeSession),
          Expanded(
            child:
                sessions.isEmpty
                    ? const SizedBox()
                    : Stack(
                      children: [
                        for (final e in sessions.asMap().entries)
                          if (e.key == activeIndex)
                            RepaintBoundary(
                              child: TerminalWidget(
                                key: ValueKey(e.value.id),
                                session: e.value,
                                isActive: true,
                              ),
                            )
                          else
                            const SizedBox(),
                      ],
                    ),
          ),
          WorkspaceStatusBar(session: activeSession),
        ],
      ),
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({required this.sessions, required this.activeIndex});
  final List<AgentSession> sessions;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 36,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.tabBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Scrollable session tabs — takes all available space
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sessions.length,
              padding: const EdgeInsets.only(left: 4, right: 4),
              itemBuilder: (context, i) {
                final session = sessions[i];
                final isActive = i == activeIndex;
                return _AgentTab(
                  session: session,
                  isActive: isActive,
                  onTap: () => context.read<TerminalCubit>().switchTab(i),
                  onClose:
                      () => context.read<TerminalCubit>().closeSession(
                        session.id,
                      ),
                  onRename:
                      (name) => context.read<TerminalCubit>().renameSession(
                        session.id,
                        name,
                      ),
                );
              },
            ),
          ),
          // "+" button to launch a new agent session
          BlocBuilder<WorkspaceCubit, WorkspaceState>(
            builder: (context, wsState) {
              final workspace =
                  wsState is WorkspaceLoaded ? wsState.activeWorkspace : null;
              if (workspace == null) return const SizedBox.shrink();
              return Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: colors.border)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _AddSessionButton(workspace: workspace),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AgentTab extends StatefulWidget {
  const _AgentTab({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.onRename,
  });

  final AgentSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<String> onRename;

  @override
  State<_AgentTab> createState() => _AgentTabState();
}

class _AgentTabState extends State<_AgentTab> {
  bool _hovering = false;
  bool _editing = false;
  late final TextEditingController _nameController;
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.session.displayName);
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editing) _commitRename();
    });
  }

  @override
  void didUpdateWidget(_AgentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing &&
        oldWidget.session.displayName != widget.session.displayName) {
      _nameController.text = widget.session.displayName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _nameController.text = widget.session.displayName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocus.requestFocus();
        _nameController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _nameController.text.length,
        );
      }
    });
  }

  void _commitRename() {
    if (!_editing) {
      return; // guard against double-call (onSubmitted + focus lost)
    }
    final name = _nameController.text.trim();
    setState(() => _editing = false);
    widget.onRename(name);
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final colors = context.appColors;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.drive_file_rename_outline,
                size: 14,
                color: colors.textMuted,
              ),
              const SizedBox(width: 8),
              const Text('Rename', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'close',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.close, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              const Text('Close', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
    if (result == 'rename') _startEditing();
    if (result == 'close') widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final session = widget.session;
    final isLive = session.status == AgentStatus.live;
    final statusColor = isLive ? colors.statusActive : colors.statusIdle;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _editing ? null : widget.onTap,
        onDoubleTap: _editing ? null : _startEditing,
        onSecondaryTapDown:
            _editing
                ? null
                : (d) => _showContextMenu(context, d.globalPosition),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.isActive ? colors.background : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.isActive ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                session.type.iconLabel,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      widget.isActive ? colors.primaryLight : colors.textMuted,
                ),
              ),
              const SizedBox(width: 5),
              if (_editing)
                SizedBox(
                  width: 90,
                  height: 20,
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: colors.primary, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(
                          color: colors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _commitRename(),
                    onEditingComplete: _commitRename,
                  ),
                )
              else
                Text(
                  session.displayName,
                  style: TextStyle(
                    color:
                        widget.isActive
                            ? colors.primaryLight
                            : colors.textSecondary,
                    fontSize: 12,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              const SizedBox(width: 5),
              // Compact status dot
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!_editing) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Visibility(
                    visible: _hovering || widget.isActive,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: GestureDetector(
                      onTap: widget.onClose,
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color:
                            _hovering ? colors.textPrimary : colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionInfoBar extends StatelessWidget {
  const _SessionInfoBar({required this.session});
  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Text(
            'YoLoIT > ',
            style: TextStyle(
              color: colors.primaryLight,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            child: Text(
              session.type.command,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class TerminalWidget extends StatefulWidget {
  const TerminalWidget({
    super.key,
    required this.session,
    required this.isActive,
    this.autoRequestFocus = true,
    this.debugLabel,
    this.terminalOutputWriter,
    this.debugLogSink,
    this.debugForceAltScrollKeyFallback = false,
    this.linkOpener,
  });
  final AgentSession session;
  final bool isActive;
  final String? debugLabel;
  final void Function(String sessionId, String data)? terminalOutputWriter;
  final void Function(String message)? debugLogSink;
  final bool debugForceAltScrollKeyFallback;
  final FutureOr<void> Function(String url)? linkOpener;

  /// When false, the terminal won't auto-request focus on creation or when
  /// becoming active. This prevents focus-fighting when multiple terminals
  /// exist (e.g. mindmap cards). Focus will still be requested on click.
  final bool autoRequestFocus;

  @override
  State<TerminalWidget> createState() => TerminalWidgetState();
}

@visibleForTesting
final terminalUrlPattern = RegExp(
  r'(?:https?|file)://[^\s<>"'
  ']+',
);

@visibleForTesting
class TerminalUrlLine {
  const TerminalUrlLine(this.text, {this.isWrapped = false});

  final String text;
  final bool isWrapped;
}

@visibleForTesting
String? terminalUrlAtCell(String line, int cellX) {
  for (final match in terminalUrlPattern.allMatches(line)) {
    var end = match.end;
    while (end > match.start &&
        _terminalUrlTrailingChars.contains(line[end - 1])) {
      end--;
    }
    if (end <= match.start) continue;
    if (cellX >= match.start && cellX < end) {
      return line.substring(match.start, end);
    }
  }
  return null;
}

@visibleForTesting
String? terminalUrlAtWrappedCell(
  List<TerminalUrlLine> lines,
  int lineY,
  int cellX,
) {
  if (lineY < 0 || lineY >= lines.length) return null;

  var start = lineY;
  while (start > 0 && lines[start].isWrapped) {
    start--;
  }

  var end = lineY;
  while (end + 1 < lines.length && lines[end + 1].isWrapped) {
    end++;
  }

  final buffer = StringBuffer();
  var logicalCellX = cellX;
  for (var y = start; y <= end; y++) {
    final text = lines[y].text;
    if (y < lineY) logicalCellX += text.length;
    buffer.write(text);
  }

  return terminalUrlAtCell(buffer.toString(), logicalCellX);
}

const _terminalUrlTrailingChars = '.,;:)]}';

/// Whether a normalized (CR-stripped, left-trimmed) terminal row starts with
/// a prompt/choice prefix typical of interactive agent TUIs.
@visibleForTesting
bool terminalRowHasInterestingPrefix(String normalized) {
  return normalized.startsWith('>') ||
      normalized.startsWith('}') ||
      normalized.startsWith('1.') ||
      normalized.startsWith('2.') ||
      normalized.startsWith('3.') ||
      normalized.startsWith('◆') ||
      normalized.startsWith('❯');
}

/// Whether a normalized terminal row contains a marker typical of interactive
/// agent TUIs (trust prompts, yes/no choices, box-drawing glyphs).
@visibleForTesting
bool terminalRowHasInterestingMarker(String normalized) {
  return normalized.contains('Confirm folder trust') ||
      normalized.contains('Do you trust') ||
      normalized.contains('Yes') ||
      normalized.contains('No (Esc)') ||
      normalized.contains('◆') ||
      normalized.contains('❯') ||
      normalized.contains('→') ||
      normalized.contains('┌') ||
      normalized.contains('├') ||
      normalized.contains('└') ||
      normalized.contains('│');
}

/// Whether a raw terminal row looks like an interactive TUI row worth
/// dumping in verbose diagnostics.
@visibleForTesting
bool isInterestingTerminalRow(String text) {
  final normalized = text.replaceAll('\r', '').trimLeft();
  return terminalRowHasInterestingPrefix(normalized) ||
      terminalRowHasInterestingMarker(normalized);
}

/// Picks which buffer rows to dump in verbose diagnostics: rows around the
/// cursor and the visible edges, plus all visible rows when any of them looks
/// like an interactive TUI row. Capped at 30 rows to avoid log spam.
@visibleForTesting
List<int> collectTerminalDiagnosticRows({
  required int visibleStart,
  required int visibleEnd,
  required int cursorRow,
  required int lineCount,
  required String Function(int row) textAt,
}) {
  final rows = <int>{};
  void addAround(int row) {
    for (var delta = -1; delta <= 1; delta++) {
      final candidate = row + delta;
      if (candidate >= 0 && candidate < lineCount) {
        rows.add(candidate);
      }
    }
  }

  addAround(cursorRow);
  addAround(visibleStart);
  addAround(visibleEnd);

  bool hasInteresting = false;
  for (var row = visibleStart; row <= visibleEnd; row++) {
    final text = textAt(row);
    if (isInterestingTerminalRow(text)) {
      addAround(row);
      hasInteresting = true;
    }
  }

  // When TUI is active dump ALL visible rows for full diagnostics.
  if (hasInteresting) {
    for (var row = visibleStart; row <= visibleEnd; row++) {
      rows.add(row);
    }
  }

  final sorted = rows.toList()..sort();
  // Cap at 30 rows to avoid excessive log spam.
  if (sorted.length <= 30) return sorted;
  return sorted.sublist(0, 30);
}

/// Makes raw terminal text safe for a single log line and truncates it.
@visibleForTesting
String sanitizeTerminalLogText(String text) {
  final sanitized = text
      .replaceAll('\x1b', r'\x1b')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
  return sanitized.length <= 160
      ? sanitized
      : '${sanitized.substring(0, 160)}...';
}

/// Renders a single cell codepoint for diagnostics logs.
@visibleForTesting
String debugTerminalCellChar(int code) {
  if (code == 0) return '0x0';
  if (code == 0x20) return '<sp>';
  final char = String.fromCharCode(code);
  if (RegExp(r'^[ -~]$').hasMatch(char)) return char;
  return '0x${code.toRadixString(16)}';
}

/// Dumps per-cell content/attribute data of a buffer line for diagnostics.
@visibleForTesting
String dumpXtermCellDiagnostics(
  xterm_buffer.BufferLine line, {
  required int maxCols,
}) {
  final cell = xterm_core.CellData.empty();
  final parts = <String>[];
  for (var col = 0; col < maxCols && col < line.length; col++) {
    line.getCellData(col, cell);
    final code = cell.content & xterm_core.CellContent.codepointMask;
    final width = cell.content >> xterm_core.CellContent.widthShift;
    if (parts.length >= 40) break;
    if (code == 0 && width <= 0) continue;
    if (code == 0 && cell.flags == 0 && cell.background == 0 && col >= 6) {
      continue;
    }
    parts.add(
      '$col:${debugTerminalCellChar(code)}'
      '/w$width/f${cell.flags}/fg${cell.foreground}/bg${cell.background}',
    );
  }
  return parts.isEmpty ? '-' : parts.join(' | ');
}

class _TerminalScrollChrome extends StatelessWidget {
  const _TerminalScrollChrome({
    required this.controller,
    required this.colors,
    required this.child,
  });

  final ScrollController controller;
  final AppColorScheme colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 14,
      minThumbLength: 44,
      radius: const Radius.circular(8),
      trackRadius: const Radius.circular(8),
      thumbColor: colors.primary.withAlpha(190),
      trackColor: colors.surfaceElevated.withAlpha(180),
      trackBorderColor: colors.border.withAlpha(160),
      child: child,
    );
  }
}

class _CanvasGestureAbsorbPointer extends StatelessWidget {
  const _CanvasGestureAbsorbPointer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CanvasInteractionLock.instance.canvasGestureCount,
      builder:
          (context, activeCount, child) =>
              AbsorbPointer(absorbing: activeCount > 0, child: child),
      child: child,
    );
  }
}

class _TerminalScrollAnchor {
  const _TerminalScrollAnchor({
    required this.pixels,
    required this.fraction,
    required this.stickToBottom,
  });

  final double pixels;
  final double fraction;
  final bool stickToBottom;
}

class TerminalWidgetState extends State<TerminalWidget> {
  final _controller = TerminalController(
    pointerInputs: const PointerInputs.none(),
  );
  final _focusNode = FocusNode();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  Timer? _focusRetryTimer;
  double _fontSize = 13.0;

  bool get _hardwareKeyboardOnly {
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }
  _TerminalScrollAnchor? _resizeScrollAnchor;
  _TerminalScrollAnchor? _userScrollAnchor;
  Timer? _userScrollAnchorTimer;
  Timer? _userScrollPreserveTimer;
  Timer? _resizeDebounce;
  Timer? _terminalDiagnosticsDebounce;
  int _terminalDiagnosticsQuietTicks = 0;
  Offset? _clickDownPosition;
  String? _pendingTerminalDiagnosticsReason;

  // Manual drag-to-select: xterm 4.x's PanGestureRecognizer fails to win the
  // gesture arena in our widget tree, so we implement selection directly via
  // raw Listener pointer events — these always fire regardless of arena.
  bool _isDragSelecting = false;
  Offset? _dragStartGlobal;
  final _scrollbarPointers = <int>{};

  // Pinch-to-zoom tracked via raw pointer events (avoids gesture arena
  // conflict with xterm's internal pan recogniser used for text selection).
  final _activePointers = <int, Offset>{};
  double _pinchStartDistance = 0;
  double _pinchStartFontSize = 0;
  double _altScrollRemainder = 0;
  DateTime? _lastMetricsLogAt;

  // Search overlay state
  bool _isSearching = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<CellOffset> _searchHits = [];
  int _currentHitIndex = -1;
  bool _lastAltBuffer = false;

  Size? get _terminalRenderSize {
    final context = _terminalViewKey.currentContext;
    if (context == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    return renderBox?.size;
  }

  bool _isTerminalScrollbarHit(Offset localPosition) {
    final size = _terminalRenderSize;
    if (size == null || size == Size.zero) return false;
    const scrollbarHitWidth = 24.0;
    return localPosition.dx >= size.width - scrollbarHitWidth;
  }

  late final ScrollController _scrollController;

  // Identity-checked callbacks stored as fields so we can null them safely in
  // dispose without clobbering another TerminalWidget that rebound the same
  // shared `session.terminal` (e.g. panel + mindmap viewing same session).
  void Function(String)? _boundOnOutput;
  void Function(int, int, int, int)? _boundOnResize;

  void _persistScrollOffset() {
    if (_scrollController.hasClients) {
      widget.session.scrollOffset = _scrollController.offset;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.session.scrollOffset,
    );
    _scrollController.addListener(_persistScrollOffset);
    _bindTerminal();
    _attachTerminalDiagnostics(widget.session);
    _attachSupportLogging(widget.session);
    if (widget.autoRequestFocus) _requestFocusAfterFrame();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    // Load persisted font size (cached getter — a full prefs load per
    // terminal initState showed up in CPU profiling).
    SessionPrefs.loadTerminalFontSize().then((size) {
      if (mounted) setState(() => _fontSize = size);
    });
    // Restore scroll position after the first frame because xterm's
    // RenderTerminal defaults _stickToBottom=true and snaps to maxExtent
    // during initial layout, ignoring initialScrollOffset.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        final stored = widget.session.scrollOffset;
        final isDefault = stored <= position.minScrollExtent + 1;
        final target = isDefault
            ? position.maxScrollExtent
            : stored.clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              );
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  void didUpdateWidget(TerminalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _unbindTerminalIfOurs(oldWidget.session);
      _detachTerminalDiagnostics(oldWidget.session);
      _detachSupportLogging(oldWidget.session);
      _bindTerminal();
      _attachTerminalDiagnostics(widget.session);
      _attachSupportLogging(widget.session);
      HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    }
    // Request focus when this session becomes active (conditional render shows it).
    if (!oldWidget.isActive && widget.isActive && widget.autoRequestFocus) {
      _requestFocusAfterFrame();
    }
  }

  void _requestFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _requestKeyboardOnActiveEngine();
      }
    });
    // Retry after dialog dismiss animation (e.g. NewAgentSessionDialog pop).
    _focusRetryTimer?.cancel();
    _focusRetryTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && widget.isActive && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
        _requestKeyboardOnActiveEngine();
      }
    });
  }

  void _requestKeyboardOnActiveEngine() {
    _terminalViewKey.currentState?.requestKeyboard();
  }

  void _bindTerminal() {
    _unbindTerminalIfOurs(widget.session);
    _boundOnOutput = (data) {
      final writer =
          widget.terminalOutputWriter ?? TerminalBackendService.instance.write;
      writer(widget.session.id, data);
    };
    _boundOnResize = (cols, rows, pixelWidth, pixelHeight) {
      _captureResizeScrollAnchor();
      // Debounce backend resize — during a panel-drag the terminal dimension
      // changes on every frame, and flooding the PTY with resize signals
      // causes the shell/app to re-render output continuously which hangs UI.
      _resizeDebounce?.cancel();
      _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
        TerminalBackendService.instance.resize(widget.session.id, cols, rows);
      });
      _scheduleTerminalDiagnostics('resize cols=$cols rows=$rows');
      _restoreResizeScrollAnchor();
    };
    widget.session.terminal.onOutput = _boundOnOutput;
    widget.session.terminal.onResize = _boundOnResize;
  }

  void _unbindTerminalIfOurs(AgentSession session) {
    // Only clear if the bound callback is still ours — otherwise another
    // TerminalWidget (e.g. panel vs mindmap) has since rebound and we'd wipe
    // its binding.
    if (identical(session.terminal.onOutput, _boundOnOutput)) {
      session.terminal.onOutput = null;
    }
    if (identical(session.terminal.onResize, _boundOnResize)) {
      session.terminal.onResize = null;
    }
  }

  void _attachTerminalDiagnostics(AgentSession session) {
    if (!_terminalDiagnosticsEnabled) return;
    session.terminal.addListener(_onTerminalDiagnosticsChange);
  }

  void _detachTerminalDiagnostics(AgentSession session) {
    if (!_terminalDiagnosticsEnabled) return;
    session.terminal.removeListener(_onTerminalDiagnosticsChange);
  }

  void _attachSupportLogging(AgentSession session) {
    _lastAltBuffer = session.terminal.isUsingAltBuffer;
    _focusNode.addListener(_onFocusChanged);
    session.terminal.addListener(_onTerminalStateChangedForSupportLog);
    SupportLogService.instance.add(
      'terminal-widget',
      'session=${session.id} attach altBuffer=$_lastAltBuffer',
    );
  }

  void _detachSupportLogging(AgentSession session) {
    _focusNode.removeListener(_onFocusChanged);
    session.terminal.removeListener(_onTerminalStateChangedForSupportLog);
  }

  void _onFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    var message = 'session=${widget.session.id} focus=$hasFocus';
    if (!hasFocus) {
      // Typing silently dies when focus leaves the terminal — record who
      // holds focus now plus the active board/panel so support logs show
      // the thief.
      message += ' ${_describePrimaryFocus()} ${_describeBoardContext()}';
    }
    SupportLogService.instance.add('terminal-widget', message);
  }

  String _describePrimaryFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return 'primaryFocus=none';
    final widgetType = primary.context?.widget.runtimeType.toString() ?? '?';
    final label = primary.debugLabel ?? '-';
    return 'primaryFocus=$widgetType(label=$label)';
  }

  String _describeBoardContext() {
    try {
      final board = context.read<BoardCubit>().state.activeBoard;
      if (board == null) return 'board=none';
      final focusedId = board.viewport.focusedPanelId;
      if (focusedId == null) return 'board=${board.name} focusedPanel=none';
      for (final panel in board.panels) {
        if (panel.id == focusedId) {
          return 'board=${board.name} '
              'focusedPanel=${panel.type}:"${panel.title}"($focusedId)';
        }
      }
      return 'board=${board.name} focusedPanel=missing($focusedId)';
    } catch (_) {
      return 'board=unavailable';
    }
  }

  void _onTerminalStateChangedForSupportLog() {
    final next = widget.session.terminal.isUsingAltBuffer;
    if (next == _lastAltBuffer) return;
    _lastAltBuffer = next;
    SupportLogService.instance.add(
      'terminal-widget',
      'session=${widget.session.id} altBuffer=$next',
    );
  }

  void _onTerminalDiagnosticsChange() {
    _scheduleTerminalDiagnostics('buffer-change');
  }

  /// Whether to enable verbose per-cell terminal diagnostics.
  ///
  /// Defaults to `false` because dumping every visible cell on every buffer
  /// change (even with a short debounce) generates thousands of log lines per
  /// second and freezes the Flutter UI thread in debug builds.
  static bool enableTerminalDiagnostics = false;

  bool get _terminalDiagnosticsEnabled => kDebugMode &&
      (enableTerminalDiagnostics || widget.debugLabel != null || widget.debugLogSink != null);

  String get _terminalDiagnosticsLabel => widget.debugLabel ?? widget.session.id;

  void _debugTerminalLog(String message) {
    if (!_terminalDiagnosticsEnabled) return;
    widget.debugLogSink?.call(message);
    debugPrint('[TerminalDiag:${_terminalDiagnosticsLabel}] $message');
  }

  void _scheduleTerminalDiagnostics(String reason) {
    if (!_terminalDiagnosticsEnabled || !mounted || !widget.isActive) return;
    _pendingTerminalDiagnosticsReason = reason;
    _terminalDiagnosticsQuietTicks = 0;
    // A single periodic ticker instead of cancel+new Timer per buffer change:
    // under output floods the debounce created thousands of Timer objects per
    // second in debug builds. The ticker fires the dump once the buffer has
    // been quiet for 4 ticks (2s) and then stops itself. Tick counting (not
    // DateTime.now) keeps the debounce testable under fake async time.
    _terminalDiagnosticsDebounce ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        _terminalDiagnosticsQuietTicks++;
        if (_terminalDiagnosticsQuietTicks < 4) return;
        _terminalDiagnosticsDebounce?.cancel();
        _terminalDiagnosticsDebounce = null;
        if (!mounted || !widget.isActive) return;
        _dumpTerminalDiagnostics(_pendingTerminalDiagnosticsReason ?? reason);
      },
    );
  }

  void _dumpTerminalDiagnostics(String reason) {
    _debugTerminalLog('$reason ${debugStateSummary}');
    _dumpXtermDiagnostics(active: true);
  }

  void _dumpXtermDiagnostics({required bool active}) {
    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final lines = buffer.lines;
    if (lines.length == 0) {
      _debugTerminalLog('xterm active=$active lines=0');
      return;
    }
    final visibleStart = buffer.scrollBack.clamp(0, lines.length - 1);
    final visibleEnd = (visibleStart + terminal.viewHeight - 1).clamp(
      visibleStart,
      lines.length - 1,
    );
    final renderState = _terminalViewKey.currentState;
    final renderTerminal = renderState?.renderTerminal;
    final renderSummary =
        renderTerminal == null
            ? 'render=none'
            : 'cell=${renderTerminal.cellSize.width.toStringAsFixed(2)}x'
                '${renderTerminal.cellSize.height.toStringAsFixed(2)} '
                'lineHeight=${renderTerminal.lineHeight.toStringAsFixed(2)}';
    _debugTerminalLog(
      'xterm active=$active visible=$visibleStart-$visibleEnd '
      'cursor=${buffer.cursorX},${buffer.cursorY} abs=${buffer.absoluteCursorY} '
      'scrollBack=${buffer.scrollBack} $renderSummary',
    );
    // Per-cell row dumps are extremely verbose and can freeze the UI thread
    // in debug builds when output is continuous. Only emit them when the
    // explicit verbose flag is set.
    if (TerminalWidgetState.enableTerminalDiagnostics) {
      for (final row in collectTerminalDiagnosticRows(
        visibleStart: visibleStart,
        visibleEnd: visibleEnd,
        cursorRow: buffer.absoluteCursorY,
        lineCount: lines.length,
        textAt: (row) => lines[row].getText(),
      )) {
        final line = lines[row];
        _debugTerminalLog(
          'xterm row=$row wrapped=${line.isWrapped} '
          'text="${sanitizeTerminalLogText(line.getText())}" '
          'cells=${dumpXtermCellDiagnostics(line, maxCols: terminal.viewWidth.clamp(0, 80).toInt())}',
        );
      }
    }
  }

  /// Intercepts macOS keyboard shortcuts and translates them to PTY control
  /// sequences before [TerminalView] can process the raw key event.
  ///
  /// The key → sequence/action mapping lives in [terminalKeyEventShortcut];
  /// this method only computes modifier flags and executes the result.
  KeyEventResult _onTerminalKeyEvent(FocusNode node, KeyEvent event) {
    if (kDebugMode) {
      debugPrint(
        '[TerminalKey] _onTerminalKeyEvent key=${event.logicalKey} '
        'character=${event.character} hasFocus=${node.hasFocus} '
        'hardwareOnly=$_hardwareKeyboardOnly',
      );
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shortcut = terminalKeyEventShortcut(
      event.logicalKey,
      isShift: HardwareKeyboard.instance.isShiftPressed,
      isCmd: HardwareKeyboard.instance.isMetaPressed,
      isCtrl: HardwareKeyboard.instance.isControlPressed,
      isAlt: HardwareKeyboard.instance.isAltPressed,
      awaitingApproval: widget.session.hookPhase is AwaitingApprovalPhase,
    );
    switch (shortcut) {
      case TerminalPtyShortcut(:final sequence):
        _writePty(sequence);
        return KeyEventResult.handled;
      case TerminalActionShortcut(
        action: TerminalShortcutAction.blockNativePaste,
      ):
        return KeyEventResult.handled;
      case TerminalActionShortcut(
        action: TerminalShortcutAction.notifyEnterPressed,
      ):
        context.read<TerminalCubit>().onTerminalEnterPressed(widget.session.id);
        return KeyEventResult.ignored;
      case TerminalActionShortcut():
      case null:
        return KeyEventResult.ignored;
    }
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (kDebugMode) {
      debugPrint(
        '[TerminalKey] _handleHardwareKey key=${event.logicalKey} '
        'character=${event.character} hasFocus=${_focusNode.hasFocus} '
        'isKeyDown=${event is KeyDownEvent}',
      );
    }
    if (!_focusNode.hasFocus) return false;
    if (event is! KeyDownEvent) return false;

    final shortcut = terminalShortcutSequence(
      event.logicalKey,
      isCmd: HardwareKeyboard.instance.isMetaPressed,
      isCtrl: HardwareKeyboard.instance.isControlPressed,
      isAlt: HardwareKeyboard.instance.isAltPressed,
      hasSelection: _controller.selection != null,
    );
    switch (shortcut) {
      case TerminalPtyShortcut(:final sequence):
        _writePty(sequence);
        return true;
      case TerminalActionShortcut(:final action):
        return _runShortcutAction(action);
      case null:
        return false;
    }
  }

  bool _runShortcutAction(TerminalShortcutAction action) {
    switch (action) {
      // Cmd+V → smart paste (safe short text inline, otherwise file ref).
      case TerminalShortcutAction.paste:
        _pasteAsFileRef();
        return true;
      // Cmd+F → open search
      case TerminalShortcutAction.openSearch:
        _openSearch();
        return true;
      // Cmd+O → global quick file search (prevent terminal from swallowing it)
      case TerminalShortcutAction.openFileSearch:
        Actions.invoke(context, const OpenFileSearchIntent());
        return true;
      // Cmd+= → increase font size
      case TerminalShortcutAction.increaseFontSize:
        setState(() => _fontSize = (_fontSize + 1).clamp(8.0, 32.0));
        return true;
      // Cmd+- → decrease font size
      case TerminalShortcutAction.decreaseFontSize:
        setState(() => _fontSize = (_fontSize - 1).clamp(8.0, 32.0));
        return true;
      // Cmd+A → select all terminal buffer content
      case TerminalShortcutAction.selectAll:
        _selectAll();
        return true;
      // Cmd+C → copy selection if one exists; otherwise let xterm send ^C
      case TerminalShortcutAction.copySelection:
        final selection = _controller.selection;
        if (selection == null) return false;
        final text = widget.session.terminal.buffer.getText(selection);
        copyToClipboard(text);
        return true;
      // Never produced by terminalShortcutSequence.
      case TerminalShortcutAction.blockNativePaste:
      case TerminalShortcutAction.notifyEnterPressed:
        return false;
    }
  }

  void _selectAll() {
    final terminal = widget.session.terminal;
    _controller.setSelection(
      terminal.buffer.createAnchor(
        0,
        terminal.buffer.height - terminal.viewHeight,
      ),
      terminal.buffer.createAnchor(
        terminal.viewWidth,
        terminal.buffer.height - 1,
      ),
      mode: SelectionMode.line,
    );
  }

  void _writePty(String sequence) {
    if (kDebugMode) {
      debugPrint(
        '[TerminalKey] _writePty session=${widget.session.id} '
        'data="${sequence.replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\x03', '^C').replaceAll('\x1b', 'ESC')}"',
      );
    }
    TerminalBackendService.instance.write(widget.session.id, sequence);
  }

  /// Public API for external widgets (e.g. full-view debug overlay) to send
  /// raw input to the PTY without going through keyboard focus.
  void writeToPty(String data) => _writePty(data);

  /// Public API for panel chrome actions to move through terminal scrollback
  /// without sending PageUp/PageDown bytes to the running shell or agent.
  void scrollPageUp() {
    _scrollTerminalBy(-_quickScrollExtent, 'quick-action.page-up');
  }

  /// Public API for panel chrome actions to move through terminal scrollback
  /// without sending PageUp/PageDown bytes to the running shell or agent.
  void scrollPageDown() {
    _scrollTerminalBy(_quickScrollExtent, 'quick-action.page-down');
  }

  double get _quickScrollExtent {
    if (!_scrollController.hasClients) return 0;
    return (_scrollController.position.viewportDimension * 0.85).clamp(
      120.0,
      720.0,
    );
  }

  double get currentFontSize => _fontSize;

  String get debugStateSummary {
    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final scroll =
        _scrollController.hasClients
            ? 'scroll=${_scrollController.position.pixels.toStringAsFixed(1)}/'
                '${_scrollController.position.maxScrollExtent.toStringAsFixed(1)}'
            : 'scroll=no-client';
    return 'renderer=${AgentConfigService.instance.terminalRenderEngine.label} '
        'alt=${terminal.isUsingAltBuffer} '
        'mouse=${terminal.mouseMode} '
        'altScroll=${terminal.altBufferMouseScrollMode} '
        'forceKeys=${widget.debugForceAltScrollKeyFallback} '
        'view=${terminal.viewWidth}x${terminal.viewHeight} '
        'cursor=${buffer.cursorX},${buffer.cursorY} '
        'scrollBack=${buffer.scrollBack} '
        'buf=${buffer.height} '
        'lines=${terminal.lines.length} '
        'font=${_fontSize.toStringAsFixed(1)} '
        'size=${_terminalRenderSize?.width.toStringAsFixed(1) ?? '?'}x'
        '${_terminalRenderSize?.height.toStringAsFixed(1) ?? '?'} $scroll';
  }

  void setFontSize(double size) {
    if (mounted) setState(() => _fontSize = size.clamp(8.0, 32.0));
  }

  Future<void> _pasteAsFileRef() async {
    // Use the same smart-paste logic as chat: URLs, existing file paths and
    // safe short single-line text are pasted inline; everything else (images,
    // long text, multi-line text) becomes a temp-file reference so the
    // terminal never receives raw escape sequences.
    final pasted = await SmartClipboardPasteService.instance
        .readInlineTextOrSavedFilePath(allowInlineText: true);
    if (pasted == null || !mounted) return;
    TerminalBackendService.instance.write(widget.session.id, pasted);
  }

  // ── Selection helpers ───────────────────────────────────────────────

  /// Shows a right-click context menu with Copy (if selection) and Paste.
  Future<void> _showTerminalContextMenu(
    BuildContext context,
    Offset globalPos,
  ) async {
    final colors = context.appColors;
    final selection = _controller.selection;
    final hasSelection = selection != null;

    final items = <PopupMenuEntry<_TermCtxAction>>[
      PopupMenuItem(
        value: _TermCtxAction.selectAll,
        height: 36,
        child: Row(
          children: [
            Icon(Icons.select_all, size: 14, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Select All',
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
          ],
        ),
      ),
      if (hasSelection)
        PopupMenuItem(
          value: _TermCtxAction.copy,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.copy, size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Copy',
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
              ),
            ],
          ),
        ),
      PopupMenuItem(
        value: _TermCtxAction.paste,
        height: 36,
        child: Row(
          children: [
            Icon(Icons.content_paste, size: 14, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Paste',
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
          ],
        ),
      ),
      if (hasSelection) ...[
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: _TermCtxAction.clearSelection,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.clear, size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Clear selection',
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ],
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: _TermCtxAction.search,
        height: 36,
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Find',
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
          ],
        ),
      ),
    ];

    final action = await showMenu<_TermCtxAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 1,
        globalPos.dy + 1,
      ),
      items: items,
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.textMuted.withAlpha(60)),
      ),
    );

    if (!mounted) return;

    switch (action) {
      case _TermCtxAction.selectAll:
        _selectAll();
      case _TermCtxAction.copy:
        if (selection != null) {
          final text = widget.session.terminal.buffer.getText(selection);
          _controller.clearSelection();
          await copyToClipboard(text);
        }
      case _TermCtxAction.paste:
        await _pasteAsFileRef();
      case _TermCtxAction.clearSelection:
        _controller.clearSelection();
      case _TermCtxAction.search:
        _openSearch();
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _focusRetryTimer?.cancel();
    _userScrollAnchorTimer?.cancel();
    _userScrollPreserveTimer?.cancel();
    _resizeDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _unbindTerminalIfOurs(widget.session);
    _detachTerminalDiagnostics(widget.session);
    _detachSupportLogging(widget.session);
    _terminalDiagnosticsDebounce?.cancel();
    _scrollController.removeListener(_persistScrollOffset);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
      _searchHits = [];
      _currentHitIndex = -1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchHits = [];
      _currentHitIndex = -1;
      _searchController.clear();
    });
    _controller.clearSelection();
    if (mounted) {
      _focusNode.requestFocus();
      _requestKeyboardOnActiveEngine();
    }
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchHits = [];
        _currentHitIndex = -1;
      });
      _controller.clearSelection();
      return;
    }

    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final lowerQuery = query.toLowerCase();
    final hits = <CellOffset>[];

    for (int row = 0; row < buffer.lines.length; row++) {
      final line = buffer.lines[row];
      final text = line.getText().toLowerCase();
      int idx = 0;
      while (true) {
        idx = text.indexOf(lowerQuery, idx);
        if (idx == -1) break;
        hits.add(CellOffset(idx, row));
        idx += 1;
      }
    }

    setState(() {
      _searchHits = hits;
      _currentHitIndex = hits.isNotEmpty ? 0 : -1;
    });

    if (hits.isNotEmpty) {
      _highlightHit(0);
    } else {
      _controller.clearSelection();
    }
  }

  void _highlightHit(int index) {
    if (_searchHits.isEmpty || index < 0 || index >= _searchHits.length) return;
    final hit = _searchHits[index];
    final queryLen = _searchController.text.length;
    final state = _terminalViewKey.currentState;
    if (state == null) return;

    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final rt = state.renderTerminal;

    // Convert buffer row to visible row
    final visRow = hit.y - buffer.scrollBack;
    if (visRow < 0 || visRow >= terminal.viewHeight) {
      // Hit is in scrollback — not visible, just update counter
      return;
    }

    final termSize = _terminalRenderSize;
    if (termSize == null) return;
    final cellW = (termSize.width - 16) / terminal.viewWidth;
    final cellH = (termSize.height - 16) / terminal.viewHeight;
    final startOffset = Offset(
      hit.x * cellW + 8,
      visRow * cellH + cellH / 2 + 8,
    );
    final endOffset = Offset(
      (hit.x + queryLen) * cellW + 8,
      visRow * cellH + cellH / 2 + 8,
    );
    rt.selectCharacters(startOffset, endOffset);
  }

  void _nextHit() {
    if (_searchHits.isEmpty) return;
    setState(() {
      _currentHitIndex = (_currentHitIndex + 1) % _searchHits.length;
    });
    _highlightHit(_currentHitIndex);
  }

  void _prevHit() {
    if (_searchHits.isEmpty) return;
    setState(() {
      _currentHitIndex =
          (_currentHitIndex - 1 + _searchHits.length) % _searchHits.length;
    });
    _highlightHit(_currentHitIndex);
  }

  bool get _scrollDebugEnabled => kDebugMode && widget.debugLabel != null;

  void _debugScrollLog(String message) {
    if (!_scrollDebugEnabled) return;
    widget.debugLogSink?.call(message);
    debugPrint('[TerminalScroll:${widget.debugLabel}] $message');
  }

  void _debugScrollMetrics(String source) {
    if (!_scrollDebugEnabled) return;
    final now = DateTime.now();
    final last = _lastMetricsLogAt;
    if (last != null && now.difference(last).inMilliseconds < 500) return;
    _lastMetricsLogAt = now;

    final buffer = widget.session.terminal.buffer;
    final hasClients = _scrollController.hasClients;
    final metrics =
        hasClients
            ? 'pixels=${_scrollController.position.pixels.toStringAsFixed(1)} '
                'min=${_scrollController.position.minScrollExtent.toStringAsFixed(1)} '
                'max=${_scrollController.position.maxScrollExtent.toStringAsFixed(1)}'
            : 'no-scroll-client';
    _debugScrollLog(
      '$source metrics alt=${widget.session.terminal.isUsingAltBuffer} '
      'view=${widget.session.terminal.viewWidth}x'
      '${widget.session.terminal.viewHeight} '
      'bufferLines=${buffer.lines.length} scrollBack=${buffer.scrollBack} '
      'size=${_terminalRenderSize?.width.toStringAsFixed(1) ?? '?'}x'
      '${_terminalRenderSize?.height.toStringAsFixed(1) ?? '?'} $metrics',
    );
  }

  void _scrollTerminalBy(double delta, String source) {
    if (delta == 0) return;
    _debugScrollMetrics(source);
    if (!_scrollController.hasClients) {
      _debugScrollLog('$source ignored: no scroll clients');
      return;
    }
    final position = _scrollController.position;
    final target =
        (position.pixels + delta)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if (target == position.pixels) {
      _debugScrollLog(
        '$source clamped delta=${delta.toStringAsFixed(1)} '
        'pixels=${position.pixels.toStringAsFixed(1)} '
        'max=${position.maxScrollExtent.toStringAsFixed(1)}',
      );
      return;
    }
    position.jumpTo(target);
    _markUserScrollActive();
    _debugScrollLog(
      '$source jump delta=${delta.toStringAsFixed(1)} '
      'target=${target.toStringAsFixed(1)}',
    );
  }

  void _preserveScrollForCanvasGesture() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final offset = position.pixels;
    scheduleMicrotask(() {
      if (!mounted || !_scrollController.hasClients) return;
      final nextPosition = _scrollController.position;
      final clamped =
          offset
              .clamp(nextPosition.minScrollExtent, nextPosition.maxScrollExtent)
              .toDouble();
      if ((nextPosition.pixels - clamped).abs() < 0.5) return;
      nextPosition.jumpTo(clamped);
    });
  }

  void _markUserScrollActive() {
    final anchor = _captureScrollAnchor();
    if (anchor == null || anchor.stickToBottom) return;
    _userScrollAnchor = anchor;
    _userScrollAnchorTimer?.cancel();
    _userScrollAnchorTimer = Timer(const Duration(milliseconds: 900), () {
      _userScrollAnchor = null;
      _userScrollPreserveTimer?.cancel();
      _userScrollPreserveTimer = null;
    });
    _userScrollPreserveTimer ??= Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _preserveUserScrollDuringOutput(),
    );
    _preserveUserScrollDuringOutput();
  }

  void _preserveUserScrollDuringOutput() {
    final anchor = _userScrollAnchor;
    if (anchor == null || anchor.stickToBottom) return;
    void restore() {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      final target =
          anchor.pixels
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((position.pixels - target).abs() < 0.5) return;
      position.jumpTo(target);
    }

    scheduleMicrotask(restore);
    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
  }

  _TerminalScrollAnchor? _captureScrollAnchor() {
    if (!_scrollController.hasClients) return null;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return null;
    final max = position.maxScrollExtent;
    final pixels = position.pixels.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final distanceToBottom = max - pixels;
    return _TerminalScrollAnchor(
      pixels: pixels.toDouble(),
      fraction: max <= 0 ? 1 : (pixels / max).clamp(0.0, 1.0).toDouble(),
      stickToBottom: distanceToBottom <= 24,
    );
  }

  void _captureResizeScrollAnchor() {
    _resizeScrollAnchor = _captureScrollAnchor();
  }

  void _restoreResizeScrollAnchor() {
    final anchor = _resizeScrollAnchor;
    if (anchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target =
          anchor.stickToBottom
              ? position.maxScrollExtent
              : position.maxScrollExtent * anchor.fraction;
      position.jumpTo(
        target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  bool _isHorizontalTrackpadGesture(Offset delta) {
    final dx = delta.dx.abs();
    final dy = delta.dy.abs();
    return dx > 4 && dx >= dy * 1.1;
  }

  void _scrollAltBufferBy(double delta, Offset globalPosition, String source) {
    if (delta == 0) return;
    _debugScrollMetrics(source);
    final state = _terminalViewKey.currentState;
    final renderTerminal = state?.renderTerminal;
    if (renderTerminal == null) {
      _debugScrollLog('$source alt ignored: render terminal unavailable');
      return;
    }

    final lineHeight = renderTerminal.lineHeight;
    if (lineHeight <= 0) {
      _debugScrollLog('$source alt ignored: invalid lineHeight=$lineHeight');
      return;
    }

    _altScrollRemainder += delta;
    final wholeLines = (_altScrollRemainder / lineHeight).truncate();
    if (wholeLines == 0) return;
    _altScrollRemainder -= wholeLines * lineHeight;

    final localPosition = renderTerminal.globalToLocal(globalPosition);
    final cell = renderTerminal.getCellOffset(localPosition);
    final up = wholeLines < 0;
    var handledByMouse = false;
    for (var i = 0; i < wholeLines.abs(); i++) {
      final handled = widget.session.terminal.mouseInput(
        up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
        TerminalMouseButtonState.down,
        cell,
      );
      handledByMouse = handledByMouse || handled;
      if (!handled || widget.debugForceAltScrollKeyFallback) {
        widget.session.terminal.keyInput(
          up ? TerminalKey.arrowUp : TerminalKey.arrowDown,
        );
      }
    }
    _debugScrollLog(
      '$source alt steps=$wholeLines up=$up cell=${cell.x},${cell.y} '
      'mouse=$handledByMouse keyFallback='
      '${!handledByMouse || widget.debugForceAltScrollKeyFallback}',
    );
  }

  bool _openXtermUrlAt(Offset globalPosition) {
    final state = _terminalViewKey.currentState;
    if (state == null) return false;
    final renderTerminal = state.renderTerminal;
    final cell = renderTerminal.getCellOffset(
      renderTerminal.globalToLocal(globalPosition),
    );
    if (cell.y < 0 || cell.y >= widget.session.terminal.buffer.lines.length) {
      return false;
    }
    final bufferLines = widget.session.terminal.buffer.lines;
    final lines = List<TerminalUrlLine>.generate(bufferLines.length, (index) {
      final line = bufferLines[index];
      return TerminalUrlLine(line.toString(), isWrapped: line.isWrapped);
    }, growable: false);
    final url = terminalUrlAtWrappedCell(lines, cell.y, cell.x);
    if (url == null) return false;
    unawaited(_openTerminalUrl(url));
    return true;
  }

  Future<void> _openTerminalUrl(String url) async {
    final opener = widget.linkOpener;
    if (opener != null) {
      await opener(url);
      return;
    }
    await PlatformLauncher.instance.openUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      children: [
        _buildXtermTerminal(colors),
        // Search overlay
        if (_isSearching)
          Positioned(top: 8, right: 8, child: _buildSearchBar(colors)),
      ],
    );
  }

  Widget _buildXtermTerminal(AppColorScheme colors) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onTerminalPointerSignal,
      onPointerPanZoomStart: _onTerminalPanZoomStart,
      onPointerPanZoomUpdate: _onTerminalPanZoomUpdate,
      onPointerDown: _onTerminalPointerDown,
      onPointerMove: _onTerminalPointerMove,
      onPointerUp: _onTerminalPointerUp,
      onPointerCancel: _onTerminalPointerCancel,
      child: _wrapTerminal(colors, _buildTerminalView(colors)),
    );
  }

  void _onTerminalPointerSignal(PointerSignalEvent event) {
    final isMouseWheel =
        event is PointerScrollEvent && event.kind == PointerDeviceKind.mouse;
    if (CanvasInteractionLock.instance.isCanvasGestureActive &&
        !isMouseWheel) {
      _preserveScrollForCanvasGesture();
      return;
    }
    if (event is PointerScrollEvent) {
      if (isMouseWheel) {
        CanvasInteractionLock.instance.clearCanvasSignalGesture();
      }
      if (_isHorizontalTrackpadGesture(event.scrollDelta)) {
        CanvasInteractionLock.instance.markCanvasSignalGesture();
        _preserveScrollForCanvasGesture();
        return;
      }
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (resolved) {
          final scrollEvent = resolved as PointerScrollEvent;
          if (widget.session.terminal.isUsingAltBuffer) {
            _scrollAltBufferBy(
              scrollEvent.scrollDelta.dy,
              scrollEvent.position,
              'pointer-signal',
            );
          } else {
            _scrollTerminalBy(
              scrollEvent.scrollDelta.dy,
              'pointer-signal',
            );
          }
        },
      );
    }
  }

  void _onTerminalPanZoomStart(PointerPanZoomStartEvent event) {
    if (CanvasInteractionLock.instance.isCanvasGestureActive) {
      _preserveScrollForCanvasGesture();
      return;
    }
  }

  void _onTerminalPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if ((event.scale - 1.0).abs() > 0.01) {
      CanvasInteractionLock.instance.markCanvasSignalGesture();
      _preserveScrollForCanvasGesture();
      return;
    }
    if (_isHorizontalTrackpadGesture(event.panDelta)) {
      CanvasInteractionLock.instance.markCanvasSignalGesture();
      _preserveScrollForCanvasGesture();
      return;
    }
    if (CanvasInteractionLock.instance.isCanvasGestureActive) {
      _preserveScrollForCanvasGesture();
      return;
    }
    if (widget.session.terminal.isUsingAltBuffer) {
      _scrollAltBufferBy(
        -event.panDelta.dy,
        event.position,
        'pan-zoom',
      );
    } else {
      _scrollTerminalBy(-event.panDelta.dy, 'pan-zoom');
    }
  }

  void _onTerminalPointerDown(PointerDownEvent event) {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    if (_isTerminalScrollbarHit(event.localPosition)) {
      _scrollbarPointers.add(event.pointer);
      _clickDownPosition = null;
      _dragStartGlobal = null;
      _isDragSelecting = false;
      _activePointers.remove(event.pointer);
      _userScrollAnchorTimer?.cancel();
      _userScrollAnchorTimer = null;
      _userScrollPreserveTimer?.cancel();
      _userScrollPreserveTimer = null;
      _userScrollAnchor = null;
      return;
    }
    if (event.buttons == kSecondaryMouseButton) {
      _showTerminalContextMenu(context, event.position);
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    _clickDownPosition = event.localPosition;
    _dragStartGlobal = event.position;
    _isDragSelecting = false;
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 2 &&
        event.kind == PointerDeviceKind.touch) {
      final positions = _activePointers.values.toList();
      _pinchStartDistance = (positions[0] - positions[1]).distance;
      _pinchStartFontSize = _fontSize;
    }
  }

  void _onTerminalPointerMove(PointerMoveEvent event) {
    if (_scrollbarPointers.contains(event.pointer)) {
      return;
    }
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 2 &&
        _pinchStartDistance > 0 &&
        event.kind == PointerDeviceKind.touch) {
      final positions = _activePointers.values.toList();
      final dist = (positions[0] - positions[1]).distance;
      final newSize =
          (_pinchStartFontSize * dist / _pinchStartDistance)
              .clamp(8.0, 48.0);
      setState(() => _fontSize = newSize);
      SessionPrefs.saveTerminalFontSize(newSize);
      return;
    }
    final startGlobal = _dragStartGlobal;
    if (startGlobal == null || _activePointers.length != 1) {
      return;
    }
    final dist = (event.position - startGlobal).distance;
    if (dist < 4.0) return;
    final state = _terminalViewKey.currentState;
    if (state == null) return;
    final rt = state.renderTerminal;
    if (!_isDragSelecting) {
      _isDragSelecting = true;
      _controller.clearSelection();
    }
    final localStart = rt.globalToLocal(startGlobal);
    final localCurrent = rt.globalToLocal(event.position);
    rt.selectCharacters(localStart, localCurrent);
  }

  void _onTerminalPointerUp(PointerUpEvent event) {
    if (_scrollbarPointers.remove(event.pointer)) {
      _clickDownPosition = null;
      _dragStartGlobal = null;
      _isDragSelecting = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markUserScrollActive();
      });
      return;
    }
    _activePointers.remove(event.pointer);
    final wasDragging = _isDragSelecting;
    _isDragSelecting = false;
    _dragStartGlobal = null;
    final down = _clickDownPosition;
    _clickDownPosition = null;
    if (wasDragging) {
      return;
    }
    if (down == null) return;
    if ((event.localPosition - down).distance > 6.0) return;
    if (_openXtermUrlAt(event.position)) return;
    if (_controller.selection != null) {
      _controller.clearSelection();
      return;
    }
  }

  void _onTerminalPointerCancel(PointerCancelEvent event) {
    _scrollbarPointers.remove(event.pointer);
    _activePointers.remove(event.pointer);
    _isDragSelecting = false;
    _dragStartGlobal = null;
  }

  Widget _buildTerminalView(AppColorScheme colors) {
    return TerminalView(
      widget.session.terminal,
      key: _terminalViewKey,
      controller: _controller,
      focusNode: _focusNode,
      autofocus: widget.isActive,
      hardwareKeyboardOnly: _hardwareKeyboardOnly,
      scrollController: _scrollController,
      simulateScroll: false,
      onKeyEvent: _onTerminalKeyEvent,
      textStyle: TerminalStyle(
        fontSize: _fontSize,
        height: 1.2,
      ),
      theme: TerminalTheme(
        cursor: colors.primary,
        selection: colors.primary.withAlpha(120),
        foreground: colors.terminalText,
        background: colors.terminalBackground,
        black: colors.surface,
        red: colors.accentRed,
        green: colors.accentGreen,
        yellow: colors.accentOrange,
        blue: colors.accentBlue,
        magenta: colors.primary,
        cyan: colors.terminalPrompt,
        white: colors.terminalText,
        brightBlack: colors.textMuted,
        brightRed: colors.accentRedDim,
        brightGreen: colors.accentGreenDim,
        brightYellow: colors.statusWarning,
        brightBlue: colors.accentBlue,
        brightMagenta: colors.primaryLight,
        brightCyan: colors.accentBlue,
        brightWhite: colors.textPrimary,
        searchHitBackground: colors.accentOrange,
        searchHitBackgroundCurrent: colors.statusWarning,
        searchHitForeground: colors.background,
      ),
      padding: const EdgeInsets.all(8),
    );
  }

  Widget _wrapTerminal(AppColorScheme colors, Widget child) {
    return _CanvasGestureAbsorbPointer(
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: _TerminalScrollChrome(
          controller: _scrollController,
          colors: colors,
          child: child,
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppColorScheme colors) {
    final hitCount = _searchHits.length;
    final hitLabel = hitCount == 0 ? 'No results' : '${_currentHitIndex + 1} of $hitCount';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.textMuted.withAlpha(80)),
          boxShadow: [
            BoxShadow(
              color: colors.background.withAlpha(80),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(skipTraversal: true),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _closeSearch();
                  }
                },
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Find in terminal…',
                    hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: _performSearch,
                  onSubmitted: (_) => _nextHit(),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty) ...[
              Caption(hitLabel),
              const SizedBox(width: 4),
              _searchIconBtn(Icons.keyboard_arrow_up, _prevHit),
              _searchIconBtn(Icons.keyboard_arrow_down, _nextHit),
            ],
            _searchIconBtn(Icons.close, _closeSearch),
          ],
        ),
      ),
    );
  }

  Widget _searchIconBtn(IconData icon, VoidCallback onTap) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: colors.textSecondary),
      ),
    );
  }
}

class _AddSessionButton extends StatefulWidget {
  const _AddSessionButton({required this.workspace});
  final Workspace workspace;

  @override
  State<_AddSessionButton> createState() => _AddSessionButtonState();
}

class _AddSessionButtonState extends State<_AddSessionButton> {
  bool _hovering = false;

  Future<void> _showDialog(BuildContext context) async {
    final worktrees = <String, List<WorktreeEntry>>{};
    for (final repoPath in widget.workspace.paths) {
      worktrees[repoPath] = await WorktreeService.instance.listWorktrees(
        repoPath,
      );
    }
    if (!context.mounted) return;
    showNewAgentSessionDialog(
      context,
      workspace: widget.workspace,
      worktrees: worktrees,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: 'New agent session',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _showDialog(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hovering ? colors.surfaceElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(
              Icons.add,
              size: 14,
              color: _hovering ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentLaunchButton extends StatelessWidget {
  const _AgentLaunchButton({
    required this.type,
    required this.workspacePath,
    required this.workspaceId,
  });

  final AgentType type;
  final String workspacePath;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: 'Start ${type.displayName} session',
      child: GestureDetector(
        onTap:
            () => context.read<TerminalCubit>().spawnSession(
              type: type,
              workspacePath: workspacePath,
              workspaceId: workspaceId,
            ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.primary.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.primary.withAlpha(80)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(type.iconLabel, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 5),
              Text(
                type.displayName,
                style: TextStyle(
                  color: colors.primaryLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TermCtxAction { selectAll, copy, paste, clearSelection, search }
