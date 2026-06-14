import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Renders named group backgrounds and headers behind board panels.
///
/// When a group is collapsed, the panels themselves are resized and stacked by
/// [BoardCubit.toggleGroupCollapse], so the overlay only needs to draw the
/// background, header, and navigation controls.
class BoardGroupOverlay extends StatelessWidget {
  const BoardGroupOverlay({
    super.key,
    required this.board,
    required this.origin,
    required this.onToggleCollapse,
    required this.onMoveGroup,
    required this.onMoveGroupStart,
    required this.onMoveGroupEnd,
    required this.onRenameGroup,
    required this.onCycleFocus,
    required this.onResizeCollapsedGroup,
  });

  final BoardDocument board;
  final Offset origin;
  final ValueChanged<String> onToggleCollapse;
  final void Function(String groupId, DragUpdateDetails details) onMoveGroup;
  final ValueChanged<String> onMoveGroupStart;
  final ValueChanged<String> onMoveGroupEnd;
  final ValueChanged<String> onRenameGroup;
  final void Function(String groupId, int direction) onCycleFocus;
  final void Function(String groupId, BoardPanelBounds newBounds)
  onResizeCollapsedGroup;

  static const double _padding = 16;
  static const double _headerHeight = 28;
  static const double _borderRadius = 12;

  static Color _contrastColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final children = <Widget>[];

