import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/nodes/node_registry.dart';
import 'package:yoloit/features/mindmap/widgets/mindmap_connector.dart';

/// Cell dimensions for grid mode.
const _cellW    = 1400.0;
const _cellH    = 900.0;
const _cellGapX = 80.0;
const _cellGapY = 80.0;

/// Column x-offsets within a single cell (mirrors layout engine columns).
const _localColX = [0.0, 230.0, 460.0, 640.0, 820.0, 1150.0, 1380.0];

/// Computes grid positions for all nodes, grouping by workspace.
Map<String, Offset> computeGridPositions({
  required List<MindMapNodeData> nodes,
  required List<WorkspaceNodeData> workspaceNodes,
}) {
  final result = <String, Offset>{};
  final n = workspaceNodes.length;
  if (n == 0) return result;

  final cols = math.max(1, math.sqrt(n).ceil());

  for (var wi = 0; wi < workspaceNodes.length; wi++) {
    final wsNode = workspaceNodes[wi];
    final row = wi ~/ cols;
    final col = wi % cols;
    final cellOriginX = col * (_cellW + _cellGapX) + _cellGapX;
    final cellOriginY = row * (_cellH + _cellGapY) + _cellGapY + 40;

    result[wsNode.id] = Offset(cellOriginX + _localColX[0], cellOriginY + 10);

    final wsId = _wsIdFromNodeId(wsNode.id);

    final colNextY = <int, double>{};
    for (var ci = 0; ci < _localColX.length; ci++) {
      colNextY[ci] = cellOriginY + 10;
    }
    colNextY[0] = cellOriginY + 10 + (wsNode.defaultSize.height) + 20;

    for (final node in nodes) {
      if (node is WorkspaceNodeData) continue;
      if (!_belongsToWorkspace(node, wsId)) continue;
      if (result.containsKey(node.id)) continue;

      final col2 = node.columnIndex.clamp(0, _localColX.length - 1);
      final y = colNextY[col2] ?? (cellOriginY + 10);
      result[node.id] = Offset(cellOriginX + _localColX[col2], y);
      colNextY[col2] = y + (node.defaultSize.height) + 16;
    }
  }

  return result;
}

String _wsIdFromNodeId(String wsNodeId) {
  if (wsNodeId.startsWith('ws:')) return wsNodeId.substring(3);
  return wsNodeId;
}

bool _belongsToWorkspace(MindMapNodeData node, String wsId) {
  return switch (node) {
    SessionNodeData  n => n.workspaceId == wsId,
    AgentNodeData    n => n.workspaceId == wsId,
    RunNodeData      n => n.workspaceId == wsId,
    _ => node.id.contains(wsId),
  };
}

/// Grid canvas widget — uses computed grid positions instead of cubit positions.
class GridMindMapCanvas extends StatefulWidget {
  const GridMindMapCanvas({
    super.key,
    required this.nodes,
    required this.conns,
    required this.transformCtrl,
    required this.dashAnimation,
  });

  final List<MindMapNodeData> nodes;
  final List<MindMapConnection> conns;
  final TransformationController transformCtrl;
  final Animation<double> dashAnimation;

  @override
  State<GridMindMapCanvas> createState() => _GridMindMapCanvasState();
}

class _GridMindMapCanvasState extends State<GridMindMapCanvas> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final wsNodes = widget.nodes.whereType<WorkspaceNodeData>().toList();
    final gridPositions = computeGridPositions(
      nodes:          widget.nodes,
      workspaceNodes: wsNodes,
    );

    final n    = wsNodes.length;
    final cols = math.max(1, math.sqrt(n).ceil());
    final rows = n == 0 ? 1 : (n / cols).ceil();
    final canvasW = cols * (_cellW + _cellGapX) + _cellGapX;
    final canvasH = rows * (_cellH + _cellGapY) + _cellGapY + 60;

    final defaultSizeMap = {for (final nd in widget.nodes) nd.id: nd.defaultSize};

    return Container(
      color: colors.surface,
      child: Stack(
        children: [
          InteractiveViewer(
            transformationController: widget.transformCtrl,
            minScale: 0.1,
            maxScale: 3.0,
            panEnabled: true,
            scaleEnabled: true,
            constrained: false,
            child: SizedBox(
              width:  canvasW,
              height: canvasH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Dot-grid background.
                  Positioned.fill(child: CustomPaint(painter: _DotGridPainter(dotColor: colors.border.withAlpha(0x8C)))),

                  // Cell outlines.
                  for (var wi = 0; wi < wsNodes.length; wi++)
                    _CellOutline(
                      wsNode:  wsNodes[wi],
                      cellIdx: wi,
                      cols:    cols,
                    ),

                  // Connectors.
                  Positioned.fill(
                    child: MindMapConnectorLayer(
                      connections:  widget.conns,
                      positions:    gridPositions,
                      sizes:        {},
                      defaultSizes: defaultSizeMap,
                      dashAnimation: widget.dashAnimation,
                    ),
                  ),

                  // Nodes.
                  for (final nd in widget.nodes)
                    _GridNode(
                      node:     nd,
                      position: gridPositions[nd.id] ?? Offset.zero,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A non-draggable read-only node card used in grid mode.
class _GridNode extends StatelessWidget {
  const _GridNode({required this.node, required this.position});
  final MindMapNodeData node;
  final Offset position;

  @override
  Widget build(BuildContext context) {
    final size = node.defaultSize;
    return Positioned(
      left: position.dx,
      top:  position.dy,
      child: SizedBox(
        width:  size.width,
        height: size.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: NodeRegistry.build(node),
        ),
      ),
    );
  }
}

/// Draws a faint rounded-rectangle cell outline + workspace name label.
class _CellOutline extends StatelessWidget {
  const _CellOutline({required this.wsNode, required this.cellIdx, required this.cols});
  final WorkspaceNodeData wsNode;
  final int cellIdx;
  final int cols;

  @override
  Widget build(BuildContext context) {
    final row = cellIdx ~/ cols;
    final col = cellIdx % cols;
    final x = col * (_cellW + _cellGapX) + _cellGapX / 2;
    final y = row * (_cellH + _cellGapY) + _cellGapY / 2 + 40;

    return Positioned(
      left: x,
      top:  y,
      child: Container(
        width:  _cellW + _cellGapX,
        height: _cellH + _cellGapY,
        decoration: BoxDecoration(
          border: Border.all(
            color: (wsNode.workspace.color ?? const Color(0xFF60A5FA)).withAlpha(40),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: Text(
            wsNode.workspace.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: (wsNode.workspace.color ?? const Color(0xFF60A5FA)).withAlpha(100),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.dotColor});
  final Color dotColor;
  static const _spacing = 28.0;
  static const _dotR    = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;
    for (double x = 14; x < size.width; x += _spacing) {
      for (double y = 14; y < size.height; y += _spacing) {
        canvas.drawCircle(Offset(x, y), _dotR, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.dotColor != dotColor;
}
