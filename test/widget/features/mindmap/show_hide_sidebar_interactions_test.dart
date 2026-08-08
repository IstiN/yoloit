import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_cubit.dart';
import 'package:yoloit/features/mindmap/bloc/mindmap_state.dart';
import 'package:yoloit/features/mindmap/sidebar/show_hide_sidebar.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/review/bloc/review_state.dart';
import 'package:yoloit/features/review/models/review_models.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

class _MockReviewCubit extends Mock implements ReviewCubit {}

class _MockTerminalCubit extends Mock implements TerminalCubit {}

class _MockMindMapCubit extends Mock implements MindMapCubit {}

class _MockWorkspaceCubit extends Mock implements WorkspaceCubit {}

class _Callbacks {
  final toggledIds = <String>[];
  final toggledGroups = <List<String>>[];
  final focusedIds = <String>[];
  final toggledTypes = <String>[];
  final removedFolders = <(String, String)>[];
  final hiddenDescendants = <Set<String>>[];
  final shownDescendants = <Set<String>>[];
  var showAllCount = 0;
  var hideAllCount = 0;
  var createWorkspaceCount = 0;
}

_MockReviewCubit _reviewCubit([ReviewState? state]) {
  final cubit = _MockReviewCubit();
  when(() => cubit.state).thenReturn(state ?? const ReviewInitial());
  when(() => cubit.stream).thenAnswer((_) => const Stream<ReviewState>.empty());
  return cubit;
}

_MockTerminalCubit _terminalCubit() {
  final cubit = _MockTerminalCubit();
  when(() => cubit.state).thenReturn(
    TerminalLoaded(
      sessions: const [],
      activeIndex: 0,
      allSessions: [
        AgentSession(
          id: 's1',
          type: AgentType.copilot,
          workspacePath: '/tmp/alpha',
          customName: 'Copilot Session',
        ),
      ],
    ),
  );
  when(() => cubit.stream).thenAnswer((_) => const Stream<TerminalState>.empty());
  return cubit;
}

_MockMindMapCubit _mindMapCubit() {
  final cubit = _MockMindMapCubit();
  when(() => cubit.state).thenReturn(const MindMapState());
  when(() => cubit.stream).thenAnswer((_) => const Stream<MindMapState>.empty());
  return cubit;
}

_MockWorkspaceCubit _workspaceCubit() {
  final cubit = _MockWorkspaceCubit();
  when(() => cubit.state).thenReturn(const WorkspaceInitial());
  when(() => cubit.stream).thenAnswer((_) => const Stream<WorkspaceState>.empty());
  when(() => cubit.removeWorkspace(any())).thenAnswer((_) async {});
  return cubit;
}

ShowHideSidebarData _sampleData() {
  return const ShowHideSidebarData(
    workspaces: [
      ShowHideSidebarNode(
        id: 'ws:alpha',
        type: 'workspace',
        label: 'Alpha',
        hidden: false,
        path: '/tmp/alpha',
        children: [
          ShowHideSidebarNode(
            id: 'agent:s1',
            type: 'agent',
            label: 'Copilot Session',
            hidden: false,
            children: [
              ShowHideSidebarNode(
                id: 'repo:alpha:/tmp/repo',
                type: 'repo',
                label: 'inner-repo',
                hidden: false,
                children: [
                  ShowHideSidebarNode(
                    id: 'branch:1',
                    type: 'branch',
                    label: 'main',
                    hidden: false,
                  ),
                ],
              ),
            ],
          ),
          ShowHideSidebarNode(
            id: 'run:1',
            type: 'run',
            label: 'flutter test',
            hidden: true,
          ),
        ],
      ),
    ],
    orphans: [
      ShowHideSidebarNode(
        id: 'diff:1',
        type: 'diff',
        label: 'Diff View',
        hidden: false,
      ),
    ],
    hiddenCount: 1,
  );
}

