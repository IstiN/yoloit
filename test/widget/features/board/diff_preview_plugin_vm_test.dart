import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/diff_preview_plugin_vm.dart';

const String _kDiff =
    'diff --git a/lib/a.dart b/lib/a.dart\n'
    'index 111..222 100644\n'
    '--- a/lib/a.dart\n'
    '+++ b/lib/a.dart\n'
    '@@ -1,3 +1,3 @@\n'
    ' ctx-line\n'
    '-rem-line\n'
    '+add-line\n';

BoardPanelInstance _panel({String filePath = 'lib/a.dart', String rootPath = ''}) =>
    BoardPanelInstance(
      id: 'diff-1',
      type: 'board.diff.preview',
      title: 'Diff',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 500),
      state: {'filePath': filePath, 'rootPath': rootPath},
    );

Widget _harness(
  BoardPanelInstance panel, {
  Future<String?> Function(String, Map<String, dynamic>, String)?
  onCreateLinkedPanel,
}) {
  const plugin = DiffPreviewPlugin();
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 500,
        child: Builder(
          builder:
              (context) => plugin.buildContent(
                context,
                panel,
                BoardPanelRenderContext(
                  isSelected: false,
                  onFocus: () {},
                  onDelete: () {},
                  onUpdateState: (_) {},
                  onShowEditor: () {},
                  onCreateLinkedPanel: onCreateLinkedPanel,
                ),
              ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yoloit_diff_preview_test');
  });

  tearDown(() {
    diffPreviewProcessRun = Process.run;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void mockGit({String diffHead = '', String diff = '', String status = ''}) {
    diffPreviewProcessRun = (
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      if (arguments.contains('status')) return ProcessResult(0, 0, status, '');
      if (arguments.contains('HEAD')) return ProcessResult(0, 0, diffHead, '');
      return ProcessResult(0, 0, diff, '');
    };
  }

  testWidgets('loads and renders a unified diff, toggles to split view', (
    tester,
  ) async {
    mockGit(diffHead: _kDiff);

    await tester.pumpWidget(_harness(_panel(rootPath: tempDir.path)));
    await tester.pump();

    // Unified view renders all line kinds.
    expect(find.text('ctx-line'), findsOneWidget);
    expect(find.text('rem-line'), findsOneWidget);
    expect(find.text('add-line'), findsOneWidget);
    expect(
      find.textContaining('@@ -1,3 +1,3 @@'),
      findsOneWidget,
    );

    // Switch to side-by-side (context lines render in both columns).
    await tester.tap(find.text('Split'));
    await tester.pump();
    expect(find.text('ctx-line'), findsNWidgets(2));
    expect(find.text('rem-line'), findsOneWidget);
    expect(find.text('add-line'), findsOneWidget);

    // And back to unified.
    await tester.tap(find.text('Unified'));
    await tester.pump();
    expect(find.text('add-line'), findsOneWidget);
  });

  testWidgets('falls back to unstaged diff when HEAD diff is empty', (
    tester,
  ) async {
    mockGit(diff: _kDiff);

    await tester.pumpWidget(_harness(_panel(rootPath: tempDir.path)));
    await tester.pump();

    expect(find.text('add-line'), findsOneWidget);
  });

  testWidgets('shows "No changes" for a tracked file without diff', (
    tester,
  ) async {
    mockGit();

    await tester.pumpWidget(_harness(_panel(rootPath: tempDir.path)));
    await tester.pump();

    expect(find.text('No changes'), findsOneWidget);
  });

  testWidgets('shows untracked file content as all-new lines', (tester) async {
    await tester.runAsync(() async {
      File('${tempDir.path}/new.txt').writeAsStringSync('line one\nline two');
      mockGit(status: '?? new.txt');

      await tester.pumpWidget(
        _harness(_panel(filePath: 'new.txt', rootPath: tempDir.path)),
      );
      // Let the real file I/O in _showUntrackedFileContent complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('line one'), findsOneWidget);
      expect(find.text('line two'), findsOneWidget);
    });
  });

  testWidgets('shows "No changes" when untracked file is missing on disk', (
    tester,
  ) async {
    mockGit(status: '?? gone.txt');

    await tester.pumpWidget(
      _harness(_panel(filePath: 'gone.txt', rootPath: tempDir.path)),
    );
    await tester.pump();

    expect(find.text('No changes'), findsOneWidget);
  });

  testWidgets('shows placeholder when no file is selected', (tester) async {
    mockGit();

    await tester.pumpWidget(_harness(_panel(filePath: '')));
    await tester.pump();

    expect(find.text('No file selected'), findsOneWidget);
    expect(find.text('Diff Preview'), findsOneWidget);
  });

  testWidgets('shows error when git invocation fails', (tester) async {
    diffPreviewProcessRun = (
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      throw ProcessException('git', arguments);
    };

    await tester.pumpWidget(_harness(_panel(rootPath: tempDir.path)));
    await tester.pump();

    expect(find.textContaining('Failed to get diff'), findsOneWidget);
  });

  testWidgets('reloads when the file path changes', (tester) async {
    mockGit(diffHead: _kDiff);

    await tester.pumpWidget(_harness(_panel(rootPath: tempDir.path)));
    await tester.pump();
    expect(find.text('add-line'), findsOneWidget);

    mockGit();
    await tester.pumpWidget(
      _harness(_panel(filePath: 'lib/b.dart', rootPath: tempDir.path)),
    );
    await tester.pump();
    expect(find.text('No changes'), findsOneWidget);
  });

  testWidgets('open file preview creates a linked panel', (tester) async {
    mockGit(diffHead: _kDiff);
    final created = <List<Object?>>[];

    await tester.pumpWidget(
      _harness(
        _panel(rootPath: tempDir.path),
        onCreateLinkedPanel: (type, state, title) async {
          created.add([type, state, title]);
          return null;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Open file preview'));
    await tester.pump();

    expect(created, hasLength(1));
    expect(created.single[0], 'board.file.preview');
    final state = created.single[1]! as Map<String, dynamic>;
    expect(state['path'], '${tempDir.path}/lib/a.dart');
    expect(created.single[2], 'a.dart');
  });

  testWidgets('refresh button reloads the diff', (tester) async {
    var calls = 0;
    diffPreviewProcessRun = (
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      calls++;
      return ProcessResult(0, 0, _kDiff, '');
    };

    await tester.pumpWidget(_harness(_panel(rootPath: tempDir.path)));
    await tester.pump();
    final afterLoad = calls;

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    expect(calls, greaterThan(afterLoad));
  });
}
