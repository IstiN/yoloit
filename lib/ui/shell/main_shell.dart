import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yoloit/core/hotkeys/hotkey_registry.dart';
import 'package:yoloit/core/hotkeys/hotkeys.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/ui/board_view.dart';
import 'package:yoloit/features/mindmap/mindmap_view.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/editor/ui/file_editor_panel.dart';
import 'package:yoloit/features/search/ui/file_search_overlay.dart';
import 'package:yoloit/features/settings/ui/settings_page.dart';
import 'package:yoloit/features/settings/ui/setup_guide_page.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/ui/review_panel.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/ui/workspace_panel.dart';
import 'package:yoloit/features/updates/data/update_service.dart';
import 'package:yoloit/features/updates/ui/update_banner.dart';
import 'package:yoloit/ui/widgets/activity_rail.dart';
import 'package:yoloit/ui/widgets/panel_shell.dart';
import 'package:yoloit/ui/widgets/panel_visibility.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

enum _CanvasMode { panes, mindMap, board }

class _MainShellState extends State<MainShell> with WindowListener {
  final _workspacePanelKey = GlobalKey<WorkspacePanelState>();
  final _terminalFocusNode = FocusNode();
  PanelVisibility _workspaceVis = PanelVisibility.open;
  PanelVisibility _agentsVis = PanelVisibility.open;
  PanelVisibility _fileTreeVis = PanelVisibility.open;
  SessionSnapshot? _sessionSnapshot;
  _CanvasMode _canvasMode = _CanvasMode.panes;