Future<void> _pumpSidebar(
  WidgetTester tester,
  _Callbacks callbacks, {
  ReviewState? reviewState,
  _MockTerminalCubit? terminalCubit,
  _MockMindMapCubit? mindMapCubit,
  _MockWorkspaceCubit? workspaceCubit,
}) async {
  tester.view.physicalSize = const Size(560, 560);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ReviewCubit>.value(value: _reviewCubit(reviewState)),
        BlocProvider<TerminalCubit>.value(
          value: terminalCubit ?? _terminalCubit(),
        ),
        BlocProvider<MindMapCubit>.value(value: mindMapCubit ?? _mindMapCubit()),
        BlocProvider<WorkspaceCubit>.value(
          value: workspaceCubit ?? _workspaceCubit(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          extensions: [AppColorScheme.fromAccent(const Color(0xFF7C6BFF))],
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MindMapShowHideSidebar(
              data: _sampleData(),
              onToggleHide: callbacks.toggledIds.add,
              onToggleGroup: callbacks.toggledGroups.add,
              onFocusNode: callbacks.focusedIds.add,
              onShowAll: () => callbacks.showAllCount++,
              onHideAll: () => callbacks.hideAllCount++,
              onToggleType: callbacks.toggledTypes.add,
              onCreateWorkspace: () => callbacks.createWorkspaceCount++,
              onRemoveFolder:
                  (ws, path) => callbacks.removedFolders.add((ws, path)),
              onHideDescendants: callbacks.hiddenDescendants.add,
              onShowDescendants: callbacks.shownDescendants.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// Secondary (right) click and wait for the popup-menu open animation.
Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, buttons: kSecondaryMouseButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardText;
  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  group('MindMapShowHideSidebar interactions', () {
    testWidgets('collapse hides sidebar and toggle brings it back', (tester) async {
      await _pumpSidebar(tester, _Callbacks());

      expect(find.text('Show / Hide'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Show / Hide'), findsNothing);
      expect(find.byTooltip('Show sidebar'), findsOneWidget);

      await tester.tap(find.byTooltip('Show sidebar'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Show / Hide'), findsOneWidget);
    });

    testWidgets('dragging the resize handle changes sidebar width', (tester) async {
      await _pumpSidebar(tester, _Callbacks());

      final container = find
          .ancestor(of: find.text('Show / Hide'), matching: find.byType(Container))
          .first;
      expect(tester.getSize(container).width, 220);

      final handle = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeColumn,
      );
      // The handle is half outside the sidebar (Positioned right: -4), so its
      // exact center sits on the stack's right edge and misses the hit test.
      // Start the drag 3px inside the handle instead.
      await tester.dragFrom(
        tester.getCenter(handle) - const Offset(3, 0),
        const Offset(80, 0),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.getSize(container).width, 300);
    });

    testWidgets('header actions fire hide-all, show-all and create-workspace', (
      tester,
    ) async {
      final callbacks = _Callbacks();
      await _pumpSidebar(tester, callbacks);

      await tester.tap(find.text('Hide all'));
      await tester.pump();
      await tester.tap(find.text('Show all'));
      await tester.pump();
      await tester.tap(find.text('+ Workspace'));
      await tester.pump();

      expect(callbacks.hideAllCount, 1);
      expect(callbacks.showAllCount, 1);
      expect(callbacks.createWorkspaceCount, 1);
    });

    testWidgets('type filter chips report the tapped type', (tester) async {
      final callbacks = _Callbacks();
      await _pumpSidebar(tester, callbacks);

      await tester.tap(find.text('Sessions'));
      await tester.pump();
      await tester.tap(find.text('Branches'));
      await tester.pump();

      expect(callbacks.toggledTypes, ['agent', 'branch']);
    });

    testWidgets('workspace eye toggles the whole group', (tester) async {
      final callbacks = _Callbacks();
      await _pumpSidebar(tester, callbacks);

      await tester.tap(find.byIcon(Icons.visibility).first);
      await tester.pump();

      expect(callbacks.toggledGroups, [
        ['ws:alpha', 'agent:s1', 'repo:alpha:/tmp/repo', 'branch:1', 'run:1'],
      ]);
      expect(callbacks.toggledIds, isEmpty);
    });

    testWidgets('child eye toggles only that node', (tester) async {
      final callbacks = _Callbacks();
      await _pumpSidebar(tester, callbacks);

      await tester.tap(find.byIcon(Icons.visibility).at(1));
      await tester.pump();

      expect(callbacks.toggledIds, ['agent:s1']);
      expect(callbacks.toggledGroups, isEmpty);
    });

    testWidgets('tapping a parent row expands and collapses its children', (
      tester,
    ) async {
      await _pumpSidebar(tester, _Callbacks());

      expect(find.text('inner-repo'), findsNothing);
      await tester.tap(find.text('Copilot Session'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('inner-repo'), findsOneWidget);

      await tester.tap(find.text('Copilot Session'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('inner-repo'), findsNothing);
    });

    testWidgets('tapping a leaf row focuses the node', (tester) async {
      final callbacks = _Callbacks();
      await _pumpSidebar(tester, callbacks);

      await tester.tap(find.text('flutter test'));
      await tester.pump();

      expect(callbacks.focusedIds, ['run:1']);
    });

    testWidgets('quick filter narrows rows and the clear icon restores them', (
      tester,
    ) async {
      await _pumpSidebar(tester, _Callbacks());

      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('flutter test'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget); // matching descendant
      expect(find.text('Copilot Session'), findsNothing);
      expect(find.text('Diff View'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Copilot Session'), findsOneWidget);
      expect(find.text('Diff View'), findsOneWidget);
    });

    testWidgets('node context menu hides and shows descendants', (tester) async {
      final callbacks = _Callbacks();
      await _pumpSidebar(tester, callbacks);

      // Expand agent so the repo row (with children) is visible.
      await tester.tap(find.text('Copilot Session'));
      await tester.pump(const Duration(milliseconds: 50));

      await _rightClick(tester, find.text('inner-repo'));
      await _tapMenuItem(tester, 'Hide all below');
      expect(callbacks.hiddenDescendants, [
        {'branch:1'},
      ]);

      await _rightClick(tester, find.text('inner-repo'));
      await _tapMenuItem(tester, 'Show all below');
      expect(callbacks.shownDescendants, [
        {'branch:1'},
      ]);
    });

    testWidgets('repo folder context menu removes the folder', (tester) async {
      final callbacks = _Callbacks();
      await _pumpSidebar(tester, callbacks);

      await tester.tap(find.text('Copilot Session'));
      await tester.pump(const Duration(milliseconds: 50));

      await _rightClick(tester, find.text('inner-repo'));
      await _tapMenuItem(tester, 'Remove Folder');

      expect(callbacks.removedFolders, [('alpha', '/tmp/repo')]);
    });

    testWidgets('workspace context menu copies the folder path', (tester) async {
      await _pumpSidebar(tester, _Callbacks());

      await _rightClick(tester, find.text('Alpha'));
      await _tapMenuItem(tester, 'Copy path');

      expect(clipboardText, '/tmp/alpha');
    });

    testWidgets('workspace delete flow confirms via dialog', (tester) async {
      final workspaceCubit = _workspaceCubit();
      await _pumpSidebar(tester, _Callbacks(), workspaceCubit: workspaceCubit);

      await _rightClick(tester, find.text('Alpha'));
      await _tapMenuItem(tester, 'Delete workspace');

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      verify(() => workspaceCubit.removeWorkspace('alpha')).called(1);
    });

    testWidgets('workspace delete can be cancelled', (tester) async {
      final workspaceCubit = _workspaceCubit();
      await _pumpSidebar(tester, _Callbacks(), workspaceCubit: workspaceCubit);

      await _rightClick(tester, find.text('Alpha'));
      await _tapMenuItem(tester, 'Delete workspace');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => workspaceCubit.removeWorkspace(any()));
    });

    testWidgets('agent rename dialog renames the session', (tester) async {
      final terminalCubit = _terminalCubit();
      await _pumpSidebar(tester, _Callbacks(), terminalCubit: terminalCubit);

      await _rightClick(tester, find.text('Copilot Session'));
      await _tapMenuItem(tester, 'Rename Session');

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Renamed Session');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      verify(
        () => terminalCubit.renameSession('s1', 'Renamed Session'),
      ).called(1);
    });

    testWidgets('agent rename cancel leaves the session untouched', (
      tester,
    ) async {
      final terminalCubit = _terminalCubit();
      await _pumpSidebar(tester, _Callbacks(), terminalCubit: terminalCubit);

      await _rightClick(tester, find.text('Copilot Session'));
      await _tapMenuItem(tester, 'Rename Session');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => terminalCubit.renameSession(any(), any()));
    });

    testWidgets('agent close dialog pause hides the node', (tester) async {
      final mindMapCubit = _mindMapCubit();
      await _pumpSidebar(tester, _Callbacks(), mindMapCubit: mindMapCubit);

      await _rightClick(tester, find.text('Copilot Session'));
      await _tapMenuItem(tester, 'Delete Session');

      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      verify(() => mindMapCubit.hideNode('agent:s1')).called(1);
    });

    testWidgets('agent close dialog kill closes the session', (tester) async {
      final terminalCubit = _terminalCubit();
      await _pumpSidebar(tester, _Callbacks(), terminalCubit: terminalCubit);

      await _rightClick(tester, find.text('Copilot Session'));
      await _tapMenuItem(tester, 'Delete Session');

      await tester.tap(find.text('Kill Forever'));
      await tester.pumpAndSettle();

      verify(() => terminalCubit.closeSession('s1')).called(1);
    });

    testWidgets('diff rows show the changed-files badge', (tester) async {
      await _pumpSidebar(
        tester,
        _Callbacks(),
        reviewState: const ReviewLoaded(
          fileTree: [],
          changedFiles: [
            FileChange(path: 'a.dart', status: FileChangeStatus.modified),
            FileChange(path: 'b.dart', status: FileChangeStatus.added),
          ],
        ),
      );

      expect(find.text('2'), findsOneWidget);
    });
  });
}
