import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('workspace_cubit_test_');
    // Keep WorkspaceDirService symlink/dir writes inside the temp home.
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempDir.path));
  });

  tearDown(() async {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    await tempDir.delete(recursive: true);
  });

  String tempFile(String name) => '${tempDir.path}/$name.json';

  List<Workspace> readPersisted(String name) {
    final raw = jsonDecode(File(tempFile(name)).readAsStringSync()) as List;
    return raw
        .map((e) => Workspace.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  group('WorkspaceCubit', () {
    test('initial state is WorkspaceInitial', () {
      final cubit = WorkspaceCubit(testWorkspacesFilePath: tempFile('ws'));
      expect(cubit.state, const WorkspaceInitial());
      cubit.close();
    });

    blocTest<WorkspaceCubit, WorkspaceState>(
      'load() with empty prefs emits WorkspaceLoading then WorkspaceLoaded with empty list',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws')),
      act: (cubit) => cubit.load(),
      expect: () => [
        const WorkspaceLoading(),
        isA<WorkspaceLoaded>().having((s) => s.workspaces, 'workspaces', isEmpty),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'load() restores persisted workspaces',
      setUp: () async {
        File(tempFile('ws_restore')).writeAsStringSync(
          '[{"id":"ws_1","name":"project","paths":["/tmp/project"],"gitBranch":null,"addedLines":0,"removedLines":0}]',
        );
      },
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_restore')),
      act: (cubit) => cubit.load(),
      expect: () => [
        const WorkspaceLoading(),
        isA<WorkspaceLoaded>().having(
          (s) => s.workspaces.first.name,
          'first workspace name',
          'project',
        ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removeWorkspace removes correct workspace',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_remove')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/b']),
        ],
      ),
      act: (cubit) => cubit.removeWorkspace('ws_1'),
      expect: () => [
        isA<WorkspaceLoaded>().having(
          (s) => s.workspaces.map((w) => w.id).toList(),
          'remaining workspaces',
          ['ws_2'],
        ),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'setActive updates activeWorkspaceId',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_active')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/b']),
        ],
      ),
      act: (cubit) => cubit.setActive('ws_2'),
      expect: () => [
        isA<WorkspaceLoaded>().having((s) => s.activeWorkspaceId, 'activeId', 'ws_2'),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removeWorkspace clears activeWorkspaceId when active is removed',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_clear')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
        activeWorkspaceId: 'ws_1',
      ),
      act: (cubit) => cubit.removeWorkspace('ws_1'),
      expect: () => [
        isA<WorkspaceLoaded>().having((s) => s.activeWorkspaceId, 'activeId', isNull),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'addPathToWorkspace appends a new path and persists it',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_addpath')),
      seed: () => const WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws_1', name: 'alpha', paths: ['/a'])],
        activeWorkspaceId: 'ws_1',
      ),
      act: (cubit) => cubit.addPathToWorkspace('ws_1', '/b'),
      expect: () => [
        isA<WorkspaceLoaded>()
            .having((s) => s.workspaces.single.paths, 'paths', ['/a', '/b'])
            .having((s) => s.activeWorkspaceId, 'activeId', 'ws_1'),
      ],
      verify: (_) {
        final persisted = readPersisted('ws_addpath');
        expect(persisted.single.paths, ['/a', '/b']);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'addPathToWorkspace ignores a duplicate path',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_duppath')),
      seed: () => const WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws_1', name: 'alpha', paths: ['/a'])],
      ),
      act: (cubit) => cubit.addPathToWorkspace('ws_1', '/a'),
      verify: (cubit) {
        final s = cubit.state as WorkspaceLoaded;
        expect(s.workspaces.single.paths, ['/a']);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removePathFromWorkspace keeps the workspace when paths remain',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rmpath')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a', '/b']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/c']),
        ],
        activeWorkspaceId: 'ws_1',
      ),
      act: (cubit) => cubit.removePathFromWorkspace('ws_1', '/a'),
      expect: () => [
        isA<WorkspaceLoaded>()
            .having(
              (s) => s.workspaces.map((w) => w.id).toList(),
              'workspace ids',
              ['ws_1', 'ws_2'],
            )
            .having((s) => s.workspaces.first.paths, 'paths', ['/b'])
            .having((s) => s.activeWorkspaceId, 'activeId', 'ws_1'),
      ],
      verify: (_) {
        final persisted = readPersisted('ws_rmpath');
        expect(persisted.first.paths, ['/b']);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removePathFromWorkspace removes an emptied workspace and clears active',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rmempty')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/b']),
        ],
        activeWorkspaceId: 'ws_1',
      ),
      act: (cubit) => cubit.removePathFromWorkspace('ws_1', '/a'),
      expect: () => [
        isA<WorkspaceLoaded>()
            .having(
              (s) => s.workspaces.map((w) => w.id).toList(),
              'workspace ids',
              ['ws_2'],
            )
            .having((s) => s.activeWorkspaceId, 'activeId', isNull),
      ],
      verify: (_) {
        final persisted = readPersisted('ws_rmempty');
        expect(persisted.map((w) => w.id).toList(), ['ws_2']);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removePathFromWorkspace keeps active id for other workspaces',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rmother')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/b']),
        ],
        activeWorkspaceId: 'ws_2',
      ),
      act: (cubit) => cubit.removePathFromWorkspace('ws_1', '/a'),
      expect: () => [
        isA<WorkspaceLoaded>()
            .having(
              (s) => s.workspaces.map((w) => w.id).toList(),
              'workspace ids',
              ['ws_2'],
            )
            .having((s) => s.activeWorkspaceId, 'activeId', 'ws_2'),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'setWorkspaceColor sets and persists the accent color',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_color')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/b']),
        ],
      ),
      act: (cubit) => cubit.setWorkspaceColor('ws_1', const Color(0xFF123456)),
      expect: () => [
        isA<WorkspaceLoaded>()
            .having(
              (s) => s.workspaces.first.color,
              'color',
              const Color(0xFF123456),
            )
            .having((s) => s.workspaces[1].color, 'other color', isNull),
      ],
      verify: (_) {
        final persisted = readPersisted('ws_color');
        expect(persisted.first.color, const Color(0xFF123456));
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'setWorkspaceColor with null clears the accent color',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_clearcolor')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(
            id: 'ws_1',
            name: 'alpha',
            paths: ['/a'],
            color: Color(0xFF123456),
          ),
        ],
      ),
      act: (cubit) => cubit.setWorkspaceColor('ws_1', null),
      expect: () => [
        isA<WorkspaceLoaded>().having(
          (s) => s.workspaces.single.color,
          'color',
          isNull,
        ),
      ],
      verify: (_) {
        final persisted = readPersisted('ws_clearcolor');
        expect(persisted.single.color, isNull);
      },
    );

    test('WorkspaceLoaded.activeWorkspace returns correct workspace', () {
      const state = WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/b']),
        ],
        activeWorkspaceId: 'ws_2',
      );
      expect(state.activeWorkspace?.id, 'ws_2');
      expect(state.activeWorkspace?.name, 'beta');
    });

    test('WorkspaceLoaded.activeWorkspace returns null when no active', () {
      const state = WorkspaceLoaded(workspaces: [
        Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
      ]);
      expect(state.activeWorkspace, isNull);
    });
  });
}
