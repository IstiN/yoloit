import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';
import 'package:yoloit/core/platform/platform_info.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/services/board_preview_cache.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_canvas_interaction.dart';
import 'package:yoloit/features/board/ui/board_constants.dart';
import 'package:yoloit/features/board/ui/board_drawing_widgets.dart';
import 'package:yoloit/features/board/ui/board_grid_painter.dart';
import 'package:yoloit/features/board/ui/board_group_overlay.dart';
import 'package:yoloit/features/board/ui/board_history_panel.dart';
import 'package:yoloit/features/board/ui/board_history_visibility.dart';
import 'package:yoloit/features/board/ui/board_link_widgets.dart';
import 'package:yoloit/features/board/ui/board_links_painter.dart';
import 'package:yoloit/features/board/ui/board_math.dart';
import 'package:yoloit/features/board/ui/board_overview_layer.dart';
import 'package:yoloit/features/board/ui/board_overview_widgets.dart';
import 'package:yoloit/features/board/ui/board_panel_actions.dart';
import 'package:yoloit/features/board/ui/board_panel_layer.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/board/ui/board_panel_resize_chrome.dart';
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
import 'package:yoloit/features/settings/ui/settings_page.dart';
import 'package:yoloit/features/templates/ui/template_wizard_dialog.dart';

part 'board_view_sections.dart';

class BoardView extends StatefulWidget {
  const BoardView({super.key, this.skipOverviewPreviewCapture = false});

  /// Test-only escape hatch for overview goldens. The production overview
  /// captures live PNG previews before opening; widget tests do not always have
  /// a real frame/image pipeline, so they can render the overview directly.
  final bool skipOverviewPreviewCapture;

  /// When `true`, `onSelectedBoard` skips the PNG preview overlay entirely
  /// and goes straight to `setActiveBoard`. Useful for users / agents that
  /// do not want any fade animation between boards. Off by default.
  @visibleForTesting
  static bool debugDisablePreviewOverlayForTesting = false;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
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
  bool _panZoomLockedByBoard = false;

  String? _syncedBoardId;
  BoardViewport? _syncedViewport;
  String? _autoFitKey;
  String? _focusedPanelVisibilityKey;
  bool _showMinimap = true;
  bool _showToolsPanel = true;
  bool _isBoardOverviewOpen = false;
  bool _isOpeningBoardOverview = false;
  bool _cancelBgCapture = false;
  bool _boardSwitchPreviewVisible = false;
  BoardDocument? _boardSwitchPreviewBoard;
  Uint8List? _boardSwitchPreviewPng;
  Timer? _boardSwitchPreviewFadeTimer;
  int _debugFadeOutCount = 0;
  final Map<String, Uint8List> _boardPreviewPngs = {};
  final BoardPreviewCache _previewCache = BoardPreviewCache.instance;

  bool _isCapturingScreenshot = false;

  String get _currentPanelPlatform {
    if (kIsWeb) return 'web';
    return currentPlatformName;
  }

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

  final List<Offset> _activeStroke = [];

