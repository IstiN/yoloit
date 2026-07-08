import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Global signal that disables canvas pan while the pointer is inside a
/// scrollable card body (terminal, file tree, editor, diff). This way a
/// two-finger pan over the terminal scrolls the terminal's scrollback,
/// not the infinite canvas underneath.
class CanvasInteractionLock {
  CanvasInteractionLock._();
  static final instance = CanvasInteractionLock._();

  /// Number of active scrollable regions that currently own the pointer.
  /// A counter (not a bool) tolerates overlapping MouseRegions and fast
  /// enter/exit events during drags.
  final ValueNotifier<int> _count = ValueNotifier<int>(0);
  final ValueNotifier<int> _canvasGestureCount = ValueNotifier<int>(0);
  final ValueNotifier<int> _lockStateVersion = ValueNotifier<int>(0);
  Timer? _canvasSignalTimer;

  ValueListenable<int> get activeCount => _count;
  ValueListenable<int> get canvasGestureCount => _canvasGestureCount;
  ValueListenable<int> get lockStateVersion => _lockStateVersion;

  bool get isLocked => _count.value > 0 && !isCanvasGestureActive;
  bool get isCanvasGestureActive => _canvasGestureCount.value > 0;

  void _notifyLockStateChanged() {
    _lockStateVersion.value = _lockStateVersion.value + 1;
  }

  void enter() {
    if (isCanvasGestureActive) return;
    _count.value = _count.value + 1;
    _notifyLockStateChanged();
    if (kDebugMode) {
      debugPrint('[CanvasInteractionLock] enter activeCount=${_count.value}');
    }
  }

  void exit() {
    if (_count.value == 0) return;
    _count.value = _count.value - 1;
    _notifyLockStateChanged();
    if (kDebugMode) {
      debugPrint('[CanvasInteractionLock] exit activeCount=${_count.value}');
    }
  }

  void beginCanvasGesture() {
    _canvasSignalTimer?.cancel();
    _canvasGestureCount.value = _canvasGestureCount.value + 1;
    _notifyLockStateChanged();
    if (kDebugMode) {
      debugPrint(
        '[CanvasInteractionLock] canvas enter activeCount=${_canvasGestureCount.value}',
      );
    }
  }

  void endCanvasGesture() {
    _canvasSignalTimer?.cancel();
    if (_canvasGestureCount.value == 0) return;
    _canvasGestureCount.value = _canvasGestureCount.value - 1;
    _notifyLockStateChanged();
    if (kDebugMode) {
      debugPrint(
        '[CanvasInteractionLock] canvas exit activeCount=${_canvasGestureCount.value}',
      );
    }
  }

  /// Clears a transient canvas signal gesture (e.g. mouse wheel over a panel).
  void clearCanvasSignalGesture() {
    _canvasSignalTimer?.cancel();
    _canvasSignalTimer = null;
    if (_canvasGestureCount.value == 0) return;
    _canvasGestureCount.value = 0;
    _notifyLockStateChanged();
    if (kDebugMode) {
      debugPrint('[CanvasInteractionLock] canvas signal cleared');
    }
  }

  void markCanvasSignalGesture({
    Duration hold = const Duration(milliseconds: 180),
  }) {
    _canvasSignalTimer?.cancel();
    if (_canvasGestureCount.value == 0) {
      _canvasGestureCount.value = 1;
      _notifyLockStateChanged();
      if (kDebugMode) {
        debugPrint('[CanvasInteractionLock] canvas signal enter');
      }
    }
    _canvasSignalTimer = Timer(hold, () {
      _canvasGestureCount.value = 0;
      _notifyLockStateChanged();
      if (kDebugMode) {
        debugPrint('[CanvasInteractionLock] canvas signal exit');
      }
    });
  }

  @visibleForTesting
  void resetForTesting() {
    _canvasSignalTimer?.cancel();
    _canvasSignalTimer = null;
    _count.value = 0;
    _canvasGestureCount.value = 0;
    _notifyLockStateChanged();
  }
}

/// A [ScrollBehavior] that wraps every scrollable inside a board panel with
/// [ScrollableCardRegion]. This makes the canvas lock its pan/zoom whenever
/// the pointer is over a panel that has internal scrollable content, so the
/// panel's own scroll consumes the wheel/trackpad event instead of also
/// scrolling the infinite board.
class PanelScrollLockBehavior extends ScrollBehavior {
  const PanelScrollLockBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return ScrollableCardRegion(
      child: super.buildOverscrollIndicator(context, child, details),
    );
  }
}

/// Wraps a scrollable widget so that while the pointer is over it, the
/// mindmap canvas pan is disabled. The wrapped widget can freely consume
/// wheel / two-finger scroll / drag gestures.
class ScrollableCardRegion extends StatefulWidget {
  const ScrollableCardRegion({super.key, required this.child});
  final Widget child;

  @override
  State<ScrollableCardRegion> createState() => _ScrollableCardRegionState();
}

class _ScrollableCardRegionState extends State<ScrollableCardRegion> {
  bool _entered = false;
  Timer? _exitTimer;
  Timer? _scrollTimer;
  bool _mousePhysicallyExited = false;
  Offset? _lastGlobalPosition;

  @override
  void dispose() {
    _exitTimer?.cancel();
    _scrollTimer?.cancel();
    if (_entered) {
      CanvasInteractionLock.instance.exit();
      _entered = false;
    }
    super.dispose();
  }

  void _enter(PointerEnterEvent event) {
    _lastGlobalPosition = event.position;
    _exitTimer?.cancel();
    _mousePhysicallyExited = false;
    if (_entered) return;
    _entered = true;
    CanvasInteractionLock.instance.enter();
  }

