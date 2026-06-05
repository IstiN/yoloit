import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/ui/components/buttons/markdown_tool_button.dart';
import 'package:yoloit/ui/components/buttons/overlay_icon_button.dart';
import 'package:yoloit/ui/components/buttons/panel_header_icon_button.dart';
import 'package:yoloit/ui/components/chip/toolbar_chip.dart';
import 'package:yoloit/core/utils/date_utils.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/assistant/yolo_voice_overlay.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/provider_icon.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_plugin.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_overview_layer.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';
import 'package:yoloit/features/board/ui/board_overview_widgets.dart';
import 'package:yoloit/features/board/ui/dialogs/board_settings_dialog.dart';
import 'package:yoloit/features/board/ui/miro_panel_toolbar.dart';
import 'package:yoloit/features/board/ui/dialogs/connect_remote_yoloit_dialog.dart';
import 'package:yoloit/features/board/ui/dialogs/share_board_dialog.dart';
import 'package:yoloit/features/board/ui/board_drawing_widgets.dart';
import 'package:yoloit/features/board/ui/board_history_panel.dart';
import 'package:yoloit/features/board/ui/board_link_widgets.dart';
import 'package:yoloit/features/board/ui/board_links_painter.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/search/ui/file_search_overlay.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';

class BoardView extends StatefulWidget {
  const BoardView({super.key, this.skipOverviewPreviewCapture = false});

  /// Test-only escape hatch for overview goldens. The production overview
  /// captures live PNG previews before opening; widget tests do not always have
  /// a real frame/image pipeline, so they can render the overview directly.
  final bool skipOverviewPreviewCapture;

  @override
  State<BoardView> createState() => _BoardViewState();
}