  // ── Silent auto-update state ───────────────────────────────────────────────
  UpdateInfo? _updateInfo;
  AutoUpdatePhase? _updatePhase; // null = no banner
  double? _updateProgress;
  String _updateStatus = '';
  String? _updateLaunchToken;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadSessionAndInit();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _terminalFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSessionAndInit() async {
    final snap = await SessionPrefs.load();
    if (!mounted) return;
    setState(() {
      _workspaceVis = snap.workspaceVis;
      _agentsVis = snap.agentsVis;
      _fileTreeVis = snap.fileTreeVis;
      _sessionSnapshot = snap;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize terminal services (no sessions yet — workspace listener will load them)
      context.read<TerminalCubit>().initialize();
      context.read<BoardCubit?>()?.load();
      // Load workspaces — BlocListener in _BottomPanel will pick up active workspace
      context.read<WorkspaceCubit>().load();
      // NOTE: do NOT requestFocus on _terminalFocusNode here — TerminalWidget
      // auto-focuses its own xterm FocusNode via autofocus + _requestFocusAfterFrame.
      // Calling requestFocus on the panel node would steal focus from xterm,
      // breaking keyboard input in the terminal.
      // Show setup wizard on first launch
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) SetupGuidePage.showIfFirstLaunch(context);
      });
      // Auto-check for updates (once per day max)
      Future.delayed(const Duration(seconds: 3), _autoCheckForUpdate);
    });
  }

  Future<void> _autoCheckForUpdate() async {
    if (!mounted) return;
    if (UpdateService.isDevBuild) return;

    final autoEnabled = await SessionPrefs.isAutoUpdateCheckEnabled();
    if (!autoEnabled) return;

    // Throttle: at most once per 24 hours
    final lastMs = await SessionPrefs.getLastUpdateCheckMs();
    if (lastMs != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
      if (elapsed < const Duration(hours: 24).inMilliseconds) return;
    }

    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;

    // ── Found an update — start silent download immediately ──────────────────
    setState(() {
      _updateInfo = info;
      _updatePhase = AutoUpdatePhase.downloading;
      _updateProgress = null;
      _updateStatus = '';
    });

    try {
      final token = await UpdateService.downloadAndPrepare(
        info,
        onProgress: (progress, status) {
          if (!mounted) return;
          setState(() {
            _updateProgress = progress;
            _updateStatus = status;
            _updatePhase =
                progress == null
                    ? AutoUpdatePhase.installing
                    : AutoUpdatePhase.downloading;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _updateLaunchToken = token;
        _updatePhase = AutoUpdatePhase.ready;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _updateStatus = e.toString().replaceFirst('Exception: ', '');
          _updatePhase = AutoUpdatePhase.error;
        });
      }
    }
  }

  void _openFileSearch() {
    showFileSearch(
      context,
      onFileOpened: () {
        if (_fileTreeVis == PanelVisibility.closed) {
          _setPanelVis('filetree', PanelVisibility.open);
        }
      },
    );
  }

  void _setPanelVis(String panelId, PanelVisibility v) {
    setState(() {
      switch (panelId) {
        case 'workspace':
          _workspaceVis = v;
        case 'agents':
          _agentsVis = v;
        case 'filetree':
          _fileTreeVis = v;
      }
    });
    SessionPrefs.savePanelVis(panelId, v);
  }

  void _previousTab() {
    final cubit = context.read<TerminalCubit>();
    final state = cubit.state;
    if (state is TerminalLoaded && state.sessions.isNotEmpty) {
      final prev =
          (state.activeIndex - 1 + state.sessions.length) %
          state.sessions.length;
      cubit.switchTab(prev);
    }
  }

  void _nextTab() {
    final cubit = context.read<TerminalCubit>();
    final state = cubit.state;
    if (state is TerminalLoaded && state.sessions.isNotEmpty) {
      final next = (state.activeIndex + 1) % state.sessions.length;
      cubit.switchTab(next);
    }
  }

  void _closeTab() {
    final cubit = context.read<TerminalCubit>();
    final state = cubit.state;
    if (state is TerminalLoaded && state.sessions.isNotEmpty) {
      final session = state.sessions[state.activeIndex];
      cubit.closeSession(session.id);
    }
  }

  void _toggleCanvasMode(_CanvasMode targetMode) {
    setState(() {
      _canvasMode = _canvasMode == targetMode ? _CanvasMode.panes : targetMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListenableBuilder(
      listenable: HotkeyRegistry.instance,
      builder:
          (context, _) => Shortcuts(
            shortcuts: HotkeyRegistry.instance.shortcuts,
            child: Actions(
              actions: {
                PreviousAgentTabIntent: CallbackAction<PreviousAgentTabIntent>(
                  onInvoke: (_) => _previousTab(),
                ),
                NextAgentTabIntent: CallbackAction<NextAgentTabIntent>(
                  onInvoke: (_) => _nextTab(),
                ),
                CloseTerminalTabIntent: CallbackAction<CloseTerminalTabIntent>(
                  onInvoke: (_) => _closeTab(),
                ),
                ToggleWorkspacePanelIntent:
                    CallbackAction<ToggleWorkspacePanelIntent>(
                      onInvoke: (_) {
                        final next =
                            _workspaceVis == PanelVisibility.open
                                ? PanelVisibility.closed
                                : PanelVisibility.open;
                        _setPanelVis('workspace', next);
                        return null;
                      },
                    ),
                ToggleTerminalPanelIntent:
                    CallbackAction<ToggleTerminalPanelIntent>(
                      onInvoke: (_) {
                        final next =
                            _agentsVis == PanelVisibility.open
                                ? PanelVisibility.closed
                                : PanelVisibility.open;
                        _setPanelVis('agents', next);
                        return null;
                      },
                    ),
                ToggleReviewPanelIntent:
                    CallbackAction<ToggleReviewPanelIntent>(
                      onInvoke: (_) {
                        final next =
                            _fileTreeVis == PanelVisibility.open
                                ? PanelVisibility.closed
                                : PanelVisibility.open;
                        _setPanelVis('filetree', next);
                        return null;
                      },
                    ),
                FocusTerminalIntent: CallbackAction<FocusTerminalIntent>(
                  onInvoke: (_) {
                    // Focus the panel scope then immediately descend to the xterm widget
                    // so Cmd+` brings keyboard focus to the actual terminal, not just its container.
                    _terminalFocusNode.requestFocus();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final scope = FocusScope.of(context);
                      if (scope.focusedChild == _terminalFocusNode ||
                          _terminalFocusNode.hasFocus) {
                        FocusTraversalGroup.maybeOf(
                          context,
                        )?.next(_terminalFocusNode);
                      }
                    });
                    return null;
                  },
                ),
                OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
                  onInvoke: (_) => SettingsPage.show(context),
                ),
                OpenFileSearchIntent: CallbackAction<OpenFileSearchIntent>(
                  onInvoke: (_) => _openFileSearch(),
                ),
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  backgroundColor: colors.background,
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleBar(
                        onSettings: () => SettingsPage.show(context),
                        workspaceVis: _workspaceVis,
                        agentsVis: _agentsVis,
                        fileTreeVis: _fileTreeVis,
                        canvasMode: _canvasMode,
                        onToggleWorkspace: () {
                          final next =
                              _workspaceVis == PanelVisibility.open
                                  ? PanelVisibility.closed
                                  : PanelVisibility.open;
                          _setPanelVis('workspace', next);
                        },
                        onToggleAgents: () {
                          final next =
                              _agentsVis == PanelVisibility.open
                                  ? PanelVisibility.closed
                                  : PanelVisibility.open;
                          _setPanelVis('agents', next);
                        },
                        onToggleFileTree: () {
                          final next =
                              _fileTreeVis == PanelVisibility.open
                                  ? PanelVisibility.closed
                                  : PanelVisibility.open;
                          _setPanelVis('filetree', next);
                        },
                        onToggleMapView:
                            () => _toggleCanvasMode(_CanvasMode.mindMap),
                        onToggleBoardView:
                            () => _toggleCanvasMode(_CanvasMode.board),
                        onSearch: _openFileSearch,
                      ),
                      if (_updatePhase != null && _updateInfo != null)
                        AutoUpdateBanner(
                          info: _updateInfo!,
                          phase: _updatePhase!,
                          progress: _updateProgress,
                          status: _updateStatus,
                          launchToken: _updateLaunchToken,
                          onDismiss: () {
                            if (mounted) setState(() => _updatePhase = null);
                          },
                        ),
                      Expanded(
                        child:
                            _canvasMode == _CanvasMode.mindMap
                                ? const MindMapView()
                                : _canvasMode == _CanvasMode.board
                                ? const BoardView()
                                : _FourPaneLayout(
                                  workspacePanelKey: _workspacePanelKey,
                                  terminalFocusNode: _terminalFocusNode,
                                  workspaceVis: _workspaceVis,
                                  agentsVis: _agentsVis,
                                  fileTreeVis: _fileTreeVis,
                                  initialSnapshot: _sessionSnapshot,
                                  onSetPanelVis: _setPanelVis,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ), // Shortcuts
    ); // ListenableBuilder
  }
}

/// 4-pane layout: [Workspace] [Terminal] [FileEditor?] [ReviewPanel?]
/// FileEditor appears when a file is open.
class _FourPaneLayout extends StatefulWidget {
  const _FourPaneLayout({
    required this.workspacePanelKey,
    required this.terminalFocusNode,
    required this.workspaceVis,
    required this.agentsVis,
    required this.fileTreeVis,
    required this.onSetPanelVis,
    this.initialSnapshot,
  });

  final GlobalKey<WorkspacePanelState> workspacePanelKey;
  final FocusNode terminalFocusNode;
  final PanelVisibility workspaceVis;
  final PanelVisibility agentsVis;
  final PanelVisibility fileTreeVis;
  final void Function(String panelId, PanelVisibility v) onSetPanelVis;
  final SessionSnapshot? initialSnapshot;

  @override
  State<_FourPaneLayout> createState() => _FourPaneLayoutState();
}

class _FourPaneLayoutState extends State<_FourPaneLayout> {
  late double _workspaceWidth;
  late double _editorWidth;
  late double _reviewWidth;

  // Vertical heights (null = fill all available space)
  double? _agentsHeight;
  double? _editorHeight;
  double? _reviewHeight;

  static const _minWidth = 160.0;
  static const _minHeight = 120.0;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSnapshot;
    _workspaceWidth = s?.workspaceWidth ?? 260;
    _editorWidth = s?.editorWidth ?? 480;
    _reviewWidth = s?.reviewWidth ?? 360;
    _agentsHeight = s?.agentsHeight;
    _editorHeight = s?.editorHeight;
    _reviewHeight = s?.reviewHeight;
  }

  @override
  void dispose() {
    super.dispose();
  }

  static const _kPanelDuration = Duration(milliseconds: 200);
  static const _kPanelCurve = Curves.easeInOut;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FileEditorCubit, FileEditorState>(
      builder: (context, editorState) {
        final showWorkspace = widget.workspaceVis == PanelVisibility.open;
        final workspaceCollapsed =
            widget.workspaceVis == PanelVisibility.collapsed;
        final showAgents = widget.agentsVis == PanelVisibility.open;
        final agentsCollapsed = widget.agentsVis == PanelVisibility.collapsed;
        final showEditor = editorState.isVisible;
        final showFileTree = widget.fileTreeVis == PanelVisibility.open;
        final fileTreeCollapsed =
            widget.fileTreeVis == PanelVisibility.collapsed;
        final leftRailVisible = workspaceCollapsed || agentsCollapsed;
        final rightRailVisible = fileTreeCollapsed;

        return LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final totalHeight = constraints.maxHeight;

            return Row(
              children: [
                // Left ActivityRail (workspace or agents collapsed)
                AnimatedSize(
                  duration: _kPanelDuration,
                  curve: _kPanelCurve,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: leftRailVisible ? 32 : 0,
                    child:
                        leftRailVisible
                            ? ActivityRail(
                              side: ActivityRailSide.left,
                              items: [
                                if (workspaceCollapsed)
                                  ActivityRailItem(
                                    iconWidget: SvgPicture.asset(
                                      'assets/images/yoloit_mark.svg',
                                      colorFilter: const ColorFilter.mode(
                                        AppColors.textMuted,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                    tooltip: 'Expand Workspaces',
                                    onTap:
                                        () => widget.onSetPanelVis(
                                          'workspace',
                                          PanelVisibility.open,
                                        ),
                                  ),
                                if (agentsCollapsed)
                                  ActivityRailItem(
                                    icon: Icons.terminal,
                                    tooltip: 'Expand Agents',
                                    onTap:
                                        () => widget.onSetPanelVis(
                                          'agents',
                                          PanelVisibility.open,
                                        ),
                                  ),
                              ],
                            )
                            : const SizedBox.shrink(),
                  ),
                ),

                // Workspace panel (slides in/out)
                AnimatedSize(
                  duration: _kPanelDuration,
                  curve: _kPanelCurve,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: showWorkspace ? _workspaceWidth : 0,
                    child:
                        showWorkspace
                            ? SizedBox(
                              width: _workspaceWidth,
                              child: PanelShell(
                                title: 'WORKSPACES',
                                iconWidget: SvgPicture.asset(
                                  'assets/images/yoloit_mark.svg',
                                  colorFilter: const ColorFilter.mode(
                                    AppColors.textMuted,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                actions: [
                                  PanelActionBtn(
                                    icon: Icons.add,
                                    tooltip: 'Add workspace',
                                    onTap:
                                        () =>
                                            widget
                                                .workspacePanelKey
                                                .currentState
                                                ?.addWorkspace(),
                                  ),
                                ],
                                onCollapse:
                                    () => widget.onSetPanelVis(
                                      'workspace',
                                      PanelVisibility.collapsed,
                                    ),
                                collapseIcon: Icons.keyboard_arrow_left,
                                onClose:
                                    () => widget.onSetPanelVis(
                                      'workspace',
                                      PanelVisibility.closed,
                                    ),
                                child: WorkspacePanel(
                                  key: widget.workspacePanelKey,
                                ),
                              ),
                            )
                            : const SizedBox.shrink(),
                  ),
                ),

                // Workspace divider (slides out with panel)
                AnimatedSize(
                  duration: _kPanelDuration,
                  curve: _kPanelCurve,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: showWorkspace ? 4 : 0,
                    child:
                        showWorkspace
                            ? _Divider(
                              onDrag: (dx) {
                                setState(
                                  () =>
                                      _workspaceWidth = (_workspaceWidth + dx)
                                          .clamp(_minWidth, totalWidth / 3),
                                );
                                SessionPrefs.saveWorkspaceWidth(
                                  _workspaceWidth,
                                );
                              },
                            )
                            : const SizedBox.shrink(),
                  ),
                ),

                // Agents panel (fills remaining, fades when collapsed)
                if (showAgents || agentsCollapsed)
                  Expanded(
                    child: AnimatedOpacity(
                      duration: _kPanelDuration,
                      curve: _kPanelCurve,
                      opacity: showAgents ? 1.0 : 0.0,
                      child: Focus(
                        focusNode: widget.terminalFocusNode,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: PanelShell(
                                title: 'AGENTS',
                                icon: Icons.terminal,
                                onCollapse:
                                    () => widget.onSetPanelVis(
                                      'agents',
                                      PanelVisibility.collapsed,
                                    ),
                                collapseIcon: Icons.keyboard_arrow_left,
                                onClose:
                                    () => widget.onSetPanelVis(
                                      'agents',
                                      PanelVisibility.closed,
                                    ),
                                child: const _AgentsContent(),
                              ),
                            ),
                            _HorizontalDivider(
                              onDrag: (dy) {
                                setState(
                                  () =>
                                      _agentsHeight = ((_agentsHeight ??
                                                  totalHeight) +
                                              dy)
                                          .clamp(_minHeight, totalHeight - 40),
                                );
                                SessionPrefs.saveAgentsHeight(_agentsHeight);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // File Editor
                if (showEditor) ...[
                  if (showAgents)
                    _Divider(
                      onDrag: (dx) {
                        setState(
                          () =>
                              _editorWidth = (_editorWidth - dx).clamp(
                                _minWidth,
                                totalWidth / 2,
                              ),
                        );
                        SessionPrefs.saveEditorWidth(_editorWidth);
                      },
                    ),
                  if (showAgents)
                    SizedBox(
                      width: _editorWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: PanelShell(
                              title: 'EDITOR',
                              icon: Icons.code,
                              onClose:
                                  () =>
                                      context
                                          .read<FileEditorCubit>()
                                          .hidePanel(),
                              child: const FileEditorPanel(),
                            ),
                          ),
                          _HorizontalDivider(
                            onDrag: (dy) {
                              setState(
                                () =>
                                    _editorHeight = ((_editorHeight ??
                                                totalHeight) +
                                            dy)
                                        .clamp(_minHeight, totalHeight - 40),
                              );
                              SessionPrefs.saveEditorHeight(_editorHeight);
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: PanelShell(
                              title: 'EDITOR',
                              icon: Icons.code,
                              onClose:
                                  () =>
                                      context
                                          .read<FileEditorCubit>()
                                          .hidePanel(),
                              child: const FileEditorPanel(),
                            ),
                          ),
                          _HorizontalDivider(
                            onDrag: (dy) {
                              setState(
                                () =>
                                    _editorHeight = ((_editorHeight ??
                                                totalHeight) +
                                            dy)
                                        .clamp(_minHeight, totalHeight - 40),
                              );
                              SessionPrefs.saveEditorHeight(_editorHeight);
                            },
                          ),
                        ],
                      ),
                    ),
                ],

                // File tree divider (slides out with panel)
                AnimatedSize(
                  duration: _kPanelDuration,
                  curve: _kPanelCurve,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: showFileTree ? 4 : 0,
                    child:
                        showFileTree
                            ? _Divider(
                              onDrag: (dx) {
                                setState(
                                  () =>
                                      _reviewWidth = (_reviewWidth - dx).clamp(
                                        _minWidth,
                                        totalWidth / 2,
                                      ),
                                );
                                SessionPrefs.saveReviewWidth(_reviewWidth);
                              },
                            )
                            : const SizedBox.shrink(),
                  ),
                ),

                // File tree panel (slides in/out)
                AnimatedSize(
                  duration: _kPanelDuration,
                  curve: _kPanelCurve,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: showFileTree ? _reviewWidth : 0,
                    child:
                        showFileTree
                            ? SizedBox(
                              width: _reviewWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: PanelShell(
                                      title: 'FILE TREE',
                                      icon: Icons.account_tree,
                                      onCollapse:
                                          () => widget.onSetPanelVis(
                                            'filetree',
                                            PanelVisibility.collapsed,
                                          ),
                                      collapseIcon: Icons.keyboard_arrow_right,
                                      onClose:
                                          () => widget.onSetPanelVis(
                                            'filetree',
                                            PanelVisibility.closed,
                                          ),
                                      child: const ReviewPanel(),
                                    ),
                                  ),
                                  _HorizontalDivider(
                                    onDrag: (dy) {
                                      setState(
                                        () =>
                                            _reviewHeight = ((_reviewHeight ??
                                                        totalHeight) +
                                                    dy)
                                                .clamp(
                                                  _minHeight,
                                                  totalHeight - 40,
                                                ),
                                      );
                                      SessionPrefs.saveReviewHeight(
                                        _reviewHeight,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            )
                            : const SizedBox.shrink(),
                  ),
                ),

                // Right ActivityRail (file tree collapsed)
                AnimatedSize(
                  duration: _kPanelDuration,
                  curve: _kPanelCurve,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: rightRailVisible ? 32 : 0,
                    child:
                        rightRailVisible
                            ? ActivityRail(
                              side: ActivityRailSide.right,
                              items: [
                                ActivityRailItem(
                                  icon: Icons.account_tree,
                                  tooltip: 'Expand File Tree',
                                  onTap:
                                      () => widget.onSetPanelVis(
                                        'filetree',
                                        PanelVisibility.open,
                                      ),
                                ),
                              ],
                            )
                            : const SizedBox.shrink(),
                  ),
                ),

                if (!showAgents &&
                    !agentsCollapsed &&
                    !showEditor &&
                    !showFileTree)
                  const Expanded(child: SizedBox.shrink()),
              ],
            );
          },
        );
      },
    );
  }
}

/// Content of the Agents panel: listens to workspace changes and hosts TerminalPanel.
class _AgentsContent extends StatelessWidget {
  const _AgentsContent();

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // Workspace switch: reinitialize terminal, run, review, editor
        BlocListener<WorkspaceCubit, WorkspaceState>(
          listenWhen: (prev, curr) {
            if (curr is! WorkspaceLoaded) return false;
            if (prev is! WorkspaceLoaded) return true;
            return prev.activeWorkspaceId != curr.activeWorkspaceId &&
                curr.activeWorkspaceId != null;
          },
          listener: (context, state) {
            if (state is! WorkspaceLoaded) return;
            final wsId = state.activeWorkspaceId;
            if (wsId == null) return;
            final ws = state.workspaces.firstWhere(
              (w) => w.id == wsId,
              orElse: () => state.workspaces.first,
            );
            context.read<TerminalCubit>().setActiveWorkspace(
              workspaceId: wsId,
              workspacePath: ws.workspaceDir,
              workspacePaths: ws.paths,
            );
            context.read<RunCubit>().loadForWorkspace(ws.path);
            context.read<ReviewCubit>().loadWorkspace(
              ws.paths,
              workspaceId: wsId,
            );
            context.read<FileEditorCubit>().setWorkspace(wsId);
          },
        ),
        // Session switch: sync file tree and editor tabs to the active session
        BlocListener<TerminalCubit, TerminalState>(
          listenWhen: (prev, curr) {
            if (curr is! TerminalLoaded) return false;
            if (prev is! TerminalLoaded) return true;
            return prev.activeSession?.id != curr.activeSession?.id;
          },
          listener: (context, state) {
            if (state is! TerminalLoaded) return;
            final session = state.activeSession;
            if (session == null) return;
            final wsState = context.read<WorkspaceCubit>().state;
            // Resolve file tree paths: worktreeContexts values if set, else workspace paths
            final List<String> paths;
            if (session.worktreeContexts != null &&
                session.worktreeContexts!.isNotEmpty) {
              paths = session.worktreeContexts!.values.toList();
            } else if (wsState is WorkspaceLoaded &&
                wsState.activeWorkspaceId != null) {
              final ws = wsState.workspaces.firstWhere(
                (w) => w.id == wsState.activeWorkspaceId,
                orElse: () => wsState.workspaces.first,
              );
              paths = ws.paths;
            } else {
              paths = [];
            }
            context.read<ReviewCubit>().loadSession(paths, session.id);
            context.read<FileEditorCubit>().setSession(session.id);
            // Reload run configs for the session's active worktree path so
            // each session/worktree shows its own configurations and run history.
            if (paths.isNotEmpty) {
              context.read<RunCubit>().loadForWorkspace(paths.first);
            }
          },
        ),
      ],
      child: const TerminalPanel(),
    );
  }
}

