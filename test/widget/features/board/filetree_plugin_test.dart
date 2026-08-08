import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/filetree_plugin.dart';

void main() {
  const plugin = FileTreePlugin();

  test('typeId is board.filetree', () {
    expect(plugin.typeId, 'board.filetree');
    expect(FileTreePlugin.kTypeId, 'board.filetree');
  });

  test('displayName is File Tree', () {
    expect(plugin.displayName, 'File Tree');
  });

  test('icon is account_tree_outlined', () {
    expect(plugin.icon, Icons.account_tree_outlined);
  });

  test('accentColor is set', () {
    expect(plugin.accentColor, Colors.blueGrey);
  });

  test('defaultSize is 320x500', () {
    expect(plugin.defaultSize, const Size(320, 500));
  });

  test('initialState has expected keys', () {
    final state = plugin.initialState;
    expect(state.containsKey('rootPath'), isTrue);
    expect(state.containsKey('expandedDirs'), isTrue);
    expect(state.containsKey('selectedFile'), isTrue);
    expect(state['rootPath'], '');
    expect(state['expandedDirs'], <String>[]);
    expect(state['selectedFile'], '');
  });

  group('file tree content', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('yoloit_filetree_test_');
      Directory(p.join(fixture.path, 'sub')).createSync();
      File(p.join(fixture.path, 'alpha.txt')).writeAsStringSync('a');
      File(p.join(fixture.path, 'beta.md')).writeAsStringSync('b');
      File(
        p.join(fixture.path, 'sub', 'nested.dart'),
      ).writeAsStringSync('void main() {}');
      File(p.join(fixture.path, '.hidden')).writeAsStringSync('h');
    });

    tearDown(() {
      try {
        fixture.deleteSync(recursive: true);
      } on FileSystemException {
        // Already removed by a test (e.g. delete flow).
      }
    });

    testWidgets('shows select-folder prompt when no root is set', (
      tester,
    ) async {
      await tester.pumpWidget(_fileTreeApp(_PanelHarness(_emptyState())));
      await _pumpOut(tester);

      expect(find.text('Select a folder to browse'), findsOneWidget);
      expect(find.text('No folder selected'), findsOneWidget);
    });

    testWidgets('shows not-found message for a missing folder', (tester) async {
      final harness = _PanelHarness({
        ..._emptyState(),
        'rootPath': p.join(fixture.path, 'does-not-exist'),
      });
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      expect(find.text('Folder not found'), findsOneWidget);
    });

    testWidgets('renders directories first and expands them on tap', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      // Directories are sorted before files.
      final subPos = tester.getTopLeft(find.text('sub'));
      final alphaPos = tester.getTopLeft(find.text('alpha.txt'));
      expect(subPos.dy, lessThan(alphaPos.dy));
      expect(find.text('nested.dart'), findsNothing);

      await tester.tap(find.text('sub'));
      await _pumpOut(tester);

      expect(
        (harness.state['expandedDirs'] as List).cast<String>(),
        contains(p.join(fixture.path, 'sub')),
      );
      expect(find.text('nested.dart'), findsOneWidget);

      // Tapping again collapses the directory.
      await tester.tap(find.text('sub'));
      await _pumpOut(tester);
      expect(
        (harness.state['expandedDirs'] as List).cast<String>(),
        isNot(contains(p.join(fixture.path, 'sub'))),
      );
    });

    testWidgets('selecting a file stores it and opens a preview panel', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.text('alpha.txt'));
      await _pumpOut(tester);

      expect(harness.state['selectedFile'], p.join(fixture.path, 'alpha.txt'));
      expect(harness.linkedPanels, hasLength(1));
      expect(harness.linkedPanels.single.typeId, 'board.file.preview');
      expect(
        harness.linkedPanels.single.state['path'],
        p.join(fixture.path, 'alpha.txt'),
      );
    });

    testWidgets('visibility toggle hides dotfiles', (tester) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      expect(find.text('.hidden'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide dotfiles'));
      await _pumpOut(tester);
      expect(find.text('.hidden'), findsNothing);

      await tester.tap(find.byTooltip('Show dotfiles'));
      await _pumpOut(tester);
      expect(find.text('.hidden'), findsOneWidget);
    });

    testWidgets('refresh button touches panel state', (tester) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byTooltip('Refresh'));
      await _pumpOut(tester);

      expect(harness.state.containsKey('_refreshAt'), isTrue);
    });

    testWidgets('search finds matching entries in subdirectories', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byTooltip('Search files'));
      await _pumpOut(tester);
      await _enterSearch(tester, 'nested');

      // Relative path of the match deep inside `sub` is shown.
      expect(find.text(p.join('sub', 'nested.dart')), findsOneWidget);
    });

    testWidgets('search shows empty message when nothing matches', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byTooltip('Search files'));
      await _pumpOut(tester);
      await _enterSearch(tester, 'zzz-no-match');

      expect(find.text('No matching files'), findsOneWidget);
    });

    testWidgets('tapping a file search result selects the file', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byTooltip('Search files'));
      await _pumpOut(tester);
      await _enterSearch(tester, 'alpha');

      await tester.tap(find.text('alpha.txt'));
      await _pumpOut(tester);

      expect(harness.state['selectedFile'], p.join(fixture.path, 'alpha.txt'));
      expect(harness.linkedPanels.single.typeId, 'board.file.preview');
    });

    testWidgets('tapping a directory search result expands it in the tree', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byTooltip('Search files'));
      await _pumpOut(tester);
      await _enterSearch(tester, 'sub');

      await tester.tap(find.widgetWithText(InkWell, 'sub'));
      await _pumpOut(tester);

      expect(
        (harness.state['expandedDirs'] as List).cast<String>(),
        contains(p.join(fixture.path, 'sub')),
      );
      // Search UI is cleared and the regular tree is visible again.
      expect(find.byTooltip('Search files'), findsOneWidget);
      expect(find.text('nested.dart'), findsOneWidget);
    });

    testWidgets('context menu renames a file on disk', (tester) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await _runRealIo(tester, () async {
        await _secondaryTap(tester, find.text('alpha.txt'));
        expect(find.text('✏️ Rename'), findsOneWidget);
        // File entries offer no folder-only actions.
        expect(find.text('📁 New Folder'), findsNothing);

        await tester.tap(find.text('✏️ Rename'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField).last, 'renamed.txt');
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      expect(File(p.join(fixture.path, 'renamed.txt')).existsSync(), isTrue);
      expect(File(p.join(fixture.path, 'alpha.txt')).existsSync(), isFalse);
      expect(find.text('renamed.txt'), findsOneWidget);
    });

    testWidgets('context menu creates a new folder inside a directory', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await _runRealIo(tester, () async {
        await _secondaryTap(tester, find.text('sub'));
        expect(find.text('📁 New Folder'), findsOneWidget);
        expect(find.text('📄 New File'), findsOneWidget);

        await tester.tap(find.text('📁 New Folder'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField).last, 'created');
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      expect(
        Directory(p.join(fixture.path, 'sub', 'created')).existsSync(),
        isTrue,
      );
    });

    testWidgets('context menu deletes a file after confirmation', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await _runRealIo(tester, () async {
        await _secondaryTap(tester, find.text('beta.md'));
        await tester.tap(find.text('🗑️ Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Delete "beta.md"? This cannot be undone.'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      expect(File(p.join(fixture.path, 'beta.md')).existsSync(), isFalse);
    });

    testWidgets('diff tab reports folders that are not git repositories', (
      tester,
    ) async {
      final harness = _PanelHarness(_stateFor(fixture));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await _openDiffTab(tester);

      expect(find.text('Not a git repository'), findsOneWidget);
    });

    testWidgets('diff tab lists changes and opens a diff preview panel', (
      tester,
    ) async {
      final repo = Directory.systemTemp.createTempSync('yoloit_filetree_git_');
      addTearDown(() {
        try {
          repo.deleteSync(recursive: true);
        } on FileSystemException {
          // Ignore cleanup races.
        }
      });
      _initGitRepo(repo);
      final harness = _PanelHarness(_stateFor(repo));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await _openDiffTab(tester);

      expect(find.text('2 changed files'), findsOneWidget);
      expect(find.text('tracked.md'), findsOneWidget);
      expect(find.text('added.dart'), findsOneWidget);

      // Tapping a changed file opens the linked diff preview panel.
      await tester.tap(find.text('added.dart'));
      await _pumpOut(tester);
      expect(harness.linkedPanels.single.typeId, 'board.diff.preview');
      expect(harness.linkedPanels.single.state['filePath'], 'added.dart');
      expect(harness.linkedPanels.single.state['rootPath'], repo.path);
    });

    testWidgets('diff tab groups nested changes into expandable dir rows', (
      tester,
    ) async {
      final repo = Directory.systemTemp.createTempSync('yoloit_filetree_git_');
      addTearDown(() {
        try {
          repo.deleteSync(recursive: true);
        } on FileSystemException {
          // Ignore cleanup races.
        }
      });
      _initNestedGitRepo(repo);
      final harness = _PanelHarness(_stateFor(repo));
      await tester.pumpWidget(_fileTreeApp(harness));
      await _pumpOut(tester);

      await _openDiffTab(tester);

      expect(find.text('3 changed files'), findsOneWidget);
      // Directory rows (auto-expanded after load) show their file counts.
      expect(find.text('src'), findsOneWidget);
      expect(find.text('sub'), findsOneWidget);
      // Files inside expanded directories are listed with their names.
      expect(find.text('added.dart'), findsOneWidget);
      expect(find.text('deep.dart'), findsOneWidget);
      expect(find.text('inner.txt'), findsOneWidget);

      // Collapsing a directory hides its own files (sibling directory rows
      // are rendered flat and stay visible).
      await tester.tap(find.text('src'));
      await _pumpOut(tester);
      expect(find.text('added.dart'), findsNothing);
      expect(find.text('deep.dart'), findsOneWidget);
      expect(find.text('inner.txt'), findsOneWidget);

      // Expanding again brings them back.
      await tester.tap(find.text('src'));
      await _pumpOut(tester);
      expect(find.text('added.dart'), findsOneWidget);
    });
  });
}

// ── Harness ─────────────────────────────────────────────────────────────────

typedef _LinkedPanel =
    ({String typeId, Map<String, dynamic> state, String title});

class _PanelHarness {
  _PanelHarness(this.state);

  Map<String, dynamic> state;
  final List<Map<String, dynamic>> updates = [];
  final List<_LinkedPanel> linkedPanels = [];
}

Map<String, dynamic> _emptyState() => {
  'rootPath': '',
  'expandedDirs': <String>[],
  'selectedFile': '',
};

Map<String, dynamic> _stateFor(Directory root) => {
  'rootPath': root.path,
  'expandedDirs': <String>[],
  'selectedFile': '',
};

Widget _fileTreeApp(_PanelHarness harness) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 420,
        height: 640,
        child: _FileTreeHost(harness: harness),
      ),
    ),
  );
}