@visibleForTesting
bool boardShouldRevertInteractionForCanvasLock({
  required bool interactionStartedLocked,
  required bool currentlyLocked,
  bool isScaleChanging = false,
}) {
  return interactionStartedLocked && currentlyLocked && !isScaleChanging;
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  static const Size _initialCanvasSize = Size(40000, 30000);
  static const double _canvasExpansionMargin = 6000;
  static const double _canvasExpansionChunk = 20000;
  static const double _edgePanZone = 120;
  static const double _edgePanMaxStep = 18;

  /// Extract the 2D uniform scale from a Matrix4.
  /// `getMaxScaleOnAxis()` returns max(scaleX, scaleY, 1.0) — wrong when
  /// zoomed out (scale < 1) because the Z column is always 1.
  static double _scaleOf(Matrix4 m) {
    final s = m.storage;
    return math.sqrt(s[0] * s[0] + s[1] * s[1]);
  }

  static bool _isPointerOverScrollableCard(Offset position, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    return result.path.any(
      (entry) => entry.target is RenderScrollableCardMarker,
    );
  }

  final FocusNode _boardFocus = FocusNode();

  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey _screenshotBoundaryKey = GlobalKey();
  Size? _viewportSize;
  Size _canvasSize = _initialCanvasSize;
  Offset _canvasOrigin = const Offset(20000, 15000);
  bool _canvasExpansionScheduled = false;
  bool _isPanelDragging = false;
  bool _isViewportInteracting = false;
  bool _isViewportZooming = false;
  double _interactionStartScale = 1.0;
  Matrix4? _interactionStartMatrix;
  bool _interactionStartedLocked = false;
  int? _lastLoggedLockCount;
  Offset? _lastPanelDragBoardPointer;

  String? _syncedBoardId;
  BoardViewport? _syncedViewport;
  String? _autoFitKey;
  String? _focusedPanelVisibilityKey;
  bool _showMinimap = true;
  bool _showToolsPanel = true;
  bool _showHistoryPanel = false;
  bool _isBoardOverviewOpen = false;
  bool _cancelBgCapture = false;
  bool _boardSwitchPreviewVisible = false;
  BoardDocument? _boardSwitchPreviewBoard;
  Uint8List? _boardSwitchPreviewPng;
  final Map<String, Uint8List> _boardPreviewPngs = {};

  /// When true, panel chrome (borders, accents, sidebar, minimap) is hidden
  /// to produce a clean screenshot without purple-tinted decorations.
  bool _isCapturingScreenshot = false;

  String get _currentPanelPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// Suppresses focused-panel auto-centering for one rebuild cycle after
  /// switching boards so the restored viewport position is preserved.
  bool _suppressFocusVisibility = false;
  late final AnimationController _panController;
  Animation<Matrix4>? _panAnimation;
  VoidCallback? _panAnimationListener;
  AnimationStatusListener? _panStatusListener;

  // ── Tool state ────────────────────────────────────────────────────────────
  BoardToolId _activeTool = BoardToolId.select;
  DrawSettings _drawSettings = const DrawSettings();
  ConnectSettings _connectSettings = const ConnectSettings();

  /// Link id currently hovered (for showing delete badge).
  String? _hoveredLinkId;

  /// Points accumulated for the active stroke (board-space).
  final List<Offset> _activeStroke = [];

  /// Active pointer id for drawing (null when not drawing).
  int? _drawPointer;

  /// Pending connection source panel id.
  String? _connectSourceId;
  Offset? _connectPreviewPointer; // board-space pointer for preview line

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _transformController.addListener(_scheduleCanvasExpansionIfNeeded);
    BoardScreenshotService.instance.registerBoundaryKey(_screenshotBoundaryKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BoardCubit?>()?.load();
    });
  }

  @override
  void dispose() {
    _stopPanAnimation();
    _transformController.removeListener(_scheduleCanvasExpansionIfNeeded);
    _panController.dispose();
    _transformController.dispose();
    _boardFocus.dispose();
    unawaited(BoardShareServer.instance.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Use Focus with canRequestFocus:false so the board handles shortcuts
    // (ESC) without stealing keyboard focus away from TextFields or WebViews.
    return Focus(
      focusNode: _boardFocus,
      autofocus: false,
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_connectSourceId != null) {
            setState(() {
              _connectSourceId = null;
              _connectPreviewPointer = null;
            });
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: BlocBuilder<BoardCubit, BoardState>(
        builder: (context, state) {
          if (!state.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final activeBoard = state.activeBoard;
          if (activeBoard == null) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => context.read<BoardCubit>().createBoard(),
                icon: const Icon(Icons.add),
                label: const Text('Create board'),
              ),
            );
          }

          _syncViewport(activeBoard);

          return Container(
            color: colors.background,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BoardToolbar(
                  board: activeBoard,
                  onCreateBoard: () => _createBoard(context),
                  onConnectRemote: () => _connectRemoteYoloit(context),
                  onShareBoard: () => _shareBoard(context),
                  onBoardSettings:
                      () => _showBoardSettings(context, activeBoard),
                  onDeleteBoard: () => _deleteBoard(context, activeBoard),
                  onOpenBoardOverview: () => _openBoardOverview(activeBoard),
                  onSearch: () => _openBoardSearch(context),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.divider)),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _viewportSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        _scheduleAutoFitIfNeeded(activeBoard);
                        _scheduleFocusedPanelVisibilityIfNeeded(activeBoard);
                        final focusedPanelId =
                            activeBoard.viewport.focusedPanelId;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            RepaintBoundary(
                              key: _screenshotBoundaryKey,
                              child: Stack(
                                key: _viewportKey,
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _InfiniteBoardGridPainter(
                                          transformCtrl: _transformController,
                                          origin: _canvasOrigin,
                                          minorColor: colors.divider.withAlpha(
                                            60,
                                          ),
                                          majorColor: colors.divider.withAlpha(
                                            110,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  ValueListenableBuilder<int>(
                                    valueListenable:
                                        CanvasInteractionLock
                                            .instance
                                            .lockStateVersion,
                                    builder: (context, lockVersion, child) {
                                      final activeCount =
                                          CanvasInteractionLock
                                              .instance
                                              .activeCount
                                              .value;
                                      final isLocked =
                                          CanvasInteractionLock
                                              .instance
                                              .isLocked;
                                      if (_lastLoggedLockCount != lockVersion) {
                                        _lastLoggedLockCount = lockVersion;
                                        debugPrint(
                                          '[BoardViewLock] activeCount=$activeCount, isLocked=$isLocked',
                                        );
                                      }
                                      return Listener(
                                        behavior: HitTestBehavior.translucent,
                                        onPointerSignal: (event) {
                                          if (event is PointerScrollEvent) {
                                            final overScrollable =
                                                _isPointerOverScrollableCard(
                                                  event.position,
                                                  event.viewId,
                                                );
                                            final scale =
                                                _BoardViewState._scaleOf(
                                                  _transformController.value,
                                                );
                                            _boardSupportLog(
                                              'pointerScroll locked=$isLocked '
                                              'canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} '
                                              'overScrollable=$overScrollable '
                                              'tool=${_activeTool.name} '
                                              'kind=${event.kind.name} '
                                              'delta=${_fmtOffset(event.scrollDelta)} '
                                              'pos=${_fmtOffset(event.position)} '
                                              'scale=${_fmt(scale)}',
                                            );
                                            if (!isLocked && !overScrollable) {
                                              CanvasInteractionLock.instance
                                                  .markCanvasSignalGesture();
                                            }
                                          } else {
                                            _boardSupportLog(
                                              'pointerSignal locked=$isLocked '
                                              'canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} '
                                              'tool=${_activeTool.name} '
                                              'type=${event.runtimeType} '
                                              'pos=${_fmtOffset(event.position)}',
                                            );
                                          }
                                          if (isLocked) {
                                            // Swallow the event here so
                                            // InteractiveViewer never sees it.
                                            return;
                                          }
                                        },
                                        onPointerPanZoomStart: (event) {
                                          final overScrollable =
                                              _isPointerOverScrollableCard(
                                                event.position,
                                                event.viewId,
                                              );
                                          if (!isLocked && !overScrollable) {
                                            CanvasInteractionLock.instance
                                                .beginCanvasGesture();
                                          }
                                          _boardSupportLog(
                                            'panZoom.start locked=$isLocked '
                                            'canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} '
                                            'overScrollable=$overScrollable '
                                            'tool=${_activeTool.name} '
                                            'pos=${_fmtOffset(event.position)} '
                                            'scale=${_fmt(_scaleOf(_transformController.value))}',
                                          );
                                        },
                                        onPointerPanZoomUpdate: (event) {
                                          _boardSupportLog(
                                            'panZoom.update locked=$isLocked '
                                            'tool=${_activeTool.name} '
                                            'pan=${_fmtOffset(event.pan)} '
                                            'panDelta=${_fmtOffset(event.panDelta)} '
                                            'scale=${_fmt(event.scale)} '
                                            'rotation=${event.rotation.toStringAsFixed(3)} '
                                            'viewScale=${_fmt(_scaleOf(_transformController.value))}',
                                          );
                                        },
                                        onPointerPanZoomEnd: (event) {
                                          if (CanvasInteractionLock
                                              .instance
                                              .isCanvasGestureActive) {
                                            CanvasInteractionLock.instance
                                                .endCanvasGesture();
                                          }
                                          _boardSupportLog(
                                            'panZoom.end locked=$isLocked '
                                            'canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} '
                                            'tool=${_activeTool.name} '
                                            'scale=${_fmt(_scaleOf(_transformController.value))}',
                                          );
                                        },
                                        child: InteractiveViewer(
                                          key: const ValueKey(
                                            'board_interactive_viewer',
                                          ),
                                          constrained: false,
                                          minScale: 0.2,
                                          maxScale: 2.5,
                                          scaleEnabled: true,
                                          boundaryMargin: const EdgeInsets.all(
                                            _canvasExpansionChunk,
                                          ),
                                          // Disable pan only while actively drawing (drawPointer held) or canvas is locked
                                          panEnabled:
                                              (_activeTool !=
                                                      BoardToolId.draw ||
                                                  _drawPointer == null),
                                          transformationController:
                                              _transformController,
                                          onInteractionStart: (details) {
                                            final startScale =
                                                _BoardViewState._scaleOf(
                                                  _transformController.value,
                                                );
                                            _boardSupportLog(
                                              'interaction.start locked=$isLocked '
                                              'tool=${_activeTool.name} '
                                              'pointerCount=${details.pointerCount} '
                                              'focal=${_fmtOffset(details.focalPoint)} '
                                              'local=${_fmtOffset(details.localFocalPoint)} '
                                              'scale=${_fmt(startScale)}',
                                            );
                                            _interactionStartScale =
                                                _BoardViewState._scaleOf(
                                                  _transformController.value,
                                                );
                                            _interactionStartMatrix =
                                                _transformController.value
                                                    .clone();
                                            _interactionStartedLocked =
                                                CanvasInteractionLock
                                                    .instance
                                                    .isLocked;
                                            setState(() {
                                              _isViewportInteracting = true;
                                              _isViewportZooming = false;
                                            });
                                            _boardDebugLog('interaction.start');
                                            _stopPanAnimation();
                                          },
                                          onInteractionUpdate: (details) {
                                            final currentScale =
                                                _BoardViewState._scaleOf(
                                                  _transformController.value,
                                                );
                                            if (boardShouldRevertInteractionForCanvasLock(
                                                  interactionStartedLocked:
                                                      _interactionStartedLocked,
                                                  currentlyLocked:
                                                      CanvasInteractionLock
                                                          .instance
                                                          .isLocked,
                                                  isScaleChanging:
                                                      (currentScale -
                                                              _interactionStartScale)
                                                          .abs() >
                                                      0.01,
                                                ) &&
                                                _interactionStartMatrix !=
                                                    null) {
                                              _boardSupportLog(
                                                'interaction.update.reverted '
                                                'reason=canvasLock '
                                                'pointerCount=${details.pointerCount} '
                                                'scale=${_fmt(_scaleOf(_transformController.value))}',
                                              );
                                              _transformController.value =
                                                  _interactionStartMatrix!;
                                              return;
                                            }
                                            _boardSupportLog(
                                              'interaction.update locked=$isLocked '
                                              'tool=${_activeTool.name} '
                                              'pointerCount=${details.pointerCount} '
                                              'scaleDelta=${_fmt(details.scale)} '
                                              'currentScale=${_fmt(currentScale)} '
                                              'focalDelta=${_fmtOffset(details.focalPointDelta)}',
                                            );
                                            // Detect zoom by comparing current scale to
                                            // the scale at interaction start.
                                            if (!_isViewportZooming) {
                                              if ((currentScale -
                                                          _interactionStartScale)
                                                      .abs() >
                                                  0.01) {
                                                setState(
                                                  () =>
                                                      _isViewportZooming = true,
                                                );
                                              }
                                            }
                                          },
                                          onInteractionEnd: (details) {
                                            _boardSupportLog(
                                              'interaction.end locked=$isLocked '
                                              'tool=${_activeTool.name} '
                                              'velocity=${_fmtOffset(details.velocity.pixelsPerSecond)} '
                                              'scale=${_fmt(_scaleOf(_transformController.value))}',
                                            );
                                            _interactionStartMatrix = null;
                                            _interactionStartedLocked = false;
                                            setState(() {
                                              _isViewportInteracting = false;
                                              _isViewportZooming = false;
                                            });
                                            _boardDebugLog('interaction.end');
                                            // pageZoom is updated by Swift frame observer; just dispatch resize.
                                            for (final panel
                                                in activeBoard.panels) {
                                              if (panel.type !=
                                                  WebpagePlugin.kTypeId) {
                                                continue;
                                              }
                                              final ctrl =
                                                  WebpagePlugin
                                                      .controllers[panel.id];
                                              if (ctrl == null) continue;
                                              ctrl.runJavaScript(
                                                "window.dispatchEvent(new Event('resize'));",
                                              );
                                            }
                                            _persistViewport(
                                              context,
                                              activeBoard,
                                            );
                                          },
                                          child: SizedBox(
                                            width: _canvasSize.width,
                                            height: _canvasSize.height,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    child: CustomPaint(
                                                      painter:
                                                          BoardLinksPainter(
                                                            panels:
                                                                activeBoard
                                                                    .panels,
                                                            links:
                                                                activeBoard
                                                                    .links,
                                                            origin:
                                                                _canvasOrigin,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                // ── Canvas background tap — clear focus ──
                                                // Stack hit-tests children in reverse order
                                                // (last child first).  Panels are added
                                                // AFTER this Listener, so they absorb
                                                // clicks first.  Only clicks on empty
                                                // canvas reach this Listener.
                                                Positioned.fill(
                                                  child: Listener(
                                                    behavior:
                                                        HitTestBehavior
                                                            .translucent,
                                                    onPointerDown: (_) {
                                                      if (focusedPanelId !=
                                                          null) {
                                                        _boardWebFocusLog(
                                                          'canvas tap -> clearFocusedPanel',
                                                        );
                                                        context
                                                            .read<BoardCubit>()
                                                            .clearFocusedPanel();
                                                      }
                                                    },
                                                  ),
                                                ),
                                                // ── Link delete badges ─────────────────────
                                                if (_activeTool ==
                                                    BoardToolId.select)
                                                  ..._buildLinkDeleteBadges(
                                                    context,
                                                    activeBoard,
                                                  ),
                                                ...(() {
                                                  final visiblePanels =
                                                      activeBoard.panels
                                                          .where(
                                                            (panel) =>
                                                                !panel.hidden,
                                                          )
                                                          .toList()
                                                        ..sort(
                                                          (a, b) => a.zIndex
                                                              .compareTo(
                                                                b.zIndex,
                                                              ),
                                                        );
                                                  return visiblePanels.map((
                                                    panel,
                                                  ) {
                                                    final boardCubit =
                                                        context
                                                            .read<BoardCubit>();
                                                    return _BoardPanelCard(
                                                      key: ValueKey(panel.id),
                                                      panel: panel,
                                                      positionOffset:
                                                          _canvasOrigin,
                                                      capturingScreenshot:
                                                          _isCapturingScreenshot,
                                                      onTap:
                                                          () => boardCubit
                                                              .focusPanel(
                                                                panel.id,
                                                              ),
                                                      onMove:
                                                          (details) =>
                                                              _movePanelWithEdgePan(
                                                                context,
                                                                panel.id,
                                                                details,
                                                              ),
                                                      onResize:
                                                          (update) =>
                                                              _resizePanelWithEdgePan(
                                                                context,
                                                                panel,
                                                                update,
                                                              ),
                                                      onDragStart:
                                                          (details) =>
                                                              _handlePanelDragStart(
                                                                panel.id,
                                                                details,
                                                              ),
                                                      onDragEnd:
                                                          _handlePanelDragEnd,
                                                      onDelete: () async {
                                                        if (panel.type ==
                                                            'board.widget.custom') {
                                                          WidgetEngineManager
                                                              .instance
                                                              .remove(panel.id);
                                                        }
                                                        await boardCubit
                                                            .removePanel(
                                                              panel.id,
                                                            );
                                                      },
                                                      onEditColor:
                                                          () =>
                                                              _showPanelColorDialog(
                                                                context,
                                                                panel,
                                                              ),
                                                      onEditNote:
                                                          _editPanelCallback(
                                                            context,
                                                            panel,
                                                          ),
                                                      onBringToFront: () {
                                                        final board =
                                                            boardCubit
                                                                .state
                                                                .activeBoard;
                                                        if (board == null) {
                                                          return;
                                                        }
                                                        final maxZ = board
                                                            .panels
                                                            .fold<int>(
                                                              0,
                                                              (value, panel) =>
                                                                  panel.zIndex >
                                                                          value
                                                                      ? panel
                                                                          .zIndex
                                                                      : value,
                                                            );
                                                        boardCubit.updatePanel(
                                                          panel.id,
                                                          (p) => p.copyWith(
                                                            zIndex: maxZ + 1,
                                                          ),
                                                        );
                                                      },
                                                      onSendToBack: () {
                                                        final board =
                                                            boardCubit
                                                                .state
                                                                .activeBoard;
                                                        if (board == null) {
                                                          return;
                                                        }
                                                        final minZ = board
                                                            .panels
                                                            .fold<int>(
                                                              0,
                                                              (value, panel) =>
                                                                  panel.zIndex <
                                                                          value
                                                                      ? panel
                                                                          .zIndex
                                                                      : value,
                                                            );
                                                        boardCubit.updatePanel(
                                                          panel.id,
                                                          (p) => p.copyWith(
                                                            zIndex: minZ - 1,
                                                          ),
                                                        );
                                                      },
                                                      onUpdateState: (
                                                        newState,
                                                      ) {
                                                        boardCubit.updatePanel(
                                                          panel.id,
                                                          (p) => p.copyWith(
                                                            state: newState,
                                                          ),
                                                        );
                                                      },
                                                      onCreateLinkedPanel: (
                                                        typeId,
                                                        state,
                                                        title,
                                                      ) async {
                                                        final cubit =
                                                            boardCubit;
                                                        final plugin =
                                                            BoardPluginRegistry
                                                                .instance
                                                                .pluginFor(
                                                                  typeId,
                                                                );
                                                        final size =
                                                            plugin
                                                                ?.defaultSize ??
                                                            const Size(
                                                              460,
                                                              380,
                                                            );
                                                        final board =
                                                            cubit
                                                                .state
                                                                .activeBoard;
                                                        if (board == null) {
                                                          return null;
                                                        }
                                                        final currentBounds =
                                                            panel.bounds;
                                                        // Place to the right of the source panel, then
                                                        // stack downward if that slot is already taken.
                                                        final baseX =
                                                            currentBounds.x +
                                                            currentBounds
                                                                .width +
                                                            40;
                                                        var baseY =
                                                            currentBounds.y;
                                                        final occupiedRects =
                                                            board.panels
                                                                .where(
                                                                  (p) =>
                                                                      !p.hidden,
                                                                )
                                                                .map(
                                                                  (
                                                                    p,
                                                                  ) => Rect.fromLTWH(
                                                                    p.bounds.x,
                                                                    p.bounds.y,
                                                                    p
                                                                        .bounds
                                                                        .width,
                                                                    p
                                                                        .bounds
                                                                        .height,
                                                                  ),
                                                                )
                                                                .toList();
                                                        var candidate =
                                                            Rect.fromLTWH(
                                                              baseX,
                                                              baseY,
                                                              size.width,
                                                              size.height,
                                                            );
                                                        // Shift down until no overlap with existing panels.
                                                        var attempts = 0;
                                                        while (attempts < 50 &&
                                                            occupiedRects.any(
                                                              (r) => r.overlaps(
                                                                candidate,
                                                              ),
                                                            )) {
                                                          baseY +=
                                                              size.height + 20;
                                                          candidate =
                                                              Rect.fromLTWH(
                                                                baseX,
                                                                baseY,
                                                                size.width,
                                                                size.height,
                                                              );
                                                          attempts++;
                                                        }
                                                        final newBounds =
                                                            BoardPanelBounds(
                                                              x: baseX,
                                                              y: baseY,
                                                              width: size.width,
                                                              height:
                                                                  size.height,
                                                            );
                                                        final ts =
                                                            DateTime.now()
                                                                .microsecondsSinceEpoch;
                                                        final newPanel =
                                                            BoardPanelInstance(
                                                              id: 'panel-$ts',
                                                              type: typeId,
                                                              title: title,
                                                              bounds: newBounds,
                                                              state: state,
                                                              zIndex:
                                                                  board.panels.fold<
                                                                    int
                                                                  >(
                                                                    0,
                                                                    (v, p) =>
                                                                        p.zIndex >
                                                                                v
                                                                            ? p.zIndex
                                                                            : v,
                                                                  ) +
                                                                  1,
                                                            );
                                                        await cubit.addPanel(
                                                          newPanel,
                                                        );
                                                        await cubit.upsertLink(
                                                          BoardPanelLink(
                                                            id: 'link-$ts',
                                                            fromPanelId:
                                                                panel.id,
                                                            toPanelId:
                                                                newPanel.id,
                                                            style:
                                                                BoardLinkStyle
                                                                    .arrow,
                                                            behavior:
                                                                BoardLinkBehavior
                                                                    .dynamic,
                                                            geometry:
                                                                BoardLinkGeometry
                                                                    .bezier,
                                                          ),
                                                        );
                                                        return newPanel.id;
                                                      },
                                                      connectMode:
                                                          _activeTool ==
                                                          BoardToolId.connect,
                                                      connectSourceId:
                                                          _connectSourceId,
                                                      onConnectTap:
                                                          _activeTool ==
                                                                  BoardToolId
                                                                      .connect
                                                              ? () =>
                                                                  _handleConnectTap(
                                                                    context,
                                                                    activeBoard,
                                                                    panel.id,
                                                                  )
                                                              : null,
                                                    );
                                                  }).toList();
                                                })(),
                                                // ── Drawing layer (above panels visually;
                                                //    only intercepts gestures on actual stroke
                                                //    pixels via path-based hitTest) ──────────
                                                ...activeBoard.drawings
                                                    .where((d) => !d.hidden)
                                                    .map(
                                                      (drawing) => Positioned(
                                                        key: ValueKey(
                                                          drawing.id,
                                                        ),
                                                        left:
                                                            drawing
                                                                .position
                                                                .dx +
                                                            _canvasOrigin.dx,
                                                        top:
                                                            drawing
                                                                .position
                                                                .dy +
                                                            _canvasOrigin.dy,
                                                        width:
                                                            drawing.size.width,
                                                        height:
                                                            drawing.size.height,
                                                        child: IgnorePointer(
                                                          ignoring:
                                                              _activeTool ==
                                                              BoardToolId
                                                                  .connect,
                                                          child: BoardDrawingWidget(
                                                            drawing: drawing,
                                                            isSelectMode:
                                                                _activeTool ==
                                                                BoardToolId
                                                                    .select,
                                                            onMove:
                                                                (
                                                                  newPos,
                                                                ) => context
                                                                    .read<
                                                                      BoardCubit
                                                                    >()
                                                                    .moveDrawing(
                                                                      drawing
                                                                          .id,
                                                                      newPos,
                                                                    ),
                                                            onDelete:
                                                                () => context
                                                                    .read<
                                                                      BoardCubit
                                                                    >()
                                                                    .removeDrawing(
                                                                      drawing
                                                                          .id,
                                                                    ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                // ── Active stroke preview ─────────────────
                                                if (_activeStroke.isNotEmpty)
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      child: CustomPaint(
                                                        painter: ActiveStrokePainter(
                                                          points: _activeStroke,
                                                          origin: _canvasOrigin,
                                                          color:
                                                              _drawSettings
                                                                  .strokeColor,
                                                          strokeWidth:
                                                              _drawSettings
                                                                  .strokeWidth,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                // ── Connect preview line ──────────────────
                                                if (_activeTool ==
                                                        BoardToolId.connect &&
                                                    _connectSourceId != null &&
                                                    _connectPreviewPointer !=
                                                        null)
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      child: CustomPaint(
                                                        painter: ConnectPreviewPainter(
                                                          panels:
                                                              activeBoard
                                                                  .panels,
                                                          sourceId:
                                                              _connectSourceId!,
                                                          targetPoint:
                                                              _connectPreviewPointer!,
                                                          origin: _canvasOrigin,
                                                          color:
                                                              _connectSettings
                                                                  .color,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // ── WebView overlay ───────────────────────────────
                                  // Native platform views (WKWebView) inside
                                  // InteractiveViewer's Transform have coordinate
                                  // offset issues on macOS. Render live WebViews
                                  // outside the transform, positioned at each
                                  // panel's computed screen rect.
                                  Positioned.fill(
                                    child: _WebViewOverlays(
                                      panels: activeBoard.panels,
                                      focusedPanelId: focusedPanelId,
                                      transformController: _transformController,
                                      canvasOrigin: _canvasOrigin,
                                      isInteracting: _isViewportInteracting,
                                    ),
                                  ),
                                  // ── Draw gesture capture overlay ─────────────────
                                  // Uses Listener with translucent so InteractiveViewer
                                  // still receives trackpad scroll / pinch-to-zoom events.
                                  if (_activeTool == BoardToolId.draw)
                                    Positioned.fill(
                                      child: Listener(
                                        behavior: HitTestBehavior.translucent,
                                        onPointerDown: (e) {
                                          if (_drawPointer != null) return;
                                          final pt = _boardPointFromGlobal(
                                            e.position,
                                          );
                                          if (pt == null) return;
                                          setState(() {
                                            _drawPointer = e.pointer;
                                            _activeStroke
                                              ..clear()
                                              ..add(pt);
                                          });
                                        },
                                        onPointerMove: (e) {
                                          if (e.pointer != _drawPointer) return;
                                          final pt = _boardPointFromGlobal(
                                            e.position,
                                          );
                                          if (pt == null) return;
                                          setState(() => _activeStroke.add(pt));
                                        },
                                        onPointerUp: (e) {
                                          if (e.pointer != _drawPointer) return;
                                          _drawPointer = null;
                                          _finishDrawStroke(context);
                                        },
                                        onPointerCancel: (e) {
                                          if (e.pointer != _drawPointer) return;
                                          _drawPointer = null;
                                          setState(() => _activeStroke.clear());
                                        },
                                      ),
                                    ),
                                  // ── Connect tool pointer tracking ─────────────────
                                  // translucent so panel-tap GestureDetectors still fire.
                                  if (_activeTool == BoardToolId.connect &&
                                      _connectSourceId != null)
                                    Positioned.fill(
                                      child: Listener(
                                        behavior: HitTestBehavior.translucent,
                                        onPointerHover: (e) {
                                          final pt = _boardPointFromGlobal(
                                            e.position,
                                          );
                                          if (pt == null) return;
                                          setState(
                                            () => _connectPreviewPointer = pt,
                                          );
                                        },
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  if (activeBoard.panels.isEmpty)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        ignoring: false,
                                        child: Center(
                                          child: Container(
                                            width: 420,
                                            padding: const EdgeInsets.all(20),
                                            decoration: BoxDecoration(
                                              color: colors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: colors.divider,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: colors.background
                                                      .withAlpha(45),
                                                  blurRadius: 18,
                                                  offset: const Offset(0, 10),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons
                                                      .dashboard_customize_outlined,
                                                  size: 32,
                                                  color:
                                                      Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.color,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  'Board foundation is ready',
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Create named boards and start with markdown notes. '
                                                  'The first panel will open in a free slot, and links will support static and dynamic lines/arrows.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.color,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                FilledButton.icon(
                                                  onPressed:
                                                      () =>
                                                          _showMarkdownNoteDialog(
                                                            context,
                                                          ),
                                                  icon: const Icon(
                                                    Icons.note_add_outlined,
                                                  ),
                                                  label: const Text('Add note'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!_isBoardOverviewOpen &&
                                      !_isCapturingScreenshot)
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              OverlayIconButton(
                                                icon: Icons.fit_screen_outlined,
                                                tooltip: 'Fit board to content',
                                                onTap:
                                                    () => _fitBoardPanels(
                                                      activeBoard,
                                                      persist: true,
                                                    ),
                                              ),
                                              const SizedBox(width: 6),
                                              OverlayIconButton(
                                                icon:
                                                    _showMinimap
                                                        ? Icons.map
                                                        : Icons.map_outlined,
                                                tooltip:
                                                    _showMinimap
                                                        ? 'Hide minimap'
                                                        : 'Show minimap',
                                                active: _showMinimap,
                                                onTap:
                                                    () => setState(
                                                      () =>
                                                          _showMinimap =
                                                              !_showMinimap,
                                                    ),
                                              ),
                                            ],
                                          ),
                                          if (_showMinimap) ...[
                                            const SizedBox(height: 6),
                                            ValueListenableBuilder<int>(
                                              valueListenable:
                                                  ChatPanelWidget
                                                      .processingChangeNotifier,
                                              builder:
                                                  (
                                                    context,
                                                    _,
                                                    __,
                                                  ) => _BoardMiniMap(
                                                    panels: activeBoard.panels,
                                                    processingPanelIds:
                                                        ChatPanelWidget
                                                            .processingNotifiers
                                                            .entries
                                                            .where(
                                                              (e) =>
                                                                  e.value.value,
                                                            )
                                                            .map((e) => e.key)
                                                            .toSet(),
                                                    transformCtrl:
                                                        _transformController,
                                                    viewportSize:
                                                        _viewportSize ??
                                                        const Size(1, 1),
                                                    origin: _canvasOrigin,
                                                    onPanTo:
                                                        (center) =>
                                                            _centerViewportOn(
                                                              activeBoard,
                                                              center,
                                                              persist: true,
                                                            ),
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  if (!_isBoardOverviewOpen &&
                                      !_isCapturingScreenshot)
                                    Positioned(
                                      left: 12,
                                      top: 12,
                                      child: _BoardToolsPanel(
                                        board: activeBoard,
                                        platform: _currentPanelPlatform,
                                        visible: _showToolsPanel,
                                        activeTool: _activeTool,
                                        drawSettings: _drawSettings,
                                        connectSettings: _connectSettings,
                                        onToolChanged:
                                            (tool) => setState(() {
                                              _activeTool = tool;
                                              _activeStroke.clear();
                                              _connectSourceId = null;
                                              _connectPreviewPointer = null;
                                            }),
                                        onDrawSettingsChanged:
                                            (s) => setState(
                                              () => _drawSettings = s,
                                            ),
                                        onConnectSettingsChanged:
                                            (s) => setState(
                                              () => _connectSettings = s,
                                            ),
                                        historyPanelVisible: _showHistoryPanel,
                                        onToggle:
                                            () => setState(
                                              () =>
                                                  _showToolsPanel =
                                                      !_showToolsPanel,
                                            ),
                                        onUndo:
                                            () => _restoreLatestPanelHistory(
                                              context,
                                              activeBoard,
                                            ),
                                        onRedo: null,
                                        onShowHistory:
                                            () => setState(
                                              () =>
                                                  _showHistoryPanel =
                                                      !_showHistoryPanel,
                                            ),
                                        onAddNote:
                                            () => _showMarkdownNoteDialog(
                                              context,
                                            ),
                                        onAddChat: () => _addChatPanel(context),
                                        onAddTerminal:
                                            () => _addTerminalPanel(context),
                                        onAddGeneric:
                                            (typeId) =>
                                                _handleGenericToolSelection(
                                                  context,
                                                  typeId,
                                                ),
                                      ),
                                    ),
                                  if (!_isBoardOverviewOpen &&
                                      !_isCapturingScreenshot &&
                                      _showHistoryPanel)
                                    Positioned(
                                      top: 58,
                                      right: 12,
                                      bottom: 24,
                                      child: BoardHistoryPanel(
                                        board: activeBoard,
                                        onClose:
                                            () => setState(
                                              () => _showHistoryPanel = false,
                                            ),
                                      ),
                                    ),
                                  // ── Cancel connection button ───────────────────────
                                  if (!_isBoardOverviewOpen &&
                                      _activeTool == BoardToolId.connect &&
                                      _connectSourceId != null)
                                    Positioned(
                                      bottom: 24,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            onTap:
                                                () => setState(() {
                                                  _connectSourceId = null;
                                                  _connectPreviewPointer = null;
                                                }),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: colors.surfaceElevated
                                                    .withAlpha(220),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: colors.statusError
                                                      .withAlpha(160),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.close,
                                                    size: 14,
                                                    color: colors.statusError
                                                        .withAlpha(200),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Cancel connection  (Esc)',
                                                    style: TextStyle(
                                                      color: colors.statusError
                                                          .withAlpha(200),
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
                                  // ── YOLO badge removed from canvas stack ──────────────
                                ],
                              ),
                            ), // RepaintBoundary
                            if (_isBoardOverviewOpen)
                              Positioned.fill(
                                child: BoardOverviewLayer(
                                  activeBoardId: activeBoard.id,
                                  boards: state.boards,
                                  previewPngs: _boardPreviewPngs,
                                  debugLog: _boardOverviewLog,
                                  onDisconnectRemoteBoard:
                                      (board) => context
                                          .read<BoardCubit>()
                                          .disconnectRemoteBoard(board.id),
                                  onDeleteRemoteBoard:
                                      (board) => _deleteRemoteBoardOnServer(
                                        context,
                                        board,
                                      ),
                                  onDisconnectRemoteUrl:
                                      (url) => context
                                          .read<BoardCubit>()
                                          .disconnectRemoteBoardsForUrl(url),
                                  onClose: () {
                                    if (!mounted) return;
                                    _boardOverviewLog('close.parent');
                                    setState(() {
                                      _isBoardOverviewOpen = false;
                                      _cancelBgCapture = true;
                                    });
                                  },
                                  onCreateBoard: () {
                                    if (!mounted) return;
                                    _boardOverviewLog('create.parent');
                                    setState(() {
                                      _isBoardOverviewOpen = false;
                                      _cancelBgCapture = true;
                                    });
                                    _createBoard(context);
                                  },
                                  onSelectedBoard: (board, previewPng) {
                                    if (!mounted) return;
                                    final switchWatch = Stopwatch()..start();
                                    _boardOverviewLog(
                                      'select.parent.start board=${board.id} '
                                      'hasPng=${previewPng != null}',
                                    );
                                    setState(() {
                                      _isBoardOverviewOpen = false;
                                      _cancelBgCapture = true;
                                      _boardSwitchPreviewBoard = board;
                                      _boardSwitchPreviewPng = previewPng;
                                      _boardSwitchPreviewVisible = true;
                                    });
                                    _boardOverviewLog(
                                      'select.parent.previewVisible '
                                      'elapsed=${switchWatch.elapsedMilliseconds}ms',
                                    );
                                    context.read<BoardCubit>().setActiveBoard(
                                      board.id,
                                    );
                                    _boardOverviewLog(
                                      'select.parent.setActiveBoard.called '
                                      'elapsed=${switchWatch.elapsedMilliseconds}ms',
                                    );
                                    WidgetsBinding.instance.addPostFrameCallback((
                                      _,
                                    ) {
                                      _boardOverviewLog(
                                        'select.parent.postFrame '
                                        'elapsed=${switchWatch.elapsedMilliseconds}ms',
                                      );
                                      Future<void>.delayed(
                                        const Duration(milliseconds: 80),
                                        () {
                                          if (!mounted) return;
                                          _boardOverviewLog(
                                            'select.parent.fadeStart '
                                            'elapsed=${switchWatch.elapsedMilliseconds}ms',
                                          );
                                          setState(
                                            () =>
                                                _boardSwitchPreviewVisible =
                                                    false,
                                          );
                                        },
                                      );
                                    });
                                  },
                                ),
                              ),
                            if (_boardSwitchPreviewBoard != null)
                              Positioned.fill(
                                child: BoardSwitchPreviewOverlay(
                                  board: _boardSwitchPreviewBoard!,
                                  previewPng: _boardSwitchPreviewPng,
                                  visible: _boardSwitchPreviewVisible,
                                  onHidden: () {
                                    _boardOverviewLog(
                                      'switchPreview.hidden '
                                      'visible=$_boardSwitchPreviewVisible',
                                    );
                                    if (!mounted ||
                                        _boardSwitchPreviewVisible) {
                                      return;
                                    }
                                    setState(() {
                                      _boardSwitchPreviewBoard = null;
                                      _boardSwitchPreviewPng = null;
                                    });
                                  },
                                ),
                              ),
                            // ── YOLO badge fixed overlay (bottom-right) ────────────
                            if (!_isBoardOverviewOpen)
                              const Positioned(
                                left: 0,
                                right: 0,
                                bottom: 22,
                                child: _YoloBadgeWithChat(),
                              ),
                          ], // outer Stack children
                        ); // outer Stack
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ), // BlocBuilder
    ); // Focus
  }

  void _syncViewport(BoardDocument board) {
    final vp = board.viewport;
    final boardSwitched = _syncedBoardId != board.id;
    // Also re-apply when viewport changed externally (e.g. via CLI board:zoom)
    // while the user is not actively interacting.
    final externalChange =
        !boardSwitched &&
        _syncedViewport != null &&
        !_isViewportInteracting &&
        !_isPanelDragging &&
        (_syncedViewport!.scale != vp.scale ||
            _syncedViewport!.translation != vp.translation);

    if (!boardSwitched && !externalChange) return;
    _syncedBoardId = board.id;
    _syncedViewport = vp;
    if (boardSwitched) {
      // Suppress focus-panel auto-centering so the saved viewport is preserved.
      _suppressFocusVisibility = true;
    }
    _boardOverviewLog(
      'syncViewport board=${board.id} scale=${_fmt(vp.scale)} '
      'translation=${_fmtOffset(vp.translation)} '
      'isDefault=${_isDefaultViewport(vp)} '
      '${externalChange ? "(external)" : "(board switch)"}',
    );
    if (_shouldAutoFit(board)) {
      _boardDebugLog('syncViewport.scheduleAutoFit board=${board.id}');
      _scheduleAutoFitIfNeeded(board);
      return;
    }
    _stopPanAnimation();
    _transformController.value = _matrixFromViewport(vp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _syncedBoardId != board.id) return;
      if (_shouldAutoFit(board)) return;
      if (_hasVisiblePanels(board) && !_hasAnyPanelInViewport(board)) {
        _boardOverviewLog('syncViewport.recoverOffscreen board=${board.id}');
        _fitBoardPanels(board, persist: true);
      }
    });
  }

  Future<void> _persistViewport(BuildContext context, BoardDocument board) {
    final matrix = _transformController.value.storage;
    final scale = _scaleOf(_transformController.value);
    final translation = Offset(
      matrix[12] + (_canvasOrigin.dx * scale),
      matrix[13] + (_canvasOrigin.dy * scale),
    );
    _boardOverviewLog(
      'persistViewport board=${board.id} scale=${_fmt(scale)} '
      'translation=${_fmtOffset(translation)}',
    );
    final newVp = board.viewport.copyWith(
      scale: scale,
      translation: translation,
    );
    _syncedViewport = newVp; // track so external changes are detected correctly
    return context.read<BoardCubit>().updateViewport(newVp, boardId: board.id);
  }

  Future<void> _captureBoardPreviewPng(String boardId) async {
    final watch = Stopwatch()..start();
    _boardOverviewLog('capture.start board=$boardId pixelRatio=0.28');

    // Hide panel chrome (borders, accents, sidebar, minimap) so the
    // screenshot is clean — no purple-tinted decorations.
    setState(() => _isCapturingScreenshot = true);
    await WidgetsBinding.instance.endOfFrame;

    final bytes = await BoardScreenshotService.instance.capturePng(
      pixelRatio: 0.28,
    );

    // Restore decorations.
    if (mounted) setState(() => _isCapturingScreenshot = false);

    _boardOverviewLog(
      'capture.done board=$boardId '
      'bytes=${bytes?.length ?? 0} elapsed=${watch.elapsedMilliseconds}ms',
    );
    if (bytes == null || !mounted) {
      _boardOverviewLog(
        'capture.skipStore board=$boardId mounted=$mounted hasBytes=${bytes != null}',
      );
      return;
    }
    setState(() {
      _boardPreviewPngs[boardId] = bytes;
    });
    _boardOverviewLog(
      'capture.stored board=$boardId elapsed=${watch.elapsedMilliseconds}ms',
    );
    // Persist to disk so previews survive hot restart.
    _saveBoardPreviewPngToDisk(boardId, bytes);
  }

  static Directory get _previewCacheDir {
    final dir = Directory('${Directory.systemTemp.path}/yoloit_board_previews');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static File _previewFile(String boardId) =>
      File('${_previewCacheDir.path}/$boardId.png');

  void _saveBoardPreviewPngToDisk(String boardId, Uint8List bytes) {
    try {
      _previewFile(boardId).writeAsBytesSync(bytes);
    } catch (_) {
      // Best-effort — don't crash if disk write fails.
    }
  }

  void _loadBoardPreviewPngsFromDisk() {
    final boards = context.read<BoardCubit>().state.boards;
    for (final board in boards) {
      if (_boardPreviewPngs.containsKey(board.id)) continue;
      final file = _previewFile(board.id);
      if (file.existsSync()) {
        try {
          _boardPreviewPngs[board.id] = file.readAsBytesSync();
        } catch (_) {
          // Ignore corrupt/unreadable files.
        }
      }
    }
  }

  /// Generate a synthetic PNG preview for a board using dart:ui Canvas.
  /// Generate previews for boards that have no cached PNG using offscreen
  /// rendering. This is fast (no frame scheduling needed) and produces
  /// the same quality as the background refresh.
  Future<void> _generateMissingBoardPreviews(String activeBoardId) async {
    final allBoards = context.read<BoardCubit>().state.boards;
    final missing =
        allBoards
            .where(
              (b) =>
                  !_boardPreviewPngs.containsKey(b.id) && b.id != activeBoardId,
            )
            .toList();
    if (missing.isEmpty) return;

    _boardOverviewLog('offscreen.start count=${missing.length}');
    final watch = Stopwatch()..start();
    for (final board in missing) {
      if (!mounted) break;
      final png = await BoardOffscreenRenderer.instance.renderBoard(
        board,
        size: const Size(480, 320),
        pixelRatio: 1.0,
      );
      if (png != null && mounted) {
        _boardPreviewPngs[board.id] = png;
      }
    }
    _boardOverviewLog(
      'offscreen.done count=${missing.length} elapsed=${watch.elapsedMilliseconds}ms',
    );
  }

  /// Refresh board previews in the background using offscreen rendering.
  /// Each board is rendered independently from its data model — no board
  /// switching needed, no JSC crashes, no UI flicker.
  Future<void> _refreshBoardPreviewsInBackground(String activeBoardId) async {
    final allBoards = context.read<BoardCubit>().state.boards;
    final toCapture =
        allBoards
            .where((b) => b.id != activeBoardId && b.panels.isNotEmpty)
            .toList();
    if (toCapture.isEmpty) return;

    _boardOverviewLog('bgCapture.start count=${toCapture.length} (offscreen)');
    final watch = Stopwatch()..start();

    for (final board in toCapture) {
      if (_cancelBgCapture || !mounted || !_isBoardOverviewOpen) {
        _boardOverviewLog('bgCapture.canceled loop broken (transition active)');
        break;
      }

      final boardWatch = Stopwatch()..start();
      try {
        _boardOverviewLog(
          'bgCapture.render board=${board.id} (${board.name}) started',
        );
        final png = await BoardOffscreenRenderer.instance.renderBoard(board);
        if (_cancelBgCapture || !mounted || !_isBoardOverviewOpen) {
          _boardOverviewLog(
            'bgCapture.render board=${board.id} completed but discarded (transition active)',
          );
          break;
        }
        if (png != null) {
          setState(() {
            _boardPreviewPngs[board.id] = png;
          });
          _saveBoardPreviewPngToDisk(board.id, png);
          _boardOverviewLog(
            'bgCapture.captured board=${board.id} bytes=${png.length} elapsed=${boardWatch.elapsedMilliseconds}ms',
          );
        } else {
          _boardOverviewLog(
            'bgCapture.render board=${board.id} returned null elapsed=${boardWatch.elapsedMilliseconds}ms',
          );
        }
      } catch (e) {
        _boardOverviewLog(
          'bgCapture.error board=${board.id} $e elapsed=${boardWatch.elapsedMilliseconds}ms',
        );
      }
    }

    _boardOverviewLog('bgCapture.done elapsed=${watch.elapsedMilliseconds}ms');
  }

  Future<void> _openBoardOverview(BoardDocument activeBoard) async {
    final watch = Stopwatch()..start();
    _boardOverviewLog(
      'open.request board=${activeBoard.id} boards=${context.read<BoardCubit>().state.boards.length}',
    );
    try {
      await context.read<BoardCubit>().refreshRemoteBoards();
    } catch (error) {
      _boardOverviewLog('open.remoteRefresh.error $error');
    }
    if (!mounted) return;
    // Load real cached PNGs from disk (from previous CLI captures or sessions).
    _loadBoardPreviewPngsFromDisk();
    if (!widget.skipOverviewPreviewCapture) {
      // Capture a real screenshot of the active board.
      await _captureBoardPreviewPng(activeBoard.id);
      if (!mounted) return;
    }

    // Generate synthetic previews for boards still missing a PNG
    // (instant — just canvas drawing, no widget rendering).
    if (!widget.skipOverviewPreviewCapture) {
      await _generateMissingBoardPreviews(activeBoard.id);
      if (!mounted) return;
    }

    _boardOverviewLog(
      'open.showOverlay board=${activeBoard.id} elapsed=${watch.elapsedMilliseconds}ms',
    );
    setState(() {
      _isBoardOverviewOpen = true;
      _cancelBgCapture = false;
      _connectSourceId = null;
      _connectPreviewPointer = null;
    });

    // Refresh previews with real screenshots in the background.
    // The overview is already visible with synthetic/cached previews —
    // as each real screenshot arrives, the card updates live.
    if (!widget.skipOverviewPreviewCapture) {
      _refreshBoardPreviewsInBackground(activeBoard.id);
    }
  }

  Matrix4 _matrixFromViewport(BoardViewport viewport) {
    final scale = viewport.scale;
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, 1)
      ..setTranslationRaw(
        viewport.translation.dx - (_canvasOrigin.dx * scale),
        viewport.translation.dy - (_canvasOrigin.dy * scale),
        0,
      );
  }

  bool _isDefaultViewport(BoardViewport viewport) {
    return viewport.scale == 1.0 &&
        viewport.translation == Offset.zero &&
        viewport.focusedPanelId == null;
  }

  bool _shouldAutoFit(BoardDocument board) {
    final result =
        _viewportSize != null &&
        _isDefaultViewport(board.viewport) &&
        board.panels.any((panel) => !panel.hidden);
    if (result) {
      _boardOverviewLog(
        'shouldAutoFit=true board=${board.id} '
        'vpScale=${_fmt(board.viewport.scale)} '
        'vpTx=${_fmtOffset(board.viewport.translation)}',
      );
    }
    return result;
  }

  void _scheduleAutoFitIfNeeded(BoardDocument board) {
    if (!_shouldAutoFit(board)) return;
    final size = _viewportSize;
    if (size == null) return;
    final key =
        '${board.id}:${board.panels.where((panel) => !panel.hidden).length}:${size.width}:${size.height}';
    if (_autoFitKey == key) return;
    _autoFitKey = key;
    _boardDebugLog('autoFit.scheduled key=$key');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitBoardPanels(board, persist: true);
    });
  }

  void _scheduleFocusedPanelVisibilityIfNeeded(BoardDocument board) {
    final focusedPanelId = board.viewport.focusedPanelId;
    final size = _viewportSize;
    if (focusedPanelId == null || size == null || _shouldAutoFit(board)) return;
    if (_isPanelDragging || _isViewportInteracting) {
      return;
    }
    if (_suppressFocusVisibility) {
      _suppressFocusVisibility = false;
      // Set the key to match so subsequent rebuilds don't re-schedule.
      BoardPanelInstance? fp;
      for (final entry in board.panels) {
        if (entry.id == focusedPanelId) {
          fp = entry;
          break;
        }
      }
      if (fp != null) {
        _focusedPanelVisibilityKey =
            '${board.id}:${fp.id}:${fp.bounds.x}:${fp.bounds.y}:${fp.bounds.width}:${fp.bounds.height}:${size.width}:${size.height}:z${board.viewport.zoomOnFocus}';
      }
      _boardOverviewLog('focusVisibility.suppressed (board switch)');
      return;
    }
    BoardPanelInstance? panel;
    for (final entry in board.panels) {
      if (entry.id == focusedPanelId) {
        panel = entry;
        break;
      }
    }
    if (panel == null || panel.hidden) return;
    final resolvedPanel = panel;
    final shouldZoom = board.viewport.zoomOnFocus;
    final key =
        '${board.id}:${resolvedPanel.id}:${resolvedPanel.bounds.x}:${resolvedPanel.bounds.y}:${resolvedPanel.bounds.width}:${resolvedPanel.bounds.height}:${size.width}:${size.height}:z$shouldZoom';
    if (_focusedPanelVisibilityKey == key) return;
    _focusedPanelVisibilityKey = key;
    _boardOverviewLog(
      'focusVisibility.scheduled panel=${resolvedPanel.id} zoom=$shouldZoom',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isPanelDragging || _isViewportInteracting) {
        return;
      }
      if (shouldZoom) {
        _boardOverviewLog(
          'focusVisibility.zoomToPanel panel=${resolvedPanel.id}',
        );
        _zoomToPanel(board, resolvedPanel.bounds.rect);
        return;
      }
      if (_isPanelComfortablyVisible(resolvedPanel.bounds.rect)) {
        _boardOverviewLog(
          'focusVisibility.alreadyVisible panel=${resolvedPanel.id}',
        );
        return;
      }
      _boardOverviewLog('focusVisibility.center panel=${resolvedPanel.id}');
      _centerViewportOn(board, resolvedPanel.bounds.rect.center, persist: true);
    });
  }

  void _fitBoardPanels(BoardDocument board, {required bool persist}) {
    final screen = _viewportSize ?? MediaQuery.sizeOf(context);
    if (screen.isEmpty) return;
    final visiblePanels = board.panels.where((panel) => !panel.hidden).toList();
    if (visiblePanels.isEmpty) {
      _boardDebugLog('fitBoardPanels.empty persist=$persist');
      _animateToMatrix(Matrix4.identity(), board: board, persist: persist);
      if (persist) {
        _focusedPanelVisibilityKey = null;
      }
      return;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    for (final panel in visiblePanels) {
      final rect = panel.bounds.rect;
      if (rect.left < minX) minX = rect.left;
      if (rect.top < minY) minY = rect.top;
      if (rect.right > maxX) maxX = rect.right;
      if (rect.bottom > maxY) maxY = rect.bottom;
    }

    const padding = 120.0;
    final spanW = (maxX - minX) + (padding * 2);
    final spanH = (maxY - minY) + (padding * 2);
    final scale = math
        .min(screen.width / spanW, screen.height / spanH)
        .clamp(0.2, 0.95);
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final tx = centerX - screen.width / (2 * scale);
    final ty = centerY - screen.height / (2 * scale);
    _boardDebugLog(
      'fitBoardPanels scale=${_fmt(scale)} topLeft=${_fmtOffset(Offset(tx, ty))} '
      'screen=${_fmtSize(screen)} panels=${visiblePanels.length} persist=$persist',
    );
    _animateToMatrix(
      _matrixForBoardTopLeft(scale: scale, topLeft: Offset(tx, ty)),
      board: board,
      persist: persist,
    );
  }

  void _centerViewportOn(
    BoardDocument board,
    Offset canvasCenter, {
    required bool persist,
  }) {
    final screen = _viewportSize ?? MediaQuery.sizeOf(context);
    if (screen.isEmpty) return;
    final scale = _scaleOf(_transformController.value);
    final tx = canvasCenter.dx - screen.width / (2 * scale);
    final ty = canvasCenter.dy - screen.height / (2 * scale);
    _boardDebugLog(
      'centerViewportOn center=${_fmtOffset(canvasCenter)} scale=${_fmt(scale)} '
      'topLeft=${_fmtOffset(Offset(tx, ty))} persist=$persist',
    );
    _animateToMatrix(
      _matrixForBoardTopLeft(scale: scale, topLeft: Offset(tx, ty)),
      board: board,
      persist: persist,
    );
  }

  /// Zooms the viewport so [panelRect] fills ~70% of the screen width,
  /// then centers it. Used when focus is triggered via CLI/voice commands.
  void _zoomToPanel(BoardDocument board, Rect panelRect) {
    final screen = _viewportSize ?? MediaQuery.sizeOf(context);
    if (screen.isEmpty) return;

    const targetFill = 0.70; // panel should occupy ~70% of screen width
    const minScale = 0.40;
    const maxScale = 2.0;

    final scaleX = screen.width * targetFill / panelRect.width;
    final scaleY = screen.height * targetFill / panelRect.height;
    // Use the smaller scale so the whole panel is visible, but don't exceed max
    final targetScale = math.min(scaleX, scaleY).clamp(minScale, maxScale);

    final centerX = panelRect.center.dx;
    final centerY = panelRect.center.dy;
    final tx = centerX - screen.width / (2 * targetScale);
    final ty = centerY - screen.height / (2 * targetScale);

    _boardDebugLog(
      'zoomToPanel panelRect=${panelRect.shortestSide.toStringAsFixed(0)} '
      'scale=${_fmt(targetScale)} center=${_fmtOffset(panelRect.center)} persist=true',
    );
    _animateToMatrix(
      _matrixForBoardTopLeft(scale: targetScale, topLeft: Offset(tx, ty)),
      board: board,
      persist: true,
    );
    // Clear the zoom-on-focus flag so we don't re-zoom on next rebuild.
    context.read<BoardCubit>().clearZoomFocus();
  }

  Matrix4 _matrixForBoardTopLeft({
    required double scale,
    required Offset topLeft,
  }) {
    return Matrix4.identity()
      ..scale(scale)
      ..translate(
        -(topLeft.dx + _canvasOrigin.dx),
        -(topLeft.dy + _canvasOrigin.dy),
      );
  }

  void _movePanelWithEdgePan(
    BuildContext context,
    String panelId,
    DragUpdateDetails details,
  ) {
    _panViewportNearEdge(details.globalPosition);
    final delta = _consumePanelDragDelta(details.globalPosition, details.delta);
    context.read<BoardCubit>().movePanel(panelId, delta);
  }

  void _resizePanelWithEdgePan(
    BuildContext context,
    BoardPanelInstance panel,
    _BoardPanelResizeUpdate update,
  ) {
    _panViewportNearEdge(update.globalPosition);
    final delta = _consumePanelDragDelta(update.globalPosition, update.delta);
    final next = _resizeBoundsForHandle(panel, update.handle, delta);
    context.read<BoardCubit>().updatePanel(
      panel.id,
      (p) => p.copyWith(bounds: next),
    );
  }

  BoardPanelBounds _resizeBoundsForHandle(
    BoardPanelInstance panel,
    _BoardPanelResizeHandle handle,
    Offset delta,
  ) {
    const minWidth = 220.0;
    const minHeight = 140.0;
    final maxWidth =
        panel.type == WebpagePlugin.kTypeId ? 1440.0 : double.infinity;

    var x = panel.bounds.x;
    var y = panel.bounds.y;
    var width = panel.bounds.width;
    var height = panel.bounds.height;

    if (handle.affectsLeft) {
      final proposedWidth = (width - delta.dx).clamp(minWidth, maxWidth);
      x += width - proposedWidth;
      width = proposedWidth;
    }
    if (handle.affectsRight) {
      width = (width + delta.dx).clamp(minWidth, maxWidth);
    }
    if (handle.affectsTop) {
      final proposedHeight = math.max(minHeight, height - delta.dy);
      y += height - proposedHeight;
      height = proposedHeight;
    }
    if (handle.affectsBottom) {
      height = math.max(minHeight, height + delta.dy);
    }

    return panel.bounds.copyWith(x: x, y: y, width: width, height: height);
  }

  void _handlePanelDragStart(String panelId, DragStartDetails details) {
    _isPanelDragging = true;
    _lastPanelDragBoardPointer = _boardPointFromGlobal(details.globalPosition);
    _boardDebugLog('panelDrag.start panel=$panelId');
    _stopPanAnimation();
  }

  void _handlePanelDragEnd() {
    _boardDebugLog('panelDrag.end');
    _isPanelDragging = false;
    _lastPanelDragBoardPointer = null;
    final board = context.read<BoardCubit>().state.activeBoard;
    if (board != null) {
      _persistViewport(context, board);
    }
    _scheduleCanvasExpansionIfNeeded();
  }

  void _handleGenericToolSelection(BuildContext context, String value) {
    if (value.startsWith('__connector:')) {
      final parts = value.split(':');
      final geometryName = parts.length > 1 ? parts[1] : 'bezier';
      final showArrow = parts.length <= 2 || parts[2] != 'line';
      final geometry = switch (geometryName) {
        'straight' => BoardLinkGeometry.straight,
        'elbow' => BoardLinkGeometry.elbow,
        _ => BoardLinkGeometry.bezier,
      };
      setState(() {
        _activeTool = BoardToolId.connect;
        _connectSettings = _connectSettings.copyWith(
          geometry: geometry,
          showArrow: showArrow,
        );
        _activeStroke.clear();
        _connectSourceId = null;
        _connectPreviewPointer = null;
      });
      return;
    }

    if (value.startsWith('__shape:')) {
      final shape = value.substring('__shape:'.length);
      final title = switch (shape) {
        'circle' => 'Oval',
        'diamond' => 'Rhombus',
        'frame' => 'Frame',
        _ => '${shape[0].toUpperCase()}${shape.substring(1)}',
      };
      context.read<BoardCubit>().createGenericPanel(
        'board.shape',
        title: title,
        panelState: {'shape': shape},
      );
      return;
    }

    if (value == '__divider') {
      context.read<BoardCubit>().createGenericPanel(
        'board.shape',
        title: 'Divider',
        panelState: {'shape': 'frame', 'text': '', 'strokeWidth': 2.0},
        preferredSize: const Size(320, 44),
      );
      return;
    }

    context.read<BoardCubit>().createGenericPanel(value);
  }

  Future<void> _restoreLatestPanelHistory(
    BuildContext context,
    BoardDocument board,
  ) async {
    final cubit = context.read<BoardCubit>();
    final undone = await cubit.undoLatestPanelHistory(board.id);
    if (!undone) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No restorable panel history yet')),
      );
    }
  }

  Offset _consumePanelDragDelta(Offset globalPosition, Offset fallbackDelta) {
    final previous = _lastPanelDragBoardPointer;
    final current = _boardPointFromGlobal(globalPosition);
    if (previous == null || current == null) {
      _lastPanelDragBoardPointer = current;
      return fallbackDelta;
    }
    _lastPanelDragBoardPointer = current;
    final delta = current - previous;
    _boardDebugLog(
      'panelDrag.delta pointer=${_fmtOffset(current)} delta=${_fmtOffset(delta)} fallback=${_fmtOffset(fallbackDelta)}',
    );
    return delta;
  }

  Offset? _boardPointFromGlobal(Offset globalPosition) {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final local = renderObject.globalToLocal(globalPosition);
    return _boardPointFromCanvasScene(_transformController.toScene(local));
  }

  void _panViewportNearEdge(Offset globalPosition) {
    final viewport = _viewportSize;
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (viewport == null ||
        viewport.isEmpty ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return;
    }

    final local = renderObject.globalToLocal(globalPosition);
    final screenDelta = Offset(
      _edgePanStep(local.dx, viewport.width),
      _edgePanStep(local.dy, viewport.height),
    );
    if (screenDelta == Offset.zero) return;

    final scale = _scaleOf(_transformController.value);
    if (scale == 0) return;

    final matrix = _transformController.value.clone();
    final storage = matrix.storage;
    storage[12] -= screenDelta.dx;
    storage[13] -= screenDelta.dy;
    _transformController.value = matrix;

    _boardDebugLog(
      'edgePan local=${_fmtOffset(local)} screenDelta=${_fmtOffset(screenDelta)} '
      'boardDelta=${_fmtOffset(screenDelta / scale)} scale=${_fmt(scale)}',
    );
  }

  double _edgePanStep(double position, double extent) {
    if (extent <= 0) return 0;
    if (position < _edgePanZone) {
      final t = ((_edgePanZone - position) / _edgePanZone).clamp(0.0, 1.0);
      return -_edgePanMaxStep * Curves.easeOut.transform(t);
    }
    if (extent - position < _edgePanZone) {
      final t = ((_edgePanZone - (extent - position)) / _edgePanZone).clamp(
        0.0,
        1.0,
      );
      return _edgePanMaxStep * Curves.easeOut.transform(t);
    }
    return 0;
  }

  void _scheduleCanvasExpansionIfNeeded() {
    if (_canvasExpansionScheduled ||
        _viewportSize == null ||
        _isPanelDragging) {
      return;
    }
    _canvasExpansionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _canvasExpansionScheduled = false;
      if (!mounted) return;
      _expandCanvasIfNeeded();
    });
  }

  void _expandCanvasIfNeeded() {
    final viewport = _viewportSize;
    if (viewport == null || viewport.isEmpty) return;

    final visible = Rect.fromPoints(
      _transformController.toScene(Offset.zero),
      _transformController.toScene(Offset(viewport.width, viewport.height)),
    );

    var addLeft = 0.0;
    var addTop = 0.0;
    var addRight = 0.0;
    var addBottom = 0.0;

    if (visible.left < _canvasExpansionMargin) {
      addLeft = _canvasExpansionChunk;
    }
    if (visible.top < _canvasExpansionMargin) {
      addTop = _canvasExpansionChunk;
    }
    if (_canvasSize.width - visible.right < _canvasExpansionMargin) {
      addRight = _canvasExpansionChunk;
    }
    if (_canvasSize.height - visible.bottom < _canvasExpansionMargin) {
      addBottom = _canvasExpansionChunk;
    }

    if (addLeft == 0 && addTop == 0 && addRight == 0 && addBottom == 0) {
      return;
    }

    final scale = _scaleOf(_transformController.value);
    final matrix = _transformController.value.clone();
    final storage = matrix.storage;
    storage[12] -= addLeft * scale;
    storage[13] -= addTop * scale;

    _boardDebugLog(
      'canvas.expand visible=${_fmtRect(visible)} add=(${_fmt(addLeft)}, ${_fmt(addTop)}, ${_fmt(addRight)}, ${_fmt(addBottom)}) '
      'oldSize=${_fmtSize(_canvasSize)} oldOrigin=${_fmtOffset(_canvasOrigin)} scale=${_fmt(scale)}',
    );
    setState(() {
      _canvasSize = Size(
        _canvasSize.width + addLeft + addRight,
        _canvasSize.height + addTop + addBottom,
      );
      _canvasOrigin += Offset(addLeft, addTop);
      _transformController.value = matrix;
    });
    _boardDebugLog(
      'canvas.expanded newSize=${_fmtSize(_canvasSize)} newOrigin=${_fmtOffset(_canvasOrigin)}',
    );
  }

  void _animateToMatrix(
    Matrix4 target, {
    required BoardDocument board,
    required bool persist,
  }) {
    _boardDebugLog(
      'animateToMatrix board=${board.id} persist=$persist '
      'from=${_fmtMatrix(_transformController.value)} to=${_fmtMatrix(target)}',
    );
    _stopPanAnimation();
    final animation = Matrix4Tween(
      begin: _transformController.value.clone(),
      end: target,
    ).animate(
      CurvedAnimation(parent: _panController, curve: Curves.easeInOutCubic),
    );
    _panAnimation = animation;
    _panAnimationListener = () {
      _transformController.value = animation.value;
    };
    _panStatusListener = (status) {
      _boardDebugLog('panAnimation.status=$status persist=$persist');
      if (status == AnimationStatus.completed && persist && mounted) {
        _persistViewport(context, board);
      }
    };
    animation.addListener(_panAnimationListener!);
    _panController.addStatusListener(_panStatusListener!);
    _panController.forward(from: 0);
  }

  void _stopPanAnimation() {
    if (_panAnimation != null || _panController.isAnimating) {
      _boardDebugLog('panAnimation.stop');
    }
    _panController.stop();
    final animation = _panAnimation;
    final listener = _panAnimationListener;
    if (animation != null && listener != null) {
      animation.removeListener(listener);
    }
    final statusListener = _panStatusListener;
    if (statusListener != null) {
      _panController.removeStatusListener(statusListener);
    }
    _panAnimation = null;
    _panAnimationListener = null;
    _panStatusListener = null;
  }

  bool _isPanelComfortablyVisible(Rect panelRect) {
    final size = _viewportSize;
    if (size == null || size.isEmpty) return false;
    final viewportRect = Rect.fromPoints(
      _boardPointFromCanvasScene(_transformController.toScene(Offset.zero)),
      _boardPointFromCanvasScene(
        _transformController.toScene(Offset(size.width, size.height)),
      ),
    );
    final comfortRect = viewportRect.deflate(48);
    if (comfortRect.isEmpty) {
      return viewportRect.contains(panelRect.center);
    }
    return comfortRect.contains(panelRect.topLeft) &&
        comfortRect.contains(panelRect.topRight) &&
        comfortRect.contains(panelRect.bottomLeft) &&
        comfortRect.contains(panelRect.bottomRight);
  }

  bool _hasVisiblePanels(BoardDocument board) =>
      board.panels.any((panel) => !panel.hidden);

  bool _hasAnyPanelInViewport(BoardDocument board) {
    final size = _viewportSize;
    if (size == null || size.isEmpty) return true;
    final tl = _boardPointFromCanvasScene(
      _transformController.toScene(Offset.zero),
    );
    final br = _boardPointFromCanvasScene(
      _transformController.toScene(Offset(size.width, size.height)),
    );
    final viewportRect = Rect.fromLTRB(
      math.min(tl.dx, br.dx),
      math.min(tl.dy, br.dy),
      math.max(tl.dx, br.dx),
      math.max(tl.dy, br.dy),
    );
    for (final panel in board.panels) {
      if (panel.hidden) continue;
      if (panel.bounds.rect.overlaps(viewportRect)) return true;
    }
    return false;
  }

  Offset _boardPointFromCanvasScene(Offset scenePoint) {
    return scenePoint - _canvasOrigin;
  }

  void _boardDebugLog(String message) {
    if (!kDebugMode || !const bool.fromEnvironment('YOLOIT_BOARD_DEBUG')) {
      return;
    }
    debugPrint('[BoardView] $message');
  }

  void _boardSupportLog(String message) {
    SupportLogService.instance.add('board-scroll', message);
  }

  void _boardOverviewLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[BoardOverview] $message');
  }

  void _boardWebFocusLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[BoardWebFocus] $message');
  }

  String _fmt(double value) => value.toStringAsFixed(2);

  String _fmtOffset(Offset offset) =>
      '(${_fmt(offset.dx)}, ${_fmt(offset.dy)})';

  String _fmtSize(Size size) => '${_fmt(size.width)}x${_fmt(size.height)}';

  String _fmtRect(Rect rect) =>
      'l=${_fmt(rect.left)} t=${_fmt(rect.top)} r=${_fmt(rect.right)} b=${_fmt(rect.bottom)}';

  String _fmtMatrix(Matrix4 matrix) {
    final storage = matrix.storage;
    return 'scale=${_fmt(_scaleOf(matrix))} t=${_fmtOffset(Offset(storage[12], storage[13]))}';
  }

  // ── Tool actions ──────────────────────────────────────────────────────────

  /// Builds small ×-badge widgets at the midpoint of each link so the user
  /// can delete them by tapping.
  List<Widget> _buildLinkDeleteBadges(
    BuildContext context,
    BoardDocument board,
  ) {
    final colors = context.appColors;
    final panelMap = {for (final p in board.panels) p.id: p};
    final badges = <Widget>[];
    for (final link in board.links) {
      final from = panelMap[link.fromPanelId];
      final to = panelMap[link.toPanelId];
      if (from == null || to == null || from.hidden || to.hidden) continue;

      // Use edge-to-edge points (same as painter) for accurate midpoint
      final fromRect = from.bounds.rect.translate(
        _canvasOrigin.dx,
        _canvasOrigin.dy,
      );
      final toRect = to.bounds.rect.translate(
        _canvasOrigin.dx,
        _canvasOrigin.dy,
      );
      final start = BoardLinksPainter.edgePointToward(fromRect, toRect.center);
      final end = BoardLinksPainter.edgePointToward(toRect, fromRect.center);
      final mid = _linkMidpoint(start, end, link.geometry);

      // Large transparent hit area so mouse-over the line is easy to trigger
      const hitR = 24.0;
      const badgeR = 11.0;
      final isHovered = _hoveredLinkId == link.id;
      final linkColor = link.color ?? colors.accentBlue;
      badges.add(
        Positioned(
          left: mid.dx - hitR,
          top: mid.dy - hitR,
          width: hitR * 2,
          height: hitR * 2,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredLinkId = link.id),
            onExit:
                (_) => setState(() {
                  if (_hoveredLinkId == link.id) _hoveredLinkId = null;
                }),
            child: Center(
              child: GestureDetector(
                onTap: () => context.read<BoardCubit>().removeLink(link.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isHovered ? badgeR * 2 : 8,
                  height: isHovered ? badgeR * 2 : 8,
                  decoration: BoxDecoration(
                    color:
                        isHovered
                            ? colors.statusError.withAlpha(204)
                            : linkColor.withAlpha(100),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isHovered
                              ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(80)
                              : linkColor.withAlpha(50),
                      width: 1,
                    ),
                  ),
                  child:
                      isHovered
                          ? Icon(
                            Icons.close,
                            size: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          )
                          : null,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return badges;
  }

  /// Returns the midpoint of the link curve between [start] and [end].
  static Offset _linkMidpoint(
    Offset start,
    Offset end,
    BoardLinkGeometry geometry,
  ) {
    switch (geometry) {
      case BoardLinkGeometry.straight:
        return Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      case BoardLinkGeometry.elbow:
        // Mid of the elbow corner
        return Offset(end.dx, start.dy);
      case BoardLinkGeometry.bezier:
        // Sample cubic bezier at t=0.5
        final cx1 = start.dx + (end.dx - start.dx) * 0.35;
        final cy1 = start.dy;
        final cx2 = end.dx - (end.dx - start.dx) * 0.35;
        final cy2 = end.dy;
        const t = 0.5;
        const mt = 1 - t;
        return Offset(
          mt * mt * mt * start.dx +
              3 * mt * mt * t * cx1 +
              3 * mt * t * t * cx2 +
              t * t * t * end.dx,
          mt * mt * mt * start.dy +
              3 * mt * mt * t * cy1 +
              3 * mt * t * t * cy2 +
              t * t * t * end.dy,
        );
    }
  }

  void _finishDrawStroke(BuildContext context) {
    if (_activeStroke.length < 2) {
      setState(() => _activeStroke.clear());
      return;
    }
    final drawing = BoardDrawingElement.fromRawStroke(
      id: 'draw_${DateTime.now().millisecondsSinceEpoch}',
      rawPoints: List.of(_activeStroke),
      strokeColor: _drawSettings.strokeColor,
      strokeWidth: _drawSettings.strokeWidth,
    );
    context.read<BoardCubit>().addDrawing(drawing);
    setState(() => _activeStroke.clear());
  }

  Future<void> _handleConnectTap(
    BuildContext context,
    BoardDocument board,
    String panelId,
  ) async {
    if (_connectSourceId == null) {
      setState(() {
        _connectSourceId = panelId;
        _connectPreviewPointer = null;
      });
      return;
    }
    if (_connectSourceId == panelId) {
      setState(() {
        _connectSourceId = null;
        _connectPreviewPointer = null;
      });
      return;
    }
    // Show style picker then create link
    final style = await _showConnectStyleDialog(context);
    if (style == null) {
      setState(() {
        _connectSourceId = null;
        _connectPreviewPointer = null;
      });
      return;
    }
    final link = BoardPanelLink(
      id: 'link_${DateTime.now().millisecondsSinceEpoch}',
      fromPanelId: _connectSourceId!,
      toPanelId: panelId,
      style: style.showArrow ? BoardLinkStyle.arrow : BoardLinkStyle.line,
      behavior: BoardLinkBehavior.fixed,
      color: style.color,
      geometry: style.geometry,
    );
    if (!context.mounted) return;
    context.read<BoardCubit>().upsertLink(link);
    setState(() {
      _connectSourceId = null;
      _connectPreviewPointer = null;
    });
  }

  Future<LinkStyleChoice?> _showConnectStyleDialog(
    BuildContext context,
  ) async {
    return showAdaptiveYoloDialog<LinkStyleChoice>(
      context: context,
      builder: (ctx) => LinkStyleDialog(initialSettings: _connectSettings),
    );
  }

  Future<void> _createBoard(BuildContext context) async {
    final name = await _showTextDialog(
      context,
      title: 'Create board',
      label: 'Board name',
      initialValue: '',
      confirmLabel: 'Create',
    );
    if (!context.mounted) return;
    await context.read<BoardCubit>().createBoard(name: name);
  }

  Future<void> _connectRemoteYoloit(BuildContext context) async {
    final result = await showAdaptiveYoloDialog<RemoteYoloitConnection>(
      context: context,
      builder: (_) => const ConnectRemoteYoloitDialog(),
    );
    if (!context.mounted || result == null) return;
    try {
      final boards = await context.read<BoardCubit>().connectRemoteBoards(
        url: result.url,
        token: result.token,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connected ${boards.length} remote board${boards.length == 1 ? '' : 's'}',
          ),
        ),
      );
      final activeBoard = context.read<BoardCubit>().state.activeBoard;
      if (activeBoard != null) {
        await _openBoardOverview(activeBoard);
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remote YoLoIT connection failed: $error')),
      );
    }
  }

  Future<void> _shareBoard(BuildContext context) async {
    try {
      final info = await BoardShareServer.instance.start(
        context.read<BoardCubit>(),
      );
      if (!context.mounted) return;
      await showAdaptiveYoloDialog<void>(
        context: context,
        builder: (_) => ShareBoardDialog(info: info),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Board share failed: $error')));
    }
  }

  Future<void> _showBoardSettings(
    BuildContext context,
    BoardDocument board,
  ) async {
    final remote = remoteInfoForBoard(board);
    final result =
        await showAdaptiveYoloDialog<({String name, String defaultFolder})>(
          context: context,
          builder:
              (_) => BoardSettingsDialog(
                initialName: board.name,
                initialDefaultFolder: board.defaultFolder,
                remoteInfo: remote,
              ),
        );
    if (!context.mounted || result == null) return;
    final cubit = context.read<BoardCubit>();
    await cubit.renameBoard(board.id, result.name);
    await cubit.updateBoardDefaultFolder(board.id, result.defaultFolder);
  }

  Future<void> _openBoardSearch(BuildContext context) {
    return showFileSearch(context, onFileOpened: () {});
  }

  Future<void> _deleteBoard(BuildContext context, BoardDocument board) async {
    if (isRemoteBoard(board)) {
      await _disconnectRemoteBoard(context, board);
      return;
    }
    final shouldDelete = await showAdaptiveYoloDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete board?'),
            content: Text('Delete "${board.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (!context.mounted || shouldDelete != true) return;
    await context.read<BoardCubit>().deleteBoard(board.id);
  }

  Future<void> _disconnectRemoteBoard(
    BuildContext context,
    BoardDocument board,
  ) async {
    final shouldDisconnect = await showAdaptiveYoloDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Disconnect remote board?'),
            content: Text(
              'Remove "${board.name}" from this device only? '
              'The board will remain on the remote YoLoIT server.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Disconnect'),
              ),
            ],
          ),
    );
    if (!context.mounted || shouldDisconnect != true) return;
    await context.read<BoardCubit>().disconnectRemoteBoard(board.id);
  }

  Future<void> _deleteRemoteBoardOnServer(
    BuildContext context,
    BoardDocument board,
  ) async {
    final remote = remoteInfoForBoard(board);
    if (remote == null) return;
    final remoteLabel = Uri.tryParse(remote.url)?.authority ?? remote.url;
    final shouldDelete = await showAdaptiveYoloDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete remote board?'),
            content: Text(
              'Delete "${board.name}" from $remoteLabel? '
              'This removes it from the remote machine for everyone connected to that server.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.appColors.accentRed,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete remote'),
              ),
            ],
          ),
    );
    if (!context.mounted || shouldDelete != true) return;
    await context.read<BoardCubit>().deleteRemoteBoardOnServer(board.id);
  }

  void _addChatPanel(BuildContext context) {
    context.read<BoardCubit>().createChatPanel();
  }

  void _addTerminalPanel(BuildContext context) {
    context.read<BoardCubit>().createTerminalPanel();
  }

  VoidCallback? _editPanelCallback(
    BuildContext context,
    BoardPanelInstance panel,
  ) {
    if (panel.type == 'board.note.markdown') {
      return () => _showMarkdownNoteDialog(context, panel: panel);
    }
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    if (plugin?.hasEditor != true) return null;
    return () async {
      await plugin!.showEditor(context, panel, (newState) {
        context.read<BoardCubit>().updatePanel(
          panel.id,
          (p) => p.copyWith(state: newState),
        );
      });
    };
  }

  Future<void> _showMarkdownNoteDialog(
    BuildContext context, {
    BoardPanelInstance? panel,
  }) async {
    final initialTitle = panel?.title ?? 'Note';
    final initialMarkdown = panel?.state['markdown'] as String? ?? '';
    Color? selectedColor = panel?.color;
    final titleController = TextEditingController(text: initialTitle);
    final markdownController = TextEditingController(text: initialMarkdown);
    final result = await showAdaptiveYoloDialog<
      ({String title, String markdown, Color? color})
    >(
      context: context,
      builder: (dialogContext) {
        var isPreview = false;
        return AlertDialog(
          title: Text(
            panel == null ? 'Add markdown note' : 'Edit markdown note',
          ),
          content: SizedBox(
            width: 760,
            child: StatefulBuilder(
              builder:
                  (context, setDialogState) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          MarkdownToolButton(
                            icon: Icons.title,
                            tooltip: 'Heading',
                            onTap: () {
                              _prefixSelectedLines(markdownController, '# ');
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.format_bold,
                            tooltip: 'Bold',
                            onTap: () {
                              _wrapSelection(
                                markdownController,
                                before: '**',
                                after: '**',
                                placeholder: 'bold',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.format_italic,
                            tooltip: 'Italic',
                            onTap: () {
                              _wrapSelection(
                                markdownController,
                                before: '*',
                                after: '*',
                                placeholder: 'italic',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.format_list_bulleted,
                            tooltip: 'Bullet list',
                            onTap: () {
                              _prefixSelectedLines(markdownController, '- ');
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.check_box_outlined,
                            tooltip: 'Checklist',
                            onTap: () {
                              _prefixSelectedLines(
                                markdownController,
                                '- [ ] ',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.link,
                            tooltip: 'Link',
                            onTap: () {
                              _wrapSelection(
                                markdownController,
                                before: '[',
                                after: '](https://)',
                                placeholder: 'text',
                              );
                              setDialogState(() {});
                            },
                          ),
                          MarkdownToolButton(
                            icon: Icons.code,
                            tooltip: 'Code block',
                            onTap: () {
                              _wrapSelection(
                                markdownController,
                                before: '```\n',
                                after: '\n```',
                                placeholder: 'code',
                              );
                              setDialogState(() {});
                            },
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () async {
                              final color = await _showInlineColorDialog(
                                dialogContext,
                                selectedColor,
                              );
                              if (color == null && !dialogContext.mounted) {
                                return;
                              }
                              setDialogState(() {
                                selectedColor = color;
                              });
                            },
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color:
                                    selectedColor ?? context.appColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: context.appColors.textPrimary
                                      .withAlpha(90),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(
                                value: false,
                                icon: Icon(Icons.edit_outlined),
                                label: Text('Write'),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                icon: Icon(Icons.preview_outlined),
                                label: Text('Preview'),
                              ),
                            ],
                            selected: {isPreview},
                            onSelectionChanged: (selection) {
                              setDialogState(() {
                                isPreview = selection.first;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 360,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            isPreview
                                ? SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: MarkdownBody(
                                    data:
                                        markdownController.text.isEmpty
                                            ? '*Empty note*'
                                            : markdownController.text,
                                  ),
                                )
                                : TextField(
                                  controller: markdownController,
                                  expands: true,
                                  minLines: null,
                                  maxLines: null,
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                    hintText:
                                        'Write your markdown note here...',
                                  ),
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                      ),
                    ],
                  ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.of(dialogContext).pop((
                    title: titleController.text.trim(),
                    markdown: markdownController.text,
                    color: selectedColor,
                  )),
              child: Text(panel == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
    titleController.dispose();
    markdownController.dispose();

    if (!context.mounted || result == null) return;
    final cubit = context.read<BoardCubit>();
    if (panel == null) {
      await cubit.createMarkdownNote(
        title: result.title,
        markdown: result.markdown,
      );
      final createdPanelId = cubit.state.activeBoard?.viewport.focusedPanelId;
      if (result.color != null && createdPanelId != null) {
        await cubit.updatePanelColor(createdPanelId, color: result.color);
      }
      return;
    }
    await cubit.updateMarkdownNote(
      panel.id,
      title: result.title,
      markdown: result.markdown,
    );
    await cubit.updatePanelColor(panel.id, color: result.color);
  }

  Future<void> _showPanelColorDialog(
    BuildContext context,
    BoardPanelInstance panel,
  ) async {
    final color = await _showInlineColorDialog(context, panel.color);
    if (!context.mounted) return;
    await context.read<BoardCubit>().updatePanelColor(panel.id, color: color);
  }

  Future<Color?> _showInlineColorDialog(
    BuildContext context,
    Color? initialColor,
  ) {
    var selectedColor = initialColor ?? context.appColors.primary;
    return showAdaptiveYoloDialog<Color?>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Panel color'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (color) {
                    selectedColor = color;
                  },
                  enableAlpha: false,
                  displayThumbColor: true,
                  portraitOnly: true,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(selectedColor),
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }

  Future<String?> _showTextDialog(
    BuildContext context, {
    required String title,
    required String label,
    required String initialValue,
    required String confirmLabel,
  }) {
    return showAdaptiveYoloDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: initialValue);
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
            autofocus: true,
            onSubmitted:
                (_) => Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  void _wrapSelection(
    TextEditingController controller, {
    required String before,
    required String after,
    required String placeholder,
  }) {
    final value = controller.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final selected = start < end ? value.text.substring(start, end) : '';
    final replacement =
        '$before${selected.isEmpty ? placeholder : selected}$after';
    final updated = value.text.replaceRange(start, end, replacement);
    final cursorOffset = start + replacement.length;
    controller.value = value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  void _prefixSelectedLines(TextEditingController controller, String prefix) {
    final value = controller.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final block = start < end ? value.text.substring(start, end) : '';
    final source = block.isEmpty ? 'item' : block;
    final replacement = source
        .split('\n')
        .map((line) => line.isEmpty ? prefix.trimRight() : '$prefix$line')
        .join('\n');
    final updated = value.text.replaceRange(start, end, replacement);
    controller.value = value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }
}



class _BoardToolbar extends StatelessWidget {
  const _BoardToolbar({
    required this.board,
    required this.onCreateBoard,
    required this.onConnectRemote,
    required this.onShareBoard,
    required this.onBoardSettings,
    required this.onDeleteBoard,
    required this.onOpenBoardOverview,
    required this.onSearch,
  });

  final BoardDocument board;
  final VoidCallback onCreateBoard;
  final VoidCallback onConnectRemote;
  final VoidCallback onShareBoard;
  final VoidCallback onBoardSettings;
  final VoidCallback onDeleteBoard;
  final VoidCallback onOpenBoardOverview;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final remoteBoard = isRemoteBoard(board);
    final deleteTooltip =
        remoteBoard ? 'Disconnect remote board' : 'Delete board';
    final deleteLabel = remoteBoard ? 'Disconnect' : 'Delete';
    final deleteIcon =
        remoteBoard ? Icons.link_off_rounded : Icons.delete_outline;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final phone = constraints.maxWidth < 560;
        final horizontalPadding = phone ? 8.0 : 16.0;
        final gap = phone ? 6.0 : 12.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            phone ? 8 : 12,
            horizontalPadding,
            phone ? 8 : 12,
          ),
          child: Row(
            children: [
              if (compact)
                Flexible(
                  child: _BoardSwitcherButton(
                    board: board,
                    onOpenBoardOverview: onOpenBoardOverview,
                    compact: phone,
                  ),
                )
              else
                _BoardSwitcherButton(
                  board: board,
                  onOpenBoardOverview: onOpenBoardOverview,
                ),
              if (!compact && board.defaultFolder.isNotEmpty) ...[
                const SizedBox(width: 12),
                ToolbarChip(
                  icon: Icons.folder_outlined,
                  label: _shortToolbarPath(board.defaultFolder),
                ),
              ],
              SizedBox(width: gap),
              if (!compact)
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onSearch,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.appColors.border),
                            color: context.appColors.surface,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search,
                                size: 18,
                                color: context.appColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'Search boards and panels…',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.appColors.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                Platform.isMacOS ? '⌘O' : 'Ctrl+O',
                                style: TextStyle(
                                  color: context.appColors.textMuted.withAlpha(
                                    120,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (!phone)
                Tooltip(
                  message: 'Search boards and panels',
                  child: IconButton(
                    onPressed: onSearch,
                    icon: const Icon(Icons.search),
                  ),
                ),
              if (compact) const Spacer() else const SizedBox(width: 16),
              if (phone)
                PopupMenuButton<String>(
                  tooltip: 'Board actions',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    switch (value) {
                      case 'search':
                        onSearch();
                      case 'new':
                        onCreateBoard();
                      case 'remote':
                        onConnectRemote();
                      case 'share':
                        onShareBoard();
                      case 'settings':
                        onBoardSettings();
                      case 'delete':
                        onDeleteBoard();
                    }
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'search',
                          child: Text('Search boards and panels'),
                        ),
                        const PopupMenuItem(
                          value: 'new',
                          child: Text('New board'),
                        ),
                        const PopupMenuItem(
                          value: 'remote',
                          child: Text('Connect remote YoLoIT'),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Text('Share board'),
                        ),
                        const PopupMenuItem(
                          value: 'settings',
                          child: Text('Settings'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(deleteLabel),
                        ),
                      ],
                )
              else if (compact) ...[
                IconButton(
                  tooltip: 'New board',
                  onPressed: onCreateBoard,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Connect remote YoLoIT',
                  onPressed: onConnectRemote,
                  icon: const Icon(Icons.cloud_outlined),
                ),
                IconButton(
                  tooltip: 'Share board',
                  onPressed: onShareBoard,
                  icon: const Icon(Icons.ios_share_outlined),
                ),
                IconButton(
                  tooltip: 'Board settings',
                  onPressed: onBoardSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
                IconButton(
                  tooltip: deleteTooltip,
                  onPressed: onDeleteBoard,
                  icon: Icon(deleteIcon),
                ),
              ] else ...[
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onCreateBoard,
                  icon: const Icon(Icons.add),
                  label: const Text('New board'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onConnectRemote,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Remote'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onShareBoard,
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('Share'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onBoardSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Settings'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: _toolbarButtonStyle(),
                  onPressed: onDeleteBoard,
                  icon: Icon(deleteIcon),
                  label: Text(deleteLabel),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static ButtonStyle _toolbarButtonStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  static String _shortToolbarPath(String path) {
    final normalized = path.trim();
    if (normalized.length <= 28) return normalized;
    final parts = normalized.split(Platform.pathSeparator);
    if (parts.length >= 2) return '…${Platform.pathSeparator}${parts.last}';
    return '…${normalized.substring(normalized.length - 27)}';
  }
}

class _BoardSwitcherButton extends StatelessWidget {
  const _BoardSwitcherButton({
    required this.board,
    required this.onOpenBoardOverview,
    this.compact = false,
  });

  final BoardDocument board;
  final VoidCallback onOpenBoardOverview;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final mutedColor =
        context.appColors.textMuted;
    return Tooltip(
      message: 'Open boards overview',
      child: InkWell(
        onTap: onOpenBoardOverview,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          constraints: BoxConstraints(
            minWidth: compact ? 0 : 160,
            maxWidth: compact ? 220 : 260,
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 16,
                color: mutedColor,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  board.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.expand_more, size: 18, color: mutedColor),
            ],
          ),
        ),
      ),
    );
  }
}


enum _BoardPanelResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get affectsLeft => this == left || this == topLeft || this == bottomLeft;
  bool get affectsRight =>
      this == right || this == topRight || this == bottomRight;
  bool get affectsTop => this == top || this == topLeft || this == topRight;
  bool get affectsBottom =>
      this == bottom || this == bottomLeft || this == bottomRight;

  SystemMouseCursor get cursor => switch (this) {
    topLeft || bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    topRight || bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    left || right => SystemMouseCursors.resizeLeftRight,
    top || bottom => SystemMouseCursors.resizeUpDown,
  };

  String get tooltip => switch (this) {
    topLeft => 'Resize from top left',
    top => 'Resize height',
    topRight => 'Resize from top right',
    right => 'Resize width',
    bottomRight => 'Resize from bottom right',
    bottom => 'Resize height',
    bottomLeft => 'Resize from bottom left',
    left => 'Resize width',
  };
}

class _BoardPanelResizeUpdate {
  const _BoardPanelResizeUpdate({
    required this.handle,
    required this.delta,
    required this.globalPosition,
  });

  final _BoardPanelResizeHandle handle;
  final Offset delta;
  final Offset globalPosition;
}

class _BoardPanelCard extends StatefulWidget {
  const _BoardPanelCard({
    super.key,
    required this.panel,
    required this.positionOffset,
    required this.onTap,
    required this.onMove,
    required this.onResize,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDelete,
    required this.onEditColor,
    required this.onBringToFront,
    required this.onSendToBack,
    this.onEditNote,
    this.onUpdateState,
    this.onCreateLinkedPanel,
    this.connectMode = false,
    this.connectSourceId,
    this.onConnectTap,
    this.capturingScreenshot = false,
  });

  final BoardPanelInstance panel;
  final Offset positionOffset;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onMove;
  final ValueChanged<_BoardPanelResizeUpdate> onResize;
  final ValueChanged<DragStartDetails> onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onDelete;
  final VoidCallback onEditColor;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback? onEditNote;
  final ValueChanged<Map<String, dynamic>>? onUpdateState;
  final Future<String?> Function(
    String typeId,
    Map<String, dynamic> state,
    String title,
  )?
  onCreateLinkedPanel;
  final bool connectMode;
  final String? connectSourceId;
  final VoidCallback? onConnectTap;
  final bool capturingScreenshot;

  @override
  State<_BoardPanelCard> createState() => _BoardPanelCardState();
}

class _BoardPanelCardState extends State<_BoardPanelCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  bool _isTransformingPanel = false;

  // Convenience getters so build code can still use widget.panel etc.
  BoardPanelInstance get panel => widget.panel;
  Offset get positionOffset => widget.positionOffset;
  VoidCallback get onTap => widget.onTap;
  ValueChanged<DragUpdateDetails> get onMove => widget.onMove;
  ValueChanged<_BoardPanelResizeUpdate> get onResize => widget.onResize;
  ValueChanged<DragStartDetails> get onDragStart => widget.onDragStart;
  VoidCallback get onDragEnd => widget.onDragEnd;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback get onEditColor => widget.onEditColor;
  VoidCallback get onBringToFront => widget.onBringToFront;
  VoidCallback get onSendToBack => widget.onSendToBack;
  VoidCallback? get onEditNote => widget.onEditNote;
  ValueChanged<Map<String, dynamic>>? get onUpdateState => widget.onUpdateState;
  Future<String?> Function(String, Map<String, dynamic>, String)?
  get onCreateLinkedPanel => widget.onCreateLinkedPanel;
  bool get connectMode => widget.connectMode;
  String? get connectSourceId => widget.connectSourceId;
  VoidCallback? get onConnectTap => widget.onConnectTap;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _opacity = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack),
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _showPanelSettingsDialog(
    BuildContext context, {
    required BoardPanelInstance panel,
    required BoardPanelPlugin? plugin,
    required VoidCallback? onEditPanel,
    required VoidCallback onEditColor,
    required VoidCallback onBringToFront,
    required VoidCallback onSendToBack,
  }) async {
    await showAdaptiveYoloDialog<void>(
      context: context,
      builder:
          (dialogContext) => PanelSettingsDialog(
            panel: panel,
            plugin: plugin,
            onEditPanel:
                onEditPanel == null
                    ? null
                    : () {
                      Navigator.of(dialogContext).pop();
                      onEditPanel();
                    },
            onEditColor: () {
              Navigator.of(dialogContext).pop();
              onEditColor();
            },
            onBringToFront: () {
              Navigator.of(dialogContext).pop();
              onBringToFront();
            },
            onSendToBack: () {
              Navigator.of(dialogContext).pop();
              onSendToBack();
            },
          ),
    );
  }

  void _startPanelTransform(DragStartDetails details) {
    onTap();
    setState(() => _isTransformingPanel = true);
    onDragStart(details);
  }

  void _endPanelTransform() {
    if (_isTransformingPanel) {
      setState(() => _isTransformingPanel = false);
    }
    onDragEnd();
  }

  void _resizeFromHandle(
    _BoardPanelResizeHandle handle,
    DragUpdateDetails details,
  ) {
    onResize(
      _BoardPanelResizeUpdate(
        handle: handle,
        delta: details.delta,
        globalPosition: details.globalPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final focusedPanelId = context.select<BoardCubit, String?>(
      (cubit) => cubit.state.activeBoard?.viewport.focusedPanelId,
    );
    final isFocused = panel.id == focusedPanelId;
    final isWebpage = panel.type == 'board.webpage';
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    final usePanelChrome = plugin?.usePanelChrome ?? true;
    final showHeader = plugin?.showHeader ?? true;
    final accent = panel.color;
    final isCapturing = widget.capturingScreenshot;
    final panelFill =
        !usePanelChrome
            ? Colors.transparent
            : isCapturing
            ? colors.background
            : accent == null
            ? colors.surface
            : Color.lerp(colors.surface, accent, 0.12) ?? colors.surface;
    final panelHeaderFill =
        isCapturing
            ? colors.background
            : accent == null
            ? colors.surfaceElevated
            : Color.lerp(colors.surfaceElevated, accent, 0.18) ??
                colors.surfaceElevated;
    final borderColor =
        !usePanelChrome
            ? Colors.transparent
            : isCapturing
            ? colors.background
            : accent == null
            ? colors.divider
            : Color.lerp(colors.divider, accent, 0.65) ?? colors.divider;
    final showSelectionChrome = isFocused && !isCapturing;
    const selectionSideGutter = 18.0;
    const selectionTopGutter = 62.0;
    const selectionBottomGutter = 18.0;
    const selectionHandleInset = 12.0;
    final selectionToolbarMinWidth =
        panel.type == 'board.sticky' || panel.type == 'board.shape'
            ? 680.0
            : 360.0;
    final selectionToolbarWidth = math.max(
      selectionToolbarMinWidth,
      panel.bounds.width,
    );
    final selectionWrapperWidth = math.max(
      panel.bounds.width + selectionSideGutter * 2,
      selectionToolbarWidth + selectionSideGutter * 2,
    );
    return AnimatedPositioned(
      duration:
          _isTransformingPanel
              ? Duration.zero
              : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: panel.bounds.x + positionOffset.dx - selectionSideGutter,
      top: panel.bounds.y + positionOffset.dy - selectionTopGutter,
      width: selectionWrapperWidth,
      height: panel.bounds.height + selectionTopGutter + selectionBottomGutter,
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          alignment: Alignment.topLeft,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: selectionSideGutter,
                top: selectionTopGutter,
                width: panel.bounds.width,
                height: panel.bounds.height,
                child: _ChatGlowWrapper(
                  panelId: panel.id,
                  borderRadius: BorderRadius.circular(16),
                  child: Listener(
                    behavior: HitTestBehavior.deferToChild,
                    onPointerDown: (_) {
                      if (isWebpage) {
                        if (!isFocused) {
                          if (kDebugMode) {
                            debugPrint(
                              '[BoardWebFocus] panelPointerDown -> focus webpage panel=${panel.id}',
                            );
                          }
                          onTap();
                        } else {
                          if (kDebugMode) {
                            debugPrint(
                              '[BoardWebFocus] panelPointerDown -> already focused, releasing Flutter focus panel=${panel.id}',
                            );
                          }
                        }
                        // Release ALL Flutter keyboard focus so the native WKWebView
                        // can become firstResponder and receive keyboard input.
                        FocusManager.instance.primaryFocus?.unfocus();
                        return;
                      }
                      if (!isFocused) {
                        onTap();
                      }
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: panelFill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              isCapturing
                                  ? colors.background
                                  : isFocused
                                  ? colors.primary
                                  : borderColor,
                          width: isFocused && !isCapturing ? 1.5 : 1,
                        ),
                        boxShadow:
                            isCapturing || !usePanelChrome
                                ? null
                                : [
                                  BoxShadow(
                                    color: colors.background.withAlpha(35),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (isFocused && !isCapturing)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: colors.primary,
                                      width: usePanelChrome ? 1.6 : 2.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showHeader)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: _startPanelTransform,
                                  onPanUpdate:
                                      panel.locked
                                          ? null
                                          : (details) => onMove(details),
                                  onPanEnd: (_) => _endPanelTransform(),
                                  onPanCancel: _endPanelTransform,
                                  child: Container(
                                    height: 44,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: panelHeaderFill,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(16),
                                      ),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: colors.divider,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        if (panel.type ==
                                            ChatPanelPlugin.kTypeId)
                                          ChatProviderIcon(
                                            provider:
                                                (panel.state['config']
                                                        as Map?)?['provider']
                                                    as String? ??
                                                'copilot',
                                            size: 18,
                                          )
                                        else
                                          Builder(
                                            builder: (ctx) {
                                              final plugin = BoardPluginRegistry
                                                  .instance
                                                  .pluginFor(panel.type);
                                              final svgIcon = plugin
                                                  ?.buildIconWidget(
                                                    ctx,
                                                    size: 16,
                                                  );
                                              if (svgIcon != null) {
                                                return svgIcon;
                                              }
                                              return Icon(
                                                plugin?.icon ??
                                                    Icons
                                                        .dashboard_customize_outlined,
                                                size: 16,
                                                color:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.color ??
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                              );
                                            },
                                          ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            panel.title,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: TextStyle(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        if (panel.type !=
                                            ChatPanelPlugin.kTypeId) ...[
                                          GestureDetector(
                                            onTap: onEditColor,
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                color:
                                                    accent ??
                                                    (Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.color ??
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .onSurface),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: colors.textPrimary
                                                      .withAlpha(100),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (onEditNote != null)
                                            SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: IconButton(
                                                tooltip: 'Edit note',
                                                onPressed: onEditNote,
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 16,
                                                ),
                                                splashRadius: 14,
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                        ],
                                        if (panel.type ==
                                            ChatPanelPlugin.kTypeId)
                                          _ChatHeaderMenu(
                                            panel: panel,
                                            onEditColor: onEditColor,
                                            onUpdateState: onUpdateState,
                                          ),
                                        // Plugin-specific header actions (e.g. env gear for widget panels)
                                        ...() {
                                          final plugin = BoardPluginRegistry
                                              .instance
                                              .pluginFor(panel.type);
                                          if (plugin == null ||
                                              onUpdateState == null) {
                                            return <Widget>[];
                                          }
                                          return plugin.buildHeaderActions(
                                            context,
                                            panel,
                                            onUpdateState!,
                                            onResize:
                                                (w, h) => context
                                                    .read<BoardCubit>()
                                                    .resizePanel(
                                                      panel.id,
                                                      width: w,
                                                      height: h,
                                                    ),
                                          );
                                        }(),
                                        PanelHeaderIconButton(
                                          tooltip: 'Panel settings',
                                          icon: Icons.tune_rounded,
                                          onPressed:
                                              () => _showPanelSettingsDialog(
                                                context,
                                                panel: panel,
                                                plugin: plugin,
                                                onEditPanel: onEditNote,
                                                onEditColor: onEditColor,
                                                onBringToFront: onBringToFront,
                                                onSendToBack: onSendToBack,
                                              ),
                                        ),
                                        PanelHeaderIconButton(
                                          tooltip: 'Bring to front',
                                          icon: Icons.flip_to_front_outlined,
                                          onPressed: onBringToFront,
                                        ),
                                        PanelHeaderIconButton(
                                          tooltip: 'Send to back',
                                          icon: Icons.flip_to_back_outlined,
                                          onPressed: onSendToBack,
                                        ),
                                        SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: IconButton(
                                            tooltip: 'Remove panel',
                                            onPressed: onDelete,
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            splashRadius: 14,
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding:
                                      !showHeader ||
                                              panel.type ==
                                                  ChatPanelPlugin.kTypeId ||
                                              panel.type ==
                                                  BoardTerminalPanelPlugin
                                                      .kTypeId ||
                                              panel.type == 'board.webpage'
                                          ? EdgeInsets.zero
                                          : const EdgeInsets.all(12),
                                  child: _buildPanelContent(context, panel),
                                ),
                              ),
                            ],
                          ),
                          // ── Connect mode overlay ──────────────────────────────────────
                          if (connectMode)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: onConnectTap,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          connectSourceId == panel.id
                                              ? colors.statusActive
                                              : colors.statusActive.withAlpha(
                                                100,
                                              ),
                                      width:
                                          connectSourceId == panel.id
                                              ? 2.5
                                              : 1.5,
                                    ),
                                    color:
                                        connectSourceId == panel.id
                                            ? colors.statusActive.withAlpha(21)
                                            : Colors.transparent,
                                  ),
                                  child:
                                      connectSourceId == null
                                          ? Center(
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: colors.statusActive
                                                    .withAlpha(102),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.add_link,
                                                size: 18,
                                                color: colors.statusActive,
                                              ),
                                            ),
                                          )
                                          : connectSourceId == panel.id
                                          ? Center(
                                            child: Text(
                                              'Source\n(tap to cancel)',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: colors.statusActive,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          )
                                          : Center(
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: colors.statusActive
                                                    .withAlpha(102),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.call_made,
                                                size: 18,
                                                color: colors.statusActive,
                                              ),
                                            ),
                                          ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (showSelectionChrome)
                Positioned(
                  top: 8,
                  left: selectionSideGutter,
                  child: MiroPanelToolbar(
                    maxWidth: selectionToolbarWidth,
                    panel: panel,
                    plugin: plugin,
                    canEdit: onEditNote != null,
                    onEdit: onEditNote,
                    onEditColor: onEditColor,
                    onBringToFront: onBringToFront,
                    onSendToBack: onSendToBack,
                    onDelete: onDelete,
                    onToggleLocked: () {
                      context.read<BoardCubit>().updatePanel(
                        panel.id,
                        (p) => p.copyWith(locked: !p.locked),
                      );
                    },
                    onMoveStart: _startPanelTransform,
                    onMoveUpdate:
                        panel.locked ? null : (details) => onMove(details),
                    onMoveEnd: _endPanelTransform,
                    onSettings:
                        () => _showPanelSettingsDialog(
                          context,
                          panel: panel,
                          plugin: plugin,
                          onEditPanel: onEditNote,
                          onEditColor: onEditColor,
                          onBringToFront: onBringToFront,
                          onSendToBack: onSendToBack,
                        ),
                    onUpdateState: onUpdateState,
                  ),
                ),
              if (showSelectionChrome)
                Positioned(
                  left: selectionSideGutter - selectionHandleInset,
                  top: selectionTopGutter - selectionHandleInset,
                  width: panel.bounds.width + selectionHandleInset * 2,
                  height: panel.bounds.height + selectionHandleInset * 2,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: _BoardPanelResizeOverlay.handles(
                      locked: panel.locked,
                      onStart: _startPanelTransform,
                      onUpdate: _resizeFromHandle,
                      onEnd: _endPanelTransform,
                      colors: colors,
                    ),
                  ),
                ),
            ],
          ),
        ), // ScaleTransition
      ), // FadeTransition
    );
  }

  Widget _buildPanelContent(BuildContext context, BoardPanelInstance panel) {
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    if (plugin != null) {
      final activeBoard = context.read<BoardCubit>().state.activeBoard;
      return plugin.buildContent(
        context,
        panel,
        BoardPanelRenderContext(
          isSelected:
              panel.id ==
              context.select<BoardCubit, String?>(
                (cubit) => cubit.state.activeBoard?.viewport.focusedPanelId,
              ),
          onFocus: onTap,
          onDelete: onDelete,
          onUpdateState: onUpdateState ?? (_) {},
          onShowEditor: onEditNote ?? () {},
          remoteInfo:
              activeBoard == null ? null : remoteInfoForBoard(activeBoard),
          onCreateLinkedPanel: onCreateLinkedPanel,
          onFindPanelByGroup: (typeId, group) {
            final board = context.read<BoardCubit>().state.activeBoard;
            if (board == null) return null;
            for (final p in board.panels) {
              if (p.type != typeId) continue;
              final panelGroup = p.state['group'];
              if (panelGroup is String && panelGroup.trim() == group.trim()) {
                return p.id;
              }
            }
            return null;
          },
          onRevealSessionInPanel: (panelId, sessionId) async {
            final cubit = context.read<BoardCubit>();
            await cubit.updatePanel(panelId, (p) {
              final hiddenRaw = p.state['hiddenSessionIds'];
              final hidden =
                  hiddenRaw is List
                      ? hiddenRaw.whereType<String>().toSet()
                      : <String>{};
              hidden.remove(sessionId);
              return p.copyWith(
                state: {
                  ...p.state,
                  'activeSessionId': sessionId,
                  'hiddenSessionIds': hidden.toList(),
                },
              );
            });
          },
          onFocusPanelById:
              (panelId) => context.read<BoardCubit>().focusPanel(panelId),
          onResize:
              (w, h) => context.read<BoardCubit>().resizePanel(
                panel.id,
                width: w,
                height: h,
              ),
        ),
      );
    }
    // Fallback for unknown types
    return Center(
      child: Text(
        'Unknown: ${panel.type}',
        style: TextStyle(
          color: context.appColors.textMuted,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _BoardPanelResizeOverlay {
  const _BoardPanelResizeOverlay._();

  static List<Widget> handles({
    required bool locked,
    required ValueChanged<DragStartDetails> onStart,
    required void Function(_BoardPanelResizeHandle, DragUpdateDetails) onUpdate,
    required VoidCallback onEnd,
    required AppColorScheme colors,
  }) {
    if (locked) return const [];
    return _BoardPanelResizeHandle.values
        .map(
          (handle) => _PanelResizeHandleWidget(
            handle: handle,
            onStart: onStart,
            onUpdate: (details) => onUpdate(handle, details),
            onEnd: onEnd,
            colors: colors,
          ),
        )
        .toList(growable: false);
  }
}

class _PanelResizeHandleWidget extends StatelessWidget {
  const _PanelResizeHandleWidget({
    required this.handle,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.colors,
  });

  final _BoardPanelResizeHandle handle;
  final ValueChanged<DragStartDetails> onStart;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final VoidCallback onEnd;
  final AppColorScheme colors;

  static const double _hitSize = 24;
  static const double _dotSize = 10;

  @override
  Widget build(BuildContext context) {
    final child = MouseRegion(
      cursor: handle.cursor,
      child: Tooltip(
        message: handle.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onStart,
          onPanUpdate: onUpdate,
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: SizedBox(
            width: _hitSize,
            height: _hitSize,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const SizedBox(width: _dotSize, height: _dotSize),
              ),
            ),
          ),
        ),
      ),
    );

    return switch (handle) {
      _BoardPanelResizeHandle.topLeft => Positioned(
        left: 0,
        top: 0,
        child: child,
      ),
      _BoardPanelResizeHandle.top => Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: _hitSize,
        child: Center(child: child),
      ),
      _BoardPanelResizeHandle.topRight => Positioned(
        right: 0,
        top: 0,
        child: child,
      ),
      _BoardPanelResizeHandle.right => Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: _hitSize,
        child: Center(child: child),
      ),
      _BoardPanelResizeHandle.bottomRight => Positioned(
        right: 0,
        bottom: 0,
        child: child,
      ),
      _BoardPanelResizeHandle.bottom => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: _hitSize,
        child: Center(child: child),
      ),
      _BoardPanelResizeHandle.bottomLeft => Positioned(
        left: 0,
        bottom: 0,
        child: child,
      ),
      _BoardPanelResizeHandle.left => Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: _hitSize,
        child: Center(child: child),
      ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WebView overlays — renders live WebViews for ALL webpage panels OUTSIDE the
// InteractiveViewer's Transform widget, avoiding the fundamental coordinate
// mismatch between Flutter's transform and native macOS platform views.
//
// Unfocused panels: visible but input blocked (click → focus that panel).
// Focused panel:    full interaction, on top z-order.
// ─────────────────────────────────────────────────────────────────────────────

class _WebViewOverlays extends StatelessWidget {
  const _WebViewOverlays({
    required this.panels,
    required this.focusedPanelId,
    required this.transformController,
    required this.canvasOrigin,
    required this.isInteracting,
  });

  final List<BoardPanelInstance> panels;
  final String? focusedPanelId;
  final TransformationController transformController;
  final Offset canvasOrigin;
  final bool isInteracting;

  /// Header (44) + URL bar (36) + divider (1) = content starts at 81px.
  static const double _contentOffsetY = 81.0;

  Rect? _screenRect(BoardPanelInstance panel, Matrix4 matrix, double scale) {
    final canvasPos = Offset(
      panel.bounds.x + canvasOrigin.dx,
      panel.bounds.y + canvasOrigin.dy + _contentOffsetY,
    );
    final screenPos = MatrixUtils.transformPoint(matrix, canvasPos);
    final w = panel.bounds.width * scale;
    final h = (panel.bounds.height - _contentOffsetY) * scale;
    if (w < 1 || h < 1) return null;
    return Rect.fromLTWH(screenPos.dx, screenPos.dy, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final webPanels =
        panels
            .where(
              (p) =>
                  p.type == WebpagePlugin.kTypeId &&
                  !p.hidden &&
                  WebpagePlugin.controllers.containsKey(p.id),
            )
            .toList();

    if (webPanels.isEmpty) return const SizedBox.shrink();

    // During active pinch-to-zoom / pan, hide overlays to avoid
    // visual desync — native NSView frame updates lag behind
    // the GPU-rendered InteractiveViewer transform.
    if (isInteracting) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportRect = Rect.fromLTWH(
          0,
          0,
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return ValueListenableBuilder<Matrix4>(
          valueListenable: transformController,
          builder: (context, matrix, _) {
            final scale = _BoardViewState._scaleOf(matrix);
            final children = <Widget>[];

            // Apply CSS zoom = boardScale so pages use desktop layout widths.
            // pageZoom is NOT used — it shrinks content visually without
            // changing window.innerWidth.

            // ── 1. Unfocused WebView overlays (bottom z-order) ──
            for (final panel in webPanels) {
              if (panel.id == focusedPanelId) continue;
              final rect = _screenRect(panel, matrix, scale);
              if (rect == null) continue;
              // Viewport culling — skip off-screen panels.
              if (!rect.overlaps(viewportRect)) continue;

              final ctrl = WebpagePlugin.controllers[panel.id]!;

              // pageZoom in Swift handles viewport width. No CSS zoom needed.
              if (!WebpagePlugin.pendingCssZoom.containsKey(panel.id)) {
                WebpagePlugin.pendingCssZoom[panel.id] = 1.0;
              }

              children.add(
                Positioned(
                  key: ValueKey('wv-${panel.id}'),
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(16 * scale),
                      bottomRight: Radius.circular(16 * scale),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: context.appColors.background),
                        WebViewWidget(controller: ctrl),
                        // Loading overlay
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              WebpagePlugin.pageLoading[panel.id] ??
                              ValueNotifier<bool>(false),
                          builder: (_, isLoading, __) {
                            if (!isLoading) return const SizedBox.shrink();
                            return ColoredBox(
                              color: context.appColors.surfaceHighlight,
                            );
                          },
                        ),
                        // Absorb clicks → focus this panel
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (kDebugMode) {
                              debugPrint(
                                '[BoardWebFocus] unfocused overlay tap -> focus panel=${panel.id}',
                              );
                            }
                            context.read<BoardCubit>().focusPanel(panel.id);
                            FocusManager.instance.primaryFocus?.unfocus();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ── 2. Focused WebView overlay (top z-order, full interaction) ──
            // No full-screen background — the canvas Listener inside
            // InteractiveViewer handles unfocusing when clicking empty space.
            final focusedPanel =
                webPanels.where((p) => p.id == focusedPanelId).firstOrNull;
            if (focusedPanel != null) {
              final rect = _screenRect(focusedPanel, matrix, scale);
              if (rect != null) {
                final ctrl = WebpagePlugin.controllers[focusedPanel.id]!;

                // pageZoom in Swift handles viewport width via frame observer.
                if (!WebpagePlugin.pendingCssZoom.containsKey(
                  focusedPanel.id,
                )) {
                  WebpagePlugin.pendingCssZoom[focusedPanel.id] = 1.0;
                }

                children.add(
                  Positioned(
                    key: ValueKey('wv-focused-${focusedPanel.id}'),
                    left: rect.left,
                    top: rect.top,
                    width: rect.width,
                    height: rect.height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16 * scale),
                        bottomRight: Radius.circular(16 * scale),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: context.appColors.surface),
                          WebViewWidget(controller: ctrl),
                          // Loading overlay (navigation flash hide)
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                WebpagePlugin.pageLoading[focusedPanel.id] ??
                                ValueNotifier<bool>(false),
                            builder: (_, isLoading, __) {
                              if (!isLoading) return const SizedBox.shrink();
                              return ColoredBox(
                                color: context.appColors.surfaceHighlight,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            }

            if (children.isEmpty) return const SizedBox.shrink();
            return Stack(children: children);
          },
        );
      },
    );
  }
}

class _InfiniteBoardGridPainter extends CustomPainter {
  _InfiniteBoardGridPainter({
    required this.transformCtrl,
    required this.origin,
    required this.minorColor,
    required this.majorColor,
  }) : super(repaint: transformCtrl);

  final TransformationController transformCtrl;
  final Offset origin;
  final Color minorColor;
  final Color majorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _BoardViewState._scaleOf(
      transformCtrl.value,
    ).clamp(0.0001, 1000.0);
    final translation = transformCtrl.value.storage;
    final tx = translation[12] + (origin.dx * scale);
    final ty = translation[13] + (origin.dy * scale);

    const minorStep = 24.0;
    const majorStep = 120.0;

    final minorSpacing = minorStep * scale;
    final majorSpacing = majorStep * scale;

    final minorPaint =
        Paint()
          ..color = minorColor
          ..strokeWidth = 1;
    final majorPaint =
        Paint()
          ..color = majorColor
          ..strokeWidth = 1;

    double startXMinor = tx % minorSpacing;
    if (startXMinor > 0) startXMinor -= minorSpacing;
    for (double x = startXMinor; x <= size.width; x += minorSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
    }

    double startYMinor = ty % minorSpacing;
    if (startYMinor > 0) startYMinor -= minorSpacing;
    for (double y = startYMinor; y <= size.height; y += minorSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorPaint);
    }

    double startXMajor = tx % majorSpacing;
    if (startXMajor > 0) startXMajor -= majorSpacing;
    for (double x = startXMajor; x <= size.width; x += majorSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorPaint);
    }

    double startYMajor = ty % majorSpacing;
    if (startYMajor > 0) startYMajor -= majorSpacing;
    for (double y = startYMajor; y <= size.height; y += majorSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), majorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _InfiniteBoardGridPainter oldDelegate) {
    return oldDelegate.transformCtrl != transformCtrl ||
        oldDelegate.origin != origin ||
        oldDelegate.minorColor != minorColor ||
        oldDelegate.majorColor != majorColor;
  }
}

class _BoardMiniMap extends StatelessWidget {
  const _BoardMiniMap({
    required this.panels,
    required this.processingPanelIds,
    required this.transformCtrl,
    required this.viewportSize,
    required this.origin,
    required this.onPanTo,
  });

  final List<BoardPanelInstance> panels;
  final Set<String> processingPanelIds;
  final TransformationController transformCtrl;
  final Size viewportSize;
  final Offset origin;
  final ValueChanged<Offset> onPanTo;

  static const double _mapW = 210.0;
  static const double _mapH = 130.0;
  static const double _padding = 180.0;

  Rect _canvasBounds(Rect viewportRect) {
    final visiblePanels = panels.where((panel) => !panel.hidden).toList();
    if (visiblePanels.isEmpty) {
      return viewportRect.inflate(_padding);
    }
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    for (final panel in visiblePanels) {
      final rect = panel.bounds.rect;
      if (rect.left < minX) minX = rect.left;
      if (rect.top < minY) minY = rect.top;
      if (rect.right > maxX) maxX = rect.right;
      if (rect.bottom > maxY) maxY = rect.bottom;
    }
    final contentBounds = Rect.fromLTRB(
      minX - _padding,
      minY - _padding,
      maxX + _padding,
      maxY + _padding,
    );
    return contentBounds.expandToInclude(viewportRect).inflate(_padding);
  }

  void _handleGesture(Offset local, Rect bounds) {
    final cx = bounds.left + (local.dx / _mapW) * bounds.width;
    final cy = bounds.top + (local.dy / _mapH) * bounds.height;
    onPanTo(Offset(cx, cy));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: transformCtrl,
      builder: (context, _) {
        final vpTL = transformCtrl.toScene(Offset.zero) - origin;
        final vpBR =
            transformCtrl.toScene(
              Offset(viewportSize.width, viewportSize.height),
            ) -
            origin;
        final viewportRect = Rect.fromLTRB(vpTL.dx, vpTL.dy, vpBR.dx, vpBR.dy);
        final bounds = _canvasBounds(viewportRect);
        return GestureDetector(
          onTapDown: (details) => _handleGesture(details.localPosition, bounds),
          onPanUpdate:
              (details) => _handleGesture(details.localPosition, bounds),
          child: Container(
            width: _mapW,
            height: _mapH,
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(0xE5),
              border: Border.all(color: colors.primary.withAlpha(0x50)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: colors.background.withAlpha(102),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CustomPaint(
                painter: _BoardMiniMapPainter(
                  panels: panels.where((panel) => !panel.hidden).toList(),
                  processingPanelIds: processingPanelIds,
                  bounds: bounds,
                  viewportRect: viewportRect,
                  colors: colors,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoardMiniMapPainter extends CustomPainter {
  const _BoardMiniMapPainter({
    required this.panels,
    required this.processingPanelIds,
    required this.bounds,
    required this.viewportRect,
    required this.colors,
  });

  final List<BoardPanelInstance> panels;
  final Set<String> processingPanelIds;
  final Rect bounds;
  final Rect viewportRect;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.isEmpty) return;
    final scaleX = size.width / bounds.width;
    final scaleY = size.height / bounds.height;

    for (final panel in panels) {
      final rect = panel.bounds.rect;
      final x = (rect.left - bounds.left) * scaleX;
      final y = (rect.top - bounds.top) * scaleY;
      final w = math.max(4.0, rect.width * scaleX);
      final h = math.max(3.0, rect.height * scaleY);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(1.5),
      );

      final isProcessing = processingPanelIds.contains(panel.id);

      if (isProcessing) {
        // Draw glow behind processing panels
        canvas.drawRRect(
          rrect.inflate(2),
          Paint()
            ..color = colors.accentGreen
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }

      canvas.drawRRect(
        rrect,
        Paint()
          ..color =
              isProcessing
                  ? colors.accentGreen
                  : panelTypeColor(
                    panel.type,
                    colors,
                    override: panel.color,
                  ).withAlpha(0xCC),
      );
    }

    final vx = (viewportRect.left - bounds.left) * scaleX;
    final vy = (viewportRect.top - bounds.top) * scaleY;
    final vw = math.max(8.0, viewportRect.width * scaleX);
    final vh = math.max(8.0, viewportRect.height * scaleY);
    final viewport = RRect.fromRectAndRadius(
      Rect.fromLTWH(vx, vy, vw, vh),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      viewport,
      Paint()..color = colors.accentBlue.withAlpha(32),
    );
    canvas.drawRRect(
      viewport,
      Paint()
        ..color = colors.accentBlue.withAlpha(204)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardMiniMapPainter oldDelegate) {
    return oldDelegate.panels != panels ||
        oldDelegate.bounds != bounds ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.processingPanelIds != processingPanelIds ||
        oldDelegate.colors != colors;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Tools Panel
// ─────────────────────────────────────────────────────────────────────────────

class _BoardToolsPanel extends StatelessWidget {
  const _BoardToolsPanel({
    required this.board,
    required this.platform,
    required this.visible,
    required this.activeTool,
    required this.drawSettings,
    required this.connectSettings,
    required this.onToolChanged,
    required this.onDrawSettingsChanged,
    required this.onConnectSettingsChanged,
    required this.historyPanelVisible,
    required this.onToggle,
    required this.onShowHistory,
    this.onUndo,
    this.onRedo,
    this.onAddNote,
    this.onAddChat,
    this.onAddTerminal,
    this.onAddGeneric,
  });

  final BoardDocument board;
  final String platform;
  final bool visible;
  final BoardToolId activeTool;
  final DrawSettings drawSettings;
  final ConnectSettings connectSettings;
  final ValueChanged<BoardToolId> onToolChanged;
  final ValueChanged<DrawSettings> onDrawSettingsChanged;
  final ValueChanged<ConnectSettings> onConnectSettingsChanged;
  final bool historyPanelVisible;
  final VoidCallback onToggle;
  final VoidCallback onShowHistory;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onAddNote;
  final VoidCallback? onAddChat;
  final VoidCallback? onAddTerminal;
  final ValueChanged<String>? onAddGeneric;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final mutedColor =
        isLight
            ? const Color(0xFF252A31)
            : (context.appColors.textMuted);
    final panelBg =
        isLight ? Colors.white : colors.surfaceElevated.withAlpha(0xF2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Toggle button ─────────────────────────────────────────────────
        OverlayIconButton(
          icon: visible ? Icons.tune : Icons.tune_outlined,
          tooltip: visible ? 'Hide tools' : 'Show tools',
          active: visible,
          onTap: onToggle,
        ),
        if (visible) ...[
          const SizedBox(height: 6),
          // ── Tool buttons ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border.withAlpha(180)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isLight ? 18 : 70),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in kBoardTools) ...[
                  if (kBoardTools.indexOf(tool) > 0) const SizedBox(height: 4),
                  Tooltip(
                    message:
                        tool.shortcutHint != null
                            ? '${tool.label} (${tool.shortcutHint})'
                            : tool.label,
                    child: GestureDetector(
                      onTap: () => onToolChanged(tool.id),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              activeTool == tool.id
                                  ? tool.accentColor.withAlpha(50)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              activeTool == tool.id
                                  ? Border.all(
                                    color: tool.accentColor.withAlpha(180),
                                  )
                                  : null,
                        ),
                        child: Icon(
                          tool.icon,
                          size: 18,
                          color:
                              activeTool == tool.id
                                  ? tool.accentColor
                                  : mutedColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Draw settings ────────────────────────────────────────────────
          if (activeTool == BoardToolId.draw) ...[
            const SizedBox(height: 6),
            _DrawSettingsPanel(
              settings: drawSettings,
              onChanged: onDrawSettingsChanged,
            ),
          ],
          // ── Connect settings ─────────────────────────────────────────────
          if (activeTool == BoardToolId.connect) ...[
            const SizedBox(height: 6),
            _ConnectSettingsPanel(
              settings: connectSettings,
              onChanged: onConnectSettingsChanged,
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border.withAlpha(180)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isLight ? 18 : 70),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiroLeftToolbarButton(
                  icon: Icons.undo_rounded,
                  tooltip: 'Undo latest panel change',
                  onTap: onUndo,
                  color: mutedColor,
                ),
                const SizedBox(height: 4),
                _MiroLeftToolbarButton(
                  icon: Icons.redo_rounded,
                  tooltip: 'Redo',
                  onTap: onRedo,
                  color: mutedColor,
                ),
                const SizedBox(height: 4),
                _MiroLeftToolbarButton(
                  icon: Icons.manage_history_rounded,
                  tooltip:
                      historyPanelVisible
                          ? 'Hide board history'
                          : 'Show board history',
                  active: historyPanelVisible,
                  onTap: onShowHistory,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ],
        // ── Add panel buttons (always visible) ───────────────────────────
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: panelBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border.withAlpha(180)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isLight ? 18 : 70),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: _PanelCatalogCategory.basics,
                icon: Icons.category_outlined,
                tooltip: 'Miro basics',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              _PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: _PanelCatalogCategory.ai,
                icon: Icons.auto_awesome,
                tooltip: 'AI and terminal',
                color: colors.statusActive,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              _PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: _PanelCatalogCategory.files,
                icon: Icons.folder_outlined,
                tooltip: 'Files and web',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              _PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: _PanelCatalogCategory.planning,
                icon: Icons.view_kanban_outlined,
                tooltip: 'Planning',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
              const SizedBox(height: 4),
              _PanelCatalogCategoryButton(
                board: board,
                platform: platform,
                category: _PanelCatalogCategory.advanced,
                icon: Icons.extension_outlined,
                tooltip: 'Advanced',
                color: mutedColor,
                onAddNote: onAddNote,
                onAddChat: onAddChat,
                onAddTerminal: onAddTerminal,
                onAddGeneric: onAddGeneric,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiroLeftToolbarButton extends StatelessWidget {
  const _MiroLeftToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active ? colors.primary.withAlpha(32) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:
                active
                    ? Border.all(color: colors.primary.withAlpha(180))
                    : null,
          ),
          child: Icon(
            icon,
            size: 23,
            color:
                enabled
                    ? (active ? colors.primary : color)
                    : color.withAlpha(90),
          ),
        ),
      ),
    );
  }
}

class _PanelCatalogCategoryButton extends StatelessWidget {
  const _PanelCatalogCategoryButton({
    required this.board,
    required this.platform,
    required this.category,
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onAddGeneric,
    this.onAddNote,
    this.onAddChat,
    this.onAddTerminal,
  });

  final BoardDocument board;
  final String platform;
  final _PanelCatalogCategory category;
  final IconData icon;
  final String tooltip;
  final ValueChanged<String>? onAddGeneric;
  final Color color;
  final VoidCallback? onAddNote;
  final VoidCallback? onAddChat;
  final VoidCallback? onAddTerminal;

  @override
  Widget build(BuildContext context) {
    final hasItems = _itemsFor(context, category).isNotEmpty;
    return Builder(
      builder:
          (btnCtx) => Tooltip(
            message: hasItems ? tooltip : '$tooltip unavailable on this board',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: hasItems ? () => _showCategoryItems(btnCtx) : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: hasItems ? color : color.withAlpha(80),
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _showCategoryItems(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset(box.size.width, 0));
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx + 4,
        pos.dy,
        pos.dx + 340,
        pos.dy + 100,
      ),
      color: _menuColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: _itemsFor(context, category),
    );
    if (selected == null) return;
    if (selected == '__note') {
      onAddNote?.call();
      return;
    }
    if (selected == '__chat') {
      onAddChat?.call();
      return;
    }
    if (selected == '__terminal') {
      onAddTerminal?.call();
      return;
    }
    onAddGeneric?.call(selected);
  }

  List<PopupMenuEntry<String>> _itemsFor(
    BuildContext context,
    _PanelCatalogCategory category,
  ) {
    PopupMenuEntry<String>? pluginItem(String typeId) {
      if (onAddGeneric == null) return null;
      if (!_isPanelTypeAvailable(typeId)) return null;
      final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
      if (plugin == null) return null;
      return _catalogItem(
        context,
        value: plugin.typeId,
        icon: plugin.icon,
        iconColor: plugin.accentColor,
        label: plugin.displayName,
      );
    }

    final items = switch (category) {
      _PanelCatalogCategory.basics => <PopupMenuEntry<String>?>[
        if (onAddNote != null && _isPanelTypeAvailable('board.note.markdown'))
          _catalogItem(
            context,
            value: '__note',
            icon: Icons.notes_rounded,
            iconColor: context.appColors.textMuted,
            label: 'Markdown Note',
          ),
        pluginItem('board.sticky'),
        if (onAddGeneric != null && _isPanelTypeAvailable('board.shape'))
          _catalogItem(
            context,
            value: '__shape:frame',
            icon: Icons.interests_outlined,
            iconColor: context.appColors.accentBlue,
            label: 'Shape / Frame',
          ),
      ],
      _PanelCatalogCategory.ai => <PopupMenuEntry<String>?>[
        if (onAddChat != null && _isPanelTypeAvailable('board.chat'))
          _catalogItem(
            context,
            value: '__chat',
            icon: Icons.auto_awesome,
            iconColor: context.appColors.statusActive,
            label: 'AI Chat',
          ),
        if (onAddTerminal != null && _isPanelTypeAvailable('board.terminal'))
          _catalogItem(
            context,
            value: '__terminal',
            icon: Icons.terminal,
            iconColor: context.appColors.statusActive,
            label: 'Terminal',
          ),
        pluginItem('board.yolo_assistant'),
      ],
      _PanelCatalogCategory.files => <PopupMenuEntry<String>?>[
        pluginItem('board.filetree'),
        pluginItem('board.files'),
        pluginItem('board.file.preview'),
        pluginItem('board.webpage'),
      ],
      _PanelCatalogCategory.planning => <PopupMenuEntry<String>?>[
        pluginItem('board.kanban'),
        pluginItem('board.checklist'),
        pluginItem('board.timer'),
      ],
      _PanelCatalogCategory.advanced => <PopupMenuEntry<String>?>[
        pluginItem('board.setup_guide'),
        pluginItem('board.code.snippet'),
        pluginItem('board.playlist'),
        pluginItem('board.run_configs'),
        pluginItem('board.widget.custom'),
      ],
    };
    return items.whereType<PopupMenuEntry<String>>().toList();
  }

  bool _isPanelTypeAvailable(String typeId) {
    return yoloitdPanelTypeAvailableOn(
      typeId,
      platform: platform,
      remote: isRemoteBoard(board),
    );
  }

  PopupMenuItem<String> _catalogItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 52,
      child: Row(
        children: [
          Icon(icon, size: 21, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _menuTextColor(context),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _menuColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? context.appColors.surface
        : context.appColors.surfaceElevated;
  }

  Color _menuTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF252A31)
        : (Theme.of(context).textTheme.bodyMedium?.color ??
            Theme.of(context).colorScheme.onSurface);
  }
}

enum _PanelCatalogCategory { basics, ai, files, planning, advanced }

// ─────────────────────────────────────────────────────────────────────────────
// Draw settings panel
// ─────────────────────────────────────────────────────────────────────────────

class _DrawSettingsPanel extends StatelessWidget {
  const _DrawSettingsPanel({required this.settings, required this.onChanged});

  final DrawSettings settings;
  final ValueChanged<DrawSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        context.appColors.textMuted;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(0xE5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Draw settings',
            style: TextStyle(
              color: mutedColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Color swatches
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in [
                colors.primaryLight,
                colors.accentBlue,
                colors.statusActive,
                colors.statusWarning,
                colors.statusError,
                colors.textPrimary,
              ])
                GestureDetector(
                  onTap: () => onChanged(settings.copyWith(strokeColor: c)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            settings.strokeColor == c
                                ? colors.textPrimary
                                : colors.textPrimary.withAlpha(40),
                        width: settings.strokeColor == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              // Custom color picker
              GestureDetector(
                onTap: () async {
                  Color picked = settings.strokeColor;
                  await showDialog<void>(
                    context: context,
                    builder:
                        (ctx) => AlertDialog(
                          title: const Text('Stroke color'),
                          content: ColorPicker(
                            pickerColor: picked,
                            onColorChanged: (c) => picked = c,
                            enableAlpha: false,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                onChanged(
                                  settings.copyWith(strokeColor: picked),
                                );
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                  );
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: SweepGradient(
                      colors: [
                        colors.statusError,
                        colors.statusWarning,
                        colors.statusActive,
                        colors.accentBlue,
                        colors.primary,
                        colors.primaryLight,
                        colors.statusError,
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textPrimary.withAlpha(60)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stroke width slider
          Text('Size', style: TextStyle(color: mutedColor, fontSize: 11)),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: settings.strokeColor,
              thumbColor: settings.strokeColor,
              overlayColor: settings.strokeColor.withAlpha(40),
              inactiveTrackColor: colors.border,
            ),
            child: Slider(
              value: settings.strokeWidth,
              min: 1,
              max: 20,
              onChanged: (v) => onChanged(settings.copyWith(strokeWidth: v)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connect settings panel
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectSettingsPanel extends StatelessWidget {
  const _ConnectSettingsPanel({
    required this.settings,
    required this.onChanged,
  });

  final ConnectSettings settings;
  final ValueChanged<ConnectSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        context.appColors.textMuted;
    final activeColor = settings.color;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(0xE5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Connect',
            style: TextStyle(
              color: mutedColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // ── Live mini preview ──────────────────────────────────────────
          SizedBox(
            height: 56,
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  size: const Size(double.infinity, 56),
                  painter: LinkPreviewPainter(
                    geometry: settings.geometry,
                    showArrow: settings.showArrow,
                    color: activeColor,
                    borderColor: colors.border,
                    panelColor: colors.surface,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ── Geometry buttons ───────────────────────────────────────────
          Row(
            children: [
              for (final geo in BoardLinkGeometry.values) ...[
                if (BoardLinkGeometry.values.indexOf(geo) > 0)
                  const SizedBox(width: 4),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(settings.copyWith(geometry: geo)),
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            settings.geometry == geo
                                ? activeColor.withAlpha(25)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              settings.geometry == geo
                                  ? activeColor.withAlpha(160)
                                  : colors.border,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(32, 14),
                            painter: LinkMiniPreviewPainter(
                              geometry: geo,
                              color:
                                  settings.geometry == geo
                                      ? activeColor
                                      : mutedColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            switch (geo) {
                              BoardLinkGeometry.bezier => 'Bézier',
                              BoardLinkGeometry.straight => 'Line',
                              BoardLinkGeometry.elbow => 'Elbow',
                            },
                            style: TextStyle(
                              fontSize: 8,
                              color:
                                  settings.geometry == geo
                                      ? activeColor
                                      : mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // ── Arrow + color row ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Arrow', style: TextStyle(color: mutedColor, fontSize: 11)),
              Transform.scale(
                scale: 0.75,
                alignment: Alignment.centerRight,
                child: Switch.adaptive(
                  value: settings.showArrow,
                  onChanged: (v) => onChanged(settings.copyWith(showArrow: v)),
                  activeColor: activeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── Color swatches ─────────────────────────────────────────────
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final c in [
                colors.accentBlue,
                colors.statusActive,
                colors.statusError,
                colors.statusWarning,
                colors.primaryLight,
                colors.textPrimary,
              ])
                GestureDetector(
                  onTap: () => onChanged(settings.copyWith(color: c)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            settings.color == c
                                ? colors.textPrimary
                                : colors.textPrimary.withAlpha(30),
                        width: settings.color == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated glow wrapper for chat panels while processing
// ─────────────────────────────────────────────────────────────────────────────

class _ChatGlowWrapper extends StatefulWidget {
  const _ChatGlowWrapper({
    required this.panelId,
    required this.borderRadius,
    required this.child,
  });

  final String panelId;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<_ChatGlowWrapper> createState() => _ChatGlowWrapperState();
}

class _ChatGlowWrapperState extends State<_ChatGlowWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  ValueNotifier<bool>? _notifier;
  bool _isGlowing = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _attachNotifier();
    // The child widget may register its notifier after us; retry next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notifier == null && mounted) _attachNotifier();
    });
  }

  @override
  void didUpdateWidget(_ChatGlowWrapper old) {
    super.didUpdateWidget(old);
    if (old.panelId != widget.panelId) _attachNotifier();
    // Re-attach if notifier appeared late
    if (_notifier == null) _attachNotifier();
  }

  void _attachNotifier() {
    _notifier?.removeListener(_onNotifierChange);
    _notifier = ChatPanelWidget.processingNotifiers[widget.panelId];
    _notifier?.addListener(_onNotifierChange);
    _onNotifierChange();
  }

  void _onNotifierChange() {
    final processing = _notifier?.value ?? false;
    if (processing != _isGlowing) {
      setState(() => _isGlowing = processing);
      if (processing) {
        _glowCtrl.repeat(reverse: true);
      } else {
        _glowCtrl.stop();
        _glowCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_onNotifierChange);
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow:
                _isGlowing
                    ? [
                      BoxShadow(
                        color: context.appColors.accentGreenGlow.withAlpha(
                          (20 + _glowCtrl.value * 60).round(),
                        ),
                        blurRadius: 16 + _glowCtrl.value * 8,
                        spreadRadius: 2,
                      ),
                    ]
                    : const [],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _ChatHeaderMenu extends StatelessWidget {
  const _ChatHeaderMenu({
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
      builder: (ctx) => _ChatSessionHistoryDialog(panelId: panel.id),
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

class _ChatSessionHistoryDialog extends StatefulWidget {
  const _ChatSessionHistoryDialog({required this.panelId});
  final String panelId;

  @override
  State<_ChatSessionHistoryDialog> createState() =>
      _ChatSessionHistoryDialogState();
}

class _ChatSessionHistoryDialogState extends State<_ChatSessionHistoryDialog> {
  late Future<List<ChatSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = ChatSessionHistory.instance.loadAll();
  }

  void _refresh() {
    setState(() {
      _entriesFuture = ChatSessionHistory.instance.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor =
        context.appColors.textMuted;
    final secondaryColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.history, size: 18, color: secondaryColor),
          const SizedBox(width: 8),
          Text(
            'Session history',
            style: TextStyle(color: onSurface, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 420,
        child: FutureBuilder<List<ChatSessionEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return Center(
                child: Text(
                  'No sessions yet.\nStart chatting to see history here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedColor, fontSize: 13),
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final e = entries[index];
                final isCurrent = e.id == widget.panelId;
                return GestureDetector(
                  onTap:
                      isCurrent
                          ? null
                          : () async {
                            final msgs = await ChatSessionHistory.instance
                                .loadMessages(e.id);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            final cubit = context.read<BoardCubit>();
                            await cubit.createChatPanel(
                              title:
                                  e.sessionName.isNotEmpty
                                      ? e.sessionName
                                      : 'Restored chat',
                              sessionName: e.sessionName,
                              workingDir: e.workingDir,
                              model: e.model,
                              envGroupIds: e.envGroupIds,
                              messages: msgs,
                            );
                          },
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          isCurrent ? colors.surfaceElevated : colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          isCurrent
                              ? Border.all(
                                color: colors.statusActive,
                                width: 0.5,
                              )
                              : null,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: isCurrent ? colors.statusActive : mutedColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.sessionName.isNotEmpty
                                    ? e.sessionName
                                    : 'Unnamed session',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      isCurrent
                                          ? colors.statusActive
                                          : onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${e.provider} • ${e.model} • ${e.messageCount} msgs',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: mutedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatTimeAgo(e.lastMessageAt ?? e.createdAt),
                          style: TextStyle(fontSize: 9, color: mutedColor),
                        ),
                        const SizedBox(width: 6),
                        // Restore: create a new chat panel with this session's messages
                        if (!isCurrent)
                          _actionButton(
                            icon: Icons.restore,
                            color: colors.accentBlue,
                            tooltip: 'Restore as new chat',
                            onTap: () async {
                              final msgs = await ChatSessionHistory.instance
                                  .loadMessages(e.id);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              final cubit = context.read<BoardCubit>();
                              await cubit.createChatPanel(
                                title:
                                    e.sessionName.isNotEmpty
                                        ? e.sessionName
                                        : 'Restored chat',
                                sessionName: e.sessionName,
                                workingDir: e.workingDir,
                                model: e.model,
                                envGroupIds: e.envGroupIds,
                                messages: msgs,
                              );
                            },
                          ),
                        // Delete
                        _actionButton(
                          icon: Icons.delete_outline,
                          color: colors.statusError,
                          tooltip: 'Delete',
                          onTap: () async {
                            await ChatSessionHistory.instance.delete(e.id);
                            _refresh();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// YOLO badge + slide-out chat — always visible bottom-right as a bookmark tab
// ─────────────────────────────────────────────────────────────────────────────

class _YoloBadgeWithChat extends StatefulWidget {
  const _YoloBadgeWithChat();

  @override
  State<_YoloBadgeWithChat> createState() => _YoloBadgeWithChatState();
}

class _YoloBadgeWithChatState extends State<_YoloBadgeWithChat>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceSlide;
  late final Animation<double> _entranceFade;

  late final AnimationController _chatController;
  late final Animation<double> _chatSlide;

  bool _chatOpen = false;
  Timer? _entranceDelayTimer;
  final FocusNode _voiceOverlayFocusNode = FocusNode();
  final YoloAssistantController _assistantController =
      YoloAssistantController();
  // In-memory panel instance for the embedded assistant widget
  BoardPanelInstance _badgePanel = const BoardPanelInstance(
    id: '__yolo_badge_assistant__',
    type: 'board.yolo_assistant',
    title: 'YoLo Assistant',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 380, height: 480),
  );

  @override
  void initState() {
    super.initState();
    // Entrance animation for badge
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.7, curve: Curves.easeOut),
      ),
    );
    _entranceDelayTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _entranceController.forward();
    });

    // Chat panel slide animation
    _chatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _chatSlide = Tween<double>(begin: 380, end: 0).animate(
      CurvedAnimation(parent: _chatController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _entranceDelayTimer?.cancel();
    _voiceOverlayFocusNode.dispose();
    _entranceController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() => _chatOpen = !_chatOpen);
    if (_chatOpen) {
      _chatController.forward();
    } else {
      _chatController.reverse();
    }
  }

  Future<void> _activateVoiceOverlay() async {
    setState(() {
      _badgePanel = _badgePanel.copyWith(
        state: {
          ..._badgePanel.state,
          'voiceOverlayHidden': false,
          'voiceDraft': '',
          'voicePrompt': '',
          'voiceResponse': '',
          'assistantStatus': 'idle',
        },
      );
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;
    _voiceOverlayFocusNode.requestFocus();
    await _assistantController.startMic();
  }

  Future<void> _hideVoiceOverlay() async {
    if (_assistantStatus == 'listening') {
      await _assistantController.cancelMic();
    } else {
      _assistantController.resetOverlay();
    }
    if (!mounted) return;
    _voiceOverlayFocusNode.unfocus();
  }

  Future<void> _handleVoiceOverlayPrimaryAction() async {
    switch (_assistantStatus) {
      case 'listening':
        await _assistantController.stopMic(sendAfterTranscription: true);
      case 'processing':
      case 'thinking':
      case 'responding':
        return;
      case 'output':
        await _activateVoiceOverlay();
      case 'ready':
        if (_voiceDraft.trim().isNotEmpty) {
          await _assistantController.sendDraft();
        } else {
          await _activateVoiceOverlay();
        }
      default:
        await _activateVoiceOverlay();
    }
    if (mounted) _voiceOverlayFocusNode.requestFocus();
  }

  String get _assistantStatus =>
      _badgePanel.state['assistantStatus'] as String? ?? 'idle';

  bool get _voiceOverlayHidden =>
      _badgePanel.state['voiceOverlayHidden'] as bool? ?? true;

  String get _voiceDraft => _badgePanel.state['voiceDraft'] as String? ?? '';

  String get _voicePrompt => _badgePanel.state['voicePrompt'] as String? ?? '';

  String get _voiceResponse =>
      _badgePanel.state['voiceResponse'] as String? ?? '';

  String get _voiceOverlayTitle {
    switch (_assistantStatus) {
      case 'listening':
        return 'Listening...';
      case 'processing':
        return 'Sending Audio...';
      case 'thinking':
        return 'Thinking...';
      case 'responding':
        return 'Here is what I found for you:';
      case 'output':
        return 'Here is what I found for you:';
      case 'ready':
        return 'Ready to send';
      default:
        return 'Voice command';
    }
  }

  String get _voiceOverlayHint {
    switch (_assistantStatus) {
      case 'listening':
        return 'Click or [Space] to Send';
      case 'processing':
        return 'Please wait';
      case 'thinking':
        return 'YoLo is preparing an answer...';
      case 'responding':
        return 'Streaming into this bubble and the YOLO chat.';
      case 'output':
        return 'Press Esc to hide.';
      case 'ready':
        return 'Click or [Space] to Send';
      default:
        return 'Click or [Space] to Send';
    }
  }

  String get _lastUserMessage {
    final messages =
        (_badgePanel.state['messages'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList()
            .reversed;
    for (final message in messages) {
      if ((message['role'] as String?) == 'user') {
        return message['content'] as String? ?? '';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_entranceSlide.value, 0),
          child: Opacity(opacity: _entranceFade.value, child: child),
        );
      },
      child: SizedBox(
        width: double.infinity,
        height: 540,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Voice overlay (bottom center, chat overlaps when open) ──
            Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: const Offset(0, 56),
                child: _buildVoiceOverlay(context),
              ),
            ),
            // ── Chat tab + panel (bottom-right, on top of overlay) ──
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildChatTab(context),
                  ),
                  AnimatedBuilder(
                    animation: _chatController,
                    builder: (context, child) {
                      final progress = 1.0 - (_chatSlide.value / 380);
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                          ),
                          boxShadow:
                              progress > 0.05
                                  ? [
                                    BoxShadow(
                                      color: context.appColors.background
                                          .withValues(alpha: 0.14 * progress),
                                      blurRadius: 20,
                                      spreadRadius: -4,
                                      offset: const Offset(-8, 8),
                                    ),
                                  ]
                                  : [],
                        ),
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth =
                            MediaQuery.sizeOf(context).width - 44;
                        return SizedBox(
                          width: availableWidth.clamp(260.0, 380.0),
                          height: 480,
                          child: _buildChatPanel(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: _toggleChat,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.primary, colors.primaryLight],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(-2, 2),
              ),
            ],
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child:
                _chatOpen
                    ? Icon(Icons.close, size: 14, color: colors.textPrimary)
                    : Text(
                      'YOLO',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceOverlay(BuildContext context) {
    final transcript =
        _voiceDraft.trim().isNotEmpty
            ? _voiceDraft
            : (_voicePrompt.trim().isNotEmpty
                ? _voicePrompt
                : _lastUserMessage);
    return YoloVoiceOverlay(
      status: _voiceOverlayHidden ? 'idle' : _assistantStatus,
      title: _voiceOverlayTitle,
      hint: _voiceOverlayHint,
      transcript: transcript,
      response: _voiceResponse,
      focusNode: _voiceOverlayFocusNode,
      onHide: () => unawaited(_hideVoiceOverlay()),
      onPrimaryAction: () => unawaited(_handleVoiceOverlayPrimaryAction()),
      scale: 0.70,
      orbScale: 0.30,
      ovalWidth: 2.00,
      ovalHeight: 1.10,
      titleFontSize: 9.0,
      titleColor:
          Theme.of(context).brightness == Brightness.dark
              ? context.appColors.terminalPrompt
              : context.appColors.accentBlue,
      waveBarCount: 22,
      waveAmplitude: 0.85,
      waveSpeed: 1400,
      waveWidth: 160.0,
      waveSpread: 0.50,
      particleScale: 0.50,
      responseFontSize: 15.0,
      borderSpeed: 1700,
      responseActionLabel: 'Tap YoLo to speak',
      showIdleHint: false,
      orbAlignY: 0.62,
      responseOrbAlignY: 0.66,
      micAmplitudeStream: _assistantController.micAmplitudeStream,
    );
  }

  Widget _buildChatPanel() {
    final colors = AppColorScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: YoloAssistantWidget(
        panel: _badgePanel,
        controller: _assistantController,
        onUpdateState: (newState) {
          setState(() {
            _badgePanel = _badgePanel.copyWith(state: newState);
          });
        },
      ),
    );
  }
}
