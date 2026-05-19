import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempDir.path));
  });

  tearDown(() async {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    final wsRoot = Directory(
      p.join(tempDir.path, '.config', 'yoloit', 'workspaces'),
    );
    if (await wsRoot.exists()) {
      await wsRoot.delete(recursive: true);
    }
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup on Windows when handles remain open.
      }
    }
  });

  String tempFile(String name) => '${tempDir.path}/$name.json';

  Future<String> createTempFolder(String name) async {
    final dir = Directory(p.join(tempDir.path, name));
    await dir.create(recursive: true);
    return dir.path;
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
      'load() with corrupt JSON in SharedPreferences emits WorkspaceError',
      setUp: () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await prefs.setStringList('workspaces', ['not-valid-json{{{']);
      },
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_corrupt')),
      act: (cubit) => cubit.load(),
      expect: () => [
        const WorkspaceLoading(),
        isA<WorkspaceError>(),
      ],
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'addWorkspace adds workspace with basename as default name',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_add')),
      seed: () => const WorkspaceLoaded(workspaces: []),
      act: (cubit) async {
        final folder = await createTempFolder('my_project');
        await cubit.addWorkspace(folder);
      },
      verify: (cubit) {
        final loaded = cubit.state as WorkspaceLoaded;
        expect(loaded.workspaces, hasLength(1));
        expect(loaded.workspaces.first.name, 'my_project');
        expect(loaded.workspaces.first.paths.single, endsWith('my_project'));
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'addWorkspace with customName uses supplied name',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_add_custom')),
      seed: () => const WorkspaceLoaded(workspaces: []),
      act: (cubit) async {
        final folder = await createTempFolder('folder_a');
        await cubit.addWorkspace(folder, customName: 'Custom Name');
      },
      verify: (cubit) {
        final loaded = cubit.state as WorkspaceLoaded;
        expect(loaded.workspaces.single.name, 'Custom Name');
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'addPathToWorkspace appends new path',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_add_path')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
      ),
      act: (cubit) async {
        await cubit.addPathToWorkspace('ws_1', '/b');
      },
      verify: (cubit) {
        final paths = (cubit.state as WorkspaceLoaded).workspaces.single.paths;
        expect(paths, ['/a', '/b']);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'addPathToWorkspace ignores duplicate path',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_dup_path')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
      ),
      act: (cubit) async {
        await cubit.addPathToWorkspace('ws_1', '/a');
      },
      verify: (cubit) {
        final paths = (cubit.state as WorkspaceLoaded).workspaces.single.paths;
        expect(paths, ['/a']);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removePathFromWorkspace removes one path and keeps workspace',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rm_path')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a', '/b']),
        ],
      ),
      act: (cubit) => cubit.removePathFromWorkspace('ws_1', '/a'),
      verify: (cubit) {
        final loaded = cubit.state as WorkspaceLoaded;
        expect(loaded.workspaces, hasLength(1));
        expect(loaded.workspaces.single.paths, ['/b']);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removePathFromWorkspace removes workspace when last path removed',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rm_last')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
      ),
      act: (cubit) => cubit.removePathFromWorkspace('ws_1', '/a'),
      verify: (cubit) {
        final loaded = cubit.state as WorkspaceLoaded;
        expect(loaded.workspaces, isEmpty);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'removePathFromWorkspace clears activeWorkspaceId when active workspace emptied',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rm_active')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
        activeWorkspaceId: 'ws_1',
      ),
      act: (cubit) => cubit.removePathFromWorkspace('ws_1', '/a'),
      verify: (cubit) {
        final loaded = cubit.state as WorkspaceLoaded;
        expect(loaded.workspaces, isEmpty);
        expect(loaded.activeWorkspaceId, isNull);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'renameWorkspace updates name',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rename')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
      ),
      act: (cubit) => cubit.renameWorkspace('ws_1', 'renamed'),
      verify: (cubit) {
        final ws = (cubit.state as WorkspaceLoaded).workspaces.single;
        expect(ws.id, 'ws_1');
        expect(ws.name, 'renamed');
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'renameWorkspace persists after load',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_rename_load')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
      ),
      act: (cubit) async {
        await cubit.renameWorkspace('ws_1', 'renamed');
        await cubit.load();
      },
      verify: (cubit) {
        final ws = (cubit.state as WorkspaceLoaded).workspaces.single;
        expect(ws.name, 'renamed');
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'setWorkspaceColor updates color',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_color')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
        ],
      ),
      act: (cubit) => cubit.setWorkspaceColor('ws_1', const Color(0xFF123456)),
      verify: (cubit) {
        final ws = (cubit.state as WorkspaceLoaded).workspaces.single;
        expect(ws.color, const Color(0xFF123456));
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'setWorkspaceColor with null clears color',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_clear_color')),
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
      verify: (cubit) {
        final ws = (cubit.state as WorkspaceLoaded).workspaces.single;
        expect(ws.color, isNull);
      },
    );

    blocTest<WorkspaceCubit, WorkspaceState>(
      'updateWorkspace replaces workspace by id',
      build: () => WorkspaceCubit(testWorkspacesFilePath: tempFile('ws_update')),
      seed: () => const WorkspaceLoaded(
        workspaces: [
          Workspace(id: 'ws_1', name: 'alpha', paths: ['/a']),
          Workspace(id: 'ws_2', name: 'beta', paths: ['/b']),
        ],
      ),
      act: (cubit) => cubit.updateWorkspace(
        const Workspace(
          id: 'ws_1',
          name: 'alpha',
          paths: ['/a'],
          enabledSkills: ['skill-a'],
        ),
      ),
      verify: (cubit) {
        final loaded = cubit.state as WorkspaceLoaded;
        expect(loaded.workspaces[0].enabledSkills, ['skill-a']);
        expect(loaded.workspaces[1].name, 'beta');
      },
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