class _FileTreeHost extends StatefulWidget {
  const _FileTreeHost({required this.harness});

  final _PanelHarness harness;

  @override
  State<_FileTreeHost> createState() => _FileTreeHostState();
}

class _FileTreeHostState extends State<_FileTreeHost> {
  @override
  Widget build(BuildContext context) {
    final panel = BoardPanelInstance(
      id: 'filetree-test',
      type: FileTreePlugin.kTypeId,
      title: 'Files',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 640),
      state: widget.harness.state,
    );
    return const FileTreePlugin().buildContent(
      context,
      panel,
      BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onShowEditor: () {},
        onUpdateState: (next) {
          widget.harness.updates.add(next);
          setState(() => widget.harness.state = next);
        },
        onCreateLinkedPanel: (typeId, state, title) async {
          widget.harness.linkedPanels.add((
            typeId: typeId,
            state: state,
            title: title,
          ));
          return 'linked-panel';
        },
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Pumps a handful of short frames so animations and microtasks settle
/// without tripping over persistent animations (e.g. progress spinners).
Future<void> _pumpOut(WidgetTester tester, [int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Runs [body] on the real event loop so interactions that trigger real
/// filesystem or process work complete, then pumps the resulting frames.
/// (Futures started inside the fake test zone never resolve — the 220ms
/// search debounce, directory listings and `git` child processes all need
/// the real loop.)
Future<void> _runRealIo(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  await tester.runAsync(body);
  await _pumpOut(tester);
}

Future<void> _secondaryTap(WidgetTester tester, Finder target) async {
  await tester.tapAt(tester.getCenter(target), buttons: kSecondaryButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Types [query] into the search field and waits out the real debounce
/// timer plus the asynchronous filesystem walk.
Future<void> _enterSearch(WidgetTester tester, String query) async {
  await _runRealIo(tester, () async {
    await tester.enterText(find.byType(TextField), query);
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
}

/// Switches to the DIFF tab and waits for the real `git status` process.
Future<void> _openDiffTab(WidgetTester tester) async {
  await _runRealIo(tester, () async {
    await tester.tap(find.text('DIFF'));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
}

/// Turns [dir] into a git repository with one committed file, then leaves a
/// modification and an untracked file so `git status --porcelain` reports two
/// changed entries.
void _initGitRepo(Directory dir) {
  void git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: dir.path);
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  git(['init']);
  File(p.join(dir.path, 'tracked.md')).writeAsStringSync('v1');
  git(['add', 'tracked.md']);
  git([
    '-c', 'user.email=test@example.com', //
    '-c', 'user.name=Test',
    'commit', '-m', 'init',
  ]);
  File(p.join(dir.path, 'tracked.md')).writeAsStringSync('v2');
  File(p.join(dir.path, 'added.dart')).writeAsStringSync('void main() {}');
}

/// Like [_initGitRepo] but leaves changes in nested paths so the diff tree
/// groups them under directory rows: ` M sub/inner.txt`, `A  src/added.dart`
/// and `A  src/deep/deep.dart`.
void _initNestedGitRepo(Directory dir) {
  void git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: dir.path);
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  git(['init']);
  Directory(p.join(dir.path, 'sub')).createSync();
  File(p.join(dir.path, 'sub', 'inner.txt')).writeAsStringSync('v1');
  git(['add', '.']);
  git([
    '-c', 'user.email=test@example.com', //
    '-c', 'user.name=Test',
    'commit', '-m', 'init',
  ]);
  File(p.join(dir.path, 'sub', 'inner.txt')).writeAsStringSync('v2');
  Directory(p.join(dir.path, 'src', 'deep')).createSync(recursive: true);
  File(p.join(dir.path, 'src', 'added.dart')).writeAsStringSync('void a() {}');
  File(
    p.join(dir.path, 'src', 'deep', 'deep.dart'),
  ).writeAsStringSync('void d() {}');
  // Stage the new files so porcelain reports them individually ('A') instead
  // of collapsing the untracked `src/` directory into a single '??' entry.
  git(['add', 'src']);
}
