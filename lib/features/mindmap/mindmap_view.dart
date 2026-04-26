import 'dart:math' as math show max, min;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/utils/git_init_prompt.dart';
import 'package:yoloit/features/collaboration/ui/collaboration_button.dart';
import 'package:yoloit/features/collaboration/bloc/collaboration_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_graph_builder.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/node_registry.dart';
import 'package:yoloit/features/mindmap/plugin/mindmap_plugin_registry.dart';
import 'package:yoloit/features/mindmap/sidebar/show_hide_sidebar.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/mindmap/widgets/mindmap_connector.dart';
import 'package:yoloit/features/mindmap/widgets/mindmap_node.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_session.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

/// The Miro-like mind-map canvas view.
/// Shows all workspaces, sessions, repos, branches, agents (with live terminals),
/// changed files, and the active editor as interconnected draggable cards.
class MindMapView extends StatefulWidget {
  const MindMapView({super.key});

  @override
  State<MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends State<MindMapView>
    with TickerProviderStateMixin {
  final _transformCtrl = TransformationController();
  late AnimationController _dashCtrl;
  late Animation<double> _dashAnim;

  // ── Smooth pan animation ──────────────────────────────────────────────────
  late AnimationController _panCtrl;
  Animation<Matrix4>? _panAnim;

  /// Tracks which file path was last animated to — avoids re-animating on
  /// content-only updates when the same file is still active.
  String? _lastFocusedFilePath;

  /// Set to true after the first successful pan-to-content on open.
  bool _initialPanDone = false;

  /// Viewport size supplied by the canvas LayoutBuilder once it is laid out.
  Size? _viewportSize;

  /// Called by _MindMapCanvas when its LayoutBuilder resolves the viewport.
  void _onViewportSize(Size s) {
    if (s == _viewportSize) return;
    _viewportSize = s;
    // If we haven't done the initial fit yet, try now that we have a size.
    if (!_initialPanDone) {
      final mm = context.read<MindMapCubit>();
      if (mm.state.positions.isNotEmpty) {
        _initialPanDone = true;
        _fitAllNodes(mm.state.positions, mm.state.sizes);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _dashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _dashAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_dashCtrl);

    _panCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<MindMapCubit>().loadPersistedPositions();
      if (!mounted) return;
      // Preload persisted session metadata for all non-active workspaces so
      // the mindmap can render their terminals as idle cards.
      final wsState = context.read<WorkspaceCubit>().state;
      if (wsState is WorkspaceLoaded) {
        await context.read<TerminalCubit>().loadPersistedMetadataForWorkspaces(
          wsState.workspaces.map((w) => w.id).toList(),
        );
      }
    });
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    _dashCtrl.dispose();
    _panCtrl.dispose();
    super.dispose();
  }

  /// Smoothly pans the canvas so [nodeId] is roughly centered on screen.
  /// Uses [Matrix4Tween] so the transition is animated with [Curves.easeInOutCubic].
  void _animateToNode(String nodeId, MindMapState mmState) {
    final pos = mmState.positions[nodeId];
    if (pos == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final screenSize = renderBox.size;
    const editorW = 460.0;
    const editorH = 348.0;
    final targetX = pos.dx + editorW / 2 - screenSize.width / 2;
    final targetY = pos.dy + editorH / 2 - screenSize.height / 2;
    final scale = _transformCtrl.value.getMaxScaleOnAxis();
    final targetMatrix = Matrix4.identity()
      ..scale(scale)
      ..translate(-targetX, -targetY);

    // Stop any in-progress pan, build a new tween from current position.
    _panCtrl.stop();
    _panAnim?.removeListener(_applyPanAnim);

    _panAnim =
        Matrix4Tween(
            begin: _transformCtrl.value.clone(),
            end: targetMatrix,
          ).animate(
            CurvedAnimation(parent: _panCtrl, curve: Curves.easeInOutCubic),
          )
          ..addListener(_applyPanAnim);

    _panCtrl.forward(from: 0.0);
  }

  void _applyPanAnim() {
    final anim = _panAnim;
    if (anim != null && _panCtrl.isAnimating) {
      _transformCtrl.value = anim.value;
    }
  }

  /// Pan and zoom so all nodes are visible. Uses the viewport size from
  /// [_viewportSize] (supplied by LayoutBuilder) to avoid depending on
  /// RenderBox which may not be ready on the first frame.
  void _fitAllNodes(Map<String, Offset> positions, Map<String, Size> sizes) {
    if (positions.isEmpty) return;
    // Use stored LayoutBuilder size; fall back to MediaQuery if not yet set.
    final screen = _viewportSize ?? MediaQuery.sizeOf(context);
    if (screen.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final e in positions.entries) {
      final pos = e.value;
      final sz = sizes[e.key] ?? const Size(220, 160);
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx + sz.width > maxX) maxX = pos.dx + sz.width;
      if (pos.dy + sz.height > maxY) maxY = pos.dy + sz.height;
    }

    const padding = 80.0;
    final spanW = (maxX - minX) + 2 * padding;
    final spanH = (maxY - minY) + 2 * padding;

    // Fit to the tighter dimension; allow zooming out as needed, cap at 0.85.
    final scale = (math.min(screen.width / spanW, screen.height / spanH))
        .clamp(0.08, 0.85);

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final tx = centerX - screen.width / (2 * scale);
    final ty = centerY - screen.height / (2 * scale);
    final targetMatrix = Matrix4.identity()
      ..scale(scale)
      ..translate(-tx, -ty);

    _panCtrl.stop();
    _panAnim?.removeListener(_applyPanAnim);
    _panAnim =
        Matrix4Tween(
            begin: _transformCtrl.value.clone(),
            end: targetMatrix,
          ).animate(
            CurvedAnimation(parent: _panCtrl, curve: Curves.easeInOutCubic),
          )
          ..addListener(_applyPanAnim);
    _panCtrl.forward(from: 0.0);
  }

