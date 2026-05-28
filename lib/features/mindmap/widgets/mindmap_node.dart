import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

/// A draggable, multi-directional resizable node on the mind-map canvas.
///
/// Drag: only from the grip-dot handle bar at the top.
/// Resize controls: appear on hover as a toggle button (top-right corner).
///   Click the button → show edge/corner resize handles.
///   Click again → hide them.
class MindMapNode extends StatefulWidget {
  const MindMapNode({
    super.key,
    required this.id,
    required this.defaultSize,
    required this.child,
    this.minResizeSize = const Size(140, 80),
    this.fallbackPosition = Offset.zero,
    this.resizable = true, // kept for API compat
    this.onClose,
  });

  final String id;
  final Size defaultSize;
  final Widget child;
  final Size minResizeSize;
  final Offset fallbackPosition;
  // ignore: unused_field
  final bool resizable;
  final VoidCallback? onClose;

  @override
  State<MindMapNode> createState() => _MindMapNodeState();
}

class _MindMapNodeState extends State<MindMapNode> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return BlocBuilder<MindMapCubit, MindMapState>(
      buildWhen:
          (prev, next) =>
              prev.positions[widget.id] != next.positions[widget.id] ||
              prev.sizes[widget.id] != next.sizes[widget.id],
      builder: (context, state) {
        final pos = state.positions[widget.id] ?? widget.fallbackPosition;
        final size = state.sizes[widget.id] ?? widget.defaultSize;
        final cubit = context.read<MindMapCubit>();
        final minSize = widget.minResizeSize;

        return Positioned(
          left: pos.dx,
          top: pos.dy,
          child: ScrollableCardMarker(
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: AnimatedScale(
                scale: _dragging ? 1.02 : 1.0,
                duration: const Duration(milliseconds: 100),
                // Stack with clipBehavior.none so handles can extend outside the card.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Main card ─────────────────────────────────────────
                    SizedBox(
                      width: size.width,
                      height: size.height,
                      child: Column(
                        children: [
                          // Drag handle strip.
                          GestureDetector(
                            onPanStart: (_) => setState(() => _dragging = true),
                            onPanUpdate:
                                (d) => cubit.moveNode(widget.id, d.delta),
                            onPanEnd: (_) => setState(() => _dragging = false),
                            child: _DragHandle(dragging: _dragging),
                          ),
                          // Card content. Wrapped in ScrollableCardRegion so
                          // the canvas pan is disabled while the pointer is
                          // over the card body — this way two-finger scroll
                          // inside a terminal/editor/file-tree scrolls the
                          // card, not the infinite canvas underneath.
                          // CanvasFocusScrollBlocker stops showOnScreen() from
                          // propagating to InteractiveViewer when inner widgets
                          // request focus (e.g. editor autofocus on tab switch).
                          Expanded(
                            child: CanvasFocusScrollBlocker(
                              child: ScrollableCardRegion(child: widget.child),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Resize handles — only show on direct-edge hover ──────

                    // Right edge strip (inset top/bottom so it doesn't span full height)
                    Positioned(
                      right: -6,
                      top: 32,
                      bottom: 18,
                      width: 12,
                      child: _ResizeEdge(
                        axis: Axis.vertical,
                        visible: false,
                        onDrag:
                            (d) => cubit.resizeNode(
                              widget.id,
                              Offset(d.delta.dx, 0),
                              minSize,
                            ),
                      ),
                    ),
                    // Left edge strip
                    Positioned(
                      left: -6,
                      top: 32,
                      bottom: 18,
                      width: 12,
                      child: _ResizeEdge(
                        axis: Axis.vertical,
                        visible: false,
                        onDrag:
                            (d) => cubit.resizeFromLeft(
                              widget.id,
                              d.delta.dx,
                              minSize,
                            ),
                      ),
                    ),
                    // Bottom edge strip
                    Positioned(
                      bottom: -6,
                      left: 12,
                      right: 12,
                      height: 12,
                      child: _ResizeEdge(
                        axis: Axis.horizontal,
                        visible: false,
                        onDrag:
                            (d) => cubit.resizeNode(
                              widget.id,
                              Offset(0, d.delta.dy),
                              minSize,
                            ),
                      ),
                    ),
                    // Bottom-right L-corner (inside card bounds — always visible, hit area 22×22)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _CornerResize(
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        onPanUpdate:
                            (d) =>
                                cubit.resizeNode(widget.id, d.delta, minSize),
                        painter: _LCornerPainter(
                          hovered: _hovered,
                          colors: colors,
                        ),
                      ),
                    ),
                    // Bottom-left L-corner
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: _CornerResize(
                        cursor: SystemMouseCursors.resizeUpRightDownLeft,
                        onPanUpdate: (d) {
                          cubit.resizeFromLeft(widget.id, d.delta.dx, minSize);
                          cubit.resizeNode(
                            widget.id,
                            Offset(0, d.delta.dy),
                            minSize,
                          );
                        },
                        painter: _LCornerPainter(
                          hovered: _hovered,
                          colors: colors,
                          flipX: true,
                        ),
                      ),
                    ),

                    // ── Close button (top-right, shown on hover) ─────────────
                    if (_hovered && widget.onClose != null)
                      Positioned(
                        top: 1,
                        right: 2,
                        child: _CloseButton(onTap: widget.onClose!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Drag handle ────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.dragging});
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: Container(
        height: 20,
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: dragging ? 0.19 : 0.08),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              6,
              (_) => Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(
                    alpha: dragging ? 0.53 : 0.27,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Edge resize strip — invisible hit area, subtle line on hover ──────────

class _ResizeEdge extends StatefulWidget {
  const _ResizeEdge({
    required this.axis,
    required this.visible,
    required this.onDrag,
  });
  final Axis axis;
  final bool visible;
  final ValueChanged<DragUpdateDetails> onDrag;

  @override
  State<_ResizeEdge> createState() => _ResizeEdgeState();
}

class _ResizeEdgeState extends State<_ResizeEdge> {
  bool _hovered = false;

  void _setHover(bool v) {
    if (_hovered == v) return;
    if (v) {
      CanvasInteractionLock.instance.enter();
    } else {
      CanvasInteractionLock.instance.exit();
    }
    setState(() => _hovered = v);
  }

  @override
  void dispose() {
    if (_hovered) CanvasInteractionLock.instance.exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isVertical = widget.axis == Axis.vertical;
    final showLine = _hovered || widget.visible;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: widget.onDrag,
      child: MouseRegion(
        cursor:
            isVertical
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: isVertical ? (_hovered ? 3 : 2) : null,
            height: isVertical ? null : (_hovered ? 3 : 2),
            decoration: BoxDecoration(
              color:
                  showLine
                      ? (_hovered
                          ? colors.primary
                          : colors.textPrimary.withValues(alpha: 0.23))
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// ── L-shape corner grip — always visible, inside card bounds ──────────────

class _LCornerPainter extends CustomPainter {
  _LCornerPainter({
    required this.hovered,
    required this.colors,
    this.flipX = false,
  });
  final bool hovered;
  final AppColorScheme colors;
  final bool flipX;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color =
              hovered ? colors.primary : colors.textMuted.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;

    // Draw 3 short diagonal "stair" lines in the corner.
    // Bottom-right by default, flipX mirrors horizontally for bottom-left.
    for (int i = 0; i < 3; i++) {
      final o = 4.0 + i * 4.0; // 4, 8, 12 px offsets from edges
      final xEnd = flipX ? o : size.width - o;
      final yStart = size.height - 2;
      final xStart = flipX ? 2.0 : size.width - 2;
      final yEnd = size.height - o;
      canvas.drawLine(Offset(xStart, yEnd), Offset(xEnd, yStart), paint);
    }
  }

  @override
  bool shouldRepaint(_LCornerPainter old) =>
      old.hovered != hovered || old.flipX != flipX || old.colors != colors;
}

// ── Close button ──────────────────────────────────────────────────────────

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color:
                _hovered
                    ? colors.accentRed
                    : colors.surfaceHighlight.withValues(alpha: 0.69),
            shape: BoxShape.circle,
            border: Border.all(
              color: _hovered ? colors.accentRed : colors.border,
              width: 1,
            ),
          ),
          child: Icon(
            Icons.close,
            size: 11,
            color: _hovered ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Corner resize handle — locks the canvas interaction while hovered so
/// the parent InteractiveViewer doesn't steal the drag gesture on web.
class _CornerResize extends StatefulWidget {
  const _CornerResize({
    required this.cursor,
    required this.onPanUpdate,
    required this.painter,
  });
  final MouseCursor cursor;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final CustomPainter painter;

  @override
  State<_CornerResize> createState() => _CornerResizeState();
}

class _CornerResizeState extends State<_CornerResize> {
  bool _hovered = false;

  void _setHover(bool v) {
    if (_hovered == v) return;
    if (v) {
      CanvasInteractionLock.instance.enter();
    } else {
      CanvasInteractionLock.instance.exit();
    }
    _hovered = v;
  }

  @override
  void dispose() {
    if (_hovered) CanvasInteractionLock.instance.exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: widget.onPanUpdate,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.withValues(alpha: 0),
          ),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CustomPaint(painter: widget.painter),
          ),
        ),
      ),
    );
  }
}
