import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:xterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/data/clipboard_file_service.dart';
import 'package:yoloit/features/terminal/data/pty_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/features/workspaces/ui/new_agent_session_dialog.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

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
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.primary.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.terminal_outlined, size: 32, color: colors.primary),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'AI Agents',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Open a workspace and start an AI agent to begin',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  BlocBuilder<WorkspaceCubit, WorkspaceState>(
                    builder: (context, wsState) {
                      final hasActive = wsState is WorkspaceLoaded &&
                          wsState.activeWorkspace != null;
                      if (!hasActive) {
                        return const Text(
                          'Select a workspace from the left panel first',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        );
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: AgentType.values.map((type) {
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
    final activeIndex = widget.state.activeIndex.clamp(0, sessions.isEmpty ? 0 : sessions.length - 1);
    final activeSession = widget.state.activeSession;

    return Container(
      color: colors.terminalBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TerminalHeader(sessions: sessions, activeIndex: activeIndex),
          if (activeSession != null) _SessionInfoBar(session: activeSession),
          Expanded(
            child: sessions.isEmpty
                ? const SizedBox()
                : IndexedStack(
                    index: activeIndex,
                    children: sessions.asMap().entries.map((e) {
                      return RepaintBoundary(
                        child: TerminalWidget(
                          key: ValueKey(e.value.id),
                          session: e.value,
                          isActive: e.key == activeIndex,
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
        border: Border(bottom: BorderSide(color: const Color(0xFF32327A), width: 1)),
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
                  onClose: () => context.read<TerminalCubit>().closeSession(session.id),
                  onRename: (name) => context.read<TerminalCubit>().renameSession(session.id, name),
                );
              },
            ),
          ),
          // "+" button to launch a new agent session
          BlocBuilder<WorkspaceCubit, WorkspaceState>(
            builder: (context, wsState) {
              final workspace = wsState is WorkspaceLoaded ? wsState.activeWorkspace : null;
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
    if (!_editing && oldWidget.session.displayName != widget.session.displayName) {
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
    if (!_editing) return;           // guard against double-call (onSubmitted + focus lost)
    final name = _nameController.text.trim();
    setState(() => _editing = false);
    widget.onRename(name);
  }

  void _showContextMenu(BuildContext context, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'rename',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 14, color: AppColors.textMuted),
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
              Icon(Icons.close, size: 14, color: AppColors.textMuted),
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
    final statusColor =
        isLive ? AppColors.statusActive : AppColors.statusIdle;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _editing ? null : widget.onTap,
        onDoubleTap: _editing ? null : _startEditing,
        onSecondaryTapDown: _editing ? null : (d) => _showContextMenu(context, d.globalPosition),
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
                  color: widget.isActive ? colors.primaryLight : AppColors.textMuted,
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
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: colors.primary, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: colors.primary, width: 1.5),
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
                    color: widget.isActive ? colors.primaryLight : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
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
                        color: _hovering ? AppColors.textPrimary : AppColors.textMuted,
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
      padding: EdgeInsets.symmetric(horizontal: 12),
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
              style: const TextStyle(
                color: AppColors.textSecondary,
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
  });
  final AgentSession session;
  final bool isActive;
  /// When false, the terminal won't auto-request focus on creation or when
  /// becoming active. This prevents focus-fighting when multiple terminals
  /// exist (e.g. mindmap cards). Focus will still be requested on click.
  final bool autoRequestFocus;

  @override
  State<TerminalWidget> createState() => TerminalWidgetState();
}

class TerminalWidgetState extends State<TerminalWidget> {
  final _controller = TerminalController(
    pointerInputs: const PointerInputs.none(),
  );
  final _focusNode = FocusNode();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  Timer? _focusRetryTimer;
  double _fontSize = 13.0;
  Size _terminalSize = Size.zero;
  Offset? _clickDownPosition;

  // Manual drag-to-select: xterm 4.x's PanGestureRecognizer fails to win the
  // gesture arena in our widget tree, so we implement selection directly via
  // raw Listener pointer events — these always fire regardless of arena.
  bool _isDragSelecting = false;
  Offset? _dragStartGlobal;

  // Pinch-to-zoom tracked via raw pointer events (avoids gesture arena
  // conflict with xterm's internal pan recogniser used for text selection).
  final _activePointers = <int, Offset>{};
  double _pinchStartDistance = 0;
  double _pinchStartFontSize = 0;

  // Search overlay state
  bool _isSearching = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<CellOffset> _searchHits = [];
  int _currentHitIndex = -1;

  // Identity-checked callbacks stored as fields so we can null them safely in
  // dispose without clobbering another TerminalWidget that rebound the same
  // shared `session.terminal` (e.g. panel + mindmap viewing same session).
  void Function(String)? _boundOnOutput;
  void Function(int, int, int, int)? _boundOnResize;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
    });
    _bindTerminal();
    if (widget.autoRequestFocus) _requestFocusAfterFrame();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    // Load persisted font size
    SessionPrefs.load().then((snap) {
      if (mounted) setState(() => _fontSize = snap.terminalFontSize);
    });
  }

  @override
  void didUpdateWidget(TerminalWidget old) {
    super.didUpdateWidget(old);
    if (old.session.id != widget.session.id) {
      _unbindTerminalIfOurs(old.session);
      HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
      _bindTerminal();
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    }
    // Request focus when this session becomes active (IndexedStack shows it).
    if (!old.isActive && widget.isActive && widget.autoRequestFocus) {
      _requestFocusAfterFrame();
    }
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
    _boundOnOutput = (data) {
      PtyService.instance.write(widget.session.id, data);
    };
    _boundOnResize = (cols, rows, pixelWidth, pixelHeight) {
      PtyService.instance.resize(widget.session.id, cols, rows);
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
    } else {
    }
    if (identical(session.terminal.onResize, _boundOnResize)) {
      session.terminal.onResize = null;
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
      terminal.buffer.createAnchor(0, terminal.buffer.height - terminal.viewHeight),
      terminal.buffer.createAnchor(terminal.viewWidth, terminal.buffer.height - 1),
      mode: SelectionMode.line,
    );
  }

  void _writePty(String sequence) {
    PtyService.instance.write(widget.session.id, sequence);
  }

  /// Click-to-move cursor: when the user single-clicks on the prompt row
  /// (not in alternate buffer / vim / etc.), send arrow keys to move the
  /// cursor to the clicked column. Same behavior as Superset desktop app.
  void _handleTerminalClick(Offset localPosition) {
    final terminal = widget.session.terminal;
    // Don't interfere with vim/less/etc. (alternate screen)
    if (terminal.isUsingAltBuffer) return;
    // Don't interfere with active text selection
    if (_controller.selection != null) return;

    const padding = 8.0;
    final innerWidth = _terminalSize.width - padding * 2;
    final innerHeight = _terminalSize.height - padding * 2;
    if (innerWidth <= 0 || innerHeight <= 0) return;

    final cellWidth = innerWidth / terminal.viewWidth;
    final cellHeight = innerHeight / terminal.viewHeight;

    final clickCol = ((localPosition.dx - padding) / cellWidth)
        .floor()
        .clamp(0, terminal.viewWidth - 1);
    final clickRow = ((localPosition.dy - padding) / cellHeight)
        .floor()
        .clamp(0, terminal.viewHeight - 1);

    // Only move when click is on the same row as the cursor
    if (clickRow != terminal.buffer.cursorY) return;

    final delta = clickCol - terminal.buffer.cursorX;
    if (delta == 0) return;

    // Right arrow: \x1b[C  Left arrow: \x1b[D
    final arrow = delta > 0 ? '\x1b[C' : '\x1b[D';
    _writePty(arrow * delta.abs());
  }

  Future<void> _pasteAsFileRef() async {
    // Read clipboard text first to decide how to paste.
    final clipboard = SystemClipboard.instance;
    if (clipboard != null) {
      final reader = await clipboard.read();
      if (reader.canProvide(Formats.plainText)) {
        final text = await reader.readValue(Formats.plainText);
        if (text != null && text.isNotEmpty && text.trim().split(RegExp(r'\s+')).length <= 1000) {
          // Short text — paste directly as plain text.
          if (!mounted) return;
          PtyService.instance.write(widget.session.id, text);
          return;
        }
      }
    }

    // Long text or image — save to file and paste the path.
    final path = await ClipboardFileService.instance.saveClipboardToFile();
    if (path == null || !mounted) return;
    PtyService.instance.write(widget.session.id, path);
  }

  // ── Selection helpers ───────────────────────────────────────────────


  /// Shows a right-click context menu with Copy (if selection) and Paste.
  Future<void> _showTerminalContextMenu(BuildContext context, Offset globalPos) async {
    final selection = _controller.selection;
    final hasSelection = selection != null;

    final items = <PopupMenuEntry<_TermCtxAction>>[
      const PopupMenuItem(
        value: _TermCtxAction.selectAll,
        height: 36,
        child: Row(children: [
          Icon(Icons.select_all, size: 14, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Text('Select All', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
        ]),
      ),
      if (hasSelection)
        const PopupMenuItem(
          value: _TermCtxAction.copy,
          height: 36,
          child: Row(children: [
            Icon(Icons.copy, size: 14, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text('Copy', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ]),
        ),
      const PopupMenuItem(
        value: _TermCtxAction.paste,
        height: 36,
        child: Row(children: [
          Icon(Icons.content_paste, size: 14, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Text('Paste', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
        ]),
      ),
      if (hasSelection) ...[
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: _TermCtxAction.clearSelection,
          height: 36,
          child: Row(children: [
            Icon(Icons.clear, size: 14, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text('Clear selection', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ]),
        ),
      ],
      const PopupMenuDivider(height: 1),
      const PopupMenuItem(
        value: _TermCtxAction.search,
        height: 36,
        child: Row(children: [
          Icon(Icons.search, size: 14, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Text('Find', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
        ]),
      ),
    ];

    final action = await showMenu<_TermCtxAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      items: items,
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.textMuted.withAlpha(60)),
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
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _unbindTerminalIfOurs(widget.session);
    _controller.dispose();
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
    _focusNode.requestFocus();
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
    final startOffset = Offset(hit.x * cellW + 8, visRow * cellH + cellH / 2 + 8);
    final endOffset = Offset((hit.x + queryLen) * cellW + 8, visRow * cellH + cellH / 2 + 8);
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        _terminalSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (!_focusNode.hasFocus) _focusNode.requestFocus();
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
            if (_activePointers.length == 2) {
              final positions = _activePointers.values.toList();
              _pinchStartDistance = (positions[0] - positions[1]).distance;
              _pinchStartFontSize = _fontSize;
            }
          },
          onPointerMove: (event) {
            _activePointers[event.pointer] = event.localPosition;
            if (_activePointers.length == 2 && _pinchStartDistance > 0) {
              final positions = _activePointers.values.toList();
              final dist = (positions[0] - positions[1]).distance;
              final newSize = (_pinchStartFontSize * dist / _pinchStartDistance)
                  .clamp(8.0, 48.0);
              setState(() => _fontSize = newSize);
              SessionPrefs.saveTerminalFontSize(newSize);
              return;
            }
            // Drag-to-select: bypass xterm's gesture arena entirely.
            final startGlobal = _dragStartGlobal;
            if (startGlobal == null || _activePointers.length != 1) return;
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
            // Single tap clears any existing selection
            if (_controller.selection != null) {
              _controller.clearSelection();
              return;
            }
            _handleTerminalClick(event.localPosition);
          },
          onPointerCancel: (event) {
            _activePointers.remove(event.pointer);
            _isDragSelecting = false;
            _dragStartGlobal = null;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: TerminalView(
              widget.session.terminal,
              key: _terminalViewKey,
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.isActive,
              onKeyEvent: _onTerminalKeyEvent,
              textStyle: TerminalStyle(
                fontSize: _fontSize,
                fontFamily: 'JetBrainsMono',
                height: 1.2,
              ),
              theme: TerminalTheme(
                cursor: colors.primary,
                selection: colors.primary.withAlpha(120),
                foreground: const Color(0xFFCECEEE),
                background: const Color(0xFF070714),
                black: const Color(0xFF1A1A2E),
                red: const Color(0xFFFF4F6A),
                green: const Color(0xFF00FF9F),
                yellow: const Color(0xFFFFD700),
                blue: const Color(0xFF00B4FF),
                magenta: const Color(0xFFB87FFF),
                cyan: const Color(0xFF00E5FF),
                white: const Color(0xFFCECEEE),
                brightBlack: const Color(0xFF44446A),
                brightRed: const Color(0xFFFF6B85),
                brightGreen: const Color(0xFF4DFFBE),
                brightYellow: const Color(0xFFFFE866),
                brightBlue: const Color(0xFF33C5FF),
                brightMagenta: const Color(0xFFCDA0FF),
                brightCyan: const Color(0xFF33EEFF),
                brightWhite: const Color(0xFFFFFFFF),
                searchHitBackground: const Color(0xFFFF9500),
                searchHitBackgroundCurrent: const Color(0xFFFFB700),
                searchHitForeground: const Color(0xFF000000),
              ),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ),
            // Search overlay
            if (_isSearching)
              Positioned(
                top: 8,
                right: 8,
                child: _buildSearchBar(colors),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar(dynamic colors) {
    final hitCount = _searchHits.length;
    final hitLabel = hitCount == 0
        ? 'No results'
        : '${_currentHitIndex + 1} of $hitCount';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.textMuted.withAlpha(80)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
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
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Find in terminal…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: InputBorder.none,
                ),
                onChanged: _performSearch,
                onSubmitted: (_) => _nextHit(),
              ),
              ),
            ),
            if (_searchController.text.isNotEmpty) ...[
              Text(
                hitLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
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
      worktrees[repoPath] =
          await WorktreeService.instance.listWorktrees(repoPath);
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
              color: _hovering ? AppColors.textPrimary : AppColors.textMuted,
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
        onTap: () => context.read<TerminalCubit>().spawnSession(
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
      builder: (_) => _WorkspaceColorPickerDialog(
        workspace: ws,
        initial: ws.color ?? current,
        onSave: (c) => context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, c),
        onReset: () => context.read<WorkspaceCubit>().setWorkspaceColor(ws.id, null),
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
            onTap: ws != null ? () => _showColorPicker(context, ws, accentColor) : null,
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
                          const Icon(Icons.alt_route, size: 10, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              ws!.gitBranch!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.palette_outlined, size: 10, color: accentColor.withAlpha(120)),
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

  static const _presets = [
    Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF059669),
    Color(0xFFD97706), Color(0xFFDC2626), Color(0xFF0891B2),
    Color(0xFFDB2777), Color(0xFF65A30D), Color(0xFF9333EA),
    Color(0xFFEA580C), Color(0xFF0D9488), Color(0xFF4F46E5),
    Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFFEF4444),
    Color(0xFF6366F1), Color(0xFFF97316), Color(0xFF14B8A6),
    Color(0xFFEC4899), Color(0xFF84CC16),
  ];

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
      '${c.b.toInt().toRadixString(16).padLeft(2, '0')}'.toUpperCase();

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
    return Dialog(
      backgroundColor: const Color(0xFF0F0F2A),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
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
                  const Text(
                    'HEX',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _hexCtrl,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF1A1A3E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _current.withAlpha(80)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _current.withAlpha(80)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              const Text(
                'PRESETS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _presets.map((c) {
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
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: c.withAlpha(180), blurRadius: 6)]
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
                      foregroundColor: AppColors.textMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.onSave(_current);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _current,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
