import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:kterm/kterm.dart' as kterm;
import 'package:xterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
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
                    'AI Agents',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Caption('Open a workspace and start an AI agent to begin', fontSize: 13),
                  const SizedBox(height: 24),
                  BlocBuilder<WorkspaceCubit, WorkspaceState>(
                    builder: (context, wsState) {
                      final hasActive =
                          wsState is WorkspaceLoaded &&
                          wsState.activeWorkspace != null;
                      if (!hasActive) {
                        return Text(
                          'Select a workspace from the left panel first',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        );
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children:
                              AgentType.values.map((type) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: _AgentLaunchButton(
                                    type: type,
                                    workspacePath:
                                        wsState.activeWorkspace!.workspaceDir,
                                    workspaceId: wsState.activeWorkspace!.id,
                                  ),
                                );
                              }).toList(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                      children:
                          sessions.asMap().entries.map((e) {
                            return Offstage(
                              offstage: e.key != activeIndex,
                              child: RepaintBoundary(
                                child: TerminalWidget(
                                  key: ValueKey(e.value.id),
                                  session: e.value,
                                  isActive: e.key == activeIndex,
                                ),
                              ),
                            );
                          }).toList(),
                    ),
          ),
          _WorkspaceStatusBar(session: activeSession),
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
                  child: Opacity(
                    opacity: _hovering || widget.isActive ? 1.0 : 0.0,
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
  final _kController = kterm.TerminalController(
    pointerInputs: const kterm.PointerInputs.none(),
  );
  final _focusNode = FocusNode();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  final _kTerminalViewKey = GlobalKey<kterm.TerminalViewState>();
  Timer? _focusRetryTimer;
  double _fontSize = 13.0;
  Size _terminalSize = Size.zero;
  _TerminalScrollAnchor? _resizeScrollAnchor;
  _TerminalScrollAnchor? _userScrollAnchor;
  Timer? _userScrollAnchorTimer;
  Timer? _userScrollPreserveTimer;
  Offset? _clickDownPosition;

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

  bool _isTerminalScrollbarHit(Offset localPosition) {
    if (_terminalSize == Size.zero) return false;
    const scrollbarHitWidth = 24.0;
    return localPosition.dx >= _terminalSize.width - scrollbarHitWidth;
  }

  final _scrollController = ScrollController();

  // Identity-checked callbacks stored as fields so we can null them safely in
  // dispose without clobbering another TerminalWidget that rebound the same
  // shared `session.terminal` (e.g. panel + mindmap viewing same session).
  void Function(String)? _boundOnOutput;
  void Function(int, int, int, int)? _boundOnResize;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {});
    _bindTerminal();
    AgentConfigService.instance.terminalRenderEngineNotifier.addListener(
      _rebindTerminalForActiveEngine,
    );
    if (widget.autoRequestFocus) _requestFocusAfterFrame();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    // Load persisted font size
    SessionPrefs.load().then((snap) {
      if (mounted) setState(() => _fontSize = snap.terminalFontSize);
    });
  }

  @override
  void didUpdateWidget(TerminalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _unbindTerminalIfOurs(oldWidget.session);
      HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
      _bindTerminal();
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    }
    // Request focus when this session becomes active (IndexedStack shows it).
    if (!oldWidget.isActive && widget.isActive && widget.autoRequestFocus) {
      _requestFocusAfterFrame();
    }
  }

  void _rebindTerminalForActiveEngine() {
    _bindTerminal();
    if (mounted) setState(() {});
  }

  void _requestFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
    // Retry after dialog dismiss animation (e.g. NewAgentSessionDialog pop).
    _focusRetryTimer?.cancel();
    _focusRetryTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && widget.isActive && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
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
      TerminalBackendService.instance.resize(widget.session.id, cols, rows);
      _restoreResizeScrollAnchor();
    };
    switch (AgentConfigService.instance.terminalRenderEngine) {
      case TerminalRenderEngine.kterm:
        widget.session.kTerminal.onOutput = _boundOnOutput;
        widget.session.kTerminal.onResize = _boundOnResize;
      case TerminalRenderEngine.xterm:
        widget.session.terminal.onOutput = _boundOnOutput;
        widget.session.terminal.onResize = _boundOnResize;
    }
  }

  void _unbindTerminalIfOurs(AgentSession session) {
    // Only clear if the bound callback is still ours — otherwise another
    // TerminalWidget (e.g. panel vs mindmap) has since rebound and we'd wipe
    // its binding.
    if (identical(session.terminal.onOutput, _boundOnOutput)) {
      session.terminal.onOutput = null;
    } else {}
    if (identical(session.terminal.onResize, _boundOnResize)) {
      session.terminal.onResize = null;
    }
    if (identical(session.kTerminal.onOutput, _boundOnOutput)) {
      session.kTerminal.onOutput = null;
    }
    if (identical(session.kTerminal.onResize, _boundOnResize)) {
      session.kTerminal.onResize = null;
    }
  }

  /// Intercepts macOS keyboard shortcuts and translates them to PTY control
  /// sequences before [TerminalView] can process the raw key event.
  ///
  /// Mapping (readline / bash compatible):
  ///   Cmd+V              → paste as file reference (existing behaviour)
  ///   Cmd+Backspace      → Ctrl+U  (\x15) — erase to start of line
  ///   Opt+Backspace      → Ctrl+W  (\x17) — erase word backward
  ///   Ctrl+Backspace     → Ctrl+W  (\x17) — erase word backward (PC style)
  ///   Cmd+←             → Ctrl+A  (\x01) — beginning of line
  ///   Cmd+→             → Ctrl+E  (\x05) — end of line
  /// xterm onKeyEvent — intercepts Shift+Enter to send the Kitty keyboard
  /// protocol escape sequence (\x1b[13;2u) so modern CLIs (Copilot, Claude
  /// Code) treat it as a newline in the input buffer instead of submitting.
  KeyEventResult _onTerminalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      _writePty('\x03');
      return KeyEventResult.handled;
    }
    // Shift+Enter → ESC+CR (newline-in-input for Copilot/Claude Code)
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      _writePty('\x1b\r');
      return KeyEventResult.handled;
    }
    // Plain Enter while awaiting approval → immediately signal ThinkingPhase.
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        widget.session.hookPhase is AwaitingApprovalPhase) {
      context.read<TerminalCubit>().onTerminalEnterPressed(widget.session.id);
    }
    // Cmd+V — already handled by _handleHardwareKey; block xterm's native
    // paste so text isn't inserted twice.
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  ///   Opt+←             → ESC+b   (\x1bb) — word backward
  ///   Opt+→             → ESC+f   (\x1bf) — word forward
  ///   Cmd+K             → Ctrl+L  (\x0c) — clear screen
  bool _handleHardwareKey(KeyEvent event) {
    if (!_focusNode.hasFocus) return false;
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Ctrl+C → SIGINT. Handle explicitly so Flutter focus/copy shortcuts cannot
    // swallow it before the terminal backend sees ETX.
    if (isCtrl && !isCmd && !isAlt && key == LogicalKeyboardKey.keyC) {
      _writePty('\x03');
      return true;
    }

    // Cmd+V → paste as file ref (no raw paste)
    if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.keyV) {
      _pasteAsFileRef();
      return true;
    }

    // Cmd+Backspace → erase to start of line (Ctrl+U)
    if (isCmd && key == LogicalKeyboardKey.backspace) {
      _writePty('\x15');
      return true;
    }

    // Option+Backspace or Ctrl+Backspace → erase word backward (Ctrl+W)
    if ((isAlt || isCtrl) && key == LogicalKeyboardKey.backspace) {
      _writePty('\x17');
      return true;
    }

    // Cmd+Left → beginning of line (Ctrl+A)
    if (isCmd && key == LogicalKeyboardKey.arrowLeft) {
      _writePty('\x01');
      return true;
    }

    // Cmd+Right → end of line (Ctrl+E)
    if (isCmd && key == LogicalKeyboardKey.arrowRight) {
      _writePty('\x05');
      return true;
    }

    // Option+Left → word backward (ESC b)
    if (isAlt && key == LogicalKeyboardKey.arrowLeft) {
      _writePty('\x1bb');
      return true;
    }

    // Option+Right → word forward (ESC f)
    if (isAlt && key == LogicalKeyboardKey.arrowRight) {
      _writePty('\x1bf');
      return true;
    }

    // Cmd+K → clear screen (Ctrl+L)
    if (isCmd && key == LogicalKeyboardKey.keyK) {
      _writePty('\x0c');
      return true;
    }

    // Cmd+F → open search
    if (isCmd && key == LogicalKeyboardKey.keyF) {
      _openSearch();
      return true;
    }

    // Cmd+= → increase font size
    if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.equal) {
      setState(() => _fontSize = (_fontSize + 1).clamp(8.0, 32.0));
      return true;
    }

    // Cmd+- → decrease font size
    if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.minus) {
      setState(() => _fontSize = (_fontSize - 1).clamp(8.0, 32.0));
      return true;
    }

    // Cmd+A → select all terminal buffer content
    if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.keyA) {
      _selectAll();
      return true;
    }

    // Cmd+C → copy selection if one exists; otherwise let xterm send ^C
    if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.keyC) {
      final selection = _controller.selection;
      if (selection != null) {
        final text = widget.session.terminal.buffer.getText(selection);
        Clipboard.setData(ClipboardData(text: text));
        return true;
      }
      // No selection — fall through so xterm sends ^C (SIGINT)
    }

    return false;
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
        'size=${_terminalSize.width.toStringAsFixed(1)}x'
        '${_terminalSize.height.toStringAsFixed(1)} $scroll';
  }

  void setFontSize(double size) {
    if (mounted) setState(() => _fontSize = size.clamp(8.0, 32.0));
  }

  Future<void> _pasteAsFileRef() async {
    final pasted =
        await SmartClipboardPasteService.instance
            .readInlineTextOrSavedFilePath();
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
          await Clipboard.setData(ClipboardData(text: text));
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
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    AgentConfigService.instance.terminalRenderEngineNotifier.removeListener(
      _rebindTerminalForActiveEngine,
    );
    _unbindTerminalIfOurs(widget.session);
    _controller.dispose();
    _kController.dispose();
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
    if (mounted) _focusNode.requestFocus();
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

    final cellW = (_terminalSize.width - 16) / terminal.viewWidth;
    final cellH = (_terminalSize.height - 16) / terminal.viewHeight;
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
      'size=${_terminalSize.width.toStringAsFixed(1)}x'
      '${_terminalSize.height.toStringAsFixed(1)} $metrics',
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
    void restore() {
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
    }

    scheduleMicrotask(restore);
    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => restore());
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

  bool _openKtermUrlAt(Offset globalPosition) {
    final state = _kTerminalViewKey.currentState;
    if (state == null) return false;
    final renderTerminal = state.renderTerminal;
    final cell = renderTerminal.getCellOffset(
      renderTerminal.globalToLocal(globalPosition),
    );
    if (cell.y < 0 || cell.y >= widget.session.kTerminal.buffer.lines.length) {
      return false;
    }
    final bufferLines = widget.session.kTerminal.buffer.lines;
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
    return ValueListenableBuilder<TerminalRenderEngine>(
      valueListenable: AgentConfigService.instance.terminalRenderEngineNotifier,
      builder: (context, engine, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
            if (_terminalSize != Size.zero && _terminalSize != nextSize) {
              _captureResizeScrollAnchor();
              _terminalSize = nextSize;
              _restoreResizeScrollAnchor();
            } else {
              _terminalSize = nextSize;
            }
            if (engine == TerminalRenderEngine.kterm) {
              return _buildKtermTerminal(colors);
            }
            return Stack(
              children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (event) {
                    if (CanvasInteractionLock.instance.isCanvasGestureActive) {
                      _preserveScrollForCanvasGesture();
                      return;
                    }
                    if (event is PointerScrollEvent) {
                      if (_isHorizontalTrackpadGesture(event.scrollDelta)) {
                        CanvasInteractionLock.instance
                            .markCanvasSignalGesture();
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
                  },
                  onPointerPanZoomStart: (_) {
                    if (CanvasInteractionLock.instance.isCanvasGestureActive) {
                      _preserveScrollForCanvasGesture();
                      return;
                    }
                  },
                  onPointerPanZoomUpdate: (event) {
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
                  },
                  onPointerDown: (event) {
                    if (!_focusNode.hasFocus) _focusNode.requestFocus();
                    if (_isTerminalScrollbarHit(event.localPosition)) {
                      _scrollbarPointers.add(event.pointer);
                      _clickDownPosition = null;
                      _dragStartGlobal = null;
                      _isDragSelecting = false;
                      _activePointers.remove(event.pointer);
                      return;
                    }
                    // Right-click → context menu
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
                      _pinchStartDistance =
                          (positions[0] - positions[1]).distance;
                      _pinchStartFontSize = _fontSize;
                    }
                  },
                  onPointerMove: (event) {
                    if (_scrollbarPointers.contains(event.pointer)) {
                      _markUserScrollActive();
                      return;
                    }
                    _activePointers[event.pointer] = event.localPosition;
                    if (_activePointers.length == 2 &&
                        _pinchStartDistance > 0 &&
                        event.kind == PointerDeviceKind.touch) {
                      final positions = _activePointers.values.toList();
                      final dist = (positions[0] - positions[1]).distance;
                      final newSize = (_pinchStartFontSize *
                              dist /
                              _pinchStartDistance)
                          .clamp(8.0, 48.0);
                      setState(() => _fontSize = newSize);
                      SessionPrefs.saveTerminalFontSize(newSize);
                      return;
                    }
                    // Drag-to-select: bypass xterm's gesture arena entirely.
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
                  },
                  onPointerUp: (event) {
                    if (_scrollbarPointers.remove(event.pointer)) {
                      _clickDownPosition = null;
                      _dragStartGlobal = null;
                      _isDragSelecting = false;
                      return;
                    }
                    _activePointers.remove(event.pointer);
                    final wasDragging = _isDragSelecting;
                    _isDragSelecting = false;
                    _dragStartGlobal = null;
                    final down = _clickDownPosition;
                    _clickDownPosition = null;
                    if (wasDragging) {
                      return; // keep selection
                    }
                    if (down == null) return;
                    if ((event.localPosition - down).distance > 6.0) return;
                    if (_openXtermUrlAt(event.position)) return;
                    // Single tap clears any existing selection
                    if (_controller.selection != null) {
                      _controller.clearSelection();
                      return;
                    }
                  },
                  onPointerCancel: (event) {
                    _scrollbarPointers.remove(event.pointer);
                    _activePointers.remove(event.pointer);
                    _isDragSelecting = false;
                    _dragStartGlobal = null;
                  },
                  child: _CanvasGestureAbsorbPointer(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: _TerminalScrollChrome(
                        controller: _scrollController,
                        colors: colors,
                        child: TerminalView(
                          widget.session.terminal,
                          key: _terminalViewKey,
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: widget.isActive,
                          scrollController: _scrollController,
                          // Keep trackpad scroll for terminal scrollback instead of
                          // turning it into up/down key presses in the shell.
                          simulateScroll: false,
                          onKeyEvent: _onTerminalKeyEvent,
                          textStyle: TerminalStyle(
                            fontSize: _fontSize,
                            fontFamily: 'JetBrainsMono',
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
                        ),
                      ),
                    ),
                  ),
                ),
                // Search overlay
                if (_isSearching)
                  Positioned(top: 8, right: 8, child: _buildSearchBar(colors)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildKtermTerminal(AppColorScheme colors) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (!_focusNode.hasFocus) _focusNode.requestFocus();
        if (event.buttons != kPrimaryButton) return;
        _clickDownPosition = event.localPosition;
      },
      onPointerUp: (event) {
        final down = _clickDownPosition;
        _clickDownPosition = null;
        if (down == null) return;
        if ((event.localPosition - down).distance > 6.0) return;
        _openKtermUrlAt(event.position);
      },
      onPointerCancel: (_) {
        _clickDownPosition = null;
      },
      child: _CanvasGestureAbsorbPointer(
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: _TerminalScrollChrome(
            controller: _scrollController,
            colors: colors,
            child: kterm.TerminalView(
              widget.session.kTerminal,
              key: _kTerminalViewKey,
              controller: _kController,
              focusNode: _focusNode,
              autofocus: widget.isActive,
              scrollController: _scrollController,
              simulateScroll: true,
              showSearchBar: true,
              onKeyEvent: _onTerminalKeyEvent,
              textStyle: kterm.TerminalStyle(
                fontSize: _fontSize,
                fontFamily: 'JetBrainsMono',
                height: 1.2,
              ),
              theme: kterm.TerminalTheme(
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppColorScheme colors) {
    final hitCount = _searchHits.length;
    final hitLabel =
        hitCount == 0 ? 'No results' : '${_currentHitIndex + 1} of $hitCount';

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
              Caption(hitLabel,),
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

class _WorkspaceStatusBar extends StatelessWidget {
  const _WorkspaceStatusBar({this.session});
  final AgentSession? session;

  void _showColorPicker(BuildContext context, Workspace ws, Color current) {
    showDialog<void>(
      context: context,
      builder:
          (_) => _WorkspaceColorPickerDialog(
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

/// Full custom color picker dialog for a workspace.
class _WorkspaceColorPickerDialog extends StatefulWidget {
  const _WorkspaceColorPickerDialog({
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
  State<_WorkspaceColorPickerDialog> createState() =>
      _WorkspaceColorPickerDialogState();
}

class _WorkspaceColorPickerDialogState
    extends State<_WorkspaceColorPickerDialog> {
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
    final presets = [
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
      colors.accentOrange,
      colors.accentGreenDim,
      colors.accentRedDim,
      colors.primary,
      colors.accentOrange,
      colors.terminalPrompt,
      colors.primaryLight,
      colors.statusActive,
    ];
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
              // Header
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

              // Color wheel + sliders
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

              // Hex input
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
                        enabledBorder: OutlineInputBorder(
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
                  // Preview swatch
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

              // Preset swatches
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

              // Buttons
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

enum _TermCtxAction { selectAll, copy, paste, clearSelection, search }
