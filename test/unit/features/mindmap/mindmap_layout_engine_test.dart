import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/mindmap/mindmap_layout_engine.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const workspaceNode = WorkspaceNodeData(
    id: 'ws1',
    workspace: Workspace(id: 'ws1', name: 'W1', paths: ['/tmp/w1']),
  );

  const repoNode = RepoNodeData(
    id: 'repo1',
    sessionId: 's1',
    repoPath: '/tmp/w1',
    repoName: 'w1',
    branch: 'main',
  );

  const branchNode = BranchNodeData(
    id: 'branch1',
    repoId: 'repo1',
    repoName: 'w1',
    branch: 'feature',
    commitHash: 'abc1234',
  );

  group('MindMapLayoutEngine.compute', () {
    test('places new nodes at their column x offsets', () {
      final engine = MindMapLayoutEngine();
      final positions = engine.compute(
        nodes: [workspaceNode, repoNode, branchNode],
        existing: const {},
        sizes: const {},
      );

      expect(positions['ws1']!.dx, 2040.0);
      expect(positions['repo1']!.dx, 2680.0);
      expect(positions['branch1']!.dx, 2900.0);
    });

    test('preserves existing positions', () {
      final engine = MindMapLayoutEngine();
      final existing = {
        'ws1': const Offset(1234, 5678),
      };
      final positions = engine.compute(
        nodes: [workspaceNode],
        existing: existing,
        sizes: const {},
      );

      expect(positions['ws1'], const Offset(1234, 5678));
    });

    test('locked nodes keep exact positions even when overlapping', () {
      final engine = MindMapLayoutEngine();
      final existing = {
        'ws1': const Offset(100, 100),
        'repo1': const Offset(100, 100),
      };
      final positions = engine.compute(
        nodes: [workspaceNode, repoNode],
        existing: existing,
        sizes: const {},
        locked: {'ws1', 'repo1'},
      );

      expect(positions['ws1'], const Offset(100, 100));
      expect(positions['repo1'], const Offset(100, 100));
    });

    test('places new node to the right of its connected source', () {
      final engine = MindMapLayoutEngine();
      final existing = {
        'ws1': const Offset(500, 300),
      };
      final connections = [
        const MindMapConnection(
          fromId: 'ws1',
          toId: 'repo1',
          style: ConnectorStyle.solid,
          color: Colors.black,
        ),
      ];
      final positions = engine.compute(
        nodes: [workspaceNode, repoNode],
        existing: existing,
        sizes: const {'ws1': Size(200, 100)},
        connections: connections,
      );

      // repo1 should be placed to the right of ws1 (500 + 200 + margin).
      expect(positions['repo1']!.dx, greaterThan(500 + 200));
      expect(positions['repo1']!.dy, closeTo(300, 500));
    });

    test('pushes cross-column overlapping unlocked nodes downward', () {
      final engine = MindMapLayoutEngine();
      // Place a wide workspace node in column 0 that spills into column 1's x range.
      final existing = {
        'ws1': const Offset(2040, 2000),
      };
      final positions = engine.compute(
        nodes: [workspaceNode, repoNode],
        existing: existing,
        sizes: const {
          'ws1': Size(300, 100),
          'repo1': Size(200, 100),
        },
      );

      // repo1 is newly placed in column 1. Because _findFreeY only checks its own
      // column, it may overlap horizontally with the wide ws1. The push step
      // should nudge the unlocked ws1 downward to resolve the overlap.
      expect(
        positions['ws1']!.dy,
        greaterThanOrEqualTo(2000),
      );
    });

    test('stacks multiple new nodes in same column without overlap', () {
      final engine = MindMapLayoutEngine();
      const nodeA = WorkspaceNodeData(
        id: 'wsA',
        workspace: Workspace(id: 'wsA', name: 'A', paths: ['/tmp/a']),
      );
      const nodeB = WorkspaceNodeData(
        id: 'wsB',
        workspace: Workspace(id: 'wsB', name: 'B', paths: ['/tmp/b']),
      );
      final positions = engine.compute(
        nodes: [nodeA, nodeB],
        existing: const {},
        sizes: const {
          'wsA': Size(220, 148),
          'wsB': Size(220, 148),
        },
      );

      expect(positions['wsA']!.dx, positions['wsB']!.dx);
      expect(
        positions['wsB']!.dy,
        greaterThan(positions['wsA']!.dy + 100),
      );
    });

    test('stacks many new nodes without overlap', () {
      final engine = MindMapLayoutEngine();
      final nodes = <WorkspaceNodeData>[];
      final sizes = <String, Size>{};
      for (var i = 0; i < 20; i++) {
        nodes.add(
          WorkspaceNodeData(
            id: 'ws$i',
            workspace: Workspace(id: 'ws$i', name: 'W$i', paths: ['/tmp/$i']),
          ),
        );
        sizes['ws$i'] = const Size(220, 100);
      }
      final positions = engine.compute(
        nodes: nodes,
        existing: const {},
        sizes: sizes,
      );

      final yValues = nodes.map((n) => positions[n.id]!.dy).toList()..sort();
      for (var i = 1; i < yValues.length; i++) {
        expect(
          yValues[i] - yValues[i - 1],
          greaterThanOrEqualTo(20),
          reason: 'Nodes $i and ${i - 1} should not overlap',
        );
      }
    });
  });

  group('columnLabelX', () {
    test('returns x offset for valid column index', () {
      expect(MindMapLayoutEngine.columnLabelX(0), 2040.0);
      expect(MindMapLayoutEngine.columnLabelX(2), 2680.0);
    });

    test('returns last offset for out-of-range column index', () {
      expect(
        MindMapLayoutEngine.columnLabelX(99),
        MindMapLayoutEngine.columnLabelX(8),
      );
    });
  });

  group('columnLabels', () {
    test('has one label per column offset', () {
      expect(MindMapLayoutEngine.columnLabels.length, greaterThanOrEqualTo(9));
      expect(MindMapLayoutEngine.columnLabels[0], 'WORKSPACES');
      expect(MindMapLayoutEngine.columnLabels[1], contains('SESSIONS'));
    });
  });
}
