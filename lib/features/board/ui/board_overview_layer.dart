import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_layout.dart';
import 'package:yoloit/features/board/ui/board_overview_widgets.dart';
import 'package:yoloit/ui/components/buttons/overlay_icon_button.dart';

class BoardOverviewLayer extends StatefulWidget {
  const BoardOverviewLayer({
    super.key,
    required this.activeBoardId,
    required this.boards,
    required this.previewPngs,
    required this.onSelectedBoard,
    required this.onCreateBoard,
    required this.onCreateBoardFromTemplate,
    required this.onDisconnectRemoteBoard,
    required this.onDeleteRemoteBoard,
    required this.onDisconnectRemoteUrl,
    required this.onClose,
    required this.debugLog,
  });

  final String activeBoardId;
  final List<BoardDocument> boards;
  final Map<String, Uint8List> previewPngs;
  final void Function(BoardDocument board, Uint8List? previewPng)
  onSelectedBoard;
  final VoidCallback onCreateBoard;
  final VoidCallback onCreateBoardFromTemplate;
  final ValueChanged<BoardDocument> onDisconnectRemoteBoard;
  final ValueChanged<BoardDocument> onDeleteRemoteBoard;
  final ValueChanged<String> onDisconnectRemoteUrl;
  final VoidCallback onClose;
  final ValueChanged<String> debugLog;

  @override
  State<BoardOverviewLayer> createState() => BoardOverviewLayerState();
}

