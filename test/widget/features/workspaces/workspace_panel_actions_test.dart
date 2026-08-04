import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/ui/workspace_panel.dart';

class _MockWorkspaceCubit extends Mock implements WorkspaceCubit {}

class _MockReviewCubit extends Mock implements ReviewCubit {}

class _MockTerminalCubit extends Mock implements TerminalCubit {}

_MockWorkspaceCubit _stubWorkspaceCubit(WorkspaceState state) {
  final cubit = _MockWorkspaceCubit();
  when(() => cubit.state).thenReturn(state);
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<WorkspaceState>.empty());
  when(
    () => cubit.addWorkspace(any(), customName: any(named: 'customName')),
  ).thenAnswer((_) async {});
  when(() => cubit.addPathToWorkspace(any(), any())).thenAnswer((_) async {});
  when(() => cubit.removeWorkspace(any())).thenAnswer((_) async {});
  when(() => cubit.removePathFromWorkspace(any(), any())).thenAnswer((_) async {});
  when(() => cubit.renameWorkspace(any(), any())).thenAnswer((_) async {});
  when(() => cubit.setActive(any())).thenAnswer((_) {});
  return cubit;
}

_MockReviewCubit _stubReviewCubit() {
  final cubit = _MockReviewCubit();
  when(() => cubit.state).thenReturn(const ReviewInitial());
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<ReviewState>.empty());
  when(() => cubit.loadWorkspace(any())).thenAnswer((_) async {});
  return cubit;
}

_MockTerminalCubit _stubTerminalCubit() {
  final cubit = _MockTerminalCubit();
  when(() => cubit.state).thenReturn(const TerminalInitial());
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<TerminalState>.empty());
  when(
    () => cubit.spawnSession(
      type: any(named: 'type'),
      workspacePath: any(named: 'workspacePath'),
      workspaceId: any(named: 'workspaceId'),
    ),
  ).thenAnswer((_) async {});
  return cubit;
}

Widget _buildPanel({
  required WorkspaceCubit workspaceCubit,
  required ReviewCubit reviewCubit,
  required TerminalCubit terminalCubit,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<WorkspaceCubit>.value(value: workspaceCubit),
      BlocProvider<TerminalCubit>.value(value: terminalCubit),
      BlocProvider<ReviewCubit>.value(value: reviewCubit),
      BlocProvider(create: (_) => RunCubit()),
    ],
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(
        body: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 260, child: WorkspacePanel()),
        ),
      ),
    ),
  );
}

/// Simulates a mouse hover over [finder] so hover-only controls appear.
Future<void> _hoverOver(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer();
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
}

/// Taps the tile's ⋯ button and waits for the popup-menu open animation
/// (menu items are off-screen mid-animation).
Future<void> _openTileMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More actions'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _dialogTextField() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.text(label),
);

/// Waits for [finder] to appear while real (non-fake) async work settles.
/// Must be called inside `tester.runAsync`.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .toList();
  debugPrint('visible texts on timeout: $texts');
  throw TestFailure('Timed out waiting for $finder');
}

