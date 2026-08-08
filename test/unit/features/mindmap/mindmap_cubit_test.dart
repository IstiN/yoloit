import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MindMapCubit', () {
    test('initial state is empty', () {
      final cubit = MindMapCubit();
      expect(cubit.state.positions, isEmpty);
      expect(cubit.state.nodes, isEmpty);
      expect(cubit.state.hidden, isEmpty);
      expect(cubit.state.locked, isEmpty);
    });

    blocTest<MindMapCubit, MindMapState>(
      'moveNode updates position and locks node',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(
        positions: {'n1': Offset(10, 20)},
      ),
      act: (cubit) => cubit.moveNode('n1', const Offset(5, 10)),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.positions['n1'], 'position', const Offset(15, 30))
            .having((s) => s.locked.contains('n1'), 'locked', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'hideNode adds id to hidden',
      build: () => MindMapCubit(),
      act: (cubit) => cubit.hideNode('n1'),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden.contains('n1'), 'hidden', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'showNode removes id from hidden',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(hidden: {'n1'}),
      act: (cubit) => cubit.showNode('n1'),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden.contains('n1'), 'hidden', false),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'hideNodes adds multiple ids',
      build: () => MindMapCubit(),
      act: (cubit) => cubit.hideNodes({'n1', 'n2'}),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden, 'hidden', {'n1', 'n2'}),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'showNodes removes multiple ids',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(hidden: {'n1', 'n2', 'n3'}),
      act: (cubit) => cubit.showNodes({'n1', 'n2'}),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden, 'hidden', {'n3'}),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'removeNode removes from all collections',
      build: () => MindMapCubit(),
      seed: () => MindMapState(
        nodes: [
          WorkspaceNodeData(
            id: 'n1',
            workspace: Workspace(id: 'ws1', name: 'WS', paths: ['/tmp/ws1']),
          ),
        ],
        positions: const {'n1': Offset(10, 20)},
        sizes: const {'n1': Size(100, 100)},
        hidden: const {'n1'},
        connections: const [
          MindMapConnection(
            fromId: 'n0',
            toId: 'n1',
            style: ConnectorStyle.solid,
            color: Colors.blue,
          ),
        ],
      ),
      act: (cubit) => cubit.removeNode('n1'),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.nodes.isEmpty, 'nodes empty', true)
            .having((s) => s.positions.containsKey('n1'), 'position removed', false)
            .having((s) => s.sizes.containsKey('n1'), 'size removed', false)
            .having((s) => s.hidden.contains('n1'), 'hidden removed', false)
            .having((s) => s.connections.isEmpty, 'connections empty', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'hideAll hides every node',
      build: () => MindMapCubit(),
      seed: () => MindMapState(
        nodes: [
          WorkspaceNodeData(
            id: 'n1',
            workspace: Workspace(id: 'ws1', name: 'WS', paths: ['/tmp/ws1']),
          ),
          WorkspaceNodeData(
            id: 'n2',
            workspace: Workspace(id: 'ws2', name: 'WS2', paths: ['/tmp/ws2']),
          ),
        ],
      ),
      act: (cubit) => cubit.hideAll(),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden, 'hidden', {'n1', 'n2'})
            .having((s) => s.hiddenTypes.isEmpty, 'hiddenTypes empty', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'showAllNodes clears hidden and hiddenTypes',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(
        hidden: {'n1'},
        hiddenTypes: {'ws'},
      ),
      act: (cubit) => cubit.showAllNodes(),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden.isEmpty, 'hidden empty', true)
            .having((s) => s.hiddenTypes.isEmpty, 'hiddenTypes empty', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'toggleGroupVisibility hides when any visible',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(hidden: {'n2'}),
      act: (cubit) => cubit.toggleGroupVisibility(['n1', 'n2']),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden, 'hidden', {'n1', 'n2'}),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'toggleGroupVisibility shows when all hidden',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(hidden: {'n1', 'n2'}),
      act: (cubit) => cubit.toggleGroupVisibility(['n1', 'n2']),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hidden.isEmpty, 'hidden empty', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'toggleType adds new type',
      build: () => MindMapCubit(),
      act: (cubit) => cubit.toggleType('ws'),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hiddenTypes.contains('ws'), 'hiddenTypes', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'toggleType removes existing type',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(hiddenTypes: {'ws'}),
      act: (cubit) => cubit.toggleType('ws'),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.hiddenTypes.contains('ws'), 'hiddenTypes', false),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'resizeNode updates size',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(
        sizes: {'n1': Size(200, 200)},
      ),
      act: (cubit) => cubit.resizeNode('n1', const Offset(50, 100), const Size(100, 100)),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.sizes['n1'], 'size', const Size(250, 300)),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'resizeFromLeft updates position and size',
      build: () => MindMapCubit(),
      seed: () => const MindMapState(
        positions: {'n1': Offset(100, 100)},
        sizes: {'n1': Size(200, 200)},
      ),
      act: (cubit) => cubit.resizeFromLeft('n1', 50, const Size(100, 100)),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.positions['n1']!.dx, 'position x', 150.0)
            .having((s) => s.sizes['n1']!.width, 'width', 150.0)
            .having((s) => s.locked.contains('n1'), 'locked', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'sizeOf returns fallback when unknown',
      build: () => MindMapCubit(),
      act: (cubit) {
        expect(cubit.sizeOf('n1', const Size(42, 42)), const Size(42, 42));
      },
      expect: () => <MindMapState>[],
    );

    blocTest<MindMapCubit, MindMapState>(
      'resetLayout clears locked and hidden',
      build: () => MindMapCubit(),
      seed: () => MindMapState(
        nodes: [
          WorkspaceNodeData(
            id: 'n1',
            workspace: Workspace(id: 'ws1', name: 'WS', paths: ['/tmp/ws1']),
          ),
        ],
        positions: const {'n1': Offset(10, 20)},
        locked: const {'n1'},
        hidden: const {'n1'},
        hiddenTypes: const {'ws'},
      ),
      act: (cubit) => cubit.resetLayout(),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.locked.isEmpty, 'locked empty', true)
            .having((s) => s.hidden.isEmpty, 'hidden empty', true)
            .having((s) => s.hiddenTypes.isEmpty, 'hiddenTypes empty', true),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'applyRemoteMove updates position',
      build: () => MindMapCubit(),
      act: (cubit) => cubit.applyRemoteMove('n1', const Offset(99, 88)),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.positions['n1'], 'position', const Offset(99, 88)),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'applyRemoteResize updates size',
      build: () => MindMapCubit(),
      act: (cubit) => cubit.applyRemoteResize('n1', const Size(99, 88)),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.sizes['n1'], 'size', const Size(99, 88)),
      ],
    );

    blocTest<MindMapCubit, MindMapState>(
      'updateNodeContent stores content',
      build: () => MindMapCubit(),
      act: (cubit) => cubit.updateNodeContent('n1', {'text': 'hello'}),
      expect: () => [
        isA<MindMapState>()
            .having((s) => s.nodeContent['n1'], 'content', {'text': 'hello'}),
      ],
    );
  });

  group('MindMapCubit.loadPersistedPositions', () {
    test('emits empty collections when nothing is persisted', () async {
      final cubit = MindMapCubit();
      await cubit.loadPersistedPositions();

      expect(cubit.state.positions, isEmpty);
      expect(cubit.state.sizes, isEmpty);
      expect(cubit.state.locked, isEmpty);
      expect(cubit.state.hidden, isEmpty);
      expect(cubit.state.hiddenTypes, isEmpty);
      expect(cubit.state.savedViews, isEmpty);
    });

    test('restores persisted positions, sizes, locked, hidden and views', () async {
      const view = MindMapViewSnapshot(
        name: 'Focus',
        positions: {'n1': Offset(3, 4)},
        sizes: {'n1': Size(50, 60)},
        locked: {'n1'},
        hidden: {'n2'},
        hiddenTypes: {'terminal'},
      );
      SharedPreferences.setMockInitialValues({
        'mindmap.positions': jsonEncode({'n1': [10.0, 20.0]}),
        'mindmap.sizes': jsonEncode({'n1': [200.0, 120.0]}),
        'mindmap.locked': ['n1'],
        'mindmap.hidden': ['n2', 'agent:s1'],
        'mindmap.hiddenTypes': ['terminal'],
        'mindmap.saved_views': jsonEncode({'Focus': view.toJson()}),
      });

      final cubit = MindMapCubit();
      await cubit.loadPersistedPositions();

      expect(cubit.state.positions, {'n1': const Offset(10, 20)});
      expect(cubit.state.sizes, {'n1': const Size(200, 120)});
      expect(cubit.state.locked, {'n1'});
      // Stale agent-node hides are filtered out — agent cards always reappear.
      expect(cubit.state.hidden, {'n2'});
      expect(cubit.state.hiddenTypes, {'terminal'});
      expect(cubit.state.savedViews.keys, ['Focus']);
      expect(
        cubit.state.savedViews['Focus']!.positions,
        {'n1': const Offset(3, 4)},
      );
    });

    test('clears corrupted positions when every node sits near the origin', () async {
      SharedPreferences.setMockInitialValues({
        'mindmap.positions': jsonEncode({'a': [0.0, 0.0], 'b': [5.0, 5.0]}),
        'mindmap.locked': ['a'],
        'mindmap.sizes': jsonEncode({'a': [100.0, 100.0]}),
      });

      final cubit = MindMapCubit();
      await cubit.loadPersistedPositions();

      expect(cubit.state.positions, isEmpty);
      expect(cubit.state.locked, isEmpty);
      expect(cubit.state.sizes, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mindmap.positions'), isNull);
      expect(prefs.getStringList('mindmap.locked'), isNull);
      expect(prefs.getString('mindmap.sizes'), isNull);
    });

    test('keeps positions when at least one node is away from the origin', () async {
      SharedPreferences.setMockInitialValues({
        'mindmap.positions': jsonEncode({'a': [0.0, 0.0], 'b': [500.0, 600.0]}),
      });

      final cubit = MindMapCubit();
      await cubit.loadPersistedPositions();

      expect(cubit.state.positions, {
        'a': Offset.zero,
        'b': const Offset(500, 600),
      });
    });
  });
}
