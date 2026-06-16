import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_constants.dart';
import 'package:yoloit/features/board/ui/board_drawing_widgets.dart';
import 'package:yoloit/features/board/ui/board_grid_painter.dart';
import 'package:yoloit/features/board/ui/board_group_overlay.dart';
import 'package:yoloit/features/board/ui/board_history_panel.dart';
import 'package:yoloit/features/board/ui/board_link_widgets.dart';
import 'package:yoloit/features/board/ui/board_links_painter.dart';
import 'package:yoloit/features/board/ui/board_math.dart';
import 'package:yoloit/features/board/ui/board_overview_layer.dart';
import 'package:yoloit/features/board/ui/board_overview_widgets.dart';
import 'package:yoloit/features/board/ui/board_panel_actions.dart';
import 'package:yoloit/features/board/ui/board_panel_card.dart';
import 'package:yoloit/features/board/ui/board_panel_layer.dart';
import 'package:yoloit/features/board/ui/board_toolbar.dart';
import 'package:yoloit/features/board/ui/board_tools_panel.dart';
import 'package:yoloit/features/board/ui/dialogs/board_settings_dialog.dart';
import 'package:yoloit/features/board/ui/dialogs/connect_remote_yoloit_dialog.dart';
import 'package:yoloit/features/board/ui/dialogs/share_board_dialog.dart';
import 'package:yoloit/features/board/ui/infinite_grid_painter.dart';
import 'package:yoloit/features/board/ui/webview_overlays.dart';
import 'package:yoloit/features/board/ui/widgets/board_empty_state.dart';
import 'package:yoloit/features/board/ui/widgets/board_selection_toolbar.dart';
import 'package:yoloit/features/board/ui/widgets/board_top_right_controls.dart';
import 'package:yoloit/features/board/ui/widgets/cancel_connection_bar.dart';
import 'package:yoloit/features/board/ui/widgets/link_delete_badges.dart';
import 'package:yoloit/features/board/ui/yolo_badge_with_chat.dart';
import 'package:yoloit/features/board/utils/board_grid_layout.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/search/ui/file_search_overlay.dart';


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
  Size _canvasSize = initialCanvasSize;
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
  Offset _gridDragAccumulatedDelta = Offset.zero;
  String? _transformingPanelId;
  BoardPanelBounds? _transformStartBounds;
  bool _isCurrentTransformResize = false;

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

  // ── Multi-select state ────────────────────────────────────────────────────
  Offset? _multiSelectStart;
  Offset? _multiSelectCurrent;
  String? _multiSelectStartPanelId;
  bool _multiSelectHasDragged = false;

  /// Link id currently hovered (for showing delete badge).

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
                BoardToolbar(
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
                        final selectedPanelIds = state.selectedPanelIds;

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
                                        isComplex: true,
                                        painter:
                                            activeBoard.gridMode.enabled
                                                ? BoardGridPainter(
                                                  transformCtrl:
                                                      _transformController,
                                                  origin: _canvasOrigin,
                                                  cellSize:
                                                      activeBoard
                                                          .gridMode
                                                          .cellSize,
                                                  spacing:
                                                      activeBoard
                                                          .gridMode
                                                          .spacing,
                                                  color: colors.divider
                                                      .withAlpha(90),
                                                )
                                                : InfiniteBoardGridPainter(
                                                  transformCtrl:
                                                      _transformController,
                                                  origin: _canvasOrigin,
                                                  minorColor: colors.divider
                                                      .withAlpha(60),
                                                  majorColor: colors.divider
                                                      .withAlpha(110),
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
                                        assert(() {
                                          debugPrint(
                                            '[BoardViewLock] activeCount=$activeCount, isLocked=$isLocked',
                                          );
                                          return true;
                                        }());
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
                                            final scale = matrixScaleOf(
                                              _transformController.value,
                                            );
                                            _boardSupportLog(
                                              'pointerScroll locked=$isLocked '
                                              'canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} '
                                              'overScrollable=$overScrollable '
                                              'tool=${_activeTool.name} '
                                              'kind=${event.kind.name} '
                                              'delta=${fmtOffset(event.scrollDelta)} '
                                              'pos=${fmtOffset(event.position)} '
                                              'scale=${fmtDouble(scale)}',
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
                                              'pos=${fmtOffset(event.position)}',
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
                                            'pos=${fmtOffset(event.position)} '
                                            'scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
                                          );
                                        },
                                        onPointerPanZoomUpdate: (event) {
                                          _boardSupportLog(
                                            'panZoom.update locked=$isLocked '
                                            'tool=${_activeTool.name} '
                                            'pan=${fmtOffset(event.pan)} '
                                            'panDelta=${fmtOffset(event.panDelta)} '
                                            'scale=${fmtDouble(event.scale)} '
                                            'rotation=${event.rotation.toStringAsFixed(3)} '
                                            'viewScale=${fmtDouble(matrixScaleOf(_transformController.value))}',
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
                                            'scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
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
                                            canvasExpansionChunk,
                                          ),
                                          // Disable pan while actively drawing,
                                          // in multi-select mode, or when canvas is locked.
                                          panEnabled:
                                              (_activeTool !=
                                                      BoardToolId.draw ||
                                                  _drawPointer == null) &&
                                              _activeTool !=
                                                  BoardToolId.multiSelect,
                                          transformationController:
                                              _transformController,
                                          onInteractionStart: (details) {
                                            final startScale = matrixScaleOf(
                                              _transformController.value,
                                            );
                                            _boardSupportLog(
                                              'interaction.start locked=$isLocked '
                                              'tool=${_activeTool.name} '
                                              'pointerCount=${details.pointerCount} '
                                              'focal=${fmtOffset(details.focalPoint)} '
                                              'local=${fmtOffset(details.localFocalPoint)} '
                                              'scale=${fmtDouble(startScale)}',
                                            );
                                            _interactionStartScale =
                                                matrixScaleOf(
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
                                            final currentScale = matrixScaleOf(
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
                                                'scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
                                              );
                                              _transformController.value =
                                                  _interactionStartMatrix!;
                                              return;
                                            }
                                            _boardSupportLog(
                                              'interaction.update locked=$isLocked '
                                              'tool=${_activeTool.name} '
                                              'pointerCount=${details.pointerCount} '
                                              'scaleDelta=${fmtDouble(details.scale)} '
                                              'currentScale=${fmtDouble(currentScale)} '
                                              'focalDelta=${fmtOffset(details.focalPointDelta)}',
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
                                              'velocity=${fmtOffset(details.velocity.pixelsPerSecond)} '
                                              'scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
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
                                                      isComplex: true,
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
                                                      if (_activeTool ==
                                                          BoardToolId
                                                              .multiSelect) {
                                                        context
                                                            .read<BoardCubit>()
                                                            .clearSelection();
                                                        return;
                                                      }
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
                                                // ── Group backgrounds & headers ────────────
                                                BoardGroupOverlay(
                                                  board: activeBoard,
                                                  origin: _canvasOrigin,
                                                  onToggleCollapse: (groupId) {
                                                    context
                                                        .read<BoardCubit>()
                                                        .toggleGroupCollapse(
                                                          activeBoard.id,
                                                          groupId,
                                                        );
                                                  },
                                                  onMoveGroupStart: (_) {},
                                                  onMoveGroup: (
                                                    groupId,
                                                    details,
                                                  ) =>
                                                      _moveGroupWithEdgePan(
                                                        context,
                                                        groupId,
                                                        details,
                                                      ),
                                                  onMoveGroupEnd: (_) {},
                                                  onRenameGroup: (groupId) {
                                                    _showRenameGroupDialog(
                                                      context,
                                                      activeBoard.id,
                                                      groupId,
                                                    );
                                                  },
                                                  onCycleFocus: (
                                                    groupId,
                                                    direction,
                                                  ) {
                                                    context
                                                        .read<BoardCubit>()
                                                        .cycleGroupFocus(
                                                          activeBoard.id,
                                                          groupId,
                                                          direction,
                                                        );
                                                  },
                                                  onResizeCollapsedGroup: (
                                                    groupId,
                                                    bounds,
                                                  ) {
                                                    context
                                                        .read<BoardCubit>()
                                                        .resizeGroupCollapsedBounds(
                                                          activeBoard.id,
                                                          groupId,
                                                          bounds,
                                                        );
                                                  },
                                                ),
                                                // ── Link delete badges ─────────────────────
                                                if (_activeTool ==
                                                    BoardToolId.select)
                                                  LinkDeleteBadges(
                                                    links: activeBoard.links,
                                                    panels: activeBoard.panels,
                                                    origin: _canvasOrigin,
                                                  ),
                                                BoardPanelLayer(
                                                  board: activeBoard,
                                                  canvasOrigin: _canvasOrigin,
                                                  isCapturingScreenshot:
                                                      _isCapturingScreenshot,
                                                  selectedPanelIds:
                                                      selectedPanelIds.toSet(),
                                                  activeTool: _activeTool,
                                                  connectSourceId:
                                                      _connectSourceId,
                                                  onMovePanel:
                                                      _movePanelWithEdgePan,
                                                  onResizePanel:
                                                      _resizePanelWithEdgePan,
                                                  onDragStart:
                                                      _handlePanelDragStart,
                                                  onDragEnd: _handlePanelDragEnd,
                                                  onConnectTap:
                                                      _handleConnectTap,
                                                ),
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
                                                // ── Multi-select marquee overlay ──────────
                                                if (_activeTool ==
                                                    BoardToolId.multiSelect)
                                                  _buildMultiSelectOverlay(
                                                    context,
                                                    activeBoard,
                                                  ),
                                                if (_multiSelectStart != null &&
                                                    _multiSelectCurrent != null)
                                                  _buildMultiSelectRect(),
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
                                    child: WebViewOverlays(
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
                                    BoardEmptyState(
                                      onAddNote:
                                          () => BoardPanelActions.showAddNoteDialog(
                                            context,
                                          ),
                                    ),
                                  if (!_isBoardOverviewOpen &&
                                      !_isCapturingScreenshot)
                                    BoardTopRightControls(
                                      showMinimap: _showMinimap,
                                      onToggleMinimap:
                                          () => setState(
                                            () => _showMinimap = !_showMinimap,
                                          ),
                                      onFitBoard:
                                          () => _fitBoardPanels(
                                            activeBoard,
                                            persist: true,
                                          ),
                                      isGridMode: activeBoard.gridMode.enabled,
                                      onToggleGrid:
                                          () => context
                                              .read<BoardCubit>()
                                              .setGridMode(
                                                activeBoard.id,
                                                enabled:
                                                    !activeBoard
                                                        .gridMode
                                                        .enabled,
                                              ),
                                      onResetGrid:
                                          () => context
                                              .read<BoardCubit>()
                                              .resetGridView(activeBoard.id),
                                      onGroupByType:
                                          () => context
                                              .read<BoardCubit>()
                                              .arrangePanelsByTypeInGrid(
                                                activeBoard.id,
                                              ),
                                      panels: activeBoard.panels,
                                      transformController: _transformController,
                                      viewportSize:
                                          _viewportSize ?? const Size(1, 1),
                                      origin: _canvasOrigin,
                                      onPanTo:
                                          (center) => _centerViewportOn(
                                            activeBoard,
                                            center,
                                            persist: true,
                                          ),
                                    ),
                                  if (!_isBoardOverviewOpen &&
                                      !_isCapturingScreenshot)
                                    Positioned(
                                      left: 12,
                                      top: 12,
                                      child: BoardToolsPanel(
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
                                              _clearMultiSelectGesture();
                                              if (tool !=
                                                  BoardToolId.multiSelect) {
                                                context
                                                    .read<BoardCubit>()
                                                    .clearSelection();
                                              }
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
                                            () => BoardPanelActions.showAddNoteDialog(
                                              context,
                                            ),
                                        onAddChat:
                                            () => context
                                                .read<BoardCubit>()
                                                .createChatPanel(
                                                  configured: false,
                                                ),
                                        onAddTerminal:
                                            () =>
                                                context
                                                    .read<BoardCubit>()
                                                    .createTerminalPanel(),
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
                                    CancelConnectionBar(
                                      onCancel:
                                          () => setState(() {
                                            _connectSourceId = null;
                                            _connectPreviewPointer = null;
                                          }),
                                    ),
                                  // ── Multi-selection toolbar ────────────────────────
                                  if (!_isBoardOverviewOpen &&
                                      !_isCapturingScreenshot &&
                                      selectedPanelIds.isNotEmpty)
                                    Positioned(
                                      top: 12,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: BoardSelectionToolbar(
                                          selectedCount:
                                              selectedPanelIds.length,
                                          onClear:
                                              () => context
                                                  .read<BoardCubit>()
                                                  .clearSelection(),
                                          onAddToGroup:
                                              () => _addSelectionToGroup(
                                                context,
                                                activeBoard,
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
                                child: YoloBadgeWithChat(),
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
      'syncViewport board=${board.id} scale=${fmtDouble(vp.scale)} '
      'translation=${fmtOffset(vp.translation)} '
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
    final scale = matrixScaleOf(_transformController.value);
    final translation = Offset(
      matrix[12] + (_canvasOrigin.dx * scale),
      matrix[13] + (_canvasOrigin.dy * scale),
    );
    _boardOverviewLog(
      'persistViewport board=${board.id} scale=${fmtDouble(scale)} '
      'translation=${fmtOffset(translation)}',
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
        'vpScale=${fmtDouble(board.viewport.scale)} '
        'vpTx=${fmtOffset(board.viewport.translation)}',
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
      'fitBoardPanels scale=${fmtDouble(scale)} topLeft=${fmtOffset(Offset(tx, ty))} '
      'screen=${fmtSize(screen)} panels=${visiblePanels.length} persist=$persist',
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
    final scale = matrixScaleOf(_transformController.value);
    final tx = canvasCenter.dx - screen.width / (2 * scale);
    final ty = canvasCenter.dy - screen.height / (2 * scale);
    _boardDebugLog(
      'centerViewportOn center=${fmtOffset(canvasCenter)} scale=${fmtDouble(scale)} '
      'topLeft=${fmtOffset(Offset(tx, ty))} persist=$persist',
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
      'scale=${fmtDouble(targetScale)} center=${fmtOffset(panelRect.center)} persist=true',
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
    final board = context.read<BoardCubit>().state.activeBoard;
    if (board != null && board.gridMode.enabled) {
      _gridDragAccumulatedDelta += delta;
      // In grid mode the panel follows the pointer smoothly during the drag;
      // the snap and neighbour-push happen on drag end.
      context.read<BoardCubit>().movePanel(panelId, delta);
      return;
    }
    context.read<BoardCubit>().movePanel(panelId, delta);
  }

  void _moveGroupWithEdgePan(
    BuildContext context,
    String groupId,
    DragUpdateDetails details,
  ) {
    _panViewportNearEdge(details.globalPosition);
    final delta = _consumePanelDragDelta(details.globalPosition, details.delta);
    final board = context.read<BoardCubit>().state.activeBoard;
    if (board == null) return;
    context.read<BoardCubit>().moveGroup(board.id, groupId, delta);
  }

  void _resizePanelWithEdgePan(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelResizeUpdate update,
  ) {
    _panViewportNearEdge(update.globalPosition);
    final delta = _consumePanelDragDelta(update.globalPosition, update.delta);
    _isCurrentTransformResize = true;
    final next = _resizeBoundsForHandle(panel, update.handle, delta);
    context.read<BoardCubit>().updatePanel(
      panel.id,
      (p) => p.copyWith(bounds: next),
    );
  }

  BoardPanelBounds _resizeBoundsForHandle(
    BoardPanelInstance panel,
    BoardPanelResizeHandle handle,
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
    _gridDragAccumulatedDelta = Offset.zero;
    _isCurrentTransformResize = false;
    _transformingPanelId = panelId;
    final board = context.read<BoardCubit>().state.activeBoard;
    final panel = board?.panels.where((p) => p.id == panelId).firstOrNull;
    _transformStartBounds = panel?.bounds;
    _boardDebugLog('panelDrag.start panel=$panelId');
    _stopPanAnimation();
  }

  void _handlePanelDragEnd() {
    _boardDebugLog('panelDrag.end');
    _isPanelDragging = false;
    _lastPanelDragBoardPointer = null;
    final board = context.read<BoardCubit>().state.activeBoard;
    if (board != null && board.gridMode.enabled) {
      _commitPanelGridTransform(board);
    }
    if (board != null) {
      _persistViewport(context, board);
    }
    _scheduleCanvasExpansionIfNeeded();
  }

  void _commitPanelGridTransform(BoardDocument board) {
    final panelId = _transformingPanelId;
    final startBounds = _transformStartBounds;
    if (panelId == null || startBounds == null) return;

    final mode = board.gridMode;
    final pitch = mode.cellSize + mode.spacing;

    GridRect targetRect;
    if (_isCurrentTransformResize) {
      // For a resize, snap the freeform result to the nearest grid cell.
      final panel = board.panels.where((p) => p.id == panelId).firstOrNull;
      if (panel == null) return;
      targetRect = boundsToGridRect(mode, panel.bounds);
    } else {
      // For a drag, snap the drop point to the cell offset from the start cell.
      final startRect = boundsToGridRect(mode, startBounds);
      final dCol = (_gridDragAccumulatedDelta.dx / pitch).round();
      final dRow = (_gridDragAccumulatedDelta.dy / pitch).round();
      targetRect = startRect.shifted(dCol, dRow);
    }

    context.read<BoardCubit>().placePanelInGrid(
      board.id,
      panelId,
      targetRect: targetRect,
    );

    _transformingPanelId = null;
    _transformStartBounds = null;
    _isCurrentTransformResize = false;
    _gridDragAccumulatedDelta = Offset.zero;
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
      'panelDrag.delta pointer=${fmtOffset(current)} delta=${fmtOffset(delta)} fallback=${fmtOffset(fallbackDelta)}',
    );
    return delta;
  }

  Widget _buildMultiSelectOverlay(
    BuildContext context,
    BoardDocument board,
  ) {
    return Positioned.fill(
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            final point = _boardPointFromGlobal(e.position);
            if (point == null) return;
            setState(() {
              _multiSelectStart = point;
              _multiSelectCurrent = point;
              _multiSelectHasDragged = false;
              _multiSelectStartPanelId = _panelIdAtBoardPoint(board, point);
            });
          },
          onPointerMove: (e) {
            if (_multiSelectStart == null) return;
            final point = _boardPointFromGlobal(e.position);
            if (point == null) return;
            if ((point - _multiSelectStart!).distance > 4) {
              setState(() => _multiSelectHasDragged = true);
            }
            setState(() => _multiSelectCurrent = point);
          },
          onPointerUp: (e) {
            _finishMultiSelectGesture(context, board);
          },
          onPointerCancel: (_) {
            setState(_clearMultiSelectGesture);
          },
        ),
      ),
    );
  }

  Widget _buildMultiSelectRect() {
    final start = _multiSelectStart!;
    final current = _multiSelectCurrent!;
    final left = math.min(start.dx, current.dx) + _canvasOrigin.dx;
    final top = math.min(start.dy, current.dy) + _canvasOrigin.dy;
    final width = (start.dx - current.dx).abs();
    final height = (start.dy - current.dy).abs();
    final colors = context.appColors;
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: colors.statusActive.withAlpha(30),
          border: Border.all(color: colors.statusActive, width: 1.5),
        ),
      ),
    );
  }

  String? _panelIdAtBoardPoint(BoardDocument board, Offset point) {
    for (var i = board.panels.length - 1; i >= 0; i--) {
      final panel = board.panels[i];
      if (panel.hidden) continue;
      final rect = Rect.fromLTWH(
        panel.bounds.x,
        panel.bounds.y,
        panel.bounds.width,
        panel.bounds.height,
      );
      if (rect.contains(point)) return panel.id;
    }
    return null;
  }

  void _finishMultiSelectGesture(BuildContext context, BoardDocument board) {
    final start = _multiSelectStart;
    final hasDragged = _multiSelectHasDragged;
    final startPanelId = _multiSelectStartPanelId;
    final cubit = context.read<BoardCubit>();
    if (start == null) {
      setState(_clearMultiSelectGesture);
      return;
    }
    if (!hasDragged) {
      if (startPanelId != null) {
        cubit.togglePanelSelection(startPanelId);
      } else {
        cubit.clearSelection();
      }
    } else {
      final current = _multiSelectCurrent ?? start;
      final rect = Rect.fromPoints(start, current);
      cubit.selectPanelsInRect(rect);
    }
    setState(_clearMultiSelectGesture);
  }

  void _clearMultiSelectGesture() {
    _multiSelectStart = null;
    _multiSelectCurrent = null;
    _multiSelectStartPanelId = null;
    _multiSelectHasDragged = false;
  }

  Future<void> _addSelectionToGroup(
    BuildContext context,
    BoardDocument board,
  ) async {
    final cubit = context.read<BoardCubit>();
    final result = await showDialog<
      ({String? groupId, String? newName})?
    >(
      context: context,
      builder:
          (_) => BoardSelectionGroupDialog(groups: board.groups),
    );
    if (result == null) return;
    if (result.newName != null && result.newName!.trim().isNotEmpty) {
      await cubit.createGroupFromSelection(name: result.newName!.trim());
      return;
    }
    if (result.groupId != null) {
      await cubit.addPanelsToGroup(
        board.id,
        result.groupId!,
        cubit.state.selectedPanelIds.toList(),
      );
      cubit.clearSelection();
    }
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

    final scale = matrixScaleOf(_transformController.value);
    if (scale == 0) return;

    final matrix = _transformController.value.clone();
    final storage = matrix.storage;
    storage[12] -= screenDelta.dx;
    storage[13] -= screenDelta.dy;
    _transformController.value = matrix;

    _boardDebugLog(
      'edgePan local=${fmtOffset(local)} screenDelta=${fmtOffset(screenDelta)} '
      'boardDelta=${fmtOffset(screenDelta / scale)} scale=${fmtDouble(scale)}',
    );
  }

  double _edgePanStep(double position, double extent) {
    if (extent <= 0) return 0;
    if (position < edgePanZone) {
      final t = ((edgePanZone - position) / edgePanZone).clamp(0.0, 1.0);
      return -edgePanMaxStep * Curves.easeOut.transform(t);
    }
    if (extent - position < edgePanZone) {
      final t = ((edgePanZone - (extent - position)) / edgePanZone).clamp(
        0.0,
        1.0,
      );
      return edgePanMaxStep * Curves.easeOut.transform(t);
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

    if (visible.left < canvasExpansionMargin) {
      addLeft = canvasExpansionChunk;
    }
    if (visible.top < canvasExpansionMargin) {
      addTop = canvasExpansionChunk;
    }
    if (_canvasSize.width - visible.right < canvasExpansionMargin) {
      addRight = canvasExpansionChunk;
    }
    if (_canvasSize.height - visible.bottom < canvasExpansionMargin) {
      addBottom = canvasExpansionChunk;
    }

    if (addLeft == 0 && addTop == 0 && addRight == 0 && addBottom == 0) {
      return;
    }

    final scale = matrixScaleOf(_transformController.value);
    final matrix = _transformController.value.clone();
    final storage = matrix.storage;
    storage[12] -= addLeft * scale;
    storage[13] -= addTop * scale;

    _boardDebugLog(
      'canvas.expand visible=${fmtRect(visible)} add=(${fmtDouble(addLeft)}, ${fmtDouble(addTop)}, ${fmtDouble(addRight)}, ${fmtDouble(addBottom)}) '
      'oldSize=${fmtSize(_canvasSize)} oldOrigin=${fmtOffset(_canvasOrigin)} scale=${fmtDouble(scale)}',
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
      'canvas.expanded newSize=${fmtSize(_canvasSize)} newOrigin=${fmtOffset(_canvasOrigin)}',
    );
  }

  void _animateToMatrix(
    Matrix4 target, {
    required BoardDocument board,
    required bool persist,
  }) {
    _boardDebugLog(
      'animateToMatrix board=${board.id} persist=$persist '
      'from=${fmtMatrix(_transformController.value)} to=${fmtMatrix(target)}',
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

  Future<void> _showRenameGroupDialog(
    BuildContext context,
    String boardId,
    String groupId,
  ) async {
    BoardDocument? board;
    for (final candidate in context.read<BoardCubit>().state.boards) {
      if (candidate.id == boardId) {
        board = candidate;
        break;
      }
    }
    BoardPanelGroup? group;
    if (board != null) {
      for (final candidate in board.groups) {
        if (candidate.id == groupId) {
          group = candidate;
          break;
        }
      }
    }
    if (group == null) return;

    final controller = TextEditingController(text: group.name);
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Rename group'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Group name'),
              onSubmitted: (value) {
                context.read<BoardCubit>().renameGroup(
                  boardId,
                  groupId,
                  value,
                );
                Navigator.of(dialogContext).pop();
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  context.read<BoardCubit>().renameGroup(
                    boardId,
                    groupId,
                    controller.text,
                  );
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Rename'),
              ),
            ],
          ),
    );
    controller.dispose();
  }

  void _boardDebugLog(String message) {
    if (!kDebugMode || !const bool.fromEnvironment('YOLOIT_BOARD_DEBUG')) {
      return;
    }
    assert(() {
      debugPrint('[BoardView] $message');
      return true;
    }());
  }

  void _boardSupportLog(String message) {
    SupportLogService.instance.add('board-scroll', message);
  }

  void _boardOverviewLog(String message) {
    if (!kDebugMode) return;
    assert(() {
      debugPrint('[BoardOverview] $message');
      return true;
    }());
  }

  void _boardWebFocusLog(String message) {
    if (!kDebugMode) return;
    assert(() {
      debugPrint('[BoardWebFocus] $message');
      return true;
    }());
  }

  // ── Tool actions ──────────────────────────────────────────────────────────

  /// Builds small ×-badge widgets at the midpoint of each link so the user
  /// can delete them by tapping.
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

  Future<LinkStyleChoice?> _showConnectStyleDialog(BuildContext context) async {
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
}
