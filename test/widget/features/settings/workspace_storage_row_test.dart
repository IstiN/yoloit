import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/config/app_config.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/ui/sections/workspace_storage_row_vm.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

class _FakeWorkspaceCubit extends WorkspaceCubit {
  int loadCalls = 0;

  @override
  Future<void> load() async {
    loadCalls++;
  }
}

Widget _buildRow(_FakeWorkspaceCubit cubit) {
  return BlocProvider<WorkspaceCubit>.value(
    value: cubit,
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(body: WorkspaceStorageRow()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    WorkspaceStorageRowTestHooks.pickDirectoryOverride = null;
    WorkspaceStorageRowTestHooks.setWorkspacesFilePathOverride = null;
  });

  group('WorkspaceStorageRow', () {
    testWidgets('shows the default storage path without a reset button', (
      tester,
    ) async {
      final cubit = _FakeWorkspaceCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(_buildRow(cubit));
      await tester.pump();

      expect(find.text('Workspace storage'), findsOneWidget);
      expect(find.text(AppConfig.defaultWorkspacesFilePath), findsOneWidget);
      expect(find.text('Change…'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);
    });

    testWidgets('cancelling the picker keeps the current path', (tester) async {
      var pickerCalls = 0;
      WorkspaceStorageRowTestHooks.pickDirectoryOverride = (
        context, {
        initialPath,
        title = '',
      }) async {
        pickerCalls++;
        return null;
      };
      WorkspaceStorageRowTestHooks.setWorkspacesFilePathOverride =
          (path) async => fail('must not persist when the picker is cancelled');

      final cubit = _FakeWorkspaceCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(_buildRow(cubit));
      await tester.pump();

      await tester.tap(find.text('Change…'));
      await tester.pump();

      expect(pickerCalls, 1);
      expect(cubit.loadCalls, 0);
      expect(find.text(AppConfig.defaultWorkspacesFilePath), findsOneWidget);
    });

    testWidgets('choosing a folder persists the new path and reloads', (
      tester,
    ) async {
      final persisted = <String>[];
      WorkspaceStorageRowTestHooks.pickDirectoryOverride = (
        context, {
        initialPath,
        title = '',
      }) async {
        return '/tmp/custom-store';
      };
      WorkspaceStorageRowTestHooks.setWorkspacesFilePathOverride =
          (path) async => persisted.add(path);

      final cubit = _FakeWorkspaceCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(_buildRow(cubit));
      await tester.pump();

      await tester.tap(find.text('Change…'));
      await tester.pump();
      await tester.pump();

      expect(persisted, ['/tmp/custom-store/workspaces.json']);
      expect(find.text('/tmp/custom-store/workspaces.json'), findsOneWidget);
      expect(cubit.loadCalls, 1);
      // A non-default path reveals the reset button.
      expect(find.text('Reset'), findsOneWidget);
    });
  });
}
