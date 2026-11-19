import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Controller that allows programmatic panel toggling (used by hotkeys).
class HSplitViewController extends ChangeNotifier {
  bool _leftVisible = true;
  bool _rightVisible = true;

  bool get leftVisible => _leftVisible;
  bool get rightVisible => _rightVisible;

  void toggleLeft() {
    _leftVisible = !_leftVisible;
    notifyListeners();
  }

  void toggleRight() {
    _rightVisible = !_rightVisible;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// A simple horizontal split view with a draggable divider.
///
/// Pass `initialRightWidth: 0` to use it as a two-pane (left + center)
/// layout; the hidden side leaves no gap.
class HSplitView extends StatefulWidget {
  const HSplitView({
    super.key,
    required this.left,
    required this.center,
    required this.right,
    this.initialLeftWidth = 260,
    this.initialRightWidth = 360,
    this.minPaneWidth = 160,
    this.controller,
    this.onLeftWidthChanged,
    this.onRightWidthChanged,
  });

  final Widget left;
  final Widget center;
  final Widget right;
  final double initialLeftWidth;
  final double initialRightWidth;
  final double minPaneWidth;
  final HSplitViewController? controller;

  /// Called after the user drags the left divider; use to persist the width.
  final ValueChanged<double>? onLeftWidthChanged;

  /// Called after the user drags the right divider; use to persist the width.
  final ValueChanged<double>? onRightWidthChanged;

  @override
  State<HSplitView> createState() => _HSplitViewState();
}

class _HSplitViewState extends State<HSplitView> {
  late double _leftWidth;
  late double _rightWidth;
  // Saved widths to restore after un-hiding
  late double _savedLeftWidth;
  late double _savedRightWidth;

  @override
  void initState() {
    super.initState();
    _leftWidth = widget.initialLeftWidth;
    _rightWidth = widget.initialRightWidth;
    _savedLeftWidth = widget.initialLeftWidth;
    _savedRightWidth = widget.initialRightWidth;
    widget.controller?.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(HSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChange);
      widget.controller?.addListener(_onControllerChange);
    }
    // Controllable pattern: adopt externally changed initial widths (e.g.
    // after persisting a drag and rebuilding with the stored value).
    if (oldWidget.initialLeftWidth != widget.initialLeftWidth &&
        widget.initialLeftWidth != _leftWidth) {
      _leftWidth = widget.initialLeftWidth;
      _savedLeftWidth = widget.initialLeftWidth;
    }
    if (oldWidget.initialRightWidth != widget.initialRightWidth &&
        widget.initialRightWidth != _rightWidth) {
      _rightWidth = widget.initialRightWidth;
      _savedRightWidth = widget.initialRightWidth;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    setState(() {
      if (widget.controller!.leftVisible) {
        _leftWidth = _savedLeftWidth;
      } else {
        if (_leftWidth > 0) _savedLeftWidth = _leftWidth;
        _leftWidth = 0;
      }
      if (widget.controller!.rightVisible) {
        _rightWidth = _savedRightWidth;
      } else {
        if (_rightWidth > 0) _savedRightWidth = _rightWidth;
        _rightWidth = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const dividerWidth = 4.0;
        final effectiveLeft = _leftWidth.clamp(0.0, totalWidth);
        final effectiveRight = _rightWidth.clamp(0.0, totalWidth);
        final leftVisible = effectiveLeft > 0;
        final rightVisible = effectiveRight > 0;
        // Only rendered dividers consume space — a hidden pane must not
        // leave a gap (two-pane usage with initial*Width: 0).
        final renderedDividers =
            (leftVisible ? dividerWidth : 0.0) +
            (rightVisible ? dividerWidth : 0.0);
        // Never clamp the center up to minPaneWidth: with two wide panes
        // that would overflow the Row. minPaneWidth constrains dragging,
        // not layout.
        final centerWidth =
            (totalWidth -
                    effectiveLeft -
                    effectiveRight -
                    renderedDividers)
                .clamp(0.0, totalWidth);

        return Row(
          children: [
            if (leftVisible) ...[
              SizedBox(width: effectiveLeft, child: widget.left),
              _Divider(
                onDrag: (dx) => setState(() {
                  _leftWidth = (_leftWidth + dx).clamp(
                    widget.minPaneWidth,
                    totalWidth -
                        _rightWidth -
                        widget.minPaneWidth -
                        renderedDividers,
                  );
                  widget.onLeftWidthChanged?.call(_leftWidth);
                }),
              ),
            ],
            SizedBox(width: centerWidth, child: widget.center),
            if (rightVisible) ...[
              _Divider(
                onDrag: (dx) => setState(() {
                  _rightWidth = (_rightWidth - dx).clamp(
                    widget.minPaneWidth,
                    totalWidth -
                        _leftWidth -
                        widget.minPaneWidth -
                        renderedDividers,
                  );
                  widget.onRightWidthChanged?.call(_rightWidth);
                }),
              ),
              SizedBox(width: effectiveRight, child: widget.right),
            ],
          ],
        );
      },
    );
  }
}

class _Divider extends StatefulWidget {
  const _Divider({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 4,
          color: _hovering ? colors.primary.withAlpha(180) : colors.divider,
        ),
      ),
    );
  }
}