  int? _drawPointer;

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
    _cancelBgCapture = true;
    BoardUndoRedo.undo = null;
    BoardUndoRedo.redo = null;
    _boardSwitchPreviewFadeTimer?.cancel();
    _boardSwitchPreviewFadeTimer = null;
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
      onKeyEvent: _handleBoardKeyEvent,
      child: BlocConsumer<BoardCubit, BoardState>(
        listener: _onBoardStateChanged,
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

          // Expose undo/redo to the app-level title bar (see BoardTitleBar).
          BoardUndoRedo.undo = () =>
              _restoreLatestPanelHistory(context, activeBoard);
          BoardUndoRedo.redo = () =>
              _redoLatestPanelHistory(context, activeBoard);

          return _buildBoardScaffold(context, state, activeBoard, colors);
        },
      ), // BlocBuilder
    ); // Focus
  }

  /// Triggers a rebuild from the section builders in
  /// `board_view_sections.dart` — `setState` is `@protected` and calling it
  /// from an extension trips `invalid_use_of_protected_member`.
  void _rebuild(VoidCallback fn) => setState(fn);

  void _syncViewport(BoardDocument board) {
    final vp = board.viewport;
    final boardSwitched = _syncedBoardId != board.id;
    final externalChange = _hasExternalViewportChange(board, vp);

    if (!boardSwitched && !externalChange) return;
    _syncedBoardId = board.id;
    _syncedViewport = vp;
    _noteViewportSynced(board, vp, boardSwitched, externalChange);
    if (_shouldAutoFit(board)) {
      _boardDebugLog('syncViewport.scheduleAutoFit board=${board.id}');
      _scheduleAutoFitIfNeeded(board);
      return;
    }
    _applyViewportTransform(board, vp);
  }

  /// Detects when the viewport changed externally (e.g. via CLI board:zoom)
  /// while the user is not actively interacting.
  bool _hasExternalViewportChange(BoardDocument board, BoardViewport vp) {
    return _syncedBoardId == board.id &&
        _syncedViewport != null &&
        !_isViewportInteracting &&
        !_isPanelDragging &&
        (_syncedViewport!.scale != vp.scale ||
            _syncedViewport!.translation != vp.translation);
  }

  void _noteViewportSynced(
    BoardDocument board,
    BoardViewport vp,
    bool boardSwitched,
    bool externalChange,
  ) {
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
  }

  void _applyViewportTransform(BoardDocument board, BoardViewport vp) {
    _stopPanAnimation();
    _transformController.value = _matrixFromViewport(vp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoverOffscreenPanelsIfNeeded(board);
    });
  }

  void _recoverOffscreenPanelsIfNeeded(BoardDocument board) {
    if (!mounted || _syncedBoardId != board.id) return;
    if (_shouldAutoFit(board)) return;
    if (_hasVisiblePanels(board) && !_hasAnyPanelInViewport(board)) {
      _boardOverviewLog('syncViewport.recoverOffscreen board=${board.id}');
      _fitBoardPanels(board, persist: true);
    }
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
    _boardOverviewLog('capture.start board=$boardId offscreen fit-all');

    final board = context.read<BoardCubit>().state.boards.firstWhere(
      (candidate) => candidate.id == boardId,
    );
    final bytes = await BoardOffscreenRenderer.instance
        .renderBoardOverviewPreview(board);

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
    _previewCache.save(board, bytes, themeKey: _previewThemeKey);
  }

  String get _previewThemeKey {
    final theme = ThemeManager.instance;
    return '${theme.current.name}:${theme.brightness.name}:'
        '${theme.activeCustomThemeId ?? ''}';
  }

  void _loadBoardPreviewPngsFromDisk() {
    final boards = context.read<BoardCubit>().state.boards;
    for (final board in boards) {
      final bytes = _previewCache.loadPng(board, themeKey: _previewThemeKey);
      if (bytes != null) {
        _boardPreviewPngs[board.id] = bytes;
      } else {
        _boardPreviewPngs.remove(board.id);
      }
    }
  }

  /// Generate a synthetic PNG preview for a board using dart:ui Canvas.
  /// Generate previews for boards that have no cached PNG using offscreen
  /// rendering. This is fast (no frame scheduling needed) and produces
  /// the same quality as the background refresh.
  Future<void> _generateMissingBoardPreviews(String activeBoardId) async {
    final allBoards = context.read<BoardCubit>().state.boards;
    final missing = allBoards
        .where(
          (b) =>
              b.id != activeBoardId &&
              !_boardPreviewPngs.containsKey(b.id) &&
              !_previewCache.isFresh(b, themeKey: _previewThemeKey),
        )
        .toList();
    if (missing.isEmpty) return;

    final cancelToken = CancelToken();
    _boardOverviewLog('offscreen.start count=${missing.length}');
    final watch = Stopwatch()..start();
    final captured = <String, Uint8List>{};
    for (final board in missing) {
      if (!await _captureMissingPreview(board, cancelToken, captured)) break;
    }
    _applyCapturedPreviews(captured);
    _boardOverviewLog(
      'offscreen.done count=${missing.length} elapsed=${watch.elapsedMilliseconds}ms',
    );
  }

  /// Renders one missing board preview. Returns false when the loop must
  /// stop (unmounted, capture cancelled, or overview closed).
  Future<bool> _captureMissingPreview(
    BoardDocument board,
    CancelToken cancelToken,
    Map<String, Uint8List> captured,
  ) async {
    if (!mounted || _cancelBgCapture || !_isBoardOverviewOpen) {
      cancelToken.cancel();
      return false;
    }
    final png = await BoardOffscreenRenderer.instance
        .renderBoardOverviewPreview(board, cancelToken: cancelToken);
    if (png != null) {
      captured[board.id] = png;
      _previewCache.save(board, png, themeKey: _previewThemeKey);
    }
    return true;
  }

  void _applyCapturedPreviews(Map<String, Uint8List> captured) {
    if (captured.isEmpty || !mounted || !_isBoardOverviewOpen) return;
    setState(() {
      _boardPreviewPngs.addAll(captured);
    });
  }

  /// Refresh board previews in the background using offscreen rendering.
  /// Each board is rendered independently from its data model — no board
  /// switching needed, no JSC crashes, no UI flicker.
  Future<void> _refreshBoardPreviewsInBackground(String activeBoardId) async {
    final allBoards = context.read<BoardCubit>().state.boards;
    final toCapture = allBoards
        .where(
          (b) =>
              b.id != activeBoardId &&
              (b.panels.isNotEmpty || b.drawings.any((d) => !d.hidden)) &&
              !_previewCache.isFresh(b, themeKey: _previewThemeKey),
        )
        .toList();
    if (toCapture.isEmpty) return;

    final cancelToken = CancelToken();
    _boardOverviewLog('bgCapture.start count=${toCapture.length} (offscreen)');
    final watch = Stopwatch()..start();
    final captured = <String, Uint8List>{};

    for (final board in toCapture) {
      if (!await _refreshPreviewForBoard(board, cancelToken, captured)) break;
    }

    if (captured.isNotEmpty && mounted) {
      setState(() {
        _boardPreviewPngs.addAll(captured);
      });
    }

    _boardOverviewLog('bgCapture.done elapsed=${watch.elapsedMilliseconds}ms');
  }

  /// Renders one board preview in the background. Returns false when the
  /// loop must stop (capture cancelled, unmounted, or overview closed).
  Future<bool> _refreshPreviewForBoard(
    BoardDocument board,
    CancelToken cancelToken,
    Map<String, Uint8List> captured,
  ) async {
    if (_cancelBgCapture || !mounted || !_isBoardOverviewOpen) {
      cancelToken.cancel();
      _boardOverviewLog('bgCapture.canceled loop broken (transition active)');
      return false;
    }

    final boardWatch = Stopwatch()..start();
    try {
      _boardOverviewLog(
        'bgCapture.render board=${board.id} (${board.name}) started',
      );
      final png = await BoardOffscreenRenderer.instance
          .renderBoardOverviewPreview(board, cancelToken: cancelToken);
      if (_cancelBgCapture || !mounted || !_isBoardOverviewOpen) {
        cancelToken.cancel();
        _boardOverviewLog(
          'bgCapture.render board=${board.id} completed but discarded (transition active)',
        );
        return false;
      }
      _storeRefreshedPreview(board, png, boardWatch, captured);
    } catch (e) {
      _boardOverviewLog(
        'bgCapture.error board=${board.id} $e elapsed=${boardWatch.elapsedMilliseconds}ms',
      );
    }
    return true;
  }

  void _storeRefreshedPreview(
    BoardDocument board,
    Uint8List? png,
    Stopwatch boardWatch,
    Map<String, Uint8List> captured,
  ) {
    if (png != null) {
      captured[board.id] = png;
      _previewCache.save(board, png, themeKey: _previewThemeKey);
      _boardOverviewLog(
        'bgCapture.captured board=${board.id} bytes=${png.length} elapsed=${boardWatch.elapsedMilliseconds}ms',
      );
    } else {
      _boardOverviewLog(
        'bgCapture.render board=${board.id} returned null elapsed=${boardWatch.elapsedMilliseconds}ms',
      );
    }
  }

  Future<void> _warmBoardPreviewCaptures(String activeBoardId) async {
    try {
      final boards = context.read<BoardCubit>().state.boards;
      final activeBoard = boards.firstWhere(
        (board) => board.id == activeBoardId,
      );
      if (!_previewCache.isFresh(activeBoard, themeKey: _previewThemeKey)) {
        await _captureBoardPreviewPng(activeBoardId);
      }
      if (!mounted || _cancelBgCapture || !_isBoardOverviewOpen) return;

      await _generateMissingBoardPreviews(activeBoardId);
      if (!mounted || _cancelBgCapture || !_isBoardOverviewOpen) return;

      await _refreshBoardPreviewsInBackground(activeBoardId);
    } catch (error, stackTrace) {
      _boardOverviewLog('warmPreviews.error $error');
      assert(() {
        debugPrintStack(stackTrace: stackTrace);
        return true;
      }());
    }
  }

  Future<void> _openBoardOverview(BoardDocument activeBoard) async {
    if (_isBoardOverviewOpen || _isOpeningBoardOverview) {
      _boardOverviewLog(
        'open.skip board=${activeBoard.id} '
        'open=$_isBoardOverviewOpen opening=$_isOpeningBoardOverview',
      );
      return;
    }

    final watch = Stopwatch()..start();
    _isOpeningBoardOverview = true;
    _boardOverviewLog(
      'open.request board=${activeBoard.id} boards=${context.read<BoardCubit>().state.boards.length}',
    );

    unawaited(
      context.read<BoardCubit>().refreshRemoteBoards().catchError((
        Object error,
      ) {
        _boardOverviewLog('open.remoteRefresh.error $error');
      }),
    );

    _loadBoardPreviewPngsFromDisk();

    _boardOverviewLog(
      'open.showOverlay board=${activeBoard.id} elapsed=${watch.elapsedMilliseconds}ms',
    );
    if (!mounted) {
      _isOpeningBoardOverview = false;
      return;
    }

    setState(() {
      _isBoardOverviewOpen = true;
      _cancelBgCapture = false;
      _connectSourceId = null;
      _connectPreviewPointer = null;
    });
    _isOpeningBoardOverview = false;

    if (!widget.skipOverviewPreviewCapture) {
      unawaited(_warmBoardPreviewCaptures(activeBoard.id));
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
    if (_isFocusVisibilitySchedulingBlocked(board)) return;
    final focusedPanelId = board.viewport.focusedPanelId!;
    final size = _viewportSize!;
    if (_suppressFocusVisibility) {
      _applySuppressedFocusVisibility(board, focusedPanelId, size);
      return;
    }
    final panel = _findBoardPanel(board, focusedPanelId);
    if (panel == null || panel.hidden) return;
    _scheduleFocusedPanelVisibility(board, panel, size);
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
    // Pan the viewport first so that the board-space delta includes the
    // edge-pan amount. Otherwise the panel lags behind the moving canvas.
    _panViewportNearEdge(details.globalPosition);
    final delta = _consumePanelDragDelta(details.globalPosition, details.delta);
    _reanchorPanelDragPointer(details.globalPosition);
    final board = context.read<BoardCubit>().state.activeBoard;
    if (board != null && board.gridMode.enabled) {
      _gridDragAccumulatedDelta += delta;
      // In grid mode the panel follows the pointer smoothly during the drag;
      // the snap and neighbour-push happen on drag end.
      context.read<BoardCubit>().movePanel(
        panelId,
        delta,
        recordHistory: false,
      );
      return;
    }
    context.read<BoardCubit>().movePanel(panelId, delta, recordHistory: false);
  }

  void _moveGroupWithEdgePan(
    BuildContext context,
    String groupId,
    DragUpdateDetails details,
  ) {
    _panViewportNearEdge(details.globalPosition);
    final delta = _consumePanelDragDelta(details.globalPosition, details.delta);
    _reanchorPanelDragPointer(details.globalPosition);
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
    _reanchorPanelDragPointer(update.globalPosition);
    _isCurrentTransformResize = true;
    final next = _resizeBoundsForHandle(panel, update.handle, delta);
    context.read<BoardCubit>().updatePanel(
      panel.id,
      (p) => p.copyWith(bounds: next),
      recordHistory: false,
    );
  }

  BoardPanelBounds _resizeBoundsForHandle(
    BoardPanelInstance panel,
    BoardPanelResizeHandle handle,
    Offset delta,
  ) {
    const minWidth = 220.0;
    const minHeight = 140.0;
    final maxWidth = panel.type == WebpagePluginBase.kTypeId
        ? 1440.0
        : double.infinity;

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
    context.read<BoardCubit>().beginPanelGesture(panelId, boardId: board?.id);
    _boardDebugLog('panelDrag.start panel=$panelId');
    _stopPanAnimation();
  }

  Future<void> _handlePanelDragEnd() async {
    _boardDebugLog('panelDrag.end');
    _isPanelDragging = false;
    _lastPanelDragBoardPointer = null;
    final cubit = context.read<BoardCubit>();
    final board = cubit.state.activeBoard;
    final panelId = _transformingPanelId;
    if (board != null && board.gridMode.enabled) {
      await _commitPanelGridTransform(board);
    }
    if (panelId != null) {
      unawaited(cubit.endPanelGesture(panelId, boardId: board?.id));
    }
    if (board != null && mounted) {
      _persistViewport(context, board);
    }
    _scheduleCanvasExpansionIfNeeded();
  }

  Future<void> _commitPanelGridTransform(BoardDocument board) async {
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

    await context.read<BoardCubit>().placePanelInGrid(
      board.id,
      panelId,
      targetRect: targetRect,
      recordHistory: false,
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

  // ── Test hooks ────────────────────────────────────────────────────────────
  // Widget tests drive these paths through public forwarders: Dart library
  // privacy applies to dynamic invocations too, so the private members below
  // are unreachable from the test library.

  @visibleForTesting
  void debugHandleGenericToolSelection(BuildContext context, String value) =>
      _handleGenericToolSelection(context, value);

  @visibleForTesting
  BoardToolId get debugActiveTool => _activeTool;

  @visibleForTesting
  ConnectSettings get debugConnectSettings => _connectSettings;

  @visibleForTesting
  Future<void> debugWarmBoardPreviewCaptures(String activeBoardId) =>
      _warmBoardPreviewCaptures(activeBoardId);

  @visibleForTesting
  Future<void> debugRefreshBoardPreviewsInBackground(String activeBoardId) =>
      _refreshBoardPreviewsInBackground(activeBoardId);

  @visibleForTesting
  KeyEventResult debugHandleBoardKeyEvent(KeyEvent event) =>
      _handleBoardKeyEvent(_boardFocus, event);

  @visibleForTesting
  void debugViewerInteractionStart(ScaleStartDetails details) =>
      _onViewerInteractionStart(details, false);

  @visibleForTesting
  void debugViewerInteractionUpdate(ScaleUpdateDetails details) =>
      _onViewerInteractionUpdate(details, false);

  @visibleForTesting
  Size get debugCanvasSize => _canvasSize;

  @visibleForTesting
  Offset get debugCanvasOrigin => _canvasOrigin;

  @visibleForTesting
  bool get debugIsViewportZooming => _isViewportZooming;

  @visibleForTesting
  Matrix4 get debugCanvasTransform => _transformController.value.clone();

  @visibleForTesting
  set debugCanvasTransform(Matrix4 transform) =>
      _transformController.value = transform;

  @visibleForTesting
  void debugSimulateBoardSelection(BoardDocument board, Uint8List? previewPng) {
    if (!mounted) return;
    _runBoardSwitchPreview(board, previewPng);
  }

  @visibleForTesting
  bool get debugIsBoardSwitchPreviewVisible => _boardSwitchPreviewVisible;

  @visibleForTesting
  BoardDocument? get debugBoardSwitchPreviewBoard => _boardSwitchPreviewBoard;

  @visibleForTesting
  Uint8List? get debugBoardSwitchPreviewPng => _boardSwitchPreviewPng;

  @visibleForTesting
  int get debugFadeOutCount => _debugFadeOutCount;

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

  Future<void> _redoLatestPanelHistory(
    BuildContext context,
    BoardDocument board,
  ) async {
    final cubit = context.read<BoardCubit>();
    final redone = await cubit.redoLatestPanelHistory(board.id);
    if (!redone) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No redoable panel history yet')),
      );
    }
  }

  Offset _consumePanelDragDelta(Offset globalPosition, Offset fallbackDelta) {
    final previous = _lastPanelDragBoardPointer;
    final current = _boardPointFromGlobal(globalPosition);
    if (current == null) {
      // Keep the previous anchor so the next event can resume smoothly.
      return Offset.zero;
    }
    if (previous == null) {
      _lastPanelDragBoardPointer = current;
      return Offset.zero;
    }
    _lastPanelDragBoardPointer = current;
    final delta = current - previous;
    _boardDebugLog(
      'panelDrag.delta pointer=${fmtOffset(current)} delta=${fmtOffset(delta)} fallback=${fmtOffset(fallbackDelta)}',
    );
    return delta;
  }

  void _reanchorPanelDragPointer(Offset globalPosition) {
    if (!_isPanelDragging) return;
    _lastPanelDragBoardPointer = _boardPointFromGlobal(globalPosition);
  }

  Widget _buildMultiSelectOverlay(BuildContext context, BoardDocument board) {
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
    final result = await showDialog<({String? groupId, String? newName})?>(
      context: context,
      builder: (_) => BoardSelectionGroupDialog(groups: board.groups),
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

  void _handleFullscreenPanel(BuildContext context, String panelId) {
    final board = context.read<BoardCubit>().state.activeBoard;
    if (board == null) return;
    BoardPanelInstance? panel;
    for (final p in board.panels) {
      if (p.id == panelId) {
        panel = p;
        break;
      }
    }
    if (panel == null || panel.hidden) return;
    _zoomToPanel(board, panel.bounds.rect);
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
      boardEdgePanStep(local.dx, viewport.width),
      boardEdgePanStep(local.dy, viewport.height),
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
    final animation =
        Matrix4Tween(
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
    final groupName = group.name;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _RenameGroupDialog(
        initialName: groupName,
        onSubmit: (value) =>
            context.read<BoardCubit>().renameGroup(boardId, groupId, value),
      ),
    );
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

  Future<void> _createBoardFromTemplate(BuildContext context) async {
    await TemplateWizardDialog.show(context);
  }

  Future<void> _connectRemoteYoloit(BuildContext context) async {
    final result = await showAdaptiveYoloDialog<RemoteYoloitConnection>(
      context: context,
      builder: (_) => const ConnectRemoteYoloitDialog(),
    );
    if (!context.mounted || result == null) return;
    debugPrint('[BoardView] connectRemoteYoloit result url=${result.url}');
    try {
      final boards = await context.read<BoardCubit>().connectRemoteBoards(
        url: result.url,
        token: result.token,
      );
      debugPrint('[BoardView] connectRemoteYoloit boards=${boards.length}');
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
    } catch (error, stackTrace) {
      debugPrint('[BoardView] connectRemoteYoloit error=$error');
      debugPrint('$stackTrace');
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

  Future<void> _openAppSettings(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  Future<void> _showBoardSettings(
    BuildContext context,
    BoardDocument board,
  ) async {
    final remote = remoteInfoForBoard(board);
    final result =
        await showAdaptiveYoloDialog<
          ({
            String name,
            String defaultFolder,
            bool archived,
            BoardIconSpec? icon,
            bool iconChanged,
            List<String> envGroupIds,
            Map<String, String> env,
          })
        >(
          context: context,
          builder: (_) => BoardSettingsDialog(
            initialName: board.name,
            initialDefaultFolder: board.defaultFolder,
            initialArchived: board.archived,
            initialIcon: board.icon,
            initialEnvGroupIds: board.defaultEnvGroupIds,
            initialEnv: board.defaultEnv,
            boardId: board.id,
            remoteInfo: remote,
            onPickFolder: kIsWeb
                ? null
                : () async => BoardFilePicker.pickDirectory(
                    context,
                    remoteInfo: remote,
                    initialPath: board.defaultFolder,
                    title: remote == null
                        ? 'Choose folder'
                        : 'Choose remote folder',
                  ),
          ),
        );
    if (!context.mounted || result == null) return;
    final cubit = context.read<BoardCubit>();
    await cubit.renameBoard(board.id, result.name);
    await cubit.updateBoardDefaultFolder(board.id, result.defaultFolder);
    await cubit.updateBoardDefaultEnv(
      board.id,
      envGroupIds: result.envGroupIds,
      env: result.env,
    );
    if (result.iconChanged) {
      await cubit.updateBoardIcon(board.id, result.icon);
    }
    if (result.archived && !board.archived) {
      await cubit.archiveBoard(board.id);
    } else if (!result.archived && board.archived) {
      await cubit.unarchiveBoard(board.id);
    }
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
      builder: (dialogContext) => AlertDialog(
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
      builder: (dialogContext) => AlertDialog(
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
      builder: (dialogContext) => AlertDialog(
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
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }
}

/// Rename-group dialog that owns its [TextEditingController].
///
/// Owning the controller inside the dialog's [State] keeps it alive for the
/// whole exit animation — disposing it right after `showDialog` resolves
/// leaves the still-visible [TextField] holding a disposed controller.
class _RenameGroupDialog extends StatefulWidget {
  const _RenameGroupDialog({required this.initialName, required this.onSubmit});

  final String initialName;
  final ValueChanged<String> onSubmit;

  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename group'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Group name'),
        onSubmitted: (value) {
          widget.onSubmit(value);
          Navigator.of(context).pop();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onSubmit(_controller.text);
            Navigator.of(context).pop();
          },
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
