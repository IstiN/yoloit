import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/editor/bloc/file_editor_state.dart';
import 'package:yoloit/features/editor/ui/file_editor_panel.dart';
import 'package:yoloit/features/review/models/review_models.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

FileEditorCubit _cubitWith({
  required String filePath,
  required String content,
  List<DiffHunk>? diffHunks,
}) {
  return FileEditorCubit()..emit(
    FileEditorState(
      isVisible: true,
      activeIndex: 0,
      tabs: [
        EditorTab(
          filePath: filePath,
          content: diffHunks == null ? content : null,
          originalContent: diffHunks == null ? content : null,
          diffHunks: diffHunks,
        ),
      ],
    ),
  );
}

Widget _app(
  FileEditorCubit cubit, {
  bool immersive = false,
  VoidCallback? onToggleImmersive,
}) {
  return BlocProvider<FileEditorCubit>.value(
    value: cubit,
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: FileEditorPanel(
          immersive: immersive,
          onToggleImmersive: onToggleImmersive,
        ),
      ),
    ),
  );
}

Future<void> _pressCmd(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

CodeController _controller(WidgetTester tester) {
  return tester.widget<CodeField>(find.byType(CodeField)).controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Quick find ───────────────────────────────────────────────────────────
  group('FileEditorPanel — quick find', () {
    const content = 'alpha\nvortex\nbutton\nvoltage';

    Future<void> openQuickFind(WidgetTester tester) async {
      await tester.tap(find.byType(CodeField));
      await tester.pump();
      await _pressCmd(tester, LogicalKeyboardKey.keyJ);
    }

    testWidgets('Cmd+J opens hint and typing narrows matches', (tester) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await openQuickFind(tester);
      expect(find.byKey(const Key('editor-quick-find-hint')), findsOneWidget);
      expect(find.text('Search for: '), findsOneWidget);
      // Built-in search stays hidden in quick-find mode.
      expect(_controller(tester).searchController.shouldShow, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.pump();

      expect(find.text('Search for: vo  1/2'), findsOneWidget);
      expect(_controller(tester).fullSearchResult.matches.length, 2);
      expect(
        _controller(
          tester,
        ).searchController.navigationController.value.currentMatchIndex,
        0,
      );
      // Quick find never modifies the document.
      expect(_controller(tester).text, content);
      await cubit.close();
    });

    testWidgets('backspace edits the query', (tester) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await openQuickFind(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.pump();
      expect(find.text('Search for: vo  1/2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.text('Search for: v  1/2'), findsOneWidget);

      // Backspace past the empty query is a no-op.
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.text('Search for: '), findsOneWidget);
      await cubit.close();
    });

    testWidgets('no-match query shows an error status', (tester) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await openQuickFind(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ, character: 'z');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ, character: 'z');
      await tester.pump();

      expect(find.text('Search for: zz  no matches'), findsOneWidget);
      expect(_controller(tester).fullSearchResult.matches, isEmpty);
      await cubit.close();
    });

    testWidgets('arrow/enter keys cycle matches and escape selects current', (
      tester,
    ) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await openQuickFind(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.pump();
      expect(find.text('Search for: vo  1/2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Search for: vo  2/2'), findsOneWidget);

      // Wraps around to the first match.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Search for: vo  1/2'), findsOneWidget);

      // Arrow up wraps backwards.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.text('Search for: vo  2/2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(const Key('editor-quick-find-hint')), findsNothing);
      // Second 'vo' match ('voltage') spans [20, 22).
      expect(_controller(tester).selection.start, content.indexOf('voltage'));
      expect(_controller(tester).selection.end, content.indexOf('voltage') + 2);
      expect(_controller(tester).fullSearchResult.matches, isEmpty);
      await cubit.close();
    });

    testWidgets('arrow right closes with caret at match end', (tester) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await openQuickFind(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.pump();
      expect(find.text('Search for: vo  1/2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(find.byKey(const Key('editor-quick-find-hint')), findsNothing);
      expect(_controller(tester).selection.isCollapsed, isTrue);
      // First 'vo' match ('vortex') ends at index 8.
      expect(
        _controller(tester).selection.extentOffset,
        content.indexOf('vortex') + 2,
      );
      await cubit.close();
    });

    testWidgets('arrow left closes with caret at match start', (tester) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await openQuickFind(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(find.byKey(const Key('editor-quick-find-hint')), findsNothing);
      expect(_controller(tester).selection.isCollapsed, isTrue);
      expect(
        _controller(tester).selection.extentOffset,
        content.indexOf('vortex'),
      );
      await cubit.close();
    });
  });

  // ── Native search typeahead ───────────────────────────────────────────────
  group('FileEditorPanel — native search typeahead', () {
    const content = 'hello one\nhello two';

    testWidgets('Cmd+F opens search and typing routes into the pattern field', (
      tester,
    ) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byType(CodeField));
      await tester.pump();
      await _pressCmd(tester, LogicalKeyboardKey.keyF);

      expect(_controller(tester).searchController.shouldShow, isTrue);
      expect(
        find.byKey(const Key('editor-search-replace-bar')),
        findsOneWidget,
      );

      // showSearch() focuses the find input; move focus back into the code
      // editor so the panel's typeahead forwards keys into the pattern field.
      await tester.tap(find.byType(CodeField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
      await tester.pump();

      expect(
        _controller(
          tester,
        ).searchController.settingsController.patternController.text,
        'h',
      );
      // After forwarding a character the panel moves focus to the find
      // input, so subsequent keys are handled by the field itself and are
      // not double-forwarded by the panel typeahead.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE, character: 'e');
      await tester.pump();
      expect(
        _controller(
          tester,
        ).searchController.settingsController.patternController.text,
        'h',
      );
      // Document is untouched by search typeahead.
      expect(_controller(tester).text, content);
      await cubit.close();
    });

    testWidgets(
      'characters typed while find input is focused are not doubled',
      (tester) async {
        final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
        await tester.pumpWidget(_app(cubit));
        await tester.pump();

        await tester.tap(find.byType(CodeField));
        await tester.pump();
        await _pressCmd(tester, LogicalKeyboardKey.keyF);

        await tester.enterText(
          find.byKey(const Key('editor-find-input')),
          'ab',
        );
        await tester.pump();
        expect(
          _controller(
            tester,
          ).searchController.settingsController.patternController.text,
          'ab',
        );

        // The find field now has focus: raw key events must not be forwarded
        // again by the panel typeahead.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ, character: 'z');
        await tester.pump();
        expect(
          _controller(
            tester,
          ).searchController.settingsController.patternController.text,
          isNot('abz'),
        );
        await cubit.close();
      },
    );

    testWidgets('Cmd+H replace flow replaces one and all matches', (
      tester,
    ) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byType(CodeField));
      await tester.pump();
      await _pressCmd(tester, LogicalKeyboardKey.keyH);

      expect(find.byKey(const Key('editor-replace-input')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('editor-find-input')),
        'hello',
      );
      await tester.enterText(
        find.byKey(const Key('editor-replace-input')),
        'hi',
      );
      await tester.pump();
      expect(_controller(tester).fullSearchResult.matches.length, 2);

      await tester.tap(find.byKey(const Key('editor-replace-one')));
      await tester.pump();
      var text = _controller(tester).text;
      expect('hello'.allMatches(text).length, 1);
      expect('hi'.allMatches(text).length, 1);

      await tester.tap(find.byKey(const Key('editor-replace-all')));
      await tester.pump();
      text = _controller(tester).text;
      expect(text, 'hi one\nhi two');
      await cubit.close();
    });
  });

  // ── Auto-pairs ────────────────────────────────────────────────────────────
  group('FileEditorPanel — auto-pairs', () {
    testWidgets('typing an opening bracket inserts the closer', (tester) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: 'a');
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      final controller = _controller(tester);
      // First change only syncs the previous-value tracking.
      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
      );
      await tester.pump();

      controller.value = const TextEditingValue(
        text: 'ab(',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pump();

      expect(controller.text, 'ab()');
      expect(controller.selection.baseOffset, 3);
      await cubit.close();
    });

    testWidgets('typing a plain character inserts no closer', (tester) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: 'a');
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      final controller = _controller(tester);
      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
      );
      await tester.pump();

      controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pump();

      expect(controller.text, 'abc');
      await cubit.close();
    });
  });

  // ── Toolbar: go to line / outline / word wrap ─────────────────────────────
  group('FileEditorPanel — toolbar actions', () {
    testWidgets('go-to-line dialog jumps to the entered line', (tester) async {
      const content = 'one\ntwo\nthree';
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.last_page));
      await tester.pumpAndSettle();
      expect(find.text('Go to Line'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Go to Line'), findsNothing);
      expect(_controller(tester).selection.baseOffset, content.indexOf('two'));
      await cubit.close();
    });

    testWidgets('go-to-line ignores out-of-range input', (tester) async {
      const content = 'one\ntwo';
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.last_page));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Go to Line'), findsNothing);
      expect(_controller(tester).selection.baseOffset, isNot(99));
      await cubit.close();
    });

    testWidgets('tapping an outline symbol jumps to its line', (tester) async {
      const content = 'class Foo {}\nvoid helper() {}\n';
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pump();
      expect(find.text('Outline'), findsAtLeastNWidgets(1));
      expect(find.text('helper()'), findsOneWidget);

      await tester.tap(find.text('helper()'));
      await tester.pump();

      expect(
        _controller(tester).selection.baseOffset,
        content.indexOf('void helper'),
      );
      await cubit.close();
    });

    testWidgets('word wrap toggle flips the CodeField wrap flag', (
      tester,
    ) async {
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: 'class A {}');
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      expect(tester.widget<CodeField>(find.byType(CodeField)).wrap, isFalse);
      await tester.tap(find.byIcon(Icons.wrap_text));
      await tester.pump();
      expect(tester.widget<CodeField>(find.byType(CodeField)).wrap, isTrue);
      await cubit.close();
    });
  });

  // ── Format document ───────────────────────────────────────────────────────
  group('FileEditorPanel — format document', () {
    Future<ProcessResult> Function(String, List<String>) fakeRunner({
      int exitCode = 0,
      List<String>? invokedArgs,
      void Function(String path)? onInvoke,
    }) {
      return (String executable, List<String> arguments) async {
        invokedArgs?.addAll([executable, ...arguments]);
        final path = arguments.isEmpty ? '' : arguments.last;
        onInvoke?.call(path);
        return ProcessResult(0, exitCode, '', '');
      };
    }

    testWidgets('format is a no-op for non-dart files', (tester) async {
      final invoked = <String>[];
      formatDocumentProcessRunner = fakeRunner(invokedArgs: invoked);
      addTearDown(() => formatDocumentProcessRunner = Process.run);

      const content = 'just some text';
      final cubit = _cubitWith(filePath: '/ws/notes.txt', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pump();

      expect(_controller(tester).text, content);
      expect(invoked, isEmpty, reason: 'dart format must not run for .txt');
      await cubit.close();
    });

    testWidgets('format keeps content when dart format fails', (tester) async {
      // NOTE: async dart:io futures never complete inside testWidgets in this
      // environment (see the successful-format path, which needs readAsString
      // and is therefore not widget-testable) — all file setup here is sync.
      final dir = Directory.systemTemp.createTempSync('editor_format_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/broken.dart');
      const content = 'void main(){';
      file.writeAsStringSync(content);

      final invoked = <String>[];
      formatDocumentProcessRunner = fakeRunner(
        exitCode: 1,
        invokedArgs: invoked,
      );
      addTearDown(() => formatDocumentProcessRunner = Process.run);

      final cubit = _cubitWith(filePath: file.path, content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pump();
      await tester.pump();

      expect(invoked, ['dart', 'format', '--fix', file.path]);
      expect(_controller(tester).text, content);
      await cubit.close();
    });

    testWidgets('format swallows process spawn errors', (tester) async {
      formatDocumentProcessRunner =
          (String executable, List<String> arguments) =>
              throw const ProcessException('dart', ['format']);
      addTearDown(() => formatDocumentProcessRunner = Process.run);

      const content = 'void main() {}';
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: content);
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pump();
      await tester.pump();

      expect(_controller(tester).text, content);
      await cubit.close();
    });
  });

  // ── Immersive mode ────────────────────────────────────────────────────────
  group('FileEditorPanel — immersive mode', () {
    testWidgets('immersive panel shows exit button which fires the callback', (
      tester,
    ) async {
      var toggles = 0;
      final cubit = _cubitWith(filePath: '/ws/a.dart', content: 'class A {}');
      await tester.pumpWidget(
        _app(cubit, immersive: true, onToggleImmersive: () => toggles++),
      );
      await tester.pump();

      final exitBtn = find.byIcon(Icons.close_fullscreen_rounded);
      expect(exitBtn, findsOneWidget);
      await tester.tap(exitBtn);
      await tester.pump();
      expect(toggles, 1);
      await cubit.close();
    });
  });

  // ── Diff body ─────────────────────────────────────────────────────────────
  group('FileEditorPanel — diff body', () {
    testWidgets('renders hunk header and add/remove/context lines', (
      tester,
    ) async {
      final cubit = _cubitWith(
        filePath: 'diff:lib/main.dart',
        content: '',
        diffHunks: const [
          DiffHunk(
            header: '@@ -1,2 +1,2 @@',
            oldStart: 1,
            newStart: 1,
            lines: [
              DiffLine(
                type: DiffLineType.remove,
                content: 'old line',
                oldLineNum: 1,
              ),
              DiffLine(
                type: DiffLineType.add,
                content: 'new line',
                newLineNum: 1,
              ),
              DiffLine(
                type: DiffLineType.context,
                content: 'same line',
                oldLineNum: 2,
                newLineNum: 2,
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      expect(find.text('@@ -1,2 +1,2 @@'), findsOneWidget);
      expect(find.text('old line'), findsOneWidget);
      expect(find.text('new line'), findsOneWidget);
      expect(find.text('same line'), findsOneWidget);
      await cubit.close();
    });
  });

  // ── Tab context menu ──────────────────────────────────────────────────────
  group('FileEditorPanel — tab context menu', () {
    testWidgets('secondary tap opens menu and Close Others keeps one tab', (
      tester,
    ) async {
      final cubit = FileEditorCubit()
        ..emit(
          const FileEditorState(
            isVisible: true,
            activeIndex: 0,
            tabs: [
              EditorTab(
                filePath: '/ws/a.dart',
                content: 'class A {}',
                originalContent: 'class A {}',
              ),
              EditorTab(
                filePath: '/ws/b.dart',
                content: 'class B {}',
                originalContent: 'class B {}',
              ),
            ],
          ),
        );
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      await tester.tap(find.text('a.dart'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('✕ Close Others'), findsOneWidget);

      await tester.tap(find.text('✕ Close Others'));
      await tester.pumpAndSettle();

      expect(cubit.state.tabs.length, 1);
      expect(cubit.state.tabs.single.filePath, '/ws/a.dart');
      await cubit.close();
    });
  });

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  group('FileEditorPanel — lifecycle', () {
    testWidgets('app resume with dirty tab does not reload from disk', (
      tester,
    ) async {
      final cubit = FileEditorCubit()
        ..emit(
          const FileEditorState(
            isVisible: true,
            activeIndex: 0,
            tabs: [
              EditorTab(
                filePath: '/ws/a.dart',
                content: 'edited',
                originalContent: 'original',
              ),
            ],
          ),
        );
      await tester.pumpWidget(_app(cubit));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(cubit.state.activeTab!.content, 'edited');
      await cubit.close();
    });
  });
}
