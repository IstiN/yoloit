import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

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
  late final AnimationController _panController;
  Animation<Matrix4>? _panAnimation;
  VoidCallback? _panAnimationListener;
  AnimationStatusListener? _panStatusListener;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return BlocBuilder<BoardCubit, BoardState>(
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
                                          ),
                                        )
                                        .toList();
                                  })(),
                                ],
                              ),
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
    );
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

      final start = from.bounds.rect.center + origin;
      final end = to.bounds.rect.center + origin;
      final path =
          Path()
            ..moveTo(start.dx, start.dy)
            ..cubicTo(
              start.dx + ((end.dx - start.dx) * 0.35),
              start.dy,
              end.dx - ((end.dx - start.dx) * 0.35),
              end.dy,
              end.dx,
              end.dy,
            );

      final paint =
          Paint()
            ..color = link.color.withAlpha(
              link.behavior == BoardLinkBehavior.dynamic ? 220 : 170,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                link.behavior == BoardLinkBehavior.dynamic ? 2.6 : 1.8;

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

    const arrowSize = 10.0;
    final angle = tangent.angle;
    final tip = tangent.position;
    final p1 = Offset(
      tip.dx - arrowSize * math.cos(angle - math.pi / 6),
      tip.dy - arrowSize * math.sin(angle - math.pi / 6),
    );
    final p2 = Offset(
      tip.dx - arrowSize * math.cos(angle + math.pi / 6),
      tip.dy - arrowSize * math.sin(angle + math.pi / 6),
    );

    final fillPaint =
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill;
    final arrow =
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close();
    canvas.drawPath(arrow, fillPaint);
    canvas.drawCircle(fallbackEnd, 1.2, fillPaint);
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
