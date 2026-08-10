import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/editor/ui/file_editor_panel.dart';
import 'package:yoloit/features/editor/utils/editor_panel_logic.dart';
import 'package:yoloit/ui/shell/main_shell.dart';

// ── Fakes ───────────────────────────────────────────────────────────────────

class _FakeBoardCubit extends BoardCubit {
  _FakeBoardCubit({
    List<BoardDocument> initialBoards = const [],
    String? initialActiveBoardId,
  }) : _boards = initialBoards,
       _activeBoardId = initialActiveBoardId;

  final List<BoardDocument> _boards;
  final String? _activeBoardId;
  final List<String> focusedPanels = [];

  @override
  Future<void> load() async {
    emit(
      BoardState(
        boards: _boards,
        activeBoardId: _activeBoardId,
        isLoaded: true,
      ),
    );
  }

  @override
  Future<void> focusPanel(
    String panelId, {
    String? boardId,
    bool zoomOnFocus = false,
  }) async {
    focusedPanels.add(panelId);
  }
}

// ── Harness ─────────────────────────────────────────────────────────────────

Widget _rowHarness({
  required SessionStat session,
  required BoardCubit boardCubit,
  VoidCallback? onClose,
}) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: BlocProvider<BoardCubit>.value(
      value: boardCubit,
      child: Scaffold(
        body: SessionRowTestWrapper(
          session: session,
          boardCubit: boardCubit,
          onClose: onClose,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app.setupCompleted': true});
    await ThemeManager.instance.load();
  });

  // ── #15: _SessionRow.build ────────────────────────────────────────────────
  group('_SessionRow.build', () {
    testWidgets('renders label, pid, and cpu from metadata session', (tester) async {
      const session = SessionStat(
        pid: 4242,
        label: 'copilot',
        cpuPercent: 12.5,
        memoryBytes: 1048576,
        metadata: ResourceSessionMetadata(
          kind: 'ai chat',
          boardId: 'b1',
          boardName: 'MyBoard',
          panelId: 'panel-1',
          workspacePath: '/repo',
        ),
      );

      final board = _FakeBoardCubit(
        initialBoards: const [BoardDocument(id: 'b1', name: 'MyBoard')],
        initialActiveBoardId: 'b1',
      );
      addTearDown(board.close);
      await board.load();

      await tester.pumpWidget(_rowHarness(session: session, boardCubit: board));
      await tester.pump();

      // displayLabel = 'AI Chat · MyBoard' (from metadata).
      expect(find.textContaining('AI Chat'), findsOneWidget);
      // Details include board name, workspacePath, and pid.
      expect(find.textContaining('MyBoard'), findsWidgets);
      expect(find.textContaining('pid 4242'), findsOneWidget);
      // CPU percent is rendered.
      expect(find.textContaining('12.5%'), findsOneWidget);
      // Memory rendered via formatBytes → '1 MB'.
      expect(find.textContaining('MB'), findsWidgets);

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders fallback label when metadata is absent', (tester) async {
      const session = SessionStat(
        pid: 99,
        label: 'copilot_1234567890',
        cpuPercent: 0.0,
        memoryBytes: 0,
      );

      final board = _FakeBoardCubit();
      addTearDown(board.close);
      await board.load();

      await tester.pumpWidget(_rowHarness(session: session, boardCubit: board));
      await tester.pump();

      // Without metadata, formatSessionLabel strips the numeric suffix.
      // 'copilot_1234567890' → 'Copilot'.
      expect(find.textContaining('Copilot'), findsOneWidget);
      // When metadata is null the details row is not rendered, so pid text
      // should be absent.
      expect(find.textContaining('pid 99'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('tap triggers _open without crash', (tester) async {
      const session = SessionStat(
        pid: 77,
        label: 'copilot',
        cpuPercent: 1.0,
        memoryBytes: 512,
        metadata: ResourceSessionMetadata(
          kind: 'ai chat',
          boardId: 'b1',
          boardName: 'TestBoard',
          panelId: 'panel-77',
        ),
      );

      final board = _FakeBoardCubit(
        initialBoards: const [BoardDocument(id: 'b1', name: 'TestBoard')],
        initialActiveBoardId: 'b1',
      );
      addTearDown(board.close);
      await board.load();

      await tester.pumpWidget(_rowHarness(session: session, boardCubit: board));
      await tester.pump();

      // Tap the InkWell — should call _open → openResourceSessionPanel.
      await tester.tap(find.byType(Tooltip).first);
      await tester.pump();

      // focusPanel should have been called.
      expect(board.focusedPanels, ['panel-77']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows different icon when panelId is empty', (tester) async {
      const sessionNoPanel = SessionStat(
        pid: 10,
        label: 'claude',
        cpuPercent: 5.0,
        memoryBytes: 2048,
        metadata: ResourceSessionMetadata(kind: 'terminal'),
      );

      final board = _FakeBoardCubit();
      addTearDown(board.close);
      await board.load();

      await tester.pumpWidget(
        _rowHarness(session: sessionNoPanel, boardCubit: board),
      );
      await tester.pump();

      // canFocus = false (no panelId) → Icons.circle (size 5).
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.circle && w.size == 5,
        ),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('shows focus icon when panelId is present', (tester) async {
      const sessionWithPanel = SessionStat(
        pid: 20,
        label: 'gemini',
        cpuPercent: 3.0,
        memoryBytes: 4096,
        metadata: ResourceSessionMetadata(
          kind: 'ai chat',
          panelId: 'panel-x',
        ),
      );

      final board = _FakeBoardCubit();
      addTearDown(board.close);
      await board.load();

      await tester.pumpWidget(
        _rowHarness(session: sessionWithPanel, boardCubit: board),
      );
      await tester.pump();

      // canFocus = true → Icons.center_focus_strong_outlined (size 9).
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              w.icon == Icons.center_focus_strong_outlined &&
              w.size == 9,
        ),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    });
  });

  // ── #17: _WindowControls helpers (winBtnHoverColor / winBtnIconColor) ──────
  //
  // The _WindowControls StatefulWidget calls windowManager in initState,
  // which requires a native platform channel unavailable in headless tests.
  // We directly test the @visibleForTesting color helpers used by _WinBtn.build
  // to cover the branching logic.

  group('winBtnHoverColor / winBtnIconColor', () {
    AppColorScheme colors() =>
        AppThemePreset.neonPurple.theme.extension<AppColorScheme>()!;

    test('winBtnHoverColor returns error for close, muted wash otherwise', () {
      final c = colors();

      expect(winBtnHoverColor(isClose: true, colors: c), c.statusError);
      expect(
        winBtnHoverColor(isClose: false, colors: c),
        c.textMuted.withAlpha(40),
      );
    });

    test('winBtnIconColor returns textPrimary for hovered-close, fallback otherwise', () {
      final c = colors();
      const fallback = Color(0xFFAAAAAA);

      expect(
        winBtnIconColor(
          hovered: true,
          isClose: true,
          colors: c,
          fallbackColor: fallback,
        ),
        c.textPrimary,
      );
      expect(
        winBtnIconColor(
          hovered: false,
          isClose: true,
          colors: c,
          fallbackColor: fallback,
        ),
        fallback,
      );
      expect(
        winBtnIconColor(
          hovered: true,
          isClose: false,
          colors: c,
          fallbackColor: fallback,
        ),
        fallback,
      );
    });
  });

  // ── #25: _loadGitGutter ──────────────────────────────────────────────────
  //
  // _loadGitGutter is a private method in _EditorBodyState. It checks
  // widget.tab.workspacePath (returns early if null), checks widget.tab.isDiff
  // (returns early if true), then calls GitService.instance.getDiff.
  // GitService is a const singleton with no test seam. We test the branches
  // we can reach through widget tests, and verify parseDiffMarkers on a
  // real git diff for the core logic path.

  group('_loadGitGutter', () {
    Widget editorHarness(FileEditorState state) {
      return BlocProvider<FileEditorCubit>(
        create: (_) => FileEditorCubit()..emit(state),
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const Scaffold(body: FileEditorPanel()),
        ),
      );
    }

    testWidgets('null workspacePath returns early without crash', (tester) async {
      await tester.pumpWidget(
        editorHarness(
          FileEditorState(
            isVisible: true,
            activeIndex: 0,
            tabs: [
              EditorTab(
                filePath: '/workspace/main.dart',
                content: 'class Foo {}',
                originalContent: 'class Foo {}',
                // workspacePath null → early return.
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      // Let any async git call settle.
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(FileEditorPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('isDiff tab skips _loadGitGutter', (tester) async {
      await tester.pumpWidget(
        editorHarness(
          FileEditorState(
            isVisible: true,
            activeIndex: 0,
            tabs: [
              EditorTab(
                filePath: 'diff:/workspace/main.dart',
                content: 'diff content',
                originalContent: 'diff content',
                workspacePath: '/workspace',
                diffHunks: const [],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(FileEditorPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('parseDiffMarkers on real git diff output produces markers', () async {
      // Create a temporary git repo with a committed file, then modify it.
      final tmpDir = await Directory.systemTemp.createTemp('git_gutter_test');
      addTearDown(() => tmpDir.delete(recursive: true));

      await Process.run('git', ['init'], workingDirectory: tmpDir.path);
      await Process.run(
        'git',
        ['config', 'user.email', 'test@test.com'],
        workingDirectory: tmpDir.path,
      );
      await Process.run(
        'git',
        ['config', 'user.name', 'Test'],
        workingDirectory: tmpDir.path,
      );

      final file = File('${tmpDir.path}/main.dart');
      await file.writeAsString('void main() {}\n');
      await Process.run(
        'git',
        ['add', 'main.dart'],
        workingDirectory: tmpDir.path,
      );
      await Process.run(
        'git',
        ['commit', '-m', 'init'],
        workingDirectory: tmpDir.path,
      );

      // Modify the file to produce a diff.
      await file.writeAsString('void main() {\n  print(1);\n}\n');

      final diffResult = await Process.run(
        'git',
        ['diff', 'HEAD', '--', 'main.dart'],
        workingDirectory: tmpDir.path,
      );
      final diffOutput = diffResult.stdout.toString();
      expect(diffOutput, isNotEmpty);

      // This is the exact logic _loadGitGutter uses after getDiff returns.
      final markers = parseDiffMarkers(diffOutput);
      expect(markers, isNotEmpty);
      expect(markers.values.toSet().contains(GutterMarkerType.added), isTrue);
    });

    testWidgets('loads git gutter markers from a real git repo with modified file',
        skip: 'async git deadlock in full suite', (tester) async {
      // Create a real git repo, commit a file, modify it, then open the
      // editor pointed at that repo so _loadGitGutter calls GitService.getDiff
      // and parses the diff into _gitMarkers.
      final tmpDir =
          await Directory.systemTemp.createTemp('git_gutter_integration');
      addTearDown(() => tmpDir.delete(recursive: true));

      await Process.run('git', ['init'], workingDirectory: tmpDir.path);
      await Process.run(
        'git',
        ['config', 'user.email', 'test@test.com'],
        workingDirectory: tmpDir.path,
      );
      await Process.run(
        'git',
        ['config', 'user.name', 'Test'],
        workingDirectory: tmpDir.path,
      );

      final file = File('${tmpDir.path}/main.dart');
      await file.writeAsString('void main() {}\n');
      await Process.run(
        'git',
        ['add', 'main.dart'],
        workingDirectory: tmpDir.path,
      );
      await Process.run(
        'git',
        ['commit', '-m', 'init'],
        workingDirectory: tmpDir.path,
      );

      // Modify the file to produce a diff.
      await file.writeAsString('void main() {\n  print(1);\n}\n');

      await tester.pumpWidget(
        editorHarness(
          FileEditorState(
            isVisible: true,
            activeIndex: 0,
            tabs: [
              EditorTab(
                filePath: '${tmpDir.path}/main.dart',
                content: 'void main() {\n  print(1);\n}\n',
                originalContent: 'void main() {}\n',
                workspacePath: tmpDir.path,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      // Give the async git diff call time to complete.
      await tester.pump(const Duration(seconds: 3));

      // The editor should render without errors and the gutter markers
      // should have been loaded (line 1126-1128 of _loadGitGutter).
      expect(find.byType(FileEditorPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Skipped: hangs in full-suite (async git process deadlock under
    // testWidgets fake-async). The method itself is exercised by the
    // unit test in file_editor_panel_quickfind_test.dart.
    testWidgets('_loadGitGutter does nothing for a non-git workspace path',
        skip: 'async git deadlock in full suite', (tester) async {
      await tester.pumpWidget(
        editorHarness(
          FileEditorState(
            isVisible: true,
            activeIndex: 0,
            tabs: [
              EditorTab(
                filePath: '/nonexistent/workspace/main.dart',
                content: 'void main() {}',
                originalContent: 'void main() {}',
                workspacePath: '/nonexistent/workspace',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(FileEditorPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