class BoardOverviewLayerState extends State<BoardOverviewLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  String? _zoomBoardId;
  String? _lastLayoutSignature;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _zoomBoardId = widget.activeBoardId;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 280),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _controller.addStatusListener(_handleAnimationStatus);
    widget.debugLog(
      'layer.init active=${widget.activeBoardId} boards=${widget.boards.length}',
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    widget.debugLog(
      'layer.animation.status=$status value=${_controller.value.toStringAsFixed(3)} '
      'closing=$_closing zoom=$_zoomBoardId',
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    final watch = Stopwatch()..start();
    widget.debugLog('close.start active=${widget.activeBoardId}');
    setState(() {
      _closing = true;
      _zoomBoardId = widget.activeBoardId;
    });
    await _controller.reverse();
    widget.debugLog('close.reverseDone elapsed=${watch.elapsedMilliseconds}ms');
    if (mounted) widget.onClose();
  }

  Future<void> _selectBoard(String boardId) async {
    widget.debugLog(
      'select.attempt board=$boardId closing=$_closing '
      'active=${widget.activeBoardId}',
    );
    if (_closing) return;
    final boards = _orderedBoards;
    final watch = Stopwatch()..start();
    widget.debugLog(
      'select.tap board=$boardId active=${widget.activeBoardId} '
      'hasPng=${widget.previewPngs.containsKey(boardId)}',
    );
    if (boardId == widget.activeBoardId) {
      await _close();
      return;
    }
    setState(() {
      _closing = true;
      _zoomBoardId = boardId;
    });
    widget.debugLog('select.reverseStart board=$boardId');
    await _controller.reverse();
    widget.debugLog(
      'select.reverseDone board=$boardId elapsed=${watch.elapsedMilliseconds}ms',
    );
    if (!mounted) return;
    final selected = boards.firstWhere((board) => board.id == boardId);
    widget.debugLog(
      'select.callback board=$boardId elapsed=${watch.elapsedMilliseconds}ms',
    );
    widget.onSelectedBoard(selected, widget.previewPngs[boardId]);
  }

  Future<void> _createBoard() async {
    if (_closing) return;
    final watch = Stopwatch()..start();
    widget.debugLog('create.start');
    setState(() {
      _closing = true;
      _zoomBoardId = null;
    });
    await _controller.reverse();
    if (!mounted) return;
    widget.debugLog(
      'create.reverseDone elapsed=${watch.elapsedMilliseconds}ms',
    );
    widget.onCreateBoard();
  }

  Future<void> _createBoardFromTemplate() async {
    if (_closing) return;
    widget.debugLog('createFromTemplate.start');
    setState(() {
      _closing = true;
      _zoomBoardId = null;
    });
    await _controller.reverse();
    if (!mounted) return;
    widget.onCreateBoardFromTemplate();
  }

  List<BoardDocument> get _orderedBoards {
    final localBoards =
        widget.boards.where((board) => !isRemoteBoard(board)).toList();
    final remoteBoards =
        widget.boards.where((board) => isRemoteBoard(board)).toList();
    return <BoardDocument>[...localBoards, ...remoteBoards];
  }

  List<BoardOverviewSection> get _sections {
    final localBoards =
        widget.boards.where((board) => !isRemoteBoard(board)).toList();
    final sections = <BoardOverviewSection>[
      BoardOverviewSection(
        label: 'Local boards',
        boards: localBoards,
        includesCreate: true,
      ),
    ];
    final remoteGroups = <String, List<BoardDocument>>{};
    for (final board in widget.boards.where(isRemoteBoard)) {
      final remote = remoteInfoForBoard(board);
      if (remote == null) continue;
      remoteGroups.putIfAbsent(remote.url, () => <BoardDocument>[]).add(board);
    }
    for (final entry in remoteGroups.entries) {
      sections.add(
        BoardOverviewSection(
          label: 'Remote boards',
          subtitle: Uri.tryParse(entry.key)?.authority ?? entry.key,
          remoteUrl: entry.key,
          boards: entry.value,
        ),
      );
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sections = _sections;
        final boards = _orderedBoards;
        final layout = BoardOverviewSectionedLayout.compute(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          itemCounts: sections
              .map(
                (section) =>
                    section.boards.length + (section.includesCreate ? 1 : 0),
              )
              .toList(growable: false),
        );
        final layoutSignature =
            '${constraints.maxWidth.toStringAsFixed(1)}x${constraints.maxHeight.toStringAsFixed(1)}:'
            '${layout.columns}:${layout.cardSize.width.toStringAsFixed(1)}x'
            '${layout.cardSize.height.toStringAsFixed(1)}';
        if (_lastLayoutSignature != layoutSignature) {
          _lastLayoutSignature = layoutSignature;
          widget.debugLog('layer.layout $layoutSignature');
        }
        final fullRect = Rect.fromLTWH(
          0,
          0,
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return AnimatedBuilder(
          animation: _curve,
          builder: (context, _) {
            final t = _curve.value;
            final fade = t.clamp(0.0, 1.0).toDouble();
            final highlightedBoardId =
                _closing && _zoomBoardId != null
                    ? _zoomBoardId
                    : widget.activeBoardId;
            final widgets = <Widget>[
              _buildBackdrop(colors),
              ..._buildSectionLabels(sections, layout, fade),
              ..._buildBoardCards(
                boards,
                sections,
                layout,
                fullRect,
                t,
                fade,
                highlightedBoardId,
                colors,
              ),
              _buildCreateCard(layout, sections, t, fade),
              _buildCloseButton(fade),
            ];

            return Stack(clipBehavior: Clip.none, children: widgets);
          },
        );
      },
    );
  }

  Widget _buildBackdrop(AppColorScheme colors) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: ColoredBox(
          color: colors.background,
          child: CustomPaint(
            isComplex: true,
            painter: BoardOverviewBackdropPainter(
              minorColor: colors.divider.withAlpha(45),
              majorColor: colors.divider.withAlpha(85),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSectionLabels(
    List<BoardOverviewSection> sections,
    BoardOverviewSectionedLayout layout,
    double fade,
  ) {
    final widgets = <Widget>[];
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      if (layout.itemCountForSection(sectionIndex) == 0) continue;
      widgets.add(
        BoardOverviewSectionLabel(
          rect: layout.rectFor(sectionIndex, 0),
          label: section.label,
          subtitle: section.subtitle,
          opacity: fade,
          disconnectKey:
              section.remoteUrl == null
                  ? null
                  : Key(
                    'board-overview-disconnect-remote-${section.remoteUrl}',
                  ),
          onDisconnect:
              section.remoteUrl == null
                  ? null
                  : () => widget.onDisconnectRemoteUrl(section.remoteUrl!),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildBoardCards(
    List<BoardDocument> boards,
    List<BoardOverviewSection> sections,
    BoardOverviewSectionedLayout layout,
    Rect fullRect,
    double t,
    double fade,
    String? highlightedBoardId,
    AppColorScheme colors,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < boards.length; i++) {
      final board = boards[i];
      final location = layout.locationForBoard(sections, board.id);
      if (location == null) continue;
      final endRect = layout.rectFor(
        location.sectionIndex,
        location.itemIndex,
      );
      final isZoomBoard = board.id == _zoomBoardId;
      final startRect =
          isZoomBoard
              ? fullRect
              : Rect.fromCenter(
                center: endRect.center,
                width: endRect.width * 0.82,
                height: endRect.height * 0.82,
              );
      final rect = Rect.lerp(startRect, endRect, t)!;
      final opacity = isZoomBoard ? 1.0 : fade;
      // When the zoom card is near full-screen (t < 0.5),
      // hide the card chrome so the purple-tinted surface/border
      // colors don't create an overlay effect.
      final showChrome = !isZoomBoard || t >= 0.5;
      widgets.add(
        _buildBoardCard(
          board,
          rect: rect,
          opacity: opacity,
          showChrome: showChrome,
          t: t,
          highlightedBoardId: highlightedBoardId,
          colors: colors,
        ),
      );
    }
    return widgets;
  }

  Widget _buildBoardCard(
    BoardDocument board, {
    required Rect rect,
    required double opacity,
    required bool showChrome,
    required double t,
    required String? highlightedBoardId,
    required AppColorScheme colors,
  }) {
    return Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: opacity,
        child:
            showChrome
                ? BoardOverviewCard(
                  board: board,
                  active: board.id == highlightedBoardId && t >= 0.92,
                  previewPng: widget.previewPngs[board.id],
                  onTap: () => _selectBoard(board.id),
                  onDisconnect:
                      remoteInfoForBoard(board) == null
                          ? null
                          : () => widget.onDisconnectRemoteBoard(board),
                  onDeleteRemote:
                      remoteInfoForBoard(board) == null
                          ? null
                          : () => widget.onDeleteRemoteBoard(board),
                )
                : GestureDetector(
                  onTap: () => _selectBoard(board.id),
                  child: RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        16 * t.clamp(0.0, 1.0),
                      ),
                      child:
                          widget.previewPngs[board.id] != null
                              ? Image.memory(
                                widget.previewPngs[board.id]!,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                gaplessPlayback: true,
                              )
                              : ColoredBox(
                                color: colors.background,
                                child: const SizedBox.expand(),
                              ),
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildCreateCard(
    BoardOverviewSectionedLayout layout,
    List<BoardOverviewSection> sections,
    double t,
    double fade,
  ) {
    final createLocation = layout.createLocation(sections);
    final createRect =
        createLocation == null
            ? Rect.zero
            : layout.rectFor(
              createLocation.sectionIndex,
              createLocation.itemIndex,
            );
    return Positioned.fromRect(
      rect:
          Rect.lerp(
            Rect.fromCenter(
              center: createRect.center,
              width: createRect.width * 0.82,
              height: createRect.height * 0.82,
            ),
            createRect,
            t,
          )!,
      child: Opacity(
        opacity: fade,
        child: CreateBoardOverviewCard(
          onTap: _createBoard,
          onTemplateTap: _createBoardFromTemplate,
        ),
      ),
    );
  }

  Widget _buildCloseButton(double fade) {
    return Positioned(
      top: 14,
      right: 14,
      child: Opacity(
        opacity: fade,
        child: OverlayIconButton(
          icon: Icons.close,
          tooltip: 'Close boards overview',
          onTap: _close,
        ),
      ),
    );
  }
}
