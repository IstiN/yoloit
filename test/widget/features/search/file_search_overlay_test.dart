import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/search/ui/file_search_overlay.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

import '../../../helpers/fake_board_cubit.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zqroot');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String writeFile(String name, [String content = '']) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file.path;
  }

  BoardPanelInstance panel(
    String id,
    String type,
    String title, {
    Map<String, dynamic> state = const {},
    bool hidden = false,
  }) {
    return BoardPanelInstance(
      id: id,
      type: type,
      title: title,
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      state: state,
      hidden: hidden,
    );
  }

  Future<void> openOverlay(
    WidgetTester tester, {
    required FakeBoardCubit boardCubit,
    WorkspaceCubit? workspaceCubit,
    FileEditorCubit? editorCubit,
    VoidCallback? onFileOpened,
    void Function(String filePath)? onFileSelected,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<BoardCubit>.value(value: boardCubit),
          BlocProvider<WorkspaceCubit>.value(
            value: workspaceCubit ?? WorkspaceCubit(),
          ),
          BlocProvider<ReviewCubit>.value(value: ReviewCubit()),
          BlocProvider<FileEditorCubit>.value(
            value: editorCubit ?? FileEditorCubit(),
          ),
        ],
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => showFileSearch(
                            context,
                            onFileOpened: onFileOpened ?? () {},
                            onFileSelected: onFileSelected,
                          ),
                      child: const Text('open-search'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-search'));
    await tester.pumpAndSettle();
    expect(find.byType(FileSearchOverlay), findsOneWidget);
  }

  /// Types [query] and waits for the debounced async search (real file
  /// system I/O) to finish, then rebuilds.
  /// Gives the real event loop repeated turns so that the staged real
  /// file-system I/O of a search/open (path probe → file tree scan →
  /// workspace scan) can complete one stage per round.
  Future<void> flushRealIo(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    // Advance the fake clock past the 150 ms debounce so the timer fires.
    await tester.pump(const Duration(milliseconds: 200));
    await flushRealIo(tester);
  }

  Future<void> pressEnter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // Opening results may await real file-system I/O.
    await flushRealIo(tester);
    await tester.pumpAndSettle();
  }

  Future<void> pressArrow(
    WidgetTester tester,
    LogicalKeyboardKey key,
    int times,
  ) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
  }

  /// Matches the highlighted result-tile title. Plain [Text] widgets also
  /// build an internal [RichText], so restrict to the per-character span
  /// structure that _HighlightText produces.
  Finder tileWithTitle(String title) {
    return find.byWidgetPredicate((widget) {
      if (widget is! RichText) return false;
      final span = widget.text;
      return span is TextSpan &&
          span.children != null &&
          span.toPlainText() == title;
    });
  }

  group('FileSearchOverlay', () {
    testWidgets('shows hint and shortcuts when the query is empty', (
      tester,
    ) async {
      await openOverlay(tester, boardCubit: FakeBoardCubit());

      expect(
        find.text('Type to search boards, panels & files…'),
        findsOneWidget,
      );
      expect(find.text('↑↓ navigate  ↵ open  esc close'), findsOneWidget);
      // Footer is hidden while there are no results.
      expect(find.textContaining('result'), findsNothing);
    });

    testWidgets('matches boards and panels, shows footer counts, escapes', (
      tester,
    ) async {
      final boardCubit = FakeBoardCubit()
        ..addFakeBoard(const BoardDocument(id: 'b-home', name: 'Home Board'))
        ..addFakeBoard(
          BoardDocument(
            id: 'b-road',
            name: 'Product Roadmap',
            panels: [
              panel('p-r', 'board.note.markdown', 'Roadmap Panel'),
            ],
          ),
        );
      await openOverlay(tester, boardCubit: boardCubit);

      await search(tester, 'roadmap');

      expect(tileWithTitle('Product Roadmap'), findsOneWidget);
      expect(tileWithTitle('Roadmap Panel'), findsOneWidget);
      // Board subtitle counts its visible panels.
      expect(find.text('1 panel'), findsNWidgets(2)); // subtitle + footer
      expect(find.text('1 board'), findsOneWidget);
      expect(find.text(' · '), findsOneWidget);
      expect(find.text('2 results'), findsOneWidget);
      expect(find.text('Product Roadmap · Markdown Note'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(FileSearchOverlay), findsNothing);
    });

    testWidgets('matches panel titles but skips hidden panels', (tester) async {
      final boardCubit = FakeBoardCubit()
        ..addFakePanel(panel('p-term', 'board.terminal', 'Build Server'))
        ..addFakePanel(
          panel('p-hid', 'board.terminal', 'Build Hidden', hidden: true),
        );
      await openOverlay(tester, boardCubit: boardCubit);

      await search(tester, 'build');

      expect(tileWithTitle('Build Server'), findsOneWidget);
      expect(tileWithTitle('Build Hidden'), findsNothing);
      expect(find.text('Test Board · Terminal'), findsOneWidget);
      expect(find.text('1 panel'), findsOneWidget);
      expect(find.text('1 result'), findsOneWidget);
    });

    testWidgets('matches nested panel state content and shows a snippet', (
      tester,
    ) async {
      const longText =
          'lorem ipsum dolor sit amet consectetur adipiscing elit sed do '
          'eiusmod tempor alpha incididunt ut labore et dolore magna aliqua '
          'ut enim ad minim veniam quis nostrud exercitation ullamco';
      final boardCubit = FakeBoardCubit()
        ..addFakePanel(
          panel('p-notes', 'board.note.markdown', 'Notes', state: {
            'markdown': longText,
            'nested': {
              'items': ['beta', 'gamma'],
              'count': 7,
              'enabled': true,
            },
            'empty': null,
            'blank': '   ',
            'id': 'skip-me',
            'timestamp': 'skip-me-too',
          }),
        );
      await openOverlay(tester, boardCubit: boardCubit);

      await search(tester, 'alpha');

      // The query matches only panel state content, not the title, so the
      // title renders as plain text while the preview shows a snippet.
      expect(find.text('Notes'), findsOneWidget);
      // Snippet is truncated on both sides around the match.
      expect(find.textContaining('…'), findsWidgets);
    });

    testWidgets('shows empty result message and clear button resets', (
      tester,
    ) async {
      final boardCubit = FakeBoardCubit()
        ..addFakePanel(panel('p-term', 'board.terminal', 'Build Server'));
      await openOverlay(tester, boardCubit: boardCubit);

      await search(tester, 'zzqqx');
      expect(find.text('No results found'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      // Fire the debounce scheduled by clearing the controller.
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('Type to search boards, panels & files…'),
        findsOneWidget,
      );
    });

    testWidgets('collects file tree and workspace results with dedupe', (
      tester,
    ) async {
      final filePath = writeFile('space_doc.md', '# doc');
      // Note: FakeBoardCubit.addFakePanel keeps only the active board,
      // so panels must be added before extra boards.
      final boardCubit = FakeBoardCubit()
        ..addFakePanel(
          panel(
            'p-tree',
            'board.filetree',
            'Files',
            state: {'rootPath': tempDir.path},
          ),
        )
        ..addFakeBoard(
          BoardDocument(
            id: 'b-2',
            name: 'SpDoc Hub',
            panels: [panel('p-sn', 'board.note.markdown', 'SpDoc Notes')],
          ),
        );
      final workspaceCubit =
          WorkspaceCubit()
            ..emit(
              WorkspaceLoaded(
                workspaces: [
                  Workspace(id: 'ws1', name: 'ws', paths: [tempDir.path]),
                ],
                // Unknown id forces fallback to the first workspace.
                activeWorkspaceId: 'unknown',
              ),
            );
      await openOverlay(
        tester,
        boardCubit: boardCubit,
        workspaceCubit: workspaceCubit,
      );

      await search(tester, 'spdoc');

      expect(tileWithTitle('SpDoc Hub'), findsOneWidget);
      expect(tileWithTitle('SpDoc Notes'), findsOneWidget);
      expect(tileWithTitle('space_doc.md'), findsOneWidget);
      // File tree and workspace hits for the same file are deduplicated.
      expect(find.text('space_doc.md'), findsOneWidget);
      expect(find.text('1 board'), findsOneWidget);
      expect(find.text('1 panel'), findsNWidgets(2)); // subtitle + footer
      expect(find.text('1 file'), findsOneWidget);
      expect(find.text(' · '), findsNWidgets(2));
      expect(find.text('3 results'), findsOneWidget);
      expect(filePath, isNotEmpty);
    });

    testWidgets('enter on a board result switches the active board', (
      tester,
    ) async {
      final boardCubit = FakeBoardCubit()
        ..addFakeBoard(
          BoardDocument(
            id: 'b-2',
            name: 'Beta Space',
            panels: [panel('p-sn', 'board.note.markdown', 'Space Notes')],
          ),
        );
      await openOverlay(tester, boardCubit: boardCubit);
      await search(tester, 'space');

      await pressEnter(tester);

      expect(boardCubit.state.activeBoardId, 'b-2');
      expect(find.byType(FileSearchOverlay), findsNothing);
    });

    testWidgets('arrow down then enter focuses the panel result', (
      tester,
    ) async {
      final boardCubit = FakeBoardCubit()
        ..addFakeBoard(
          BoardDocument(
            id: 'b-2',
            name: 'Beta Space',
            panels: [panel('p-sn', 'board.note.markdown', 'Space Notes')],
          ),
        );
      await openOverlay(tester, boardCubit: boardCubit);
      await search(tester, 'space');

      await pressArrow(tester, LogicalKeyboardKey.arrowDown, 1);
      await pressEnter(tester);

      expect(boardCubit.state.activeBoardId, 'b-2');
      expect(boardCubit.focusedPanelIds, contains('p-sn'));
      expect(find.byType(FileSearchOverlay), findsNothing);
    });

    testWidgets('arrow navigation clamps and scrolls the selection', (
      tester,
    ) async {
      final boardCubit = FakeBoardCubit();
      for (var i = 0; i < 12; i++) {
        final suffix = i.toString().padLeft(2, '0');
        boardCubit.addFakePanel(
          panel('p$suffix', 'board.chat', 'Panel $suffix'),
        );
      }
      await openOverlay(tester, boardCubit: boardCubit);
      await search(tester, 'panel');
      expect(tileWithTitle('Panel 00'), findsOneWidget);

      // Move past the visible viewport — the list scrolls down.
      await pressArrow(tester, LogicalKeyboardKey.arrowDown, 9);
      expect(tileWithTitle('Panel 09'), findsOneWidget);

      // Clamp back to the first result — the list scrolls back up.
      await pressArrow(tester, LogicalKeyboardKey.arrowUp, 20);
      expect(tileWithTitle('Panel 00'), findsOneWidget);

      await pressArrow(tester, LogicalKeyboardKey.arrowDown, 3);
      await pressEnter(tester);
      expect(boardCubit.focusedPanelIds, contains('p03'));
    });

    testWidgets('file result uses the onFileSelected callback', (tester) async {
      final filePath = writeFile('open_me.dart', 'void main() {}');
      var opened = false;
      String? selected;
      final boardCubit = FakeBoardCubit()
        ..addFakePanel(
          panel(
            'p-tree',
            'board.filetree',
            'Files',
            state: {'rootPath': tempDir.path},
          ),
        );
      await openOverlay(
        tester,
        boardCubit: boardCubit,
        onFileOpened: () => opened = true,
        onFileSelected: (path) => selected = path,
      );
      await search(tester, 'openme');

      await pressEnter(tester);

      expect(selected, filePath);
      expect(opened, isTrue);
      // No preview panel is created when a callback handles the file.
      expect(
        boardCubit.state.activeBoard!.panels
            .where((p) => p.type == 'board.file.preview'),
        isEmpty,
      );
      expect(find.byType(FileSearchOverlay), findsNothing);
    });

    testWidgets('file result without callback adds a preview panel', (
      tester,
    ) async {
      final filePath = writeFile('open_me.dart', 'void main() {}');
      var opened = false;
      final boardCubit = FakeBoardCubit()
        ..addFakePanel(
          panel(
            'p-tree',
            'board.filetree',
            'Files',
            state: {'rootPath': tempDir.path},
          ),
        );
      await openOverlay(
        tester,
        boardCubit: boardCubit,
        onFileOpened: () => opened = true,
      );
      await search(tester, 'openme');

      await pressEnter(tester);

      final previews =
          boardCubit.state.activeBoard!.panels
              .where((p) => p.type == 'board.file.preview')
              .toList();
      expect(previews, hasLength(1));
      expect(previews.single.state['path'], filePath);
      expect(boardCubit.focusedPanelIds, contains(previews.single.id));
      expect(opened, isTrue);
    });

    testWidgets('file result focuses an existing preview panel instead', (
      tester,
    ) async {
      final filePath = writeFile('open_me.dart', 'void main() {}');
      final boardCubit = FakeBoardCubit()
        ..addFakePanel(
          panel(
            'pv-1',
            'board.file.preview',
            'open_me.dart',
            state: {'path': filePath, 'title': 'open_me.dart'},
          ),
        )
        ..addFakePanel(
          panel(
            'p-tree',
            'board.filetree',
            'Files',
            state: {'rootPath': tempDir.path},
          ),
        );
      await openOverlay(tester, boardCubit: boardCubit);
      await search(tester, 'openme');

      // First result is the existing panel; the file result is second.
      await pressArrow(tester, LogicalKeyboardKey.arrowDown, 1);
      await pressEnter(tester);

      expect(
        boardCubit.state.activeBoard!.panels
            .where((p) => p.type == 'board.file.preview'),
        hasLength(1),
      );
      expect(boardCubit.focusedPanelIds, ['pv-1']);
    });

    testWidgets('typing an existing path opens it before the search runs', (
      tester,
    ) async {
      final filePath = writeFile('direct.txt', 'hello');
      String? selected;
      final boardCubit = FakeBoardCubit();
      await openOverlay(
        tester,
        boardCubit: boardCubit,
        onFileSelected: (path) => selected = path,
      );

      // Press enter before the 150 ms debounce fires: the result list is
      // still empty, so the overlay falls back to resolving the typed path.
      await tester.enterText(find.byType(TextField), filePath);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(selected, filePath);
      expect(find.byType(FileSearchOverlay), findsNothing);
    });

    testWidgets('enter with no results and no matching path stays open', (
      tester,
    ) async {
      var selected = false;
      final boardCubit = FakeBoardCubit();
      await openOverlay(
        tester,
        boardCubit: boardCubit,
        onFileSelected: (_) => selected = true,
      );
      await search(tester, 'zzqqx');
      expect(find.text('No results found'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      expect(selected, isFalse);
      expect(find.byType(FileSearchOverlay), findsOneWidget);
    });

    testWidgets('file result with no active board opens the editor', (
      tester,
    ) async {
      final filePath = writeFile('loose.md', 'hello loose');
      var opened = false;
      // BoardState.activeBoard falls back to the first board, so the
      // "no board" branch requires an empty board list.
      final boardCubit = FakeBoardCubit();
      boardCubit.emit(
        boardCubit.state.copyWith(boards: [], clearActiveBoardId: true),
      );
      final editorCubit = FileEditorCubit();
      await openOverlay(
        tester,
        boardCubit: boardCubit,
        editorCubit: editorCubit,
        onFileOpened: () => opened = true,
      );
      // No file tree roots exist, but typing an existing file path
      // surfaces it as a result directly.
      await search(tester, filePath);

      await pressEnter(tester);

      expect(
        editorCubit.state.tabs.any((tab) => tab.filePath == filePath),
        isTrue,
      );
      expect(opened, isTrue);
      expect(find.byType(FileSearchOverlay), findsNothing);
    });
  });
}
