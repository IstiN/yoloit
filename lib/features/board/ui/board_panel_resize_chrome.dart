import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_panel_selection_metrics.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

enum BoardPanelResizeHandle {
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

class BoardPanelResizeUpdate {
  const BoardPanelResizeUpdate({
    required this.handle,
    required this.delta,
    required this.globalPosition,
  });

  final BoardPanelResizeHandle handle;
  final Offset delta;
  final Offset globalPosition;
}

/// Top-level resize handles for the focused panel.
///
/// Rendered above all [BoardPanelCard]s (and the anchored YoLo assistant) so
/// overlapping panels cannot steal pointer events from the selection dots.
class BoardPanelResizeChrome extends StatelessWidget {
  const BoardPanelResizeChrome({
    super.key,
    required this.panel,
    required this.canvasOrigin,
    required this.capturingScreenshot,
    required this.onResize,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final BoardPanelInstance panel;
  final Offset canvasOrigin;
  final bool capturingScreenshot;
  final ValueChanged<BoardPanelResizeUpdate> onResize;
  final ValueChanged<DragStartDetails> onDragStart;
  final VoidCallback onDragEnd;

  void _handleResize(BoardPanelResizeHandle handle, DragUpdateDetails details) {
    onResize(
      BoardPanelResizeUpdate(
        handle: handle,
        delta: details.delta,
        globalPosition: details.globalPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (capturingScreenshot || panel.locked) {
      return const SizedBox.shrink();
    }

    final focusedPanelId = context.select<BoardCubit, String?>(
      (cubit) => cubit.state.activeBoard?.viewport.focusedPanelId,
    );
    if (panel.id != focusedPanelId) {
      return const SizedBox.shrink();
    }

    const inset = BoardPanelSelectionMetrics.handleInset;
    return Positioned(
      left: canvasOrigin.dx + panel.bounds.x - inset,
      top: canvasOrigin.dy + panel.bounds.y - inset,
      width: panel.bounds.width + inset * 2,
      height: panel.bounds.height + inset * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: BoardPanelResizeOverlay.handles(
          locked: panel.locked,
          onStart: onDragStart,
          onUpdate: _handleResize,
          onEnd: onDragEnd,
          colors: context.appColors,
        ),
      ),
    );
  }
}

class BoardPanelResizeOverlay {
  const BoardPanelResizeOverlay._();

  static List<Widget> handles({
    required bool locked,
    required ValueChanged<DragStartDetails> onStart,
    required void Function(BoardPanelResizeHandle, DragUpdateDetails) onUpdate,
    required VoidCallback onEnd,
    required AppColorScheme colors,
  }) {
    if (locked) return const [];
    return BoardPanelResizeHandle.values
        .map(
          (handle) => PanelResizeHandleWidget(
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

class PanelResizeHandleWidget extends StatefulWidget {
  const PanelResizeHandleWidget({
    super.key,
    required this.handle,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.colors,
  });

  final BoardPanelResizeHandle handle;
  final ValueChanged<DragStartDetails> onStart;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final VoidCallback onEnd;
  final AppColorScheme colors;

  @override
  State<PanelResizeHandleWidget> createState() =>
      _PanelResizeHandleWidgetState();
}

class _PanelResizeHandleWidgetState extends State<PanelResizeHandleWidget> {
  static const double _hitSize = 24;
  static const double _dotSize = 10;
  bool _holdingCanvasLock = false;

  @override
  void dispose() {
    _releaseCanvasLock();
    super.dispose();
  }

  void _acquireCanvasLock() {
    if (_holdingCanvasLock) return;
    _holdingCanvasLock = true;
    CanvasInteractionLock.instance.enter();
  }

  void _releaseCanvasLock() {
    if (!_holdingCanvasLock) return;
    _holdingCanvasLock = false;
    CanvasInteractionLock.instance.exit();
  }

  void _finishResize() {
    widget.onEnd();
    _releaseCanvasLock();
  }

  @override
  Widget build(BuildContext context) {
    final child = Listener(
      onPointerDown: (_) {
        if (kDebugMode) {
          debugPrint(
            '[BoardPanelResizeChrome] handle.pointerDown ${widget.handle}',
          );
        }
        _acquireCanvasLock();
      },
      onPointerUp: (_) => _releaseCanvasLock(),
      onPointerCancel: (_) => _releaseCanvasLock(),
      child: MouseRegion(
        cursor: widget.handle.cursor,
        child: Tooltip(
          message: widget.handle.tooltip,
          child: GestureDetector(
            key: ValueKey('panel-resize-handle-${widget.handle.name}'),
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.onStart,
            onPanUpdate: widget.onUpdate,
            onPanEnd: (_) => _finishResize(),
            onPanCancel: _finishResize,
            child: SizedBox(
              width: _hitSize,
              height: _hitSize,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.colors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.colors.primary, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: widget.colors.border.withValues(alpha: 0.16),
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
      ),
    );

    return switch (widget.handle) {
      BoardPanelResizeHandle.topLeft => Positioned(
        left: 0,
        top: 0,
        child: child,
      ),
      BoardPanelResizeHandle.top => Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: _hitSize,
        child: Center(child: child),
      ),
      BoardPanelResizeHandle.topRight => Positioned(
        right: 0,
        top: 0,
        child: child,
      ),
      BoardPanelResizeHandle.right => Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: _hitSize,
        child: Center(child: child),
      ),
      BoardPanelResizeHandle.bottomRight => Positioned(
        right: 0,
        bottom: 0,
        child: child,
      ),
      BoardPanelResizeHandle.bottom => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: _hitSize,
        child: Center(child: child),
      ),
      BoardPanelResizeHandle.bottomLeft => Positioned(
        left: 0,
        bottom: 0,
        child: child,
      ),
      BoardPanelResizeHandle.left => Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: _hitSize,
        child: Center(child: child),
      ),
    };
  }
}