  void _animateToIdentity() {
    _panCtrl.stop();
    _panAnim?.removeListener(_applyPanAnim);
    _panAnim =
        Matrix4Tween(
            begin: _transformCtrl.value.clone(),
            end: Matrix4.identity(),
          ).animate(
            CurvedAnimation(parent: _panCtrl, curve: Curves.easeInOutCubic),
          )
          ..addListener(_applyPanAnim);
    _panCtrl.forward(from: 0.0);
  }

  /// Smoothly pans so [canvasCenter] appears at the center of the viewport.
  /// Called by the minimap when the user taps/drags on it.
  void _animateToCenterOffset(Offset canvasCenter) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final screenSize = renderBox.size;
    final scale = _transformCtrl.value.getMaxScaleOnAxis();
    final tx = canvasCenter.dx - screenSize.width / (2 * scale);
    final ty = canvasCenter.dy - screenSize.height / (2 * scale);
    final targetMatrix = Matrix4.identity()
      ..scale(scale)
      ..translate(-tx, -ty);

    _panCtrl.stop();
    _panAnim?.removeListener(_applyPanAnim);
    _panAnim =
        Matrix4Tween(
            begin: _transformCtrl.value.clone(),
            end: targetMatrix,
          ).animate(
            CurvedAnimation(parent: _panCtrl, curve: Curves.easeInOutCubic),
          )
          ..addListener(_applyPanAnim);
    _panCtrl.forward(from: 0.0);
  }

  ({List<MindMapNodeData> nodes, List<MindMapConnection> conns}) _buildData(
    WorkspaceState wsState,
    TerminalState termState,
    ReviewState reviewState,
    FileEditorState editorState,
    RunState runState,
  ) {
    final graph = buildMindMapGraph(
      wsState: wsState,
      termState: termState,
      reviewState: reviewState,
      editorState: editorState,
      runState: runState,
    );
    final nodes = [...graph.nodes];
    final conns = [...graph.conns];

    // ── Plugin-provided nodes ────────────────────────────────────────────────
    final pluginEntries = MindMapPluginRegistry.instance.collectNodes(context);
    for (final entry in pluginEntries) {
      if (nodes.any((n) => n.id == entry.data.id)) continue; // dedup
      nodes.add(entry.data);
      conns.addAll(entry.connections);
    }

    return (nodes: nodes, conns: conns);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RunCubit, RunState>(
      builder: (context, runState) {
        return BlocBuilder<WorkspaceCubit, WorkspaceState>(
          builder: (context, wsState) {
            return BlocBuilder<TerminalCubit, TerminalState>(
              builder: (context, termState) {
                return BlocBuilder<ReviewCubit, ReviewState>(
                  builder: (context, reviewState) {
                    return BlocBuilder<FileEditorCubit, FileEditorState>(
                      builder: (context, editorState) {
                        final (:nodes, :conns) = _buildData(
                          wsState,
                          termState,
                          reviewState,
                          editorState,
                          runState,
                        );

                        // Update cubit with new nodes (triggers layout if needed).
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          final mm = context.read<MindMapCubit>();
                          mm.updateNodes(nodes, conns);
                          // On first open, fit all nodes into view.
                          // _onViewportSize also tries this — whichever fires last wins.
                          if (!_initialPanDone &&
                              mm.state.positions.isNotEmpty &&
                              _viewportSize != null) {
                            _initialPanDone = true;
                            _fitAllNodes(mm.state.positions, mm.state.sizes);
                          }
                          // Animate to editor card only when the active file changes
                          // (not on every content update for the same file).
                          // Skip auto-pan when triggered by a remote client action.
                          if (editorState.isVisible &&
                              editorState.tabs.isNotEmpty) {
                            mm.showNode('editor:active');
                            final idx = editorState.activeIndex.clamp(
                              0,
                              editorState.tabs.length - 1,
                            );
                            final filePath = editorState.tabs[idx].filePath;
                            if (filePath != _lastFocusedFilePath) {
                              _lastFocusedFilePath = filePath;
                              final collab = context.read<CollaborationCubit>();
                              if (!collab.isHandlingRemoteAction) {
                                _animateToNode('editor:active', mm.state);
                              }
                            }
                          }
                        });

                        return _MindMapCanvas(
                          nodes: nodes,
                          conns: conns,
                          transformCtrl: _transformCtrl,
                          dashAnimation: _dashAnim,
                          onResetView: _animateToIdentity,
                          onPanToOffset: _animateToCenterOffset,
                          onViewportSize: _onViewportSize,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// ── Canvas ─────────────────────────────────────────────────────────────────

class _MindMapCanvas extends StatefulWidget {
  const _MindMapCanvas({
    required this.nodes,
    required this.conns,
    required this.transformCtrl,
    required this.dashAnimation,
    required this.onResetView,
    required this.onPanToOffset,
    required this.onViewportSize,
  });
  final List<MindMapNodeData> nodes;
  final List<MindMapConnection> conns;
  final TransformationController transformCtrl;
  final Animation<double> dashAnimation;
  final VoidCallback onResetView;
  final void Function(Offset canvasCenter) onPanToOffset;
  final void Function(Size) onViewportSize;

  @override
  State<_MindMapCanvas> createState() => _MindMapCanvasState();
}

class _MindMapCanvasState extends State<_MindMapCanvas> {
  bool _nodeDragging = false;

  // Large canvas with generous top/left padding so users can scroll in all
  // directions. boundaryMargin(infinity) on InteractiveViewer makes it infinite.
  static const _canvasW = 8000.0;
  static const _canvasH = 8000.0;

  // Column x positions mirrored from MindMapLayoutEngine, offset right for space.
  static const _colX = [
    2040.0,
    2260.0,
    2680.0,
    2900.0,
    3100.0,
    3360.0,
    3860.0,
    4240.0,
    4580.0,
  ];

  /// Returns a column-based fallback so nodes are never piled at (0,0).
  Offset _fallbackPos(MindMapNodeData node) {
    final col = node.columnIndex.clamp(0, _colX.length - 1);
    // Start at y=300 so users have room to scroll upward.
    return Offset(_colX[col], 2000.0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0F14),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          // Notify parent of viewport size so it can fit all nodes.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.onViewportSize(viewportSize),
          );
          return Stack(
            children: [
              // ── Canvas (pan + pinch zoom) ────────────────────────────────
              // On native, use InteractiveViewer (works fine — trackpad pan
              // on macOS uses PointerPanZoom gestures that don't clash with
              // the inner scrollables the same way as on web).
              //
              // On web, use _WebCanvas: a Listener-based canvas that hit-
              // tests at the start of every pan / zoom gesture and skips
              // canvas manipulation when the pointer is over a card. This
              // is the only way to reliably isolate scroll/pan inside card
              // content from canvas pan on Flutter Web, because
              // InteractiveViewer's ScaleGestureRecognizer always wins the
              // gesture arena over any descendant scrollable when it is an
              // ancestor in the widget tree.
              Builder(builder: (context) {
                  final canvasChild = SizedBox(
                      width: _canvasW,
                      height: _canvasH,
                      child: BlocBuilder<MindMapCubit, MindMapState>(
                    builder: (context, mmState) {
                      final defaultSizeMap = {
                        for (final n in widget.nodes) n.id: n.defaultSize,
                      };
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Dot-grid background — RepaintBoundary so dots
                          // don't repaint when nodes move.
                          const Positioned.fill(
                            child: RepaintBoundary(child: _DotGrid()),
                          ),

                          // SVG connector layer (below nodes).
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: MindMapConnectorLayer(
                                connections: widget.conns.where((c) {
                                  if (mmState.hidden.contains(c.fromId))
                                    return false;
                                  if (mmState.hidden.contains(c.toId))
                                    return false;
                                  final fromTag = widget.nodes
                                      .where((n) => n.id == c.fromId)
                                      .firstOrNull
                                      ?.typeTag;
                                  final toTag = widget.nodes
                                      .where((n) => n.id == c.toId)
                                      .firstOrNull
                                      ?.typeTag;
                                  if (fromTag != null &&
                                      mmState.hiddenTypes.contains(fromTag))
                                    return false;
                                  if (toTag != null &&
                                      mmState.hiddenTypes.contains(toTag))
                                    return false;
                                  return true;
                                }).toList(),
                                positions: mmState.positions,
                                sizes: mmState.sizes,
                                defaultSizes: defaultSizeMap,
                                dashAnimation: widget.dashAnimation,
                              ),
                            ), // RepaintBoundary
                          ),

                           // Node cards (skip hidden and hidden-type).
                           for (final node in widget.nodes)
                             if (!mmState.hidden.contains(node.id) &&
                                 !mmState.hiddenTypes.contains(node.typeTag))
                               MindMapNode(
                                 key: ValueKey(node.id),
                                 id: node.id,
                                 defaultSize: node.defaultSize,
                                 minResizeSize: NodeRegistry.minResizeSize(node),
                                 fallbackPosition: _fallbackPos(node),
                                 onClose: () => context
                                     .read<MindMapCubit>()
                                     .hideNode(node.id),
                                 child: NodeRegistry.build(node),
                               ),
                        ],
                      );
                    },
                  ),
                );
                  if (kIsWeb) {
                    return _WebCanvas(
                      transformCtrl: widget.transformCtrl,
                      child: canvasChild,
                    );
                  }
                  return InteractiveViewer(
                    transformationController: widget.transformCtrl,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.1,
                    maxScale: 3.0,
                    panEnabled: !_nodeDragging,
                    scaleEnabled: true,
                    constrained: false,
                    child: canvasChild,
                  );
                },
              ),

              // ── Toolbar overlay ───────────────────────────────────────────
              Positioned(
                top: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _CanvasToolbar(
                      transformCtrl: widget.transformCtrl,
                      onResetView: widget.onResetView,
                    ),
                    const SizedBox(height: 8),
                    // ── Mini-map ───────────────────────────────────────────
                    BlocBuilder<MindMapCubit, MindMapState>(
                      buildWhen: (prev, next) =>
                          prev.positions != next.positions ||
                          prev.sizes != next.sizes ||
                          prev.hidden != next.hidden ||
                          prev.hiddenTypes != next.hiddenTypes,
                      builder: (ctx, mm) => _MiniMap(
                        nodes: widget.nodes,
                        positions: mm.positions,
                        sizes: mm.sizes,
                        hidden: mm.hidden,
                        hiddenTypes: mm.hiddenTypes,
                        transformCtrl: widget.transformCtrl,
                        viewportSize: viewportSize,
                        onPanTo: widget.onPanToOffset,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Group sidebar (left) ──────────────────────────────────────
              Positioned(
                top: 8,
                left: 8,
                bottom: 8,
                child: _GroupSidebar(
                  onFocusNode: (nodeId) {
                    final mm = context.read<MindMapCubit>().state;
                    final pos = mm.positions[nodeId];
                    if (pos == null) return;
                    // Reveal the node if it's hidden.
                    if (mm.hidden.contains(nodeId)) {
                      context.read<MindMapCubit>().showNode(nodeId);
                    }
                    widget.onPanToOffset(pos);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
// ── Dot-grid background ────────────────────────────────────────────────────

class _DotGrid extends StatefulWidget {
  const _DotGrid();
  @override
  State<_DotGrid> createState() => _DotGridState();
}

class _DotGridState extends State<_DotGrid> {
  ui.Image? _tile;

  @override
  void initState() {
    super.initState();
    _buildTile();
  }

  Future<void> _buildTile() async {
    const spacing = 28.0;
    const tileSize = spacing;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(tileSize / 2, tileSize / 2),
      0.9,
      Paint()..color = const Color(0x8C3A4560),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(tileSize.toInt(), tileSize.toInt());
    if (mounted) setState(() => _tile = image);
  }

  @override
  Widget build(BuildContext context) {
    final tile = _tile;
    if (tile == null) return const SizedBox.expand();
    return CustomPaint(painter: _TiledDotPainter(tile));
  }
}

class _TiledDotPainter extends CustomPainter {
  const _TiledDotPainter(this.tile);
  final ui.Image tile;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = ui.ImageShader(
      tile,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_TiledDotPainter old) => old.tile != tile;
}

// ── Toolbar ────────────────────────────────────────────────────────────────

class _CanvasToolbar extends StatelessWidget {
  const _CanvasToolbar({
    required this.transformCtrl,
    required this.onResetView,
  });
  final TransformationController transformCtrl;
  final VoidCallback onResetView;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ToolBtn(
          icon: Icons.remove,
          tooltip: 'Zoom out',
          onTap: () => _zoom(context, 0.8),
        ),
        const SizedBox(width: 1),
        _ToolBtn(
          icon: Icons.filter_center_focus,
          tooltip: 'Fit / reset',
          onTap: onResetView,
        ),
        const SizedBox(width: 1),
        _ToolBtn(
          icon: Icons.add,
          tooltip: 'Zoom in',
          onTap: () => _zoom(context, 1.25),
        ),
        const SizedBox(width: 8),
        _ToolBtn(
          icon: Icons.refresh,
          tooltip: 'Reset layout',
          onTap: () => context.read<MindMapCubit>().resetLayout(),
        ),
        const SizedBox(width: 1),
        BlocBuilder<MindMapCubit, MindMapState>(
          buildWhen: (p, n) => p.hidden.length != n.hidden.length,
          builder: (context, state) {
            if (state.hidden.isEmpty) return const SizedBox.shrink();
            return Row(
              children: [
                _ToolBtn(
                  icon: Icons.visibility,
                  tooltip: 'Show all (${state.hidden.length} hidden)',
                  onTap: () => context.read<MindMapCubit>().showAllNodes(),
                ),
                const SizedBox(width: 1),
              ],
            );
          },
        ),
        const SizedBox(width: 1),
        _ViewsButton(),
        const SizedBox(width: 1),
        const CollaborationButton(),
        const SizedBox(width: 1),
      ],
    );
  }

  void _zoom(BuildContext context, double factor) {
    final m = transformCtrl.value.clone();
    m.scaleByDouble(factor, factor, 1.0, 1.0);
    transformCtrl.value = m;
  }
}

// ── Views popover button ───────────────────────────────────────────────────

class _ViewsButton extends StatelessWidget {
  const _ViewsButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MindMapCubit, MindMapState>(
      buildWhen: (p, n) =>
          p.savedViews.length != n.savedViews.length ||
          p.activeViewName != n.activeViewName,
      builder: (context, state) {
        final hasViews = state.savedViews.isNotEmpty;
        return Tooltip(
          message: 'Views',
          child: GestureDetector(
            onTap: () => _showViewsMenu(context, state),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: hasViews
                    ? const Color(0xFF16192A)
                    : const Color(0xFF12151C),
                border: Border.all(
                  color: hasViews
                      ? const Color(0xFF7C6BFF)
                      : const Color(0xFF2A3040),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bookmarks_outlined,
                    size: 13,
                    color: hasViews
                        ? const Color(0xFF7C6BFF)
                        : const Color(0xFF6B7898),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    state.activeViewName ?? 'Views',
                    style: TextStyle(
                      fontSize: 11,
                      color: hasViews
                          ? const Color(0xFF9D8FFF)
                          : const Color(0xFF6B7898),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showViewsMenu(BuildContext context, MindMapState state) {
    final cubit = context.read<MindMapCubit>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => BlocProvider.value(
        value: cubit,
        child: _ViewsSheet(initialState: state),
      ),
    );
  }
}

class _ViewsSheet extends StatefulWidget {
  const _ViewsSheet({required this.initialState});
  final MindMapState initialState;

  @override
  State<_ViewsSheet> createState() => _ViewsSheetState();
}

class _ViewsSheetState extends State<_ViewsSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: 320,
        margin: const EdgeInsets.only(bottom: 60),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1218),
          border: Border.all(color: const Color(0xFF2A3040)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0xA0000000), blurRadius: 24),
          ],
        ),
        child: BlocBuilder<MindMapCubit, MindMapState>(
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bookmarks_outlined,
                        size: 14,
                        color: Color(0xFF7C6BFF),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Saved Views',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE8E8FF),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Color(0xFF6B7898),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF1E2330)),
                // Save current layout row.
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFE8E8FF),
                          ),
                          decoration: InputDecoration(
                            hintText: state.activeViewName ?? 'View name…',
                            hintStyle: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A5680),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: Color(0xFF2A3040),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: Color(0xFF7C6BFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          final name = _ctrl.text.trim().isEmpty
                              ? (state.activeViewName ??
                                    'View ${state.savedViews.length + 1}')
                              : _ctrl.text.trim();
                          context.read<MindMapCubit>().saveView(name);
                          _ctrl.clear();
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C6BFF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.savedViews.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 6, 14, 14),
                    child: Text(
                      'No saved views yet',
                      style: TextStyle(fontSize: 11, color: Color(0xFF4A5680)),
                    ),
                  )
                else ...[
                  const Divider(height: 1, color: Color(0xFF1E2330)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final entry in state.savedViews.entries)
                          _ViewRow(
                            snapshot: entry.value,
                            isActive: state.activeViewName == entry.key,
                            onLoad: () {
                              context.read<MindMapCubit>().loadView(entry.key);
                              Navigator.pop(context);
                            },
                            onDelete: () => context
                                .read<MindMapCubit>()
                                .deleteView(entry.key),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({
    required this.snapshot,
    required this.isActive,
    required this.onLoad,
    required this.onDelete,
  });
  final MindMapViewSnapshot snapshot;
  final bool isActive;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onLoad,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.bookmark : Icons.bookmark_border,
              size: 13,
              color: isActive
                  ? const Color(0xFF7C6BFF)
                  : const Color(0xFF4A5680),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                snapshot.name,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? const Color(0xFFE8E8FF)
                      : const Color(0xFF9BAACB),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              '${snapshot.positions.length} nodes',
              style: const TextStyle(fontSize: 10, color: Color(0xFF4A5680)),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: const Icon(
                Icons.delete_outline,
                size: 13,
                color: Color(0xFF4A5680),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF12151C),
            border: Border.all(color: const Color(0xFF2A3040)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: const Color(0xFF6B7898)),
        ),
      ),
    );
  }
}

// ── Group sidebar ──────────────────────────────────────────────────────────

// ── Workspace-tree sidebar ─────────────────────────────────────────────────

class _GroupSidebar extends StatefulWidget {
  const _GroupSidebar({this.onFocusNode});

  /// Called when the user clicks a node row — pans the canvas to that node.
  final void Function(String nodeId)? onFocusNode;

  @override
  State<_GroupSidebar> createState() => _GroupSidebarState();
}

class _GroupSidebarState extends State<_GroupSidebar> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MindMapCubit, MindMapState>(
      builder: (context, mm) {
        final cubit = context.read<MindMapCubit>();
        return MindMapShowHideSidebar(
          data: buildShowHideSidebarDataFromMindMapState(mm),
          onToggleHide: (nodeId) => mm.hidden.contains(nodeId)
              ? cubit.showNode(nodeId)
              : cubit.hideNode(nodeId),
          onFocusNode: widget.onFocusNode,
          onShowAll: cubit.showAllNodes,
          onCreateWorkspace: () => _createWorkspace(context),
          onRemoveFolder: (workspaceId, folderPath) =>
              context.read<WorkspaceCubit>().removePathFromWorkspace(workspaceId, folderPath),
          hiddenTypes: mm.hiddenTypes,
          onToggleType: cubit.toggleType,
          onHideDescendants: cubit.hideNodes,
          onShowDescendants: cubit.showNodes,
        );
      },
    );
  }
}

// ── Workspace header row ───────────────────────────────────────────────────

class _WsRow extends StatelessWidget {
  const _WsRow({
    required this.ws,
    required this.expanded,
    required this.hidden,
    required this.onToggleExpand,
    required this.onToggleHide,
  });
  final WorkspaceNodeData ws;
  final bool expanded;
  final bool hidden;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleHide;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggleExpand,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            GestureDetector(
              onTap: onToggleHide,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  hidden ? Icons.visibility_off : Icons.visibility,
                  size: 13,
                  color: hidden
                      ? const Color(0xFF4A5680)
                      : const Color(0xFF7C6BFF),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.folder_copy_outlined,
              size: 13,
              color: hidden ? const Color(0xFF4A5680) : const Color(0xFF7C6BFF),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ws.workspace.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: hidden
                      ? const Color(0xFF4A5680)
                      : const Color(0xFFE8E8FF),
                ),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 13,
              color: const Color(0xFF6B7898),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Child node row (with depth indent) ────────────────────────────────────

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.hidden,
    required this.onToggle,
    this.hasChildren = false,
    this.expanded = false,
    this.onToggleExpand,
    this.onFocus,
  });
  final MindMapNodeData node;
  final int depth;
  final bool hidden;
  final VoidCallback onToggle;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggleExpand;

  /// Called when the row label is tapped — pans the canvas to this node.
  final VoidCallback? onFocus;

  ({String label, IconData icon, Color color}) get _meta => switch (node) {
    AgentNodeData d => (
      label: d.session.displayName,
      icon: Icons.terminal,
      color: d.isRunning ? const Color(0xFF34D399) : const Color(0xFF6B7898),
    ),
    RepoNodeData d => (
      label: d.repoName,
      icon: Icons.source,
      color: const Color(0xFF9AA3BF),
    ),
    BranchNodeData d => (
      label: d.branch,
      icon: Icons.alt_route,
      color: const Color(0xFF60A5FA),
    ),
    FilesNodeData d => (
      label: p.basename(d.repoPath),
      icon: Icons.insert_drive_file_outlined,
      color: const Color(0xFFFFAA33),
    ),
    FileTreeNodeData d => (
      label: d.repoName ?? 'Tree',
      icon: Icons.account_tree_outlined,
      color: const Color(0xFF34D399),
    ),
    DiffNodeData d => (
      label: d.repoName ?? 'Diff',
      icon: Icons.compare_arrows_rounded,
      color: const Color(0xFF7C6BFF),
    ),
    EditorNodeData d => (
      label: p.basename(d.filePath),
      icon: Icons.code,
      color: const Color(0xFFFFCC44),
    ),
    RunNodeData d => (
      label: d.session.config.name,
      icon: Icons.play_circle_outline,
      color: d.session.status == RunStatus.running
          ? const Color(0xFFFF6B6B)
          : const Color(0xFF6B7898),
    ),
    SessionNodeData d => (
      label: d.session.displayName,
      icon: Icons.terminal,
      color: const Color(0xFF6B7898),
    ),
    MindMapPluginNodeData _ => (
      label: node.id,
      icon: Icons.extension_outlined,
      color: const Color(0xFF9AA3BF),
    ),
    WorkspaceNodeData _ => (
      label: node.id,
      icon: Icons.folder_outlined,
      color: const Color(0xFF7C6BFF),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final m = _meta;
    final indent = 10.0 + depth * 14.0;
    return InkWell(
      // Row tap: expand/collapse if it has children; otherwise focus the node.
      onTap: hasChildren ? onToggleExpand : onFocus,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 3, 8, 3),
        child: Row(
          children: [
            // Vertical tree line hint
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.only(right: 5),
              color: const Color(0xFF2A3040),
            ),
            // Eye icon — always toggles hide/show (independent of row tap).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  hidden ? Icons.visibility_off : Icons.visibility,
                  size: 11,
                  color: hidden
                      ? const Color(0xFF4A5680)
                      : const Color(0x997C6BFF),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              m.icon,
              size: 11,
              color: hidden ? const Color(0xFF3D475E) : m.color,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                m.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: hidden
                      ? const Color(0xFF4A5680)
                      : const Color(0xFFB0B8D0),
                ),
              ),
            ),
            if (hasChildren) ...[
              const SizedBox(width: 2),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 11,
                color: const Color(0xFF6B7898),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sidebar resize handle ──────────────────────────────────────────────────

class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => widget.onDrag(d.delta.dx),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: _hovered ? 3 : 1,
            height: double.infinity,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFF7C6BFF)
                  : const Color(0x40FFFFFF),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar collapsed toggle ───────────────────────────────────────────────

class _SidebarToggle extends StatelessWidget {
  const _SidebarToggle({required this.collapsed, required this.onTap});
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Show sidebar',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xEE0F1218),
            border: Border.all(color: const Color(0xFF1E2330)),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: const Icon(
            Icons.chevron_right,
            size: 16,
            color: Color(0xFF7C6BFF),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar actions ────────────────────────────────────────────────────────

Future<void> _createWorkspace(BuildContext context) async {
  final controller = TextEditingController();
  final String? name;
  try {
    name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12151C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF2A3040)),
        ),
        title: const Text(
          'New Workspace',
          style: TextStyle(color: Color(0xFFE8E8FF), fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFE8E8FF)),
          decoration: const InputDecoration(
            hintText: 'Workspace name',
            hintStyle: TextStyle(color: Color(0xFF6B7898)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7898)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Pick folder →',
              style: TextStyle(color: Color(0xFF7C6BFF)),
            ),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
  if (name == null || name.isEmpty || !context.mounted) return;
  final folder = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Pick a folder for "$name"',
  );
  if (folder == null || !context.mounted) return;
  await maybePromptGitInit(context, folder);
  if (!context.mounted) return;
  await context.read<WorkspaceCubit>().addWorkspace(folder, customName: name);
}

class _SidebarAction extends StatefulWidget {
  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SidebarAction> createState() => _SidebarActionState();
}

class _SidebarActionState extends State<_SidebarAction> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF2A1E66) : const Color(0xFF1A1E2A),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF7C6BFF)
                  : const Color(0xFF2A3040),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color: _hovered
                    ? const Color(0xFFC084FC)
                    : const Color(0xFF9AA3BF),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _hovered
                      ? const Color(0xFFE8E8FF)
                      : const Color(0xFF9AA3BF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mini-map ───────────────────────────────────────────────────────────────

class _MiniMap extends StatelessWidget {
  const _MiniMap({
    required this.nodes,
    required this.positions,
    required this.sizes,
    required this.hidden,
    required this.hiddenTypes,
    required this.transformCtrl,
    required this.viewportSize,
    required this.onPanTo,
  });

  final List<MindMapNodeData> nodes;
  final Map<String, Offset> positions;
  final Map<String, Size> sizes;
  final Set<String> hidden;
  final Set<String> hiddenTypes;
  final TransformationController transformCtrl;
  final Size viewportSize;
  final void Function(Offset canvasCenter) onPanTo;

  static const double _mapW = 210.0;
  static const double _mapH = 130.0;
  static const double _padding = 240.0;

  bool _isVisible(MindMapNodeData n) =>
      !hidden.contains(n.id) && !hiddenTypes.contains(n.typeTag);

  Rect _canvasBounds() {
    final visiblePositions = {
      for (final n in nodes)
        if (_isVisible(n) && positions.containsKey(n.id))
          n.id: positions[n.id]!,
    };
    if (visiblePositions.isEmpty) {
      return const Rect.fromLTWH(1800.0, 1800.0, 3500.0, 2000.0);
    }
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final e in visiblePositions.entries) {
      final pos = e.value;
      final sz = sizes[e.key] ?? const Size(200, 150);
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx + sz.width > maxX) maxX = pos.dx + sz.width;
      if (pos.dy + sz.height > maxY) maxY = pos.dy + sz.height;
    }
    return Rect.fromLTRB(
      minX - _padding,
      minY - _padding,
      maxX + _padding,
      maxY + _padding,
    );
  }

  void _handleGesture(Offset local, Rect bounds) {
    final cx = bounds.left + local.dx / _mapW * bounds.width;
    final cy = bounds.top + local.dy / _mapH * bounds.height;
    onPanTo(Offset(cx, cy));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transformCtrl,
      builder: (ctx, _) {
        final bounds = _canvasBounds();
        final vpTL = transformCtrl.toScene(Offset.zero);
        final vpBR = transformCtrl.toScene(
          Offset(viewportSize.width, viewportSize.height),
        );
        final viewportRect = Rect.fromLTRB(vpTL.dx, vpTL.dy, vpBR.dx, vpBR.dy);

        return GestureDetector(
          onTapDown: (d) => _handleGesture(d.localPosition, bounds),
          onPanUpdate: (d) => _handleGesture(d.localPosition, bounds),
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
                painter: _MiniMapPainter(
                  nodes: nodes.where(_isVisible).toList(),
                  positions: positions,
                  sizes: sizes,
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

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter({
    required this.nodes,
    required this.positions,
    required this.sizes,
    required this.bounds,
    required this.viewportRect,
  });

  final List<MindMapNodeData> nodes;
  final Map<String, Offset> positions;
  final Map<String, Size> sizes;
  final Rect bounds;
  final Rect viewportRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.isEmpty) return;
    final scaleX = size.width / bounds.width;
    final scaleY = size.height / bounds.height;

    // ── Node rectangles ────────────────────────────────────────────────────
    for (final node in nodes) {
      final pos = positions[node.id];
      if (pos == null) continue;
      final nodeSize = sizes[node.id] ?? node.defaultSize;
      final mx = (pos.dx - bounds.left) * scaleX;
      final my = (pos.dy - bounds.top) * scaleY;
      final mw = math.max(3.0, nodeSize.width * scaleX);
      final mh = math.max(2.0, nodeSize.height * scaleY);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(mx, my, mw, mh),
          const Radius.circular(1.5),
        ),
        Paint()..color = _colorForType(node.typeTag),
      );
    }

    // ── Viewport rectangle ─────────────────────────────────────────────────
    final vx = (viewportRect.left - bounds.left) * scaleX;
    final vy = (viewportRect.top - bounds.top) * scaleY;
    final vw = math.max(8.0, viewportRect.width * scaleX);
    final vh = math.max(8.0, viewportRect.height * scaleY);

    final vpRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(vx, vy, vw, vh),
      const Radius.circular(3),
    );
    canvas.drawRRect(vpRRect, Paint()..color = const Color(0x2060A5FA));
    canvas.drawRRect(
      vpRRect,
      Paint()
        ..color = const Color(0xCC60A5FA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  static Color _colorForType(String typeTag) => switch (typeTag) {
    'ws' => const Color(0xCC7C3AED),
    'agent' => const Color(0xCC34D399),
    'branch' => const Color(0xCC60A5FA),
    'tree' => const Color(0xCC10B981),
    'diff' => const Color(0xCC7C6BFF),
    'files' => const Color(0xCCF59E0B),
    'run' => const Color(0xCCF87171),
    'editor' => const Color(0xCCE879F9),
    'session' => const Color(0xCC93C5FD),
    'repo' => const Color(0xCC94A3B8),
    _ => const Color(0xCC64748B),
  };

  @override
  bool shouldRepaint(_MiniMapPainter old) =>
      old.viewportRect != viewportRect ||
      old.positions != positions ||
      old.nodes.length != nodes.length ||
      old.bounds != bounds;
}

// ────────────────────────────────────────────────────────────────────────────
// _WebCanvas — web-only replacement for InteractiveViewer.
// ────────────────────────────────────────────────────────────────────────────
//
// Why: on Flutter Web, InteractiveViewer's ScaleGestureRecognizer wins the
// gesture arena over any descendant Scrollable (terminal, editor, file tree)
// whenever it is an ancestor in the widget tree. Worse, its Listener-based
// PointerSignal handling also clashes with inner scrollables on trackpad.
// The net effect: every two-finger scroll over a card pans the whole canvas.
//
// Fix: replace InteractiveViewer with a Listener + manual transform. Before
// starting any canvas pan/zoom, hit-test the pointer position and, if any
// RenderScrollableCardMarker is in the hit path, skip — the card's inner
// content handles the gesture as usual.
class _WebCanvas extends StatefulWidget {
  const _WebCanvas({required this.transformCtrl, required this.child});
  final TransformationController transformCtrl;
  final Widget child;

  @override
  State<_WebCanvas> createState() => _WebCanvasState();
}

class _WebCanvasState extends State<_WebCanvas> {
  bool _panning = false;

  bool _pointerOverCard(Offset globalPos) {
    final result = HitTestResult();
    final view = View.of(context);
    WidgetsBinding.instance.hitTestInView(result, globalPos, view.viewId);
    for (final entry in result.path) {
      if (entry.target is RenderScrollableCardMarker) return true;
    }
    return false;
  }

  void _applyTranslation(double dx, double dy) {
    final m = widget.transformCtrl.value.clone();
    final translated = Matrix4.identity()..translate(dx, dy);
    widget.transformCtrl.value = translated..multiply(m);
  }

  void _applyZoomAroundFocal(Offset focal, double factor) {
    final m = widget.transformCtrl.value.clone();
    final around = Matrix4.identity()
      ..translate(focal.dx, focal.dy)
      ..scale(factor, factor)
      ..translate(-focal.dx, -focal.dy);
    widget.transformCtrl.value = around..multiply(m);
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _panning = !_pointerOverCard(e.position);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (!_panning) return;
    if (e.panDelta != Offset.zero) {
      _applyTranslation(e.panDelta.dx, e.panDelta.dy);
    }
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent e) {
    _panning = false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Skip if pointer is currently over a card — inner scrollable handles it
    // through its own PointerSignalResolver registration.
    if (_pointerOverCard(event.position)) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final ev = e as PointerScrollEvent;
      // Trackpad two-finger scroll delivers signed scrollDelta. Translate
      // the canvas so that scrolling "down" visually moves the canvas up
      // (i.e. we see content further down). Matches native scroll feel.
      _applyTranslation(-ev.scrollDelta.dx, -ev.scrollDelta.dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerPanZoomStart: _onPanZoomStart,
      onPointerPanZoomUpdate: _onPanZoomUpdate,
      onPointerPanZoomEnd: _onPanZoomEnd,
      onPointerSignal: _onPointerSignal,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: widget.transformCtrl,
          builder: (_, child) => Transform(
            transform: widget.transformCtrl.value,
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