/// Drives the in-app board file picker dialog to select [path] and confirm.
/// Must be called inside `tester.runAsync` (the picker does real dart:io I/O).
Future<void> _pickDirectory(WidgetTester tester, String path) async {
  await _waitFor(tester, find.byKey(const Key('board-file-picker-search')));
  // Wait for the initial home-dir listing to finish: its completion clears
  // the search controller, which would otherwise wipe the text we enter.
  await _waitFor(tester, find.text('Home'));
  await tester.enterText(
    find.byKey(const Key('board-file-picker-search')),
    path,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  // Wait until the picker header shows the loaded path as a plain Text
  // (the search field's EditableText also displays the path).
  await _waitFor(
    tester,
    find.byWidgetPredicate((w) => w is Text && w.data == path),
  );
  await tester.tap(find.byKey(const Key('board-file-picker-confirm')));
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await tester.pump();
}

/// Creates a temp directory containing a `.git` subfolder so that
/// `maybePromptGitInit` returns without showing its dialog.
Directory _createGitDir(Directory parent, String name) {
  final dir = Directory('${parent.path}/$name')..createSync();
  Directory('${dir.path}/.git').createSync();
  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(AgentType.terminal);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const ws1 = Workspace(id: 'ws_1', name: 'alpha', paths: ['/a/main']);
  const ws2 = Workspace(id: 'ws_2', name: 'beta', paths: ['/b/proj']);

  group('workspace switching', () {
    testWidgets('tapping a tile calls setActive and loads review', (
      tester,
    ) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      final reviewCubit = _stubReviewCubit();
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: reviewCubit,
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('beta'));
      await tester.pump();

      verify(() => wsCubit.setActive('ws_2')).called(1);
      verify(() => reviewCubit.loadWorkspace(['/b/proj'])).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('spawn agent', () {
    testWidgets('menu spawn activates workspace and spawns session', (
      tester,
    ) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      final terminalCubit = _stubTerminalCubit();
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: terminalCubit,
        ),
      );
      await tester.pump();

      await _hoverOver(tester, find.text('beta'));
      await _openTileMenu(tester);
      await tester.tap(find.text('Start Terminal'));
      await tester.pump();

      verify(() => wsCubit.setActive('ws_2')).called(1);
      final captured = verify(
        () => terminalCubit.spawnSession(
          type: AgentType.terminal,
          workspacePath: captureAny(named: 'workspacePath'),
          workspaceId: 'ws_2',
        ),
      ).captured;
      expect(captured.single, ws2.workspaceDir);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('remove workspace', () {
    Future<void> openRemoveDialog(
      WidgetTester tester,
      _MockWorkspaceCubit wsCubit,
    ) async {
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();
      await _hoverOver(tester, find.text('beta'));
      await tester.tap(find.byTooltip('Remove workspace'));
      await tester.pump();
      expect(find.text('Remove Workspace'), findsOneWidget);
    }

    testWidgets('confirming remove calls removeWorkspace', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await openRemoveDialog(tester, wsCubit);

      await tester.tap(_dialogButton('Remove'));
      await tester.pump();

      verify(() => wsCubit.removeWorkspace('ws_2')).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('cancelling remove does nothing', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await openRemoveDialog(tester, wsCubit);

      await tester.tap(_dialogButton('Cancel'));
      await tester.pump();

      verifyNever(() => wsCubit.removeWorkspace(any()));
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('rename workspace', () {
    Future<void> openRenameDialog(
      WidgetTester tester,
      _MockWorkspaceCubit wsCubit,
    ) async {
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();
      await _hoverOver(tester, find.text('beta'));
      await _openTileMenu(tester);
      await tester.tap(find.text('Rename'));
      await tester.pump();
      expect(find.text('Rename Workspace'), findsOneWidget);
    }

    testWidgets('entering a new name calls renameWorkspace', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await openRenameDialog(tester, wsCubit);

      await tester.enterText(_dialogTextField(), 'beta-renamed');
      await tester.tap(_dialogButton('Rename'));
      await tester.pump();
      await tester.pump(); // post-frame callback performs the rename

      verify(() => wsCubit.renameWorkspace('ws_2', 'beta-renamed')).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('cancelling rename does nothing', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await openRenameDialog(tester, wsCubit);

      await tester.tap(_dialogButton('Cancel'));
      await tester.pump();

      verifyNever(() => wsCubit.renameWorkspace(any(), any()));
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('add workspace', () {
    testWidgets('cancelling the name dialog aborts the flow', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(workspaces: []),
      );
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Add workspace'));
      await tester.pump();
      expect(find.text('New Workspace'), findsOneWidget);

      await tester.tap(_dialogButton('Cancel'));
      await tester.pump();

      expect(find.text('New Workspace'), findsNothing);
      verifyNever(
        () => wsCubit.addWorkspace(any(), customName: any(named: 'customName')),
      );
    });

    testWidgets('cancelling the folder picker aborts the flow', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(workspaces: []),
      );
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Add workspace'));
      await tester.pump();
      await tester.enterText(_dialogTextField(), 'myws');
      await tester.tap(_dialogButton('Next →'));
      await tester.pump();
      await tester.pump();

      // The in-app picker dialog is showing; dismiss it without choosing.
      expect(
        find.byKey(const Key('board-file-picker-search')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      verifyNever(
        () => wsCubit.addWorkspace(any(), customName: any(named: 'customName')),
      );
    });

    testWidgets('full flow adds workspace and offers additional folders', (
      tester,
    ) async {
      final tmp = Directory.systemTemp.createTempSync('ws_panel_test');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final proj = _createGitDir(tmp, 'proj');
      final extra = _createGitDir(tmp, 'extra');

      // `_addFolderToWorkspace` looks up the new workspace by name.
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [Workspace(id: 'ws_new', name: 'myws', paths: ['/x'])],
        ),
      );
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Add workspace'));
        await tester.pump();
        await tester.enterText(_dialogTextField(), 'myws');
        await tester.tap(_dialogButton('Next →'));
        await tester.pump();

        await _pickDirectory(tester, proj.path);

        // Step 3: the panel offers to add another folder.
        await _waitFor(tester, find.text('Add Another Folder?'));
        await tester.tap(_dialogButton('Add Folder'));
        await tester.pump();

        await _pickDirectory(tester, extra.path);

        // Second offer: decline to end the loop.
        await _waitFor(tester, find.text('Add Another Folder?'));
        await tester.tap(_dialogButton('Cancel'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      verify(
        () => wsCubit.addWorkspace(proj.path, customName: 'myws'),
      ).called(1);
      verify(() => wsCubit.addPathToWorkspace('ws_new', extra.path)).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('add folder to workspace', () {
    Future<void> openAddFolderPicker(
      WidgetTester tester,
      _MockWorkspaceCubit wsCubit,
    ) async {
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();
      await _hoverOver(tester, find.text('beta'));
      await _openTileMenu(tester);
      await tester.tap(find.text('Add Folder'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('choosing a folder calls addPathToWorkspace', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('ws_panel_test');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final folder = _createGitDir(tmp, 'lib');

      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await _hoverOver(tester, find.text('beta'));
        await tester.tap(find.byTooltip('More actions'));
        await tester.pump();
        // Popup-menu animation runs on the fake clock even inside runAsync.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Add Folder'));
        await tester.pump();

        await _pickDirectory(tester, folder.path);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      verify(() => wsCubit.addPathToWorkspace('ws_2', folder.path)).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('cancelling the picker does nothing', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [ws1, ws2],
          activeWorkspaceId: 'ws_1',
        ),
      );
      await openAddFolderPicker(tester, wsCubit);

      expect(
        find.byKey(const Key('board-file-picker-search')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      verifyNever(() => wsCubit.addPathToWorkspace(any(), any()));
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });

  group('remove folder from workspace', () {
    testWidgets('confirming path chip removal calls removePathFromWorkspace', (
      tester,
    ) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [
            Workspace(id: 'ws_9', name: 'multi', paths: ['/a/main', '/a/sub']),
          ],
        ),
      );
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();

      await _hoverOver(tester, find.text('sub'));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('Remove Folder'), findsOneWidget);

      await tester.tap(_dialogButton('Remove'));
      await tester.pump();

      verify(() => wsCubit.removePathFromWorkspace('ws_9', '/a/sub')).called(1);
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });

    testWidgets('cancelling path chip removal does nothing', (tester) async {
      final wsCubit = _stubWorkspaceCubit(
        const WorkspaceLoaded(
          workspaces: [
            Workspace(id: 'ws_9', name: 'multi', paths: ['/a/main', '/a/sub']),
          ],
        ),
      );
      await tester.pumpWidget(
        _buildPanel(
          workspaceCubit: wsCubit,
          reviewCubit: _stubReviewCubit(),
          terminalCubit: _stubTerminalCubit(),
        ),
      );
      await tester.pump();

      await _hoverOver(tester, find.text('sub'));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      await tester.tap(_dialogButton('Cancel'));
      await tester.pump();

      verifyNever(() => wsCubit.removePathFromWorkspace(any(), any()));
      await tester.pump(const Duration(seconds: 2)); // drain pending timers
    });
  });
}