  void _exit(PointerExitEvent event) {
    _lastGlobalPosition = event.position;
    _mousePhysicallyExited = true;
    _exitTimer?.cancel();
    // Short timeout: trackpad users may keep fingers stationary while
    // scrolling, so hover exit can fire even though they’re still “over”
    // the card. 100 ms is enough to absorb a brief exit without making
    // the canvas feel frozen when the user moves the cursor away.
    _exitTimer = Timer(const Duration(milliseconds: 100), () {
      _performExit(event.position);
    });
  }

  void _performExit(Offset globalPos) {
    if (!_entered) return;

    // Check if the pointer is still physically over the card; ignore false exit.
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final localPos = renderBox.globalToLocal(globalPos);
      final bounds = Rect.fromLTWH(
        0,
        0,
        renderBox.size.width,
        renderBox.size.height,
      );
      if (bounds.contains(localPos)) {
        return;
      }
    }

    if (_scrollTimer?.isActive == true) {
      // Ignore exit event during active scroll!
      return;
    }

    _entered = false;
    CanvasInteractionLock.instance.exit();
  }

  void _ensureEntered({Offset? globalPosition, bool force = false}) {
    _lastGlobalPosition = globalPosition ?? _lastGlobalPosition;
    if (!force && CanvasInteractionLock.instance.isCanvasGestureActive) return;
    _exitTimer?.cancel();
    _mousePhysicallyExited = false;
    if (_entered) return;
    _entered = true;
    CanvasInteractionLock.instance.enter();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollableCardMarker(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final vertical =
              event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs();
          final isMouseWheel = event.kind == PointerDeviceKind.mouse;
          if (vertical && isMouseWheel) {
            CanvasInteractionLock.instance.clearCanvasSignalGesture();
            _ensureEntered(globalPosition: event.position, force: true);
            GestureBinding.instance.pointerSignalResolver.register(
              event,
              (_) {
                // Physical mouse wheels must not fall through to
                // InteractiveViewer zoom when the pointer is over a panel.
              },
            );
          } else {
            _ensureEntered(globalPosition: event.position);
          }
          _exitTimer?.cancel(); // Cancel any pending exit during scroll!
          _scrollTimer?.cancel();
          _scrollTimer = Timer(const Duration(milliseconds: 100), () {
            if (_mousePhysicallyExited) {
              // Mouse physically exited during scrolling; finalize exit now.
              _performExit(event.position);
            }
          });
        }
      },
      onPointerDown: (event) {
        _ensureEntered(globalPosition: event.position);
        _exitTimer?.cancel(); // Cancel any pending exit on touch/click!
      },
      onPointerMove: (event) {
        _ensureEntered(globalPosition: event.position);
        _exitTimer?.cancel(); // Cancel any pending exit on movement!
      },
      onPointerHover: (event) {
        _ensureEntered(globalPosition: event.position);
        _exitTimer?.cancel(); // Cancel any pending exit on hover!
      },
      onPointerPanZoomStart: (event) {
        _ensureEntered(globalPosition: event.position);
        _exitTimer?.cancel();
      },
      onPointerPanZoomUpdate: (event) {
        _ensureEntered(globalPosition: event.position);
        _exitTimer?.cancel();
      },
      onPointerUp: (event) {
        _lastGlobalPosition = event.position;
        _exitTimer?.cancel();
        _scrollTimer?.cancel();
        _scrollTimer = Timer(const Duration(milliseconds: 100), () {
          _performExit(event.position);
        });
      },
      onPointerCancel: (event) {
        _exitTimer?.cancel();
        _scrollTimer?.cancel();
        if (!_entered) return;
        _entered = false;
        CanvasInteractionLock.instance.exit();
      },
      onPointerPanZoomEnd: (event) {
        _lastGlobalPosition = event.position;
        _exitTimer?.cancel();
        _scrollTimer?.cancel();
        _scrollTimer = Timer(const Duration(milliseconds: 100), () {
          _performExit(event.position);
        });
      },
      child: MouseRegion(onEnter: _enter, onExit: _exit, child: widget.child),
      ),
    );
  }
}

/// A leaf-ish marker inserted into the widget tree around each mindmap card.
///
/// The web canvas uses [WidgetsBinding.hitTestInView] at gesture start to
/// walk the hit path and look for a [RenderScrollableCardMarker]. If one is
/// present, the pointer is currently over a card and the canvas skips its
/// own pan/zoom handling so the card's inner scrollable can act.
///
/// This mechanism works for all pointer kinds (mouse, trackpad pan-zoom,
/// stylus) — unlike [MouseRegion], which only fires for mouse hover.
class ScrollableCardMarker extends SingleChildRenderObjectWidget {
  const ScrollableCardMarker({super.key, required Widget super.child});

  @override
  RenderScrollableCardMarker createRenderObject(BuildContext context) =>
      RenderScrollableCardMarker();
}

class RenderScrollableCardMarker extends RenderProxyBox {
  RenderScrollableCardMarker();
}

/// Prevents [showOnScreen] calls from inner widgets (e.g. autofocus on a
/// CodeField / TextField) from propagating to the [InteractiveViewer] canvas
/// and causing it to pan when an editor card switches tabs or opens.
///
/// Wrap each card's content area with this widget so that focus-driven
/// scroll requests are absorbed here and never reach the canvas transform.
class CanvasFocusScrollBlocker extends SingleChildRenderObjectWidget {
  const CanvasFocusScrollBlocker({super.key, required Widget super.child});

  @override
  RenderCanvasFocusScrollBlocker createRenderObject(BuildContext context) =>
      RenderCanvasFocusScrollBlocker();
}

class RenderCanvasFocusScrollBlocker extends RenderProxyBox {
  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    // Intentionally swallow — do NOT propagate to parent (InteractiveViewer).
    // This stops autofocus / focus-change events from panning the canvas.
  }
}