    for (final group in board.groups) {
      final bounds = _computeGroupBounds(group);
      if (bounds == null) continue;

      final backgroundColor =
          group.color != null
              ? Color(group.color!).withValues(alpha: 0.12)
              : colors.primary.withValues(alpha: 0.12);
      final borderColor =
          group.color != null
              ? Color(group.color!).withValues(alpha: 0.5)
              : colors.primary.withValues(alpha: 0.5);
      final iconColor = _contrastColor(borderColor);

      final left = bounds.left + origin.dx - _padding;
      final top = bounds.top + origin.dy - _padding - _headerHeight;
      final width = bounds.width + _padding * 2;
      final height = bounds.height + _padding * 2 + _headerHeight;

      children.add(
        Positioned(
          left: left,
          top: top,
          width: math.max(width, 120),
          height: math.max(height, _headerHeight + _padding * 2),
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(_borderRadius),
                border: Border.all(color: borderColor, width: 1.5),
              ),
            ),
          ),
        ),
      );

      children.add(
        Positioned(
          left: left,
          top: top,
          height: _headerHeight,
          child: Material(
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(_borderRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => onMoveGroupStart(group.id),
              onPanUpdate: (details) => onMoveGroup(group.id, details),
              onPanEnd: (_) => onMoveGroupEnd(group.id),
              child: Container(
                constraints: const BoxConstraints(minWidth: 120),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(_borderRadius),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeaderButton(
                      icon:
                          group.collapsed
                              ? Icons.keyboard_arrow_right
                              : Icons.keyboard_arrow_down,
                      tooltip: group.collapsed ? 'Expand' : 'Collapse',
                      onTap: () => onToggleCollapse(group.id),
                      color: iconColor,
                    ),
                    const SizedBox(width: 2),
                    _HeaderButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Rename',
                      onTap: () => onRenameGroup(group.id),
                      color: iconColor,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        group.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${group.panelIds.length})',
                      style: TextStyle(
                        color: iconColor.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                    if (group.collapsed && group.panelIds.length > 1) ...[
                      const SizedBox(width: 6),
                      _HeaderButton(
                        icon: Icons.arrow_left,
                        tooltip: 'Previous panel',
                        onTap: () => onCycleFocus(group.id, -1),
                        color: iconColor,
                      ),
                      _HeaderButton(
                        icon: Icons.arrow_right,
                        tooltip: 'Next panel',
                        onTap: () => onCycleFocus(group.id, 1),
                        color: iconColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      if (group.collapsed && group.collapsedBounds != null) {
        children.add(
          _CollapsedGroupResizeHandles(
            groupId: group.id,
            stackBounds: Rect.fromLTWH(
              group.collapsedBounds!.x,
              group.collapsedBounds!.y,
              group.collapsedBounds!.width,
              group.collapsedBounds!.height,
            ),
            origin: origin,
            onBoundsChanged: (rect) {
              onResizeCollapsedGroup(
                group.id,
                BoardPanelBounds(
                  x: rect.left,
                  y: rect.top,
                  width: rect.width,
                  height: rect.height,
                ),
              );
            },
          ),
        );
      }
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Rect? _computeGroupBounds(BoardPanelGroup group) {
    if (group.panelIds.isEmpty) return null;

    if (group.collapsed && group.collapsedBounds != null) {
      return Rect.fromLTWH(
        group.collapsedBounds!.x,
        group.collapsedBounds!.y,
        group.collapsedBounds!.width,
        group.collapsedBounds!.height,
      );
    }

    Rect? union;
    for (final panelId in group.panelIds) {
      BoardPanelInstance? panel;
      for (final candidate in board.panels) {
        if (candidate.id == panelId) {
          panel = candidate;
          break;
        }
      }
      if (panel == null || panel.hidden) continue;
      final rect = Rect.fromLTWH(
        panel.bounds.x,
        panel.bounds.y,
        panel.bounds.width,
        panel.bounds.height,
      );
      union = union?.expandToInclude(rect) ?? rect;
    }
    return union;
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 18,
          height: BoardGroupOverlay._headerHeight,
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

enum _ResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class _CollapsedGroupResizeHandles extends StatefulWidget {
  const _CollapsedGroupResizeHandles({
    required this.groupId,
    required this.stackBounds,
    required this.origin,
    required this.onBoundsChanged,
  });

  final String groupId;
  final Rect stackBounds;
  final Offset origin;
  final ValueChanged<Rect> onBoundsChanged;

  @override
  State<_CollapsedGroupResizeHandles> createState() =>
      _CollapsedGroupResizeHandlesState();
}

class _CollapsedGroupResizeHandlesState
    extends State<_CollapsedGroupResizeHandles> {
  static const double _padding = BoardGroupOverlay._padding;
  static const double _headerHeight = BoardGroupOverlay._headerHeight;
  static const double _handleSize = 10;
  static const double _minWidth = 80;
  static const double _minHeight = 60;

  Rect? _dragStartBounds;

  Rect get _backgroundRect {
    final left = widget.stackBounds.left + widget.origin.dx - _padding;
    final top = widget.stackBounds.top + widget.origin.dy - _padding - _headerHeight;
    final width = widget.stackBounds.width + _padding * 2;
    final height = widget.stackBounds.height + _padding * 2 + _headerHeight;
    return Rect.fromLTWH(left, top, width, height);
  }

  @override
  Widget build(BuildContext context) {
    final bg = _backgroundRect;
    final colors = context.appColors;
    final handleColor = colors.statusActive;

    Widget handle(_ResizeHandle handle, double left, double top) {
      return Positioned(
        left: left - _handleSize / 2,
        top: top - _handleSize / 2,
        width: _handleSize,
        height: _handleSize,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => _dragStartBounds = widget.stackBounds,
          onPanUpdate: (details) => _onHandleDrag(handle, details.delta),
          onPanEnd: (_) => _dragStartBounds = null,
          onPanCancel: () => _dragStartBounds = null,
          child: MouseRegion(
            cursor: _cursorFor(handle),
            child: Container(
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(_handleSize / 2),
                border: Border.all(color: colors.background, width: 1.5),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: bg.left,
      top: bg.top,
      width: bg.width,
      height: bg.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // corners
          handle(_ResizeHandle.topLeft, 0, 0),
          handle(_ResizeHandle.topRight, bg.width, 0),
          handle(_ResizeHandle.bottomLeft, 0, bg.height),
          handle(_ResizeHandle.bottomRight, bg.width, bg.height),
          // edges
          handle(_ResizeHandle.top, bg.width / 2, 0),
          handle(_ResizeHandle.bottom, bg.width / 2, bg.height),
          handle(_ResizeHandle.left, 0, bg.height / 2),
          handle(_ResizeHandle.right, bg.width, bg.height / 2),
        ],
      ),
    );
  }

  void _onHandleDrag(_ResizeHandle handle, Offset delta) {
    final start = _dragStartBounds ?? widget.stackBounds;
    var left = start.left;
    var top = start.top;
    var width = start.width;
    var height = start.height;

    switch (handle) {
      case _ResizeHandle.topLeft:
        left += delta.dx;
        top += delta.dy;
        width -= delta.dx;
        height -= delta.dy;
      case _ResizeHandle.top:
        top += delta.dy;
        height -= delta.dy;
      case _ResizeHandle.topRight:
        top += delta.dy;
        width += delta.dx;
        height -= delta.dy;
      case _ResizeHandle.right:
        width += delta.dx;
      case _ResizeHandle.bottomRight:
        width += delta.dx;
        height += delta.dy;
      case _ResizeHandle.bottom:
        height += delta.dy;
      case _ResizeHandle.bottomLeft:
        left += delta.dx;
        width -= delta.dx;
        height += delta.dy;
      case _ResizeHandle.left:
        left += delta.dx;
        width -= delta.dx;
    }

    width = math.max(width, _minWidth);
    height = math.max(height, _minHeight);

    widget.onBoundsChanged(Rect.fromLTWH(left, top, width, height));
  }

  MouseCursor _cursorFor(_ResizeHandle handle) {
    return switch (handle) {
      _ResizeHandle.topLeft || _ResizeHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      _ResizeHandle.topRight || _ResizeHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
      _ResizeHandle.top || _ResizeHandle.bottom => SystemMouseCursors.resizeUpDown,
      _ResizeHandle.left || _ResizeHandle.right => SystemMouseCursors.resizeLeftRight,
    };
  }
}
