part of 'board_view.dart';

/// Section builders for [_BoardViewState.build].
///
/// Kept in a separate part file to satisfy the repository per-file line
/// limit and to keep each section's cyclomatic complexity low. An
/// extension in the same library has full access to the private members of
/// [_BoardViewState], and its methods are callable like instance methods
/// from within the class. The rendered widget tree is identical to the
/// original monolithic `build` — same widgets, keys, order, and guards.
extension _BoardViewSections on _BoardViewState {
  // ── Keyboard shortcuts ─────────────────────────────────────────────────

  KeyEventResult _handleBoardKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent) {
      final escapeResult = _handleEscapeKey(event);
      if (escapeResult != null) return escapeResult;
      final isMeta =
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      final cubit = context.read<BoardCubit>();
      final deleteResult = _handleDeleteSelectionKey(event, cubit);
      if (deleteResult != null) return deleteResult;
      if (isMeta) {
        final metaResult = _handleMetaShortcutKey(event, cubit);
        if (metaResult != null) return metaResult;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult? _handleEscapeKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape) return null;
    if (_connectSourceId != null) {
      _rebuild(() {
        _connectSourceId = null;
        _connectPreviewPointer = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult? _handleDeleteSelectionKey(KeyEvent event, BoardCubit cubit) {
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final ids = cubit.state.selectedPanelIds.toList();
      if (ids.isNotEmpty) {
        for (final id in ids) {
          cubit.removePanel(id);
        }
        cubit.clearSelection();
        return KeyEventResult.handled;
      }
    }
    return null;
  }

  KeyEventResult? _handleMetaShortcutKey(KeyEvent event, BoardCubit cubit) {
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      cubit.copyPanels();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      cubit.pastePanels();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      cubit.duplicatePanels();
      return KeyEventResult.handled;
    }
    return null;
  }

  // ── Bloc listener ──────────────────────────────────────────────────────

  void _onBoardStateChanged(BuildContext context, BoardState state) {
    final conflictPanelId = state.panelLockConflictPanelId;
    if (conflictPanelId != null) {
      final actor = state.panelLockConflictActorId;
      final message = actor != null && actor.isNotEmpty
          ? 'Panel is being edited by $actor'
          : 'Panel is locked by another user';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      context.read<BoardCubit>().clearPanelLockConflict();
    }
  }

  // ── Board scaffold ─────────────────────────────────────────────────────

  Widget _buildBoardScaffold(
    BuildContext context,
    BoardState state,
    BoardDocument activeBoard,
    AppColorScheme colors,
  ) {
    return Container(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BoardToolbar(
            board: activeBoard,
            onCreateBoard: () => _createBoard(context),
            onCreateBoardFromTemplate: () => _createBoardFromTemplate(context),
            onConnectRemote: () => _connectRemoteYoloit(context),
            onShareBoard: () => _shareBoard(context),
            onBoardSettings: () => _showBoardSettings(context, activeBoard),
            onAppSettings: () => _openAppSettings(context),
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
                  return _buildViewportStack(
                    context,
                    state,
                    activeBoard,
                    colors,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewportStack(
    BuildContext context,
    BoardState state,
    BoardDocument activeBoard,
    AppColorScheme colors,
  ) {
    final focusedPanelId = activeBoard.viewport.focusedPanelId;
    final selectedPanelIds = state.selectedPanelIds;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // While the (opaque) board overview layer covers the canvas, pause
        // all canvas tickers — e.g. the chat processing glow — so hidden
        // animations stop scheduling frames.
        TickerMode(
          enabled: !_isBoardOverviewOpen,
          child: _buildScreenshotBoundary(
            context,
            activeBoard,
            colors,
            focusedPanelId,
            selectedPanelIds,
          ),
        ),
        if (_isBoardOverviewOpen)
          _buildBoardOverviewLayer(context, state, activeBoard),
        if (_boardSwitchPreviewBoard != null) _buildBoardSwitchPreviewOverlay(),
        // ── YOLO badge fixed overlay (bottom-right) ────────────
        if (!_isBoardOverviewOpen)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: YoloBadgeWithChat(),
            ),
          ),
      ], // outer Stack children
    ); // outer Stack
  }

  Widget _buildScreenshotBoundary(
    BuildContext context,
    BoardDocument activeBoard,
    AppColorScheme colors,
    String? focusedPanelId,
    Set<String> selectedPanelIds,
  ) {
    return RepaintBoundary(
      key: _screenshotBoundaryKey,
      child: Stack(
        key: _viewportKey,
        children: [
          _buildGridLayer(activeBoard, colors),
          _buildInteractionRegion(
            context,
            activeBoard,
            focusedPanelId,
            selectedPanelIds,
          ),
          _buildWebViewOverlayLayer(activeBoard, focusedPanelId),
          if (_activeTool == BoardToolId.draw) _buildDrawGestureOverlay(),
          if (_activeTool == BoardToolId.connect && _connectSourceId != null)
            _buildConnectTrackingOverlay(),
          if (activeBoard.panels.isEmpty)
            BoardEmptyState(
              onAddNote: () => BoardPanelActions.showAddNoteDialog(context),
            ),
          ..._buildBoardChromeControls(context, activeBoard),
          ..._buildTransientOverlayControls(
            context,
            activeBoard,
            selectedPanelIds,
          ),
          // ── YOLO badge removed from canvas stack ──────────────
        ],
      ),
    ); // RepaintBoundary
  }

  Widget _buildGridLayer(BoardDocument activeBoard, AppColorScheme colors) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          isComplex: true,
          painter: activeBoard.gridMode.enabled
              ? BoardGridPainter(
                  transformCtrl: _transformController,
                  origin: _canvasOrigin,
                  cellSize: activeBoard.gridMode.cellSize,
                  spacing: activeBoard.gridMode.spacing,
                  color: colors.divider.withAlpha(90),
                )
              : InfiniteBoardGridPainter(
                  transformCtrl: _transformController,
                  origin: _canvasOrigin,
                  minorColor: colors.divider.withAlpha(60),
                  majorColor: colors.divider.withAlpha(110),
                ),
        ),
      ),
    );
  }

  // ── Canvas interaction region ──────────────────────────────────────────

  Widget _buildInteractionRegion(
    BuildContext context,
    BoardDocument activeBoard,
    String? focusedPanelId,
    Set<String> selectedPanelIds,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: CanvasInteractionLock.instance.lockStateVersion,
      builder: (context, lockVersion, child) {
        final activeCount = CanvasInteractionLock.instance.activeCount.value;
        final isLocked = CanvasInteractionLock.instance.isLocked;
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
          onPointerSignal: (event) => _onCanvasPointerSignal(event, isLocked),
          onPointerPanZoomStart: (event) =>
              _onCanvasPanZoomStart(event, isLocked),
          onPointerPanZoomUpdate: (event) =>
              _onCanvasPanZoomUpdate(event, isLocked),
          onPointerPanZoomEnd: (event) => _onCanvasPanZoomEnd(event, isLocked),
          child: _buildInteractiveViewer(
            context,
            activeBoard,
            isLocked: isLocked,
            focusedPanelId: focusedPanelId,
            selectedPanelIds: selectedPanelIds,
          ),
        );
      },
    );
  }

  void _onCanvasPointerSignal(PointerSignalEvent event, bool isLocked) {
    final overScrollable = isPointerOverScrollableCard(
      event.position,
      event.viewId,
    );
    if (event is PointerScrollEvent) {
      final scale = matrixScaleOf(_transformController.value);
      // Per-tick scroll events fire at
      // trackpad rate (~120 Hz) — debug
      // only, never the support log.
      _boardDebugLog(
        'pointerScroll locked=$isLocked canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} overScrollable=$overScrollable tool=${_activeTool.name} kind=${event.kind.name} delta=${fmtOffset(event.scrollDelta)} pos=${fmtOffset(event.position)} scale=${fmtDouble(scale)}',
      );
      if (overScrollable) {
        CanvasInteractionLock.instance.clearCanvasSignalGesture();
        // Swallow the event so the inner
        // scrollable handles it and the
        // board canvas does not pan/zoom.
        return;
      }
      CanvasInteractionLock.instance.markCanvasSignalGesture();
    } else {
      _boardSupportLog(
        'pointerSignal locked=$isLocked canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} overScrollable=$overScrollable tool=${_activeTool.name} type=${event.runtimeType} pos=${fmtOffset(event.position)}',
      );
    }
  }

  void _onCanvasPanZoomStart(PointerPanZoomStartEvent event, bool isLocked) {
    final overScrollable = isPointerOverScrollableCard(
      event.position,
      event.viewId,
    );
    if (overScrollable) {
      CanvasInteractionLock.instance.clearCanvasSignalGesture();
      CanvasInteractionLock.instance.enter();
      _panZoomLockedByBoard = true;
    } else {
      CanvasInteractionLock.instance.beginCanvasGesture();
      _panZoomLockedByBoard = false;
    }
    _boardSupportLog(
      'panZoom.start locked=$isLocked canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} overScrollable=$overScrollable tool=${_activeTool.name} pos=${fmtOffset(event.position)} scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
    );
  }

  void _onCanvasPanZoomUpdate(PointerPanZoomUpdateEvent event, bool isLocked) {
    // Per-frame during a pan/zoom
    // gesture — debug only, never the
    // support log.
    _boardDebugLog(
      'panZoom.update locked=$isLocked tool=${_activeTool.name} pan=${fmtOffset(event.pan)} panDelta=${fmtOffset(event.panDelta)} scale=${fmtDouble(event.scale)} rotation=${event.rotation.toStringAsFixed(3)} viewScale=${fmtDouble(matrixScaleOf(_transformController.value))}',
    );
  }

  void _onCanvasPanZoomEnd(PointerPanZoomEndEvent event, bool isLocked) {
    if (_panZoomLockedByBoard) {
      CanvasInteractionLock.instance.exit();
      _panZoomLockedByBoard = false;
    } else if (CanvasInteractionLock.instance.isCanvasGestureActive) {
      CanvasInteractionLock.instance.endCanvasGesture();
    }
    _boardSupportLog(
      'panZoom.end locked=$isLocked canvasGesture=${CanvasInteractionLock.instance.isCanvasGestureActive} tool=${_activeTool.name} scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
    );
  }

  // ── InteractiveViewer ──────────────────────────────────────────────────

  Widget _buildInteractiveViewer(
    BuildContext context,
    BoardDocument activeBoard, {
    required bool isLocked,
    required String? focusedPanelId,
    required Set<String> selectedPanelIds,
  }) {
    return InteractiveViewer(
      key: const ValueKey('board_interactive_viewer'),
      constrained: false,
      minScale: 0.2,
      maxScale: 5.0,
      // Pinch-to-zoom must work everywhere,
      // including over panels (panels do not
      // consume scale gestures). Pan stays
      // gated by isLocked so two-finger
      // scroll over a panel still scrolls
      // the panel instead of the canvas.
      scaleEnabled: true,
      boundaryMargin: const EdgeInsets.all(canvasExpansionChunk),
      // Disable pan while actively drawing,
      // in multi-select mode, or when canvas is locked.
      panEnabled:
          !isLocked &&
          (_activeTool != BoardToolId.draw || _drawPointer == null) &&
          _activeTool != BoardToolId.multiSelect,
      transformationController: _transformController,
      onInteractionStart: (details) =>
          _onViewerInteractionStart(details, isLocked),
      onInteractionUpdate: (details) =>
          _onViewerInteractionUpdate(details, isLocked),
      onInteractionEnd: (details) =>
          _onViewerInteractionEnd(context, activeBoard, details, isLocked),
      child: SizedBox(
        width: _canvasSize.width,
        height: _canvasSize.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: _buildCanvasContentChildren(
            context,
            activeBoard,
            focusedPanelId,
            selectedPanelIds,
          ),
        ),
      ),
    );
  }

  void _onViewerInteractionStart(ScaleStartDetails details, bool isLocked) {
    final startScale = matrixScaleOf(_transformController.value);
    _boardSupportLog(
      'interaction.start locked=$isLocked '
      'tool=${_activeTool.name} '
      'pointerCount=${details.pointerCount} '
      'focal=${fmtOffset(details.focalPoint)} '
      'local=${fmtOffset(details.localFocalPoint)} '
      'scale=${fmtDouble(startScale)}',
    );
    _interactionStartScale = matrixScaleOf(_transformController.value);
    _interactionStartMatrix = _transformController.value.clone();
    _interactionStartedLocked = CanvasInteractionLock.instance.isLocked;
    _rebuild(() {
      _isViewportInteracting = true;
      _isViewportZooming = false;
    });
    _boardDebugLog('interaction.start');
    _stopPanAnimation();
  }

  void _onViewerInteractionUpdate(ScaleUpdateDetails details, bool isLocked) {
    final currentScale = matrixScaleOf(_transformController.value);
    final revertReason = boardViewportInteractionRevertReason(
      startScale: _interactionStartScale,
      currentScale: currentScale,
      interactionStartedLocked: _interactionStartedLocked,
    );
    if (revertReason != null && _interactionStartMatrix != null) {
      _boardSupportLog(
        'interaction.update.reverted '
        'reason=$revertReason '
        'pointerCount=${details.pointerCount} '
        'scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
      );
      _transformController.value = _interactionStartMatrix!;
      return;
    }
    // Per-frame during an
    // interaction — debug only,
    // never the support log.
    _boardDebugLog(
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
      if ((currentScale - _interactionStartScale).abs() > 0.01) {
        _rebuild(() => _isViewportZooming = true);
      }
    }
  }

  void _onViewerInteractionEnd(
    BuildContext context,
    BoardDocument activeBoard,
    ScaleEndDetails details,
    bool isLocked,
  ) {
    _boardSupportLog(
      'interaction.end locked=$isLocked '
      'tool=${_activeTool.name} '
      'velocity=${fmtOffset(details.velocity.pixelsPerSecond)} '
      'scale=${fmtDouble(matrixScaleOf(_transformController.value))}',
    );
    _interactionStartMatrix = null;
    _interactionStartedLocked = false;
    _rebuild(() {
      _isViewportInteracting = false;
      _isViewportZooming = false;
    });
    _boardDebugLog('interaction.end');
    // pageZoom is updated by Swift frame observer; just dispatch resize.
    if (!kIsWeb) {
      _dispatchWebViewResize(activeBoard);
    }
    _persistViewport(context, activeBoard);
  }

  void _dispatchWebViewResize(BoardDocument activeBoard) {
    for (final panel in activeBoard.panels) {
      if (panel.type != WebpagePluginBase.kTypeId) {
        continue;
      }
      final ctrl = WebpagePluginBase.controllers[panel.id];
      if (ctrl == null) continue;
      ctrl.runJavaScript("window.dispatchEvent(new Event('resize'));");
    }
  }

  // ── Canvas content (inside the transformed SizedBox) ───────────────────

  List<Widget> _buildCanvasContentChildren(
    BuildContext context,
    BoardDocument activeBoard,
    String? focusedPanelId,
    Set<String> selectedPanelIds,
  ) {
    return [
      _buildBoardLinksLayer(activeBoard),
      _buildCanvasBackgroundTapListener(context, focusedPanelId),
      _buildBoardGroupOverlay(context, activeBoard),
      // ── Link delete badges ─────────────────────
      if (_activeTool == BoardToolId.select)
        LinkDeleteBadges(
          links: activeBoard.links,
          panels: activeBoard.panels,
          origin: _canvasOrigin,
        ),
      _buildBoardPanelLayer(activeBoard, selectedPanelIds),
      ..._buildDrawingWidgets(context, activeBoard),
      // ── Active stroke preview ─────────────────
      if (_activeStroke.isNotEmpty) _buildActiveStrokePreview(),
      ..._buildConnectPreviewIfActive(activeBoard),
      // ── Multi-select marquee overlay ──────────
      if (_activeTool == BoardToolId.multiSelect)
        _buildMultiSelectOverlay(context, activeBoard),
      if (_multiSelectStart != null && _multiSelectCurrent != null)
        _buildMultiSelectRect(),
    ];
  }

  Widget _buildBoardLinksLayer(BoardDocument activeBoard) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          isComplex: true,
          painter: BoardLinksPainter(
            panels: activeBoard.panels,
            links: activeBoard.links,
            origin: _canvasOrigin,
          ),
        ),
      ),
    );
  }

  // ── Canvas background tap — clear focus ──
  // Opaque: only empty-canvas clicks hit this
  // listener. Translucent also fires on panel
  // taps and races with focusPanel.
  Widget _buildCanvasBackgroundTapListener(
    BuildContext context,
    String? focusedPanelId,
  ) {
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (kDebugMode) {
            debugPrint(
              '[BoardView] Canvas background pointer down at ${event.localPosition} isLocked=${CanvasInteractionLock.instance.isLocked}',
            );
          }
          if (CanvasInteractionLock.instance.isLocked) {
            return;
          }
          if (_activeTool == BoardToolId.multiSelect) {
            context.read<BoardCubit>().clearSelection();
            return;
          }
          if (focusedPanelId != null) {
            _boardWebFocusLog('canvas tap -> clearFocusedPanel');
            context.read<BoardCubit>().clearFocusedPanel();
          }
        },
      ),
    );
  }

  // ── Group backgrounds & headers ────────────
  Widget _buildBoardGroupOverlay(
    BuildContext context,
    BoardDocument activeBoard,
  ) {
    return BoardGroupOverlay(
      board: activeBoard,
      origin: _canvasOrigin,
      onToggleCollapse: (groupId) {
        context.read<BoardCubit>().toggleGroupCollapse(activeBoard.id, groupId);
      },
      onMoveGroupStart: (_) {},
      onMoveGroup: (groupId, details) =>
          _moveGroupWithEdgePan(context, groupId, details),
      onMoveGroupEnd: (_) {},
      onRenameGroup: (groupId) {
        _showRenameGroupDialog(context, activeBoard.id, groupId);
      },
      onCycleFocus: (groupId, direction) {
        context.read<BoardCubit>().cycleGroupFocus(
          activeBoard.id,
          groupId,
          direction,
        );
      },
      onResizeCollapsedGroup: (groupId, bounds) {
        context.read<BoardCubit>().resizeGroupCollapsedBounds(
          activeBoard.id,
          groupId,
          bounds,
        );
      },
    );
  }

  Widget _buildBoardPanelLayer(
    BoardDocument activeBoard,
    Set<String> selectedPanelIds,
  ) {
    return Positioned.fill(
      child: BoardPanelLayer(
        board: activeBoard,
        canvasOrigin: _canvasOrigin,
        isCapturingScreenshot: _isCapturingScreenshot,
        selectedPanelIds: selectedPanelIds.toSet(),
        activeTool: _activeTool,
        connectSourceId: _connectSourceId,
        onMovePanel: _movePanelWithEdgePan,
        onResizePanel: _resizePanelWithEdgePan,
        onDragStart: _handlePanelDragStart,
        onDragEnd: _handlePanelDragEnd,
        onConnectTap: _handleConnectTap,
        onFullscreenPanel: _handleFullscreenPanel,
      ),
    );
  }

  // ── Drawing layer (above panels visually;
  //    only intercepts gestures on actual stroke
  //    pixels via path-based hitTest) ──────────
  List<Widget> _buildDrawingWidgets(
    BuildContext context,
    BoardDocument activeBoard,
  ) {
    return activeBoard.drawings
        .where((d) => !d.hidden)
        .map(
          (drawing) => Positioned(
            key: ValueKey(drawing.id),
            left: drawing.position.dx + _canvasOrigin.dx,
            top: drawing.position.dy + _canvasOrigin.dy,
            width: drawing.size.width,
            height: drawing.size.height,
            child: IgnorePointer(
              ignoring: _activeTool == BoardToolId.connect,
              child: BoardDrawingWidget(
                drawing: drawing,
                isSelectMode: _activeTool == BoardToolId.select,
                onMove: (newPos) => context.read<BoardCubit>().moveDrawing(
                  drawing.id,
                  newPos,
                ),
                onDelete: () =>
                    context.read<BoardCubit>().removeDrawing(drawing.id),
              ),
            ),
          ),
        )
        .toList();
  }

  Widget _buildActiveStrokePreview() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: ActiveStrokePainter(
            points: _activeStroke,
            origin: _canvasOrigin,
            color: _drawSettings.strokeColor,
            strokeWidth: _drawSettings.strokeWidth,
          ),
        ),
      ),
    );
  }

  // ── Connect preview line ──────────────────
  List<Widget> _buildConnectPreviewIfActive(BoardDocument activeBoard) {
    if (_activeTool != BoardToolId.connect ||
        _connectSourceId == null ||
        _connectPreviewPointer == null) {
      return const [];
    }
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: ConnectPreviewPainter(
              panels: activeBoard.panels,
              sourceId: _connectSourceId!,
              targetPoint: _connectPreviewPointer!,
              origin: _canvasOrigin,
              color: _connectSettings.color,
            ),
          ),
        ),
      ),
    ];
  }

  // ── WebView overlay ───────────────────────────────
  // Native platform views (WKWebView) inside
  // InteractiveViewer's Transform have coordinate
  // offset issues on macOS. Render live WebViews
  // outside the transform, positioned at each
  // panel's computed screen rect.
  Widget _buildWebViewOverlayLayer(
    BoardDocument activeBoard,
    String? focusedPanelId,
  ) {
    return Positioned.fill(
      child: WebViewOverlays(
        panels: activeBoard.panels,
        focusedPanelId: focusedPanelId,
        transformController: _transformController,
        canvasOrigin: _canvasOrigin,
        isInteracting: _isViewportInteracting,
      ),
    );
  }

  // ── Draw gesture capture overlay ─────────────────
  // Uses Listener with translucent so InteractiveViewer
  // still receives trackpad scroll / pinch-to-zoom events.
  Widget _buildDrawGestureOverlay() {
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDrawPointerDown,
        onPointerMove: _onDrawPointerMove,
        onPointerUp: _onDrawPointerUp,
        onPointerCancel: _onDrawPointerCancel,
      ),
    );
  }

  void _onDrawPointerDown(PointerDownEvent e) {
    if (_drawPointer != null) return;
    final pt = _boardPointFromGlobal(e.position);
    if (pt == null) return;
    _rebuild(() {
      _drawPointer = e.pointer;
      _activeStroke
        ..clear()
        ..add(pt);
    });
  }

  void _onDrawPointerMove(PointerMoveEvent e) {
    if (e.pointer != _drawPointer) return;
    final pt = _boardPointFromGlobal(e.position);
    if (pt == null) return;
    _rebuild(() => _activeStroke.add(pt));
  }

  void _onDrawPointerUp(PointerUpEvent e) {
    if (e.pointer != _drawPointer) return;
    _drawPointer = null;
    _finishDrawStroke(context);
  }

  void _onDrawPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _drawPointer) return;
    _drawPointer = null;
    _rebuild(() => _activeStroke.clear());
  }

  // ── Connect tool pointer tracking ─────────────────
  // translucent so panel-tap GestureDetectors still fire.
  Widget _buildConnectTrackingOverlay() {
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _onConnectPointerHover,
        child: const SizedBox.expand(),
      ),
    );
  }

  void _onConnectPointerHover(PointerHoverEvent e) {
    final pt = _boardPointFromGlobal(e.position);
    if (pt == null) return;
    _rebuild(() => _connectPreviewPointer = pt);
  }

  // ── Board chrome controls (top-right, tools, history) ──────────────────

  List<Widget> _buildBoardChromeControls(
    BuildContext context,
    BoardDocument activeBoard,
  ) {
    return [
      if (!_isBoardOverviewOpen && !_isCapturingScreenshot)
        _buildTopRightControls(context, activeBoard),
      if (!_isBoardOverviewOpen && !_isCapturingScreenshot)
        _buildToolsPanel(context, activeBoard),
      _buildHistoryPanelEntry(activeBoard),
    ];
  }

  Widget _buildTopRightControls(
    BuildContext context,
    BoardDocument activeBoard,
  ) {
    return BoardTopRightControls(
      showMinimap: _showMinimap,
      onToggleMinimap: () => _rebuild(() => _showMinimap = !_showMinimap),
      onFitBoard: () => _fitBoardPanels(activeBoard, persist: true),
      isGridMode: activeBoard.gridMode.enabled,
      onToggleGrid: () => context.read<BoardCubit>().setGridMode(
        activeBoard.id,
        enabled: !activeBoard.gridMode.enabled,
      ),
      onResetGrid: () =>
          context.read<BoardCubit>().resetGridView(activeBoard.id),
      onGroupByType: () =>
          context.read<BoardCubit>().arrangePanelsByTypeInGrid(activeBoard.id),
      panels: activeBoard.panels,
      transformController: _transformController,
      viewportSize: _viewportSize ?? const Size(1, 1),
      origin: _canvasOrigin,
      onPanTo: (center) =>
          _centerViewportOn(activeBoard, center, persist: true),
    );
  }

  Widget _buildToolsPanel(BuildContext context, BoardDocument activeBoard) {
    return Positioned(
      left: 12,
      top: 12,
      child: BoardToolsPanel(
        board: activeBoard,
        platform: _currentPanelPlatform,
        visible: _showToolsPanel,
        activeTool: _activeTool,
        drawSettings: _drawSettings,
        connectSettings: _connectSettings,
        onToolChanged: (tool) => _rebuild(() {
          _activeTool = tool;
          _activeStroke.clear();
          _connectSourceId = null;
          _connectPreviewPointer = null;
          _clearMultiSelectGesture();
          if (tool != BoardToolId.multiSelect) {
            context.read<BoardCubit>().clearSelection();
          }
        }),
        onDrawSettingsChanged: (s) => _rebuild(() => _drawSettings = s),
        onConnectSettingsChanged: (s) => _rebuild(() => _connectSettings = s),
        onToggle: () => _rebuild(() => _showToolsPanel = !_showToolsPanel),
        onAddNote: () => BoardPanelActions.showAddNoteDialog(context),
        onAddChat: () =>
            context.read<BoardCubit>().createChatPanel(configured: false),
        onAddTerminal: () => context.read<BoardCubit>().createTerminalPanel(),
        onAddGeneric: (typeId) => _handleGenericToolSelection(context, typeId),
      ),
    );
  }

  Widget _buildHistoryPanelEntry(BoardDocument activeBoard) {
    return ValueListenableBuilder<bool>(
      valueListenable: boardHistoryVisibility,
      builder: (context, historyVisible, _) {
        if (_isBoardOverviewOpen || _isCapturingScreenshot || !historyVisible) {
          return const SizedBox.shrink();
        }
        return Positioned(
          top: 58,
          right: 12,
          bottom: 24,
          child: BoardHistoryPanel(
            board: activeBoard,
            onClose: () => boardHistoryVisibility.value = false,
          ),
        );
      },
    );
  }

  // ── Transient overlay controls (cancel connect, multi-selection) ───────

  List<Widget> _buildTransientOverlayControls(
    BuildContext context,
    BoardDocument activeBoard,
    Set<String> selectedPanelIds,
  ) {
    return [
      // ── Cancel connection button ───────────────────────
      if (!_isBoardOverviewOpen &&
          _activeTool == BoardToolId.connect &&
          _connectSourceId != null)
        CancelConnectionBar(
          onCancel: () => _rebuild(() {
            _connectSourceId = null;
            _connectPreviewPointer = null;
          }),
        ),
      // ── Multi-selection toolbar ────────────────────────
      if (!_isBoardOverviewOpen &&
          !_isCapturingScreenshot &&
          selectedPanelIds.isNotEmpty)
        _buildSelectionToolbar(context, activeBoard, selectedPanelIds),
    ];
  }

  Widget _buildSelectionToolbar(
    BuildContext context,
    BoardDocument activeBoard,
    Set<String> selectedPanelIds,
  ) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: BoardSelectionToolbar(
          selectedCount: selectedPanelIds.length,
          onClear: () => context.read<BoardCubit>().clearSelection(),
          onAddToGroup: () => _addSelectionToGroup(context, activeBoard),
          onDelete: () => _deleteSelectedPanels(context),
        ),
      ),
    );
  }

  void _deleteSelectedPanels(BuildContext context) {
    final cubit = context.read<BoardCubit>();
    final ids = cubit.state.selectedPanelIds.toList();
    for (final id in ids) {
      cubit.removePanel(id);
    }
    cubit.clearSelection();
  }

  // ── Board overview & switch preview ────────────────────────────────────

  Widget _buildBoardOverviewLayer(
    BuildContext context,
    BoardState state,
    BoardDocument activeBoard,
  ) {
    return Positioned.fill(
      child: BoardOverviewLayer(
        activeBoardId: activeBoard.id,
        boards: state.activeBoards,
        previewPngs: _boardPreviewPngs,
        debugLog: _boardOverviewLog,
        onDisconnectRemoteBoard: (board) =>
            context.read<BoardCubit>().disconnectRemoteBoard(board.id),
        onDeleteRemoteBoard: (board) =>
            _deleteRemoteBoardOnServer(context, board),
        onDisconnectRemoteUrl: (url) =>
            context.read<BoardCubit>().disconnectRemoteBoardsForUrl(url),
        onClose: () {
          if (!mounted) return;
          _boardOverviewLog('close.parent');
          _rebuild(() {
            _isBoardOverviewOpen = false;
            _cancelBgCapture = true;
          });
        },
        onCreateBoard: () {
          if (!mounted) return;
          _boardOverviewLog('create.parent');
          _rebuild(() {
            _isBoardOverviewOpen = false;
            _cancelBgCapture = true;
          });
          _createBoard(context);
        },
        onCreateBoardFromTemplate: () {
          if (!mounted) return;
          _boardOverviewLog('createFromTemplate.parent');
          _rebuild(() {
            _isBoardOverviewOpen = false;
            _cancelBgCapture = true;
          });
          _createBoardFromTemplate(context);
        },
        onSelectedBoard: (board, previewPng) {
          if (!mounted) return;
          _runBoardSwitchPreview(board, previewPng);
        },
      ),
    );
  }

  Widget _buildBoardSwitchPreviewOverlay() {
    return Positioned.fill(
      child: BoardSwitchPreviewOverlay(
        board: _boardSwitchPreviewBoard!,
        previewPng: _boardSwitchPreviewPng,
        visible: _boardSwitchPreviewVisible,
        onHidden: () {
          _boardOverviewLog(
            'switchPreview.hidden '
            'visible=$_boardSwitchPreviewVisible',
          );
          if (!mounted || _boardSwitchPreviewVisible) {
            return;
          }
          _rebuild(() {
            _boardSwitchPreviewBoard = null;
            _boardSwitchPreviewPng = null;
          });
        },
      ),
    );
  }

  // Drives both the production overview tap and the `@visibleForTesting`
  // `debugSimulateBoardSelection` forwarder. Centralized so the fade-out
  // timer coalescing and the debug-toggle fast-path stay in lock-step.
  void _runBoardSwitchPreview(BoardDocument board, Uint8List? previewPng) {
    _boardOverviewLog(
      'select.parent.start board=${board.id} '
      'hasPng=${previewPng != null} '
      'disabled=${BoardView.debugDisablePreviewOverlayForTesting}',
    );
    if (BoardView.debugDisablePreviewOverlayForTesting) {
      _boardOverviewLog('select.parent.disabled branch=${board.id}');
      _rebuild(() {
        _isBoardOverviewOpen = false;
        _cancelBgCapture = true;
      });
      context.read<BoardCubit>().setActiveBoard(board.id);
      return;
    }
    // Cancel any pending fade-out: when a new switch comes in within the
    // 80ms visible window, the previous preview is dropped in favor of
    // this one and a fresh timer is scheduled. Without cancellation, rapid
    // switches would stack redundant setState(visible=false) calls and
    // trigger overlapping fade-out animations on the AnimatedOpacity.
    _boardSwitchPreviewFadeTimer?.cancel();
    _boardSwitchPreviewFadeTimer = null;
    _rebuild(() {
      _isBoardOverviewOpen = false;
      _cancelBgCapture = true;
      _boardSwitchPreviewBoard = board;
      _boardSwitchPreviewPng = previewPng;
      _boardSwitchPreviewVisible = true;
    });
    context.read<BoardCubit>().setActiveBoard(board.id);
    _boardSwitchPreviewFadeTimer = Timer(
      const Duration(milliseconds: 80),
      () {
        if (!mounted) return;
        _debugFadeOutCount += 1;
        _rebuild(() => _boardSwitchPreviewVisible = false);
      },
    );
  }

  // ── Focused-panel visibility scheduling ────────────────────────────────

  bool _isFocusVisibilitySchedulingBlocked(BoardDocument board) {
    if (board.viewport.focusedPanelId == null || _viewportSize == null) {
      return true;
    }
    if (_shouldAutoFit(board)) return true;
    return _isPanelDragging || _isViewportInteracting;
  }

  BoardPanelInstance? _findBoardPanel(BoardDocument board, String panelId) {
    for (final entry in board.panels) {
      if (entry.id == panelId) {
        return entry;
      }
    }
    return null;
  }

  String _focusVisibilityKey(
    BoardDocument board,
    BoardPanelInstance panel,
    Size size,
  ) {
    return '${board.id}:${panel.id}:${panel.bounds.x}:${panel.bounds.y}:${panel.bounds.width}:${panel.bounds.height}:${size.width}:${size.height}:z${board.viewport.zoomOnFocus}';
  }

  void _applySuppressedFocusVisibility(
    BoardDocument board,
    String focusedPanelId,
    Size size,
  ) {
    _suppressFocusVisibility = false;
    // Set the key to match so subsequent rebuilds don't re-schedule.
    final fp = _findBoardPanel(board, focusedPanelId);
    if (fp != null) {
      _focusedPanelVisibilityKey = _focusVisibilityKey(board, fp, size);
    }
    _boardOverviewLog('focusVisibility.suppressed (board switch)');
  }

  void _scheduleFocusedPanelVisibility(
    BoardDocument board,
    BoardPanelInstance resolvedPanel,
    Size size,
  ) {
    final shouldZoom = board.viewport.zoomOnFocus;
    final key = _focusVisibilityKey(board, resolvedPanel, size);
    if (_focusedPanelVisibilityKey == key) return;
    _focusedPanelVisibilityKey = key;
    _boardOverviewLog(
      'focusVisibility.scheduled panel=${resolvedPanel.id} zoom=$shouldZoom',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealFocusedPanel(board, resolvedPanel, shouldZoom);
    });
  }

  void _revealFocusedPanel(
    BoardDocument board,
    BoardPanelInstance resolvedPanel,
    bool shouldZoom,
  ) {
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
  }
}