/// Thin draggable divider between panes.
class _Divider extends StatefulWidget {
  const _Divider({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 4,
          color: _hovering ? colors.primary.withAlpha(120) : colors.divider,
        ),
      ),
    );
  }
}

/// Thin horizontal draggable divider at the bottom of a pane for vertical resize.
class _HorizontalDivider extends StatefulWidget {
  const _HorizontalDivider({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  State<_HorizontalDivider> createState() => _HorizontalDividerState();
}

class _HorizontalDividerState extends State<_HorizontalDivider> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 4,
          color: _hovering ? colors.primary.withAlpha(120) : colors.divider,
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.onSettings,
    required this.workspaceVis,
    required this.agentsVis,
    required this.fileTreeVis,
    required this.canvasMode,
    required this.onToggleWorkspace,
    required this.onToggleAgents,
    required this.onToggleFileTree,
    required this.onToggleMapView,
    required this.onToggleBoardView,
    required this.onSearch,
  });
  final VoidCallback onSettings;
  final PanelVisibility workspaceVis;
  final PanelVisibility agentsVis;
  final PanelVisibility fileTreeVis;
  final _CanvasMode canvasMode;
  final VoidCallback onToggleWorkspace;
  final VoidCallback onToggleAgents;
  final VoidCallback onToggleFileTree;
  final VoidCallback onToggleMapView;
  final VoidCallback onToggleBoardView;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isWindows = Platform.isWindows;
    final isLinux = Platform.isLinux;
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 44,
        color: colors.surface,
        child: Row(
          children: [
            // macOS: reserve space for native traffic lights (close/min/max)
            // Windows/Linux: small left margin only
            SizedBox(width: isWindows || isLinux ? 12 : 82),
            // Left panel toggle buttons (fixed, left-anchored)
            _PanelToggleButton(
              icon: Icons.view_sidebar,
              tooltip: 'Toggle Workspaces (⌘\\)',
              semanticsLabel: 'Toggle left panel',
              active: workspaceVis == PanelVisibility.open,
              onTap: onToggleWorkspace,
            ),
            const SizedBox(width: 4),
            _PanelToggleButton(
              icon: Icons.terminal,
              tooltip: 'Toggle Agents / Terminal (⌘T)',
              semanticsLabel: 'Toggle agents panel',
              active: agentsVis == PanelVisibility.open,
              onTap: onToggleAgents,
            ),
            // Center: search always centered in remaining space
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: GestureDetector(
                    onTap: onSearch,
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: colors.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search,
                            size: 15,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'Quick open…',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isWindows ? 'Ctrl+O' : '⌘O',
                            style: TextStyle(
                              color: AppColors.textMuted.withAlpha(120),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Right panel buttons (fixed, always right-anchored)
            // Map view toggle button
            _PanelToggleButton(
              icon: Icons.hub_outlined,
              tooltip: 'Map View',
              semanticsLabel: 'Toggle Miro-like map view',
              active: canvasMode == _CanvasMode.mindMap,
              onTap: onToggleMapView,
            ),
            const SizedBox(width: 4),
            _PanelToggleButton(
              icon: Icons.dashboard_customize_outlined,
              tooltip: 'Board View',
              semanticsLabel: 'Toggle board view',
              active: canvasMode == _CanvasMode.board,
              onTap: onToggleBoardView,
            ),
            const SizedBox(width: 4),
            const _ResourceChip(),
            const SizedBox(width: 8),
            BlocBuilder<FileEditorCubit, FileEditorState>(
              builder:
                  (context, editorState) => _PanelToggleButton(
                    icon: Icons.edit_document,
                    tooltip: 'Toggle File Editor',
                    semanticsLabel: 'Toggle file editor panel',
                    active: editorState.isVisible,
                    onTap: () => context.read<FileEditorCubit>().togglePanel(),
                  ),
            ),
            const SizedBox(width: 4),
            _PanelToggleButton(
              icon: Icons.rate_review,
              tooltip: 'Toggle File Tree (⌘⇧\\)',
              semanticsLabel: 'Toggle right panel',
              active: fileTreeVis == PanelVisibility.open,
              onTap: onToggleFileTree,
            ),
            const SizedBox(width: 4),
            _PanelToggleButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings (⌘,)',
              semanticsLabel: 'Open settings',
              active: false,
              onTap: onSettings,
            ),
            // Windows / Linux: show custom minimize/maximize/close buttons
            // because TitleBarStyle.hidden removes native window controls.
            if (isWindows || isLinux) ...[
              const SizedBox(width: 8),
              const _WindowControls(),
            ] else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _PanelToggleButton extends StatelessWidget {
  const _PanelToggleButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.semanticsLabel,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: semanticsLabel ?? tooltip,
        button: true,
        toggled: active,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 32,
            height: 28,
            decoration: BoxDecoration(
              color: active ? colors.primary.withAlpha(40) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: 16,
              color: active ? colors.primary : AppColors.textMuted,
              semanticLabel: tooltip,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Windows / Linux window controls ──────────────────────────────────────────

/// Custom minimize / maximize / close buttons for platforms where
/// [TitleBarStyle.hidden] removes the native window chrome (Windows, Linux).
class _WindowControls extends StatefulWidget {
  const _WindowControls();

  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<_WindowControls> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinBtn(
          icon: Icons.remove,
          tooltip: 'Minimize',
          onTap: () => windowManager.minimize(),
        ),
        _WinBtn(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          tooltip: _isMaximized ? 'Restore' : 'Maximize',
          onTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WinBtn(
          icon: Icons.close,
          tooltip: 'Close',
          isClose: true,
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WinBtn extends StatefulWidget {
  const _WinBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor =
        widget.isClose
            ? const Color(0xFFE81123)
            : AppColors.textMuted.withAlpha(40);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 44,
            color: _hovered ? hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 14,
              color:
                  _hovered && widget.isClose
                      ? Colors.white
                      : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Resource Monitor Chip ────────────────────────────────────────────────────

class _ResourceChip extends StatefulWidget {
  const _ResourceChip();

  @override
  State<_ResourceChip> createState() => _ResourceChipState();
}

class _ResourceChipState extends State<_ResourceChip> {
  ResourceSnapshot _snap = ResourceMonitorService.instance.current;
  late final StreamSubscription<ResourceSnapshot> _sub;

  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _sub = ResourceMonitorService.instance.stream.listen((s) {
      if (mounted) setState(() => _snap = s);
    });
  }

  @override
  void dispose() {
    _overlay?.remove(); // remove overlay BEFORE cancelling subscription
    _overlay = null;
    _sub.cancel();
    super.dispose();
  }

  void _toggle(BuildContext context) {
    if (_overlay != null) {
      _overlay!.remove();
      _overlay = null;
      return;
    }
    final box = context.findRenderObject()! as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    _overlay = OverlayEntry(
      builder:
          (_) => _ResourcePanel(
            snapshot: _snap,
            position: Offset(
              offset.dx - 260 + box.size.width,
              offset.dy + box.size.height + 4,
            ),
            onClose: () {
              _overlay?.remove();
              _overlay = null;
            },
          ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    final mem = formatBytes(_snap.totalMemoryBytes);
    final cpu = _snap.totalCpuPercent;
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodySmall?.color ??
        const Color(0xFFB0B0D0);
    return GestureDetector(
      onTap: () => _toggle(context),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, size: 11, color: colors.primary),
            const SizedBox(width: 4),
            Text(
              cpu > 0 ? '${cpu.toStringAsFixed(1)}%  $mem' : mem,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourcePanel extends StatefulWidget {
  const _ResourcePanel({
    required this.snapshot,
    required this.position,
    required this.onClose,
  });
  final ResourceSnapshot snapshot;
  final Offset position;
  final VoidCallback onClose;

  @override
  State<_ResourcePanel> createState() => _ResourcePanelState();
}

class _ResourcePanelState extends State<_ResourcePanel> {
  late ResourceSnapshot _snap = widget.snapshot;
  late final StreamSubscription<ResourceSnapshot> _sub;

  @override
  void initState() {
    super.initState();
    _sub = ResourceMonitorService.instance.stream.listen((s) {
      if (mounted) setState(() => _snap = s);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _snap.host;
    final ramSharePercent =
        host.totalBytes > 0
            ? (_snap.totalMemoryBytes / host.totalBytes * 100).clamp(0.0, 100.0)
            : 0.0;

    final Color memBarColor;
    if (host.usedPercent >= 90) {
      memBarColor = const Color(0xFFFF4444);
    } else if (host.usedPercent >= 70) {
      memBarColor = const Color(0xFFFF8C00);
    } else {
      memBarColor = const Color(0xFF7C3AED);
    }

    // Separate registered sessions from agent-scanned ones.
    final monitorService = ResourceMonitorService.instance;
    final registeredPids = monitorService.registeredPids;
    final registeredSessions =
        _snap.sessions.where((s) => registeredPids.contains(s.pid)).toList();
    final agentSessions =
        _snap.sessions.where((s) => !registeredPids.contains(s.pid)).toList();

    return Stack(
      children: [
        // Tap-outside to close
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          width: 300,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF16163A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF32327A)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 16),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.monitor_heart_outlined,
                          size: 13,
                          color: Color(0xFF7C7CFF),
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'RESOURCE USAGE',
                            style: TextStyle(
                              color: Color(0xFFE0E0F0),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap:
                              () => ResourceMonitorService.instance.pollNow(),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.refresh,
                              size: 13,
                              color: Color(0xFF6060A0),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: widget.onClose,
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Color(0xFF6060A0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF32327A)),

                  // 3-column metric grid: CPU total%, Memory total, RAM share%
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _StatCell(
                          label: 'CPU',
                          value: '${_snap.totalCpuPercent.toStringAsFixed(1)}%',
                        ),
                        _StatCell(
                          label: 'MEMORY',
                          value: formatBytes(_snap.totalMemoryBytes),
                        ),
                        _StatCell(
                          label: 'RAM SHARE',
                          value: '${ramSharePercent.toStringAsFixed(1)}%',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF32327A)),

                  // HOST section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message:
                              'Total RAM of your Mac (all processes combined)',
                          child: const Text(
                            'SYSTEM RAM',
                            style: TextStyle(
                              color: Color(0xFF6060A0),
                              fontSize: 9,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              '${formatBytes(host.usedBytes)} used / ${formatBytes(host.totalBytes)} total',
                              style: const TextStyle(
                                color: Color(0xFFB0B0D0),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(
                              value: (host.usedPercent / 100).clamp(0.0, 1.0),
                              backgroundColor: const Color(0xFF2A2A5A),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                memBarColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Load avg row
                        Row(
                          children: [
                            const Text(
                              'LOAD AVG',
                              style: TextStyle(
                                color: Color(0xFF6060A0),
                                fontSize: 9,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              host.loadAverage1m.toStringAsFixed(2),
                              style: const TextStyle(
                                color: Color(0xFFB0B0D0),
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),

                  // SESSIONS section (registered PTYs)
                  if (registeredSessions.isNotEmpty) ...[
                    const Divider(height: 1, color: Color(0xFF32327A)),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
                      child: Text(
                        'SESSIONS',
                        style: TextStyle(
                          color: Color(0xFF6060A0),
                          fontSize: 9,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    ...registeredSessions.map((s) => _SessionRow(session: s)),
                  ],

                  // AGENTS section (ps-scanned unregistered agents)
                  if (agentSessions.isNotEmpty) ...[
                    const Divider(height: 1, color: Color(0xFF32327A)),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
                      child: Text(
                        'AGENTS & TOOLS',
                        style: TextStyle(
                          color: Color(0xFF6060A0),
                          fontSize: 9,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    ...agentSessions.map((s) => _SessionRow(session: s)),
                  ],

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6060A0),
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE0E0F0),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final SessionStat session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 5, color: Color(0xFF7C7CFF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              formatSessionLabel(session.label),
              style: const TextStyle(color: Color(0xFFB0B0D0), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${session.cpuPercent.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Color(0xFF8080B0),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              formatBytes(session.memoryBytes),
              style: const TextStyle(
                color: Color(0xFF8080B0),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
