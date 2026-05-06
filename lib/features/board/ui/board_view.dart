import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';

class BoardView extends StatefulWidget {
  const BoardView({super.key});

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  static const Size _initialCanvasSize = Size(40000, 30000);
  static const double _canvasExpansionMargin = 6000;
  static const double _canvasExpansionChunk = 20000;
  static const double _edgePanZone = 120;
  static const double _edgePanMaxStep = 18;

  final FocusNode _boardFocus = FocusNode();

  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  Size? _viewportSize;
  Size _canvasSize = _initialCanvasSize;
  Offset _canvasOrigin = const Offset(20000, 15000);
  bool _canvasExpansionScheduled = false;
  bool _isPanelDragging = false;
  bool _isViewportInteracting = false;
  Offset? _lastPanelDragBoardPointer;
  String? _syncedBoardId;
  String? _autoFitKey;
  String? _focusedPanelVisibilityKey;
  bool _showMinimap = true;
  bool _showToolsPanel = true;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return KeyboardListener(
      focusNode: _boardFocus,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_connectSourceId != null) {
            setState(() {
              _connectSourceId = null;
              _connectPreviewPointer = null;
            });
          }
        }
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
                boards: state.boards,
                onSelectedBoard:
                    (id) => context.read<BoardCubit>().setActiveBoard(id),
                onCreateBoard: () => _createBoard(context),
                onRenameBoard: () => _renameBoard(context, activeBoard),
                onDeleteBoard: () => _deleteBoard(context, activeBoard),
                onAddMarkdownNote: () => _showMarkdownNoteDialog(context),
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

                      return Stack(
                        key: _viewportKey,
                        children: [
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _InfiniteBoardGridPainter(
                                  transformCtrl: _transformController,
                                  origin: _canvasOrigin,
                                  minorColor: colors.divider.withAlpha(60),
                                  majorColor: colors.divider.withAlpha(110),
                                ),
                              ),
                            ),
                          ),
                          InteractiveViewer(
                            constrained: false,
                            minScale: 0.2,
                            maxScale: 2.5,
                            boundaryMargin: const EdgeInsets.all(
                              _canvasExpansionChunk,
                            ),
                            // Disable pan only while actively drawing (drawPointer held)
                            panEnabled:
                                _activeTool != BoardToolId.draw ||
                                _drawPointer == null,
                            transformationController: _transformController,
                            onInteractionStart: (_) {
                              _isViewportInteracting = true;
                              _boardDebugLog('interaction.start');
                              _stopPanAnimation();
                            },
                            onInteractionEnd: (_) {
                              _isViewportInteracting = false;
                              _boardDebugLog('interaction.end');
                              _persistViewport(context, activeBoard);
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
                                        painter: _BoardLinksPainter(
                                          panels: activeBoard.panels,
                                          links: activeBoard.links,
                                          origin: _canvasOrigin,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // ── Link delete badges ─────────────────────
                                  if (_activeTool == BoardToolId.select)
                                    ..._buildLinkDeleteBadges(
                                      context,
                                      activeBoard,
                                    ),
                                  ...(() {
                                    final visiblePanels =
                                        activeBoard.panels
                                            .where((panel) => !panel.hidden)
                                            .toList()
                                          ..sort(
                                            (a, b) =>
                                                a.zIndex.compareTo(b.zIndex),
                                          );
                                    return visiblePanels
                                        .map(
                                          (panel) => _BoardPanelCard(
                                            key: ValueKey(panel.id),
                                            panel: panel,
                                            positionOffset: _canvasOrigin,
                                            onTap:
                                                () => context
                                                    .read<BoardCubit>()
                                                    .focusPanel(panel.id),
                                            onMove:
                                                (details) =>
                                                    _movePanelWithEdgePan(
                                                      context,
                                                      panel.id,
                                                      details,
                                                    ),
                                            onResize:
                                                (details) =>
                                                    _resizePanelWithEdgePan(
                                                      context,
                                                      panel,
                                                      details,
                                                    ),
                                            onDragStart:
                                                (details) =>
                                                    _handlePanelDragStart(
                                                      panel.id,
                                                      details,
                                                    ),
                                            onDragEnd: _handlePanelDragEnd,
                                            onDelete:
                                                () => context
                                                    .read<BoardCubit>()
                                                    .removePanel(panel.id),
                                            onEditColor:
                                                () => _showPanelColorDialog(
                                                  context,
                                                  panel,
                                                ),
                                            onEditNote:
                                                panel.type ==
                                                        'board.note.markdown'
                                                    ? () =>
                                                        _showMarkdownNoteDialog(
                                                          context,
                                                          panel: panel,
                                                        )
                                                    : null,
                                            connectMode:
                                                _activeTool ==
                                                BoardToolId.connect,
                                            connectSourceId: _connectSourceId,
                                            onConnectTap:
                                                _activeTool ==
                                                        BoardToolId.connect
                                                    ? () =>
                                                        _handleConnectTap(
                                                          context,
                                                          activeBoard,
                                                          panel.id,
                                                        )
                                                    : null,
                                          ),
                                        )
                                        .toList();
                                  })(),
                                  // ── Drawing layer (above panels visually;
                                  //    only intercepts gestures on actual stroke
                                  //    pixels via path-based hitTest) ──────────
                                  ...activeBoard.drawings
                                      .where((d) => !d.hidden)
                                      .map(
                                        (drawing) => Positioned(
                                          key: ValueKey(drawing.id),
                                          left: drawing.position.dx +
                                              _canvasOrigin.dx,
                                          top: drawing.position.dy +
                                              _canvasOrigin.dy,
                                          width: drawing.size.width,
                                          height: drawing.size.height,
                                          child: IgnorePointer(
                                            ignoring:
                                                _activeTool ==
                                                BoardToolId.connect,
                                            child: _BoardDrawingWidget(
                                              drawing: drawing,
                                              isSelectMode:
                                                  _activeTool ==
                                                  BoardToolId.select,
                                              onMove:
                                                  (newPos) => context
                                                      .read<BoardCubit>()
                                                      .moveDrawing(
                                                        drawing.id,
                                                        newPos,
                                                      ),
                                              onDelete:
                                                  () => context
                                                      .read<BoardCubit>()
                                                      .removeDrawing(
                                                        drawing.id,
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
                                          painter: _ActiveStrokePainter(
                                            points: _activeStroke,
                                            origin: _canvasOrigin,
                                            color: _drawSettings.strokeColor,
                                            strokeWidth:
                                                _drawSettings.strokeWidth,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // ── Connect preview line ──────────────────
                                  if (_activeTool == BoardToolId.connect &&
                                      _connectSourceId != null &&
                                      _connectPreviewPointer != null)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: _ConnectPreviewPainter(
                                            panels: activeBoard.panels,
                                            sourceId: _connectSourceId!,
                                            targetPoint:
                                                _connectPreviewPointer!,
                                            origin: _canvasOrigin,
                                            color: _connectSettings.color,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
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
                                  final pt = _boardPointFromGlobal(e.position);
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
                                  final pt = _boardPointFromGlobal(e.position);
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
                                  final pt = _boardPointFromGlobal(e.position);
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
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: colors.divider),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(45),
                                          blurRadius: 18,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.dashboard_customize_outlined,
                                          size: 32,
                                          color: AppColors.textMuted,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Board foundation is ready',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Create named boards and start with markdown notes. '
                                          'The first panel will open in a free slot, and links will support static and dynamic lines/arrows.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton.icon(
                                          onPressed:
                                              () => _showMarkdownNoteDialog(
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
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _OverlayIconButton(
                                      icon: Icons.fit_screen_outlined,
                                      tooltip: 'Fit board to content',
                                      onTap:
                                          () => _fitBoardPanels(
                                            activeBoard,
                                            persist: true,
                                          ),
                                    ),
                                    const SizedBox(width: 6),
                                    _OverlayIconButton(
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
                                            () => _showMinimap = !_showMinimap,
                                          ),
                                    ),
                                  ],
                                ),
                                if (_showMinimap) ...[
                                  const SizedBox(height: 6),
                                  _BoardMiniMap(
                                    panels: activeBoard.panels,
                                    transformCtrl: _transformController,
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
                                ],
                              ],
                            ),
                          ),
                          // ── Quick Tools Panel (left side) ──────────────────
                          Positioned(
                            left: 12,
                            top: 12,
                            child: _BoardToolsPanel(
                              visible: _showToolsPanel,
                              activeTool: _activeTool,
                              drawSettings: _drawSettings,
                              connectSettings: _connectSettings,
                              onToolChanged: (tool) => setState(() {
                                _activeTool = tool;
                                _activeStroke.clear();
                                _connectSourceId = null;
                                _connectPreviewPointer = null;
                              }),
                              onDrawSettingsChanged: (s) =>
                                  setState(() => _drawSettings = s),
                              onConnectSettingsChanged: (s) =>
                                  setState(() => _connectSettings = s),
                              onToggle: () => setState(
                                () => _showToolsPanel = !_showToolsPanel,
                              ),
                            ),
                          ),
                          // ── Cancel connection button ───────────────────────
                          if (_activeTool == BoardToolId.connect &&
                              _connectSourceId != null)
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () => setState(() {
                                      _connectSourceId = null;
                                      _connectPreviewPointer = null;
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E2E)
                                            .withAlpha(220),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.redAccent
                                              .withAlpha(160),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.close,
                                            size: 14,
                                            color: Colors.redAccent
                                                .withAlpha(200),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Cancel connection  (Esc)',
                                            style: TextStyle(
                                              color: Colors.redAccent
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
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ), // BlocBuilder
    ); // KeyboardListener
  }

  void _syncViewport(BoardDocument board) {
    if (_syncedBoardId == board.id) return;
    _syncedBoardId = board.id;
    _boardDebugLog(
      'syncViewport board=${board.id} scale=${_fmt(board.viewport.scale)} '
      'translation=${_fmtOffset(board.viewport.translation)}',
    );
    if (_shouldAutoFit(board)) {
      _boardDebugLog('syncViewport.scheduleAutoFit board=${board.id}');
      _scheduleAutoFitIfNeeded(board);
      return;
    }
    _stopPanAnimation();
    _transformController.value = _matrixFromViewport(board.viewport);
  }

  Future<void> _persistViewport(BuildContext context, BoardDocument board) {
    final matrix = _transformController.value.storage;
    final scale = _transformController.value.getMaxScaleOnAxis();
    final translation = Offset(
      matrix[12] + (_canvasOrigin.dx * scale),
      matrix[13] + (_canvasOrigin.dy * scale),
    );
    _boardDebugLog(
      'persistViewport board=${board.id} scale=${_fmt(scale)} '
      'translation=${_fmtOffset(translation)} matrixT=${_fmtOffset(Offset(matrix[12], matrix[13]))} '
      'origin=${_fmtOffset(_canvasOrigin)} dragging=$_isPanelDragging viewportInteracting=$_isViewportInteracting',
    );
    return context.read<BoardCubit>().updateViewport(
      board.viewport.copyWith(scale: scale, translation: translation),
      boardId: board.id,
    );
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
    return _viewportSize != null &&
        _isDefaultViewport(board.viewport) &&
        board.panels.any((panel) => !panel.hidden);
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
      _boardDebugLog(
        'focusVisibility.skip focused=$focusedPanelId dragging=$_isPanelDragging viewportInteracting=$_isViewportInteracting',
      );
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
    final key =
        '${board.id}:${resolvedPanel.id}:${resolvedPanel.bounds.x}:${resolvedPanel.bounds.y}:${resolvedPanel.bounds.width}:${resolvedPanel.bounds.height}:${size.width}:${size.height}';
    if (_focusedPanelVisibilityKey == key) return;
    _focusedPanelVisibilityKey = key;
    _boardDebugLog('focusVisibility.scheduled key=$key');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isPanelDragging || _isViewportInteracting) {
        _boardDebugLog('focusVisibility.cancelledByInteraction');
        return;
      }
      if (_isPanelComfortablyVisible(resolvedPanel.bounds.rect)) {
        _boardDebugLog(
          'focusVisibility.alreadyVisible panel=${resolvedPanel.id}',
        );
        return;
      }
      _boardDebugLog('focusVisibility.center panel=${resolvedPanel.id}');
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
    final scale = _transformController.value.getMaxScaleOnAxis();
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
    DragUpdateDetails details,
  ) {
    _panViewportNearEdge(details.globalPosition);
    final delta = _consumePanelDragDelta(details.globalPosition, details.delta);
    context.read<BoardCubit>().resizePanel(
      panel.id,
      width: panel.bounds.width + delta.dx,
      height: panel.bounds.height + delta.dy,
    );
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

    final scale = _transformController.value.getMaxScaleOnAxis();
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

    final scale = _transformController.value.getMaxScaleOnAxis();
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

  Offset _boardPointFromCanvasScene(Offset scenePoint) {
    return scenePoint - _canvasOrigin;
  }

  void _boardDebugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[BoardView] $message');
  }

  String _fmt(double value) => value.toStringAsFixed(2);

  String _fmtOffset(Offset offset) =>
      '(${_fmt(offset.dx)}, ${_fmt(offset.dy)})';

  String _fmtSize(Size size) => '${_fmt(size.width)}x${_fmt(size.height)}';

  String _fmtRect(Rect rect) =>
      'l=${_fmt(rect.left)} t=${_fmt(rect.top)} r=${_fmt(rect.right)} b=${_fmt(rect.bottom)}';

  String _fmtMatrix(Matrix4 matrix) {
    final storage = matrix.storage;
    return 'scale=${_fmt(matrix.getMaxScaleOnAxis())} t=${_fmtOffset(Offset(storage[12], storage[13]))}';
  }

  // ── Tool actions ──────────────────────────────────────────────────────────

  /// Builds small ×-badge widgets at the midpoint of each link so the user
  /// can delete them by tapping.
  List<Widget> _buildLinkDeleteBadges(
    BuildContext context,
    BoardDocument board,
  ) {
    final panelMap = {for (final p in board.panels) p.id: p};
    final badges = <Widget>[];
    for (final link in board.links) {
      final from = panelMap[link.fromPanelId];
      final to = panelMap[link.toPanelId];
      if (from == null || to == null || from.hidden || to.hidden) continue;

      // Use edge-to-edge points (same as painter) for accurate midpoint
      final fromRect = from.bounds.rect.translate(_canvasOrigin.dx, _canvasOrigin.dy);
      final toRect = to.bounds.rect.translate(_canvasOrigin.dx, _canvasOrigin.dy);
      final start = _BoardLinksPainter.edgePointToward(fromRect, toRect.center);
      final end = _BoardLinksPainter.edgePointToward(toRect, fromRect.center);
      final mid = _linkMidpoint(start, end, link.geometry);

      // Large transparent hit area so mouse-over the line is easy to trigger
      const hitR = 20.0;
      const badgeR = 11.0;
      final isHovered = _hoveredLinkId == link.id;
      badges.add(
        Positioned(
          left: mid.dx - hitR,
          top: mid.dy - hitR,
          width: hitR * 2,
          height: hitR * 2,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredLinkId = link.id),
            onExit: (_) => setState(() {
              if (_hoveredLinkId == link.id) _hoveredLinkId = null;
            }),
            child: Center(
              child: AnimatedOpacity(
                opacity: isHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: GestureDetector(
                  onTap: () => context.read<BoardCubit>().removeLink(link.id),
                  child: Container(
                    width: badgeR * 2,
                    height: badgeR * 2,
                    decoration: BoxDecoration(
                      color: const Color(0xCCF87171),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withAlpha(80),
                        width: 1,
                      ),
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
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
        final mt = 1 - t;
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

  Future<_LinkStyleChoice?> _showConnectStyleDialog(
    BuildContext context,
  ) async {
    return showDialog<_LinkStyleChoice>(
      context: context,
      builder:
          (ctx) => _LinkStyleDialog(initialSettings: _connectSettings),
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

  Future<void> _renameBoard(BuildContext context, BoardDocument board) async {
    final name = await _showTextDialog(
      context,
      title: 'Rename board',
      label: 'Board name',
      initialValue: board.name,
      confirmLabel: 'Save',
    );
    if (!context.mounted || name == null) return;
    await context.read<BoardCubit>().renameBoard(board.id, name);
  }

  Future<void> _deleteBoard(BuildContext context, BoardDocument board) async {
    final shouldDelete = await showDialog<bool>(
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

  Future<void> _showMarkdownNoteDialog(
    BuildContext context, {
    BoardPanelInstance? panel,
  }) async {
    final initialTitle = panel?.title ?? 'Note';
    final initialMarkdown = panel?.state['markdown'] as String? ?? '';
    Color? selectedColor = panel?.color;
    final titleController = TextEditingController(text: initialTitle);
    final markdownController = TextEditingController(text: initialMarkdown);
    final result = await showDialog<
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
                          _MarkdownToolButton(
                            icon: Icons.title,
                            tooltip: 'Heading',
                            onTap: () {
                              _prefixSelectedLines(markdownController, '# ');
                              setDialogState(() {});
                            },
                          ),
                          _MarkdownToolButton(
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
                          _MarkdownToolButton(
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
                          _MarkdownToolButton(
                            icon: Icons.format_list_bulleted,
                            tooltip: 'Bullet list',
                            onTap: () {
                              _prefixSelectedLines(markdownController, '- ');
                              setDialogState(() {});
                            },
                          ),
                          _MarkdownToolButton(
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
                          _MarkdownToolButton(
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
                          _MarkdownToolButton(
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
                                color: selectedColor ?? const Color(0xFFB46CFF),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withAlpha(90),
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
    var selectedColor = initialColor ?? const Color(0xFFB46CFF);
    return showDialog<Color?>(
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
    return showDialog<String>(
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
    required this.boards,
    required this.onSelectedBoard,
    required this.onCreateBoard,
    required this.onRenameBoard,
    required this.onDeleteBoard,
    required this.onAddMarkdownNote,
  });

  final BoardDocument board;
  final List<BoardDocument> boards;
  final ValueChanged<String> onSelectedBoard;
  final VoidCallback onCreateBoard;
  final VoidCallback onRenameBoard;
  final VoidCallback onDeleteBoard;
  final VoidCallback onAddMarkdownNote;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.divider),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: board.id,
                dropdownColor: colors.surface,
                borderRadius: BorderRadius.circular(12),
                iconEnabledColor: AppColors.textMuted,
                items: [
                  for (final item in boards)
                    DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onSelectedBoard(value);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          _ToolbarChip(
            icon: Icons.dashboard_outlined,
            label: '${board.panels.length} panels',
          ),
          const SizedBox(width: 8),
          _ToolbarChip(
            icon: Icons.share_outlined,
            label: '${board.links.length} links',
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onCreateBoard,
            icon: const Icon(Icons.add),
            label: const Text('New board'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onRenameBoard,
            icon: const Icon(Icons.drive_file_rename_outline),
            label: const Text('Rename'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onDeleteBoard,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onAddMarkdownNote,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add note'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xE50B0D12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? const Color(0x8060A5FA) : const Color(0xFF2A3040),
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: active ? const Color(0xFF60A5FA) : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _MarkdownToolButton extends StatelessWidget {
  const _MarkdownToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BoardPanelCard extends StatelessWidget {
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
    this.onEditNote,
    this.connectMode = false,
    this.connectSourceId,
    this.onConnectTap,
  });

  final BoardPanelInstance panel;
  final Offset positionOffset;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onMove;
  final ValueChanged<DragUpdateDetails> onResize;
  final ValueChanged<DragStartDetails> onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onDelete;
  final VoidCallback onEditColor;
  final VoidCallback? onEditNote;
  final bool connectMode;
  final String? connectSourceId;
  final VoidCallback? onConnectTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final markdown = panel.state['markdown'] as String? ?? '';
    final accent = panel.color;
    final panelFill =
        accent == null
            ? colors.surface
            : Color.lerp(colors.surface, accent, 0.12) ?? colors.surface;
    final panelHeaderFill =
        accent == null
            ? colors.surfaceElevated
            : Color.lerp(colors.surfaceElevated, accent, 0.18) ??
                colors.surfaceElevated;
    final borderColor =
        accent == null
            ? colors.divider
            : Color.lerp(colors.divider, accent, 0.65) ?? colors.divider;
    return Positioned(
      left: panel.bounds.x + positionOffset.dx,
      top: panel.bounds.y + positionOffset.dy,
      width: panel.bounds.width,
      height: panel.bounds.height,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panelFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  panel.id ==
                          context.select<BoardCubit, String?>(
                            (cubit) =>
                                cubit
                                    .state
                                    .activeBoard
                                    ?.viewport
                                    .focusedPanelId,
                          )
                      ? colors.primary
                      : borderColor,
              width:
                  panel.id ==
                          context.select<BoardCubit, String?>(
                            (cubit) =>
                                cubit
                                    .state
                                    .activeBoard
                                    ?.viewport
                                    .focusedPanelId,
                          )
                      ? 1.5
                      : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      onTap();
                      onDragStart(details);
                    },
                    onPanUpdate:
                        panel.locked ? null : (details) => onMove(details),
                    onPanEnd: (_) => onDragEnd(),
                    onPanCancel: onDragEnd,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: panelHeaderFill,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        border: Border(
                          bottom: BorderSide(color: colors.divider),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            panel.type == 'board.note.markdown'
                                ? Icons.sticky_note_2_outlined
                                : Icons.dashboard_customize_outlined,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              panel.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: onEditColor,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: accent ?? const Color(0xFF64748B),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withAlpha(100),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (onEditNote != null)
                            IconButton(
                              tooltip: 'Edit note',
                              onPressed: onEditNote,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              splashRadius: 16,
                            ),
                          IconButton(
                            tooltip: 'Remove panel',
                            onPressed: onDelete,
                            icon: const Icon(Icons.close, size: 16),
                            splashRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child:
                          panel.type == 'board.note.markdown'
                              ? ClipRect(
                                child: SingleChildScrollView(
                                  child: MarkdownBody(
                                    data:
                                        markdown.isEmpty
                                            ? '*Empty note*'
                                            : markdown,
                                  ),
                                ),
                              )
                              : Text(
                                panel.type,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    onTap();
                    onDragStart(details);
                  },
                  onPanUpdate: onResize,
                  onPanEnd: (_) => onDragEnd(),
                  onPanCancel: onDragEnd,
                  child: const Icon(
                    Icons.drag_handle,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
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
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF34D399).withAlpha(100),
                          width: connectSourceId == panel.id ? 2.5 : 1.5,
                        ),
                        color:
                            connectSourceId == panel.id
                                ? const Color(0x1534D399)
                                : Colors.transparent,
                      ),
                      child:
                          connectSourceId == null
                              ? Center(
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0x6634D399),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_link,
                                    size: 18,
                                    color: Color(0xFF34D399),
                                  ),
                                ),
                              )
                              : connectSourceId == panel.id
                              ? const Center(
                                child: Text(
                                  'Source\n(tap to cancel)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                              : Center(
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0x6634D399),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.call_made,
                                    size: 18,
                                    color: Color(0xFF34D399),
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
    );
  }
}

class _BoardGridPainter extends CustomPainter {
  const _BoardGridPainter({required this.minorColor, required this.majorColor});

  final Color minorColor;
  final Color majorColor;

  @override
  void paint(Canvas canvas, Size size) {
    const minorStep = 24.0;
    const majorStep = 120.0;
    final minorPaint =
        Paint()
          ..color = minorColor
          ..strokeWidth = 1;
    final majorPaint =
        Paint()
          ..color = majorColor
          ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += minorStep) {
      final paint = x % majorStep == 0 ? majorPaint : minorPaint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += minorStep) {
      final paint = y % majorStep == 0 ? majorPaint : minorPaint;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardGridPainter oldDelegate) {
    return oldDelegate.minorColor != minorColor ||
        oldDelegate.majorColor != majorColor;
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
    final scale = transformCtrl.value.getMaxScaleOnAxis().clamp(0.0001, 1000.0);
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

class _BoardLinksPainter extends CustomPainter {
  const _BoardLinksPainter({
    required this.panels,
    required this.links,
    required this.origin,
  });

  final List<BoardPanelInstance> panels;
  final List<BoardPanelLink> links;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final panelMap = {for (final panel in panels) panel.id: panel};
    for (final link in links) {
      final from = panelMap[link.fromPanelId];
      final to = panelMap[link.toPanelId];
      if (from == null || to == null || from.hidden || to.hidden) continue;

      final fromRect = from.bounds.rect.translate(origin.dx, origin.dy);
      final toRect = to.bounds.rect.translate(origin.dx, origin.dy);
      final start = _edgePointToward(fromRect, toRect.center);
      final end = _edgePointToward(toRect, fromRect.center);
      final path = _buildLinkPath(start, end, link.geometry);

      final paint =
          Paint()
            ..color = link.color.withAlpha(
              link.behavior == BoardLinkBehavior.dynamic ? 220 : 200,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                link.behavior == BoardLinkBehavior.dynamic ? 2.6 : 2.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

      if (link.behavior == BoardLinkBehavior.dynamic) {
        _drawDashedPath(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }

      if (link.style == BoardLinkStyle.arrow) {
        _drawArrowHead(canvas, paint, path, end);
      }
    }
  }

  static Path buildLinkPath(Offset start, Offset end, BoardLinkGeometry geometry) =>
      _buildLinkPath(start, end, geometry);

  static Path _buildLinkPath(Offset start, Offset end, BoardLinkGeometry geometry) {
    switch (geometry) {
      case BoardLinkGeometry.straight:
        return Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
      case BoardLinkGeometry.elbow:
        final midX = (start.dx + end.dx) / 2;
        return Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(midX, start.dy)
          ..lineTo(midX, end.dy)
          ..lineTo(end.dx, end.dy);
      case BoardLinkGeometry.bezier:
        return Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + ((end.dx - start.dx) * 0.35),
            start.dy,
            end.dx - ((end.dx - start.dx) * 0.35),
            end.dy,
            end.dx,
            end.dy,
          );
    }
  }

  /// Returns the point on [rect]'s border in the direction of [target]
  /// from the rect's center. Used to start/end links at panel edges.
  static Offset edgePointToward(Rect rect, Offset target) =>
      _edgePointToward(rect, target);

  static Offset _edgePointToward(Rect rect, Offset target) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final dx = target.dx - cx;
    final dy = target.dy - cy;
    if (dx.abs() < 0.001 && dy.abs() < 0.001) return rect.center;
    double t = double.infinity;
    if (dx > 0) t = math.min(t, (rect.right - cx) / dx);
    if (dx < 0) t = math.min(t, (rect.left - cx) / dx);
    if (dy > 0) t = math.min(t, (rect.bottom - cy) / dy);
    if (dy < 0) t = math.min(t, (rect.top - cy) / dy);
    return Offset(cx + dx * t, cy + dy * t);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dash = 10.0;
      const gap = 8.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  void _drawArrowHead(
    Canvas canvas,
    Paint paint,
    Path path,
    Offset fallbackEnd,
  ) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.last;
    final tangent = metric.getTangentForOffset(metric.length);
    if (tangent == null) return;

    const arrowSize = 13.0;
    final angle = tangent.angle;
    final tip = tangent.position;
    final p1 = Offset(
      tip.dx - arrowSize * math.cos(angle - math.pi / 5),
      tip.dy - arrowSize * math.sin(angle - math.pi / 5),
    );
    final p2 = Offset(
      tip.dx - arrowSize * math.cos(angle + math.pi / 5),
      tip.dy - arrowSize * math.sin(angle + math.pi / 5),
    );

    // Open arrowhead (two lines, no fill) — cleaner look
    final arrowPaint =
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = paint.strokeWidth.clamp(1.5, 2.5)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final arrow =
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(arrow, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _BoardLinksPainter oldDelegate) {
    return oldDelegate.panels != panels ||
        oldDelegate.links != links ||
        oldDelegate.origin != origin;
  }
}

class _BoardMiniMap extends StatelessWidget {
  const _BoardMiniMap({
    required this.panels,
    required this.transformCtrl,
    required this.viewportSize,
    required this.origin,
    required this.onPanTo,
  });

  final List<BoardPanelInstance> panels;
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
              color: const Color(0xE50B0D12),
              border: Border.all(color: const Color(0x3060A5FA)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 10),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CustomPaint(
                painter: _BoardMiniMapPainter(
                  panels: panels.where((panel) => !panel.hidden).toList(),
                  bounds: bounds,
                  viewportRect: viewportRect,
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
    required this.bounds,
    required this.viewportRect,
  });

  final List<BoardPanelInstance> panels;
  final Rect bounds;
  final Rect viewportRect;

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
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(1.5),
        ),
        Paint()..color = panel.color ?? _colorForPanelType(panel.type),
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
    canvas.drawRRect(viewport, Paint()..color = const Color(0x2060A5FA));
    canvas.drawRRect(
      viewport,
      Paint()
        ..color = const Color(0xCC60A5FA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  Color _colorForPanelType(String type) {
    return switch (type) {
      'board.note.markdown' => const Color(0xCCE879F9),
      _ => const Color(0xCC64748B),
    };
  }

  @override
  bool shouldRepaint(covariant _BoardMiniMapPainter oldDelegate) {
    return oldDelegate.panels != panels ||
        oldDelegate.bounds != bounds ||
        oldDelegate.viewportRect != viewportRect;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Tools Panel
// ─────────────────────────────────────────────────────────────────────────────

class _BoardToolsPanel extends StatelessWidget {
  const _BoardToolsPanel({
    required this.visible,
    required this.activeTool,
    required this.drawSettings,
    required this.connectSettings,
    required this.onToolChanged,
    required this.onDrawSettingsChanged,
    required this.onConnectSettingsChanged,
    required this.onToggle,
  });

  final bool visible;
  final BoardToolId activeTool;
  final DrawSettings drawSettings;
  final ConnectSettings connectSettings;
  final ValueChanged<BoardToolId> onToolChanged;
  final ValueChanged<DrawSettings> onDrawSettingsChanged;
  final ValueChanged<ConnectSettings> onConnectSettingsChanged;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Toggle button ─────────────────────────────────────────────────
        _OverlayIconButton(
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
              color: const Color(0xE50B0D12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A3040)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in kBoardTools) ...[
                  if (kBoardTools.indexOf(tool) > 0)
                    const SizedBox(height: 4),
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
                                  : AppColors.textMuted,
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
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Draw settings panel
// ─────────────────────────────────────────────────────────────────────────────

class _DrawSettingsPanel extends StatelessWidget {
  const _DrawSettingsPanel({
    required this.settings,
    required this.onChanged,
  });

  final DrawSettings settings;
  final ValueChanged<DrawSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xE50B0D12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3040)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Draw settings',
            style: TextStyle(
              color: AppColors.textMuted,
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
              for (final c in const [
                Color(0xFFE879F9),
                Color(0xFF60A5FA),
                Color(0xFF34D399),
                Color(0xFFFBBF24),
                Color(0xFFF87171),
                Color(0xFFFFFFFF),
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
                                ? Colors.white
                                : Colors.white.withAlpha(40),
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
                    gradient: const SweepGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withAlpha(60)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stroke width slider
          const Text(
            'Size',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: settings.strokeColor,
              thumbColor: settings.strokeColor,
              overlayColor: settings.strokeColor.withAlpha(40),
              inactiveTrackColor: const Color(0xFF2A3040),
            ),
            child: Slider(
              value: settings.strokeWidth,
              min: 1,
              max: 20,
              onChanged:
                  (v) => onChanged(settings.copyWith(strokeWidth: v)),
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
    final activeColor = settings.color;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xE50B0D12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3040)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Connect',
            style: TextStyle(
              color: AppColors.textMuted,
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
                color: const Color(0xFF0B0D12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A3040)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  size: const Size(double.infinity, 56),
                  painter: _LinkPreviewPainter(
                    geometry: settings.geometry,
                    showArrow: settings.showArrow,
                    color: activeColor,
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
                                  : const Color(0xFF2A3040),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(32, 14),
                            painter: _LinkMiniPreviewPainter(
                              geometry: geo,
                              color:
                                  settings.geometry == geo
                                      ? activeColor
                                      : AppColors.textMuted,
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
                                      : AppColors.textMuted,
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
              const Text(
                'Arrow',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              Transform.scale(
                scale: 0.75,
                alignment: Alignment.centerRight,
                child: Switch.adaptive(
                  value: settings.showArrow,
                  onChanged:
                      (v) => onChanged(settings.copyWith(showArrow: v)),
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
              for (final c in const [
                Color(0xFF60A5FA),
                Color(0xFF34D399),
                Color(0xFFF87171),
                Color(0xFFFBBF24),
                Color(0xFFE879F9),
                Color(0xFFFFFFFF),
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
                                ? Colors.white
                                : Colors.white.withAlpha(30),
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
// Drawing widget — renders a completed BoardDrawingElement as a draggable item
// Caller is responsible for positioning (Positioned must be direct Stack child)
// ─────────────────────────────────────────────────────────────────────────────

class _BoardDrawingWidget extends StatefulWidget {
  const _BoardDrawingWidget({
    super.key,
    required this.drawing,
    required this.isSelectMode,
    required this.onMove,
    required this.onDelete,
  });

  final BoardDrawingElement drawing;
  final bool isSelectMode;
  final ValueChanged<Offset> onMove;
  final VoidCallback onDelete;

  @override
  State<_BoardDrawingWidget> createState() => _BoardDrawingWidgetState();
}

class _BoardDrawingWidgetState extends State<_BoardDrawingWidget> {
  bool _hovered = false;
  bool _selected = false;

  bool get _showBadge => widget.isSelectMode && (_hovered || _selected);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _StrokeHitTestBox(
          drawing: widget.drawing,
          onHoverChanged: (h) {
            if (_hovered != h) setState(() => _hovered = h);
          },
          child: GestureDetector(
            onTap: widget.isSelectMode
                ? () => setState(() => _selected = !_selected)
                : null,
            onPanUpdate:
                widget.isSelectMode
                    ? (d) => widget.onMove(widget.drawing.position + d.delta)
                    : null,
            child: CustomPaint(
              size: widget.drawing.size,
              painter: _DrawingElementPainter(drawing: widget.drawing),
            ),
          ),
        ),
        // Delete badge OUTSIDE _StrokeHitTestBox so it has its own hit area
        if (_showBadge)
          Positioned(
            right: -6,
            top: -6,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xCCF87171),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints a [BoardDrawingElement]'s strokes on the given canvas.
class _DrawingElementPainter extends CustomPainter {
  const _DrawingElementPainter({required this.drawing});

  final BoardDrawingElement drawing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = drawing.strokeColor
          ..strokeWidth = drawing.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    for (final stroke in drawing.strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingElementPainter oldDelegate) {
    return oldDelegate.drawing != drawing;
  }

  /// Only return true when [position] is within hit distance of an actual
  /// stroke segment. Transparent bbox areas return null (miss) so panels
  /// underneath can still handle pointer events.
  @override
  bool? hitTest(Offset position) {
    final hitRadius = (drawing.strokeWidth / 2) + 8.0;
    for (final stroke in drawing.strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        if ((stroke.first - position).distance <= hitRadius) return true;
        continue;
      }
      for (int i = 0; i < stroke.length - 1; i++) {
        if (_distToSegment(position, stroke[i], stroke[i + 1]) <= hitRadius) {
          return true;
        }
      }
    }
    return null; // transparent — let events fall through
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    final t = lenSq == 0
        ? 0.0
        : ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final closest = Offset(a.dx + t.clamp(0.0, 1.0) * dx,
                           a.dy + t.clamp(0.0, 1.0) * dy);
    return (p - closest).distance;
  }

  /// Public stroke hit test used by [_StrokeHitTestRenderBox].
  static bool strokeHitTest(BoardDrawingElement drawing, Offset position) {
    final hitRadius = (drawing.strokeWidth / 2) + 8.0;
    for (final stroke in drawing.strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        if ((stroke.first - position).distance <= hitRadius) return true;
        continue;
      }
      for (int i = 0; i < stroke.length - 1; i++) {
        if (_distToSegment(position, stroke[i], stroke[i + 1]) <= hitRadius) {
          return true;
        }
      }
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StrokeHitTestBox — SingleChildRenderObjectWidget whose RenderBox only
// returns true from hitTest when the pointer is near an actual drawn stroke.
// Transparent bbox areas pass through to panels below.
// ─────────────────────────────────────────────────────────────────────────────

class _StrokeHitTestBox extends SingleChildRenderObjectWidget {
  const _StrokeHitTestBox({
    required this.drawing,
    required this.onHoverChanged,
    required super.child,
  });

  final BoardDrawingElement drawing;
  final ValueChanged<bool> onHoverChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _StrokeHitTestRenderBox(
      drawing: drawing,
      onHoverChanged: onHoverChanged,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _StrokeHitTestRenderBox renderObject,
  ) {
    renderObject
      ..drawing = drawing
      ..onHoverChanged = onHoverChanged;
  }
}

class _StrokeHitTestRenderBox extends RenderProxyBox {
  _StrokeHitTestRenderBox({
    required BoardDrawingElement drawing,
    required this.onHoverChanged,
  }) : _drawing = drawing;

  BoardDrawingElement _drawing;
  set drawing(BoardDrawingElement value) {
    if (_drawing == value) return;
    _drawing = value;
    markNeedsPaint();
  }

  ValueChanged<bool> onHoverChanged;

  bool _lastHover = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Only hit if pointer is near a stroke
    if (!_DrawingElementPainter.strokeHitTest(_drawing, position)) {
      if (_lastHover) {
        _lastHover = false;
        // Schedule callback to avoid calling during hit test
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onHoverChanged(false);
        });
      }
      return false;
    }
    if (!_lastHover) {
      _lastHover = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHoverChanged(true);
      });
    }
    // Let child handle the event
    return super.hitTest(result, position: position);
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    super.handleEvent(event, entry);
    if (event is PointerExitEvent || event is PointerCancelEvent) {
      if (_lastHover) {
        _lastHover = false;
        onHoverChanged(false);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active stroke painter (board-space points)
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveStrokePainter extends CustomPainter {
  const _ActiveStrokePainter({
    required this.points,
    required this.origin,
    required this.color,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Offset origin;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(points.first.dx + origin.dx, points.first.dy + origin.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx + origin.dx, points[i].dy + origin.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ActiveStrokePainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Connect preview painter
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectPreviewPainter extends CustomPainter {
  const _ConnectPreviewPainter({
    required this.panels,
    required this.sourceId,
    required this.targetPoint,
    required this.origin,
    required this.color,
  });

  final List<BoardPanelInstance> panels;
  final String sourceId;
  final Offset targetPoint;
  final Offset origin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final source = panels.where((p) => p.id == sourceId).firstOrNull;
    if (source == null) return;

    final srcRect = source.bounds.rect.translate(origin.dx, origin.dy);
    final target = Offset(targetPoint.dx + origin.dx, targetPoint.dy + origin.dy);
    // Start from panel edge toward the cursor
    final srcEdge = _BoardLinksPainter.edgePointToward(srcRect, target);

    final paint =
        Paint()
          ..color = color.withAlpha(180)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    final path =
        Path()
          ..moveTo(srcEdge.dx, srcEdge.dy)
          ..cubicTo(
            srcEdge.dx + (target.dx - srcEdge.dx) * 0.4,
            srcEdge.dy,
            srcEdge.dx + (target.dx - srcEdge.dx) * 0.6,
            target.dy,
            target.dx,
            target.dy,
          );
    // Draw dashed
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      bool draw = true;
      while (dist < metric.length) {
        final next = math.min(dist + (draw ? 8.0 : 6.0), metric.length);
        if (draw) canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectPreviewPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Link style dialog
// ─────────────────────────────────────────────────────────────────────────────

class _LinkStyleChoice {
  const _LinkStyleChoice({
    required this.showArrow,
    required this.geometry,
    required this.color,
  });

  final bool showArrow;
  final BoardLinkGeometry geometry;
  final Color color;
}

class _LinkStyleDialog extends StatefulWidget {
  const _LinkStyleDialog({required this.initialSettings});

  final ConnectSettings initialSettings;

  @override
  State<_LinkStyleDialog> createState() => _LinkStyleDialogState();
}

class _LinkStyleDialogState extends State<_LinkStyleDialog> {
  late bool _showArrow;
  late BoardLinkGeometry _geometry;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _showArrow = widget.initialSettings.showArrow;
    _geometry = widget.initialSettings.geometry;
    _color = widget.initialSettings.color;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link style'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Live preview ─────────────────────────────────────────────
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A3040)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: _LinkPreviewPainter(
                    geometry: _geometry,
                    showArrow: _showArrow,
                    color: _color,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Geometry selector ────────────────────────────────────────
            const Text(
              'Line style',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final geo in BoardLinkGeometry.values) ...[
                  if (BoardLinkGeometry.values.indexOf(geo) > 0)
                    const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _geometry = geo),
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color:
                              _geometry == geo
                                  ? _color.withAlpha(30)
                                  : const Color(0xFF131620),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                _geometry == geo
                                    ? _color.withAlpha(180)
                                    : const Color(0xFF2A3040),
                            width: _geometry == geo ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(48, 24),
                              painter: _LinkMiniPreviewPainter(
                                geometry: geo,
                                color:
                                    _geometry == geo
                                        ? _color
                                        : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              switch (geo) {
                                BoardLinkGeometry.bezier => 'Bezier',
                                BoardLinkGeometry.straight => 'Straight',
                                BoardLinkGeometry.elbow => 'Elbow',
                              },
                              style: TextStyle(
                                fontSize: 10,
                                color:
                                    _geometry == geo
                                        ? _color
                                        : AppColors.textMuted,
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
            const SizedBox(height: 16),
            // ── Arrow toggle ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Show arrow',
                  style: TextStyle(fontSize: 13),
                ),
                Switch.adaptive(
                  value: _showArrow,
                  onChanged: (v) => setState(() => _showArrow = v),
                  activeColor: _color,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Color swatches ───────────────────────────────────────────
            const Text(
              'Color',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in const [
                  Color(0xFF60A5FA),
                  Color(0xFF34D399),
                  Color(0xFFF87171),
                  Color(0xFFFBBF24),
                  Color(0xFFE879F9),
                  Color(0xFFFFFFFF),
                ])
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              _color == c
                                  ? Colors.white
                                  : Colors.white.withAlpha(30),
                          width: _color == c ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.of(context).pop(
                _LinkStyleChoice(
                  showArrow: _showArrow,
                  geometry: _geometry,
                  color: _color,
                ),
              ),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

/// Full-size preview of a link style in the dialog header area.
class _LinkPreviewPainter extends CustomPainter {
  const _LinkPreviewPainter({
    required this.geometry,
    required this.showArrow,
    required this.color,
  });

  final BoardLinkGeometry geometry;
  final bool showArrow;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Stagger panels vertically so curves are clearly visible
    final start = Offset(size.width * 0.15, size.height * 0.35);
    final end = Offset(size.width * 0.85, size.height * 0.65);

    // Draw mock panels
    final panelPaint =
        Paint()
          ..color = const Color(0xFF1E2535)
          ..style = PaintingStyle.fill;
    final panelBorderPaint =
        Paint()
          ..color = const Color(0xFF2A3040)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final leftPanel = Rect.fromCenter(
      center: start,
      width: 56,
      height: 32,
    );
    final rightPanel = Rect.fromCenter(
      center: end,
      width: 56,
      height: 32,
    );
    final rr = RRect.fromRectAndRadius(leftPanel, const Radius.circular(6));
    final rr2 = RRect.fromRectAndRadius(rightPanel, const Radius.circular(6));
    canvas.drawRRect(rr, panelPaint);
    canvas.drawRRect(rr, panelBorderPaint);
    canvas.drawRRect(rr2, panelPaint);
    canvas.drawRRect(rr2, panelBorderPaint);

    // Shrink endpoints to panel edges
    final lineStart = Offset(leftPanel.right, start.dy);
    final lineEnd = Offset(rightPanel.left, end.dy);

    final path = _BoardLinksPainter.buildLinkPath(lineStart, lineEnd, geometry);
    final paint =
        Paint()
          ..color = color.withAlpha(220)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    if (showArrow) {
      _drawArrow(canvas, paint, path, lineEnd);
    }
    // Endpoint dots
    canvas.drawCircle(lineStart, 3, Paint()..color = color.withAlpha(180));
    canvas.drawCircle(lineEnd, 3, Paint()..color = color.withAlpha(180));
  }

  void _drawArrow(Canvas canvas, Paint paint, Path path, Offset end) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.last;
    final tangent = metric.getTangentForOffset(metric.length);
    if (tangent == null) return;
    const sz = 11.0;
    final angle = tangent.angle;
    final tip = tangent.position;
    final p1 = Offset(
      tip.dx - sz * math.cos(angle - math.pi / 5),
      tip.dy - sz * math.sin(angle - math.pi / 5),
    );
    final p2 = Offset(
      tip.dx - sz * math.cos(angle + math.pi / 5),
      tip.dy - sz * math.sin(angle + math.pi / 5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(p2.dx, p2.dy),
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth.clamp(1.5, 2.5)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LinkPreviewPainter old) =>
      old.geometry != geometry ||
      old.showArrow != showArrow ||
      old.color != color;
}

/// Tiny icon-sized link preview used inside the geometry selector buttons.
class _LinkMiniPreviewPainter extends CustomPainter {
  const _LinkMiniPreviewPainter({
    required this.geometry,
    required this.color,
  });

  final BoardLinkGeometry geometry;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Stagger Y so bezier/elbow/straight are visually distinct
    final start = Offset(4, size.height * 0.75);
    final end = Offset(size.width - 4, size.height * 0.25);
    final path = _BoardLinksPainter.buildLinkPath(start, end, geometry);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LinkMiniPreviewPainter old) =>
      old.geometry != geometry || old.color != color;
}
