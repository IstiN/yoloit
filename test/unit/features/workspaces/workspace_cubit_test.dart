import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('workspace_cubit_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  String tempFile(String name) => '${tempDir.path}/$name.json';

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
