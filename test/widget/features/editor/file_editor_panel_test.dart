import 'dart:io';

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

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build panel with pre-seeded state — no file I/O needed.
Widget _buildEditor(FileEditorState state) {
  return BlocProvider<FileEditorCubit>(
    create: (_) => FileEditorCubit()..emit(state),
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(body: FileEditorPanel()),
    ),
  );
}

/// A state with one open .dart file that has content already loaded.
FileEditorState _dartTab({
  String name = 'main.dart',
  String content = 'class Foo {}',
  bool isVisible = true,
}) => FileEditorState(
  isVisible: isVisible,
  activeIndex: 0,
  tabs: [
    EditorTab(
      filePath: '/workspace/$name',
      content: content,
      originalContent: content,
    ),
  ],
);

/// A state with two open tabs.
FileEditorState _twoTabs() => const FileEditorState(
  isVisible: true,
  activeIndex: 1,
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
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Hidden state ────────────────────────────────────────────────────────────
  group('FileEditorPanel — hidden state', () {
    testWidgets('renders panel widget when invisible', (tester) async {
      await tester.pumpWidget(
        _buildEditor(const FileEditorState(isVisible: false)),
      );
      await tester.pump();
      expect(find.byType(FileEditorPanel), findsOneWidget);
    });
  });

  // ── Tab bar ─────────────────────────────────────────────────────────────────
  group('FileEditorPanel — tab bar', () {
    testWidgets('shows file name in tab', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab(name: 'my_screen.dart')));
      await tester.pump();
      expect(find.text('my_screen.dart'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows both tab names when two files open', (tester) async {
      await tester.pumpWidget(_buildEditor(_twoTabs()));
      await tester.pump();
      expect(find.text('a.dart'), findsAtLeastNWidgets(1));
      expect(find.text('b.dart'), findsAtLeastNWidgets(1));
    });

    testWidgets('close button is present for each tab', (tester) async {
      await tester.pumpWidget(_buildEditor(_twoTabs()));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping close removes tab from cubit state', (tester) async {
      final cubit = FileEditorCubit()..emit(_twoTabs());
      await tester.pumpWidget(
        BlocProvider<FileEditorCubit>.value(
          value: cubit,
          child: MaterialApp(
            theme: AppThemePreset.neonPurple.theme,
            home: const Scaffold(body: FileEditorPanel()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(cubit.state.tabs.length, 1);
      cubit.close();
    });

    testWidgets('tapping inactive tab changes activeIndex', (tester) async {
      final cubit = FileEditorCubit()..emit(_twoTabs()); // active=1 (b.dart)
      await tester.pumpWidget(
        BlocProvider<FileEditorCubit>.value(
          value: cubit,
          child: MaterialApp(
            theme: AppThemePreset.neonPurple.theme,
            home: const Scaffold(body: FileEditorPanel()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('a.dart').first);
      await tester.pump();

      expect(cubit.state.activeIndex, 0);
      cubit.close();
    });

    testWidgets('dirty tab still shows file name', (tester) async {
      const state = FileEditorState(
        isVisible: true,
        tabs: [
          EditorTab(
            filePath: '/ws/dirty.dart',
            content: 'new',
            originalContent: 'old',
          ),
        ],
      );
      await tester.pumpWidget(_buildEditor(state));
      await tester.pump();
      expect(find.text('dirty.dart'), findsAtLeastNWidgets(1));
    });
  });

  // ── Toolbar ─────────────────────────────────────────────────────────────────
  group('FileEditorPanel — toolbar', () {
    testWidgets('shows search icon', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      expect(find.byIcon(Icons.search), findsAtLeastNWidgets(1));
    });

    testWidgets('shows word-wrap icon', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      expect(find.byIcon(Icons.wrap_text), findsAtLeastNWidgets(1));
    });

    testWidgets('shows outline toggle icon', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      expect(find.byIcon(Icons.account_tree_outlined), findsAtLeastNWidgets(1));
    });

    testWidgets('language label shows Dart for .dart file', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab(name: 'app.dart')));
      await tester.pump();
      expect(find.text('Dart'), findsAtLeastNWidgets(1));
    });

    testWidgets('language label shows YAML for .yaml file', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab(name: 'pubspec.yaml')));
      await tester.pump();
      expect(find.text('YAML'), findsAtLeastNWidgets(1));
    });

    testWidgets('language label shows ENV for dotenv files', (tester) async {
      await tester.pumpWidget(
        _buildEditor(
          _dartTab(name: '.env.local', content: 'OPENAI_API_KEY=test'),
        ),
      );
      await tester.pump();
      expect(find.text('ENV'), findsAtLeastNWidgets(1));
    });
  });

  // ── Find bar ────────────────────────────────────────────────────────────────
  group('FileEditorPanel — find bar', () {
    testWidgets('Find bar hidden by default', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      // Find hint text not present before opening
      expect(find.widgetWithText(TextField, 'Find'), findsNothing);
    });

    testWidgets('Find bar appears after tapping search icon', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();

      expect(find.text('Find'), findsAtLeastNWidgets(1));
    });

    testWidgets('Cmd+F opens the app find bar', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Find'), findsOneWidget);
    });

    testWidgets('Find bar selects the first match while typing', (
      tester,
    ) async {
      const content = 'alpha\nbeta target\nsecond target';
      await tester.pumpWidget(_buildEditor(_dartTab(content: content)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'target');
      await tester.pump();

      final codeField = tester.widget<CodeField>(find.byType(CodeField));
      expect(codeField.controller.selection.start, content.indexOf('target'));
      expect(codeField.controller.selection.end, content.indexOf('target') + 6);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('Find next moves the editor selection to the next match', (
      tester,
    ) async {
      const content = 'target\nmiddle\ntarget';
      await tester.pumpWidget(_buildEditor(_dartTab(content: content)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'target');
      await tester.pump();
      await tester.tap(find.byTooltip('Next  Enter'));
      await tester.pump();

      final codeField = tester.widget<CodeField>(find.byType(CodeField));
      expect(
        codeField.controller.selection.start,
        content.lastIndexOf('target'),
      );
      expect(find.text('2 / 2'), findsOneWidget);
    });

    testWidgets('Cmd+J opens quick find and arrow navigation works', (
      tester,
    ) async {
      const content = 'one apple\ntwo apple';
      await tester.pumpWidget(_buildEditor(_dartTab(content: content)));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(find.byKey(const Key('editor-quick-find-input')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('editor-quick-find-input')),
        'apple',
      );
      await tester.pump();
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      final codeField = tester.widget<CodeField>(find.byType(CodeField));
      expect(
        codeField.controller.selection.start,
        content.lastIndexOf('apple'),
      );
      expect(find.text('2 / 2'), findsOneWidget);
    });

    testWidgets('Find bar disappears after tapping close', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();

      // Open find
      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pump();

      // Close via X button
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump();

      expect(find.text('Find'), findsNothing);
    });
  });

  // ── Status bar ──────────────────────────────────────────────────────────────
  group('FileEditorPanel — status bar', () {
    testWidgets('shows UTF-8 label', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      expect(find.text('UTF-8'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows LF label', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      expect(find.text('LF'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows Ln / Col cursor position', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      expect(find.textContaining('Ln'), findsAtLeastNWidgets(1));
    });
  });

  // ── Outline panel ────────────────────────────────────────────────────────────
  group('FileEditorPanel — outline panel', () {
    testWidgets('Outline panel not visible by default', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();
      expect(find.text('Outline'), findsNothing);
    });

    testWidgets('Outline panel appears after tapping outline toggle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildEditor(_dartTab(content: 'class MyWidget {}')),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pump();

      expect(find.text('Outline'), findsAtLeastNWidgets(1));
    });

    testWidgets('Outline shows parsed class name', (tester) async {
      await tester.pumpWidget(
        _buildEditor(_dartTab(content: 'class FancyWidget {}')),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pump();

      expect(find.text('FancyWidget'), findsAtLeastNWidgets(1));
    });

    testWidgets('Outline hides after second tap of toggle', (tester) async {
      await tester.pumpWidget(_buildEditor(_dartTab()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pump();

      expect(find.text('Outline'), findsNothing);
    });
  });

  // ── Diff tab ─────────────────────────────────────────────────────────────────
  group('FileEditorPanel — diff tab', () {
    testWidgets('diff icon shown in tab for diff tab', (tester) async {
      final state = FileEditorState(
        isVisible: true,
        activeIndex: 0,
        tabs: [
          EditorTab(
            filePath: 'diff:lib/main.dart',
            diffHunks: const [],
            workspacePath: Directory.current.path,
          ),
        ],
      );
      await tester.pumpWidget(_buildEditor(state));
      await tester.pump();

      expect(find.byIcon(Icons.difference), findsAtLeastNWidgets(1));
    });

    testWidgets('diff tab shows main.dart (diff) in tab label', (tester) async {
      final state = FileEditorState(
        isVisible: true,
        activeIndex: 0,
        tabs: [
          EditorTab(
            filePath: 'diff:lib/main.dart',
            diffHunks: const [],
            workspacePath: Directory.current.path,
          ),
        ],
      );
      await tester.pumpWidget(_buildEditor(state));
      await tester.pump();

      expect(find.text('main.dart (diff)'), findsAtLeastNWidgets(1));
    });

    testWidgets('empty diff shows no hunks message', (tester) async {
      final state = FileEditorState(
        isVisible: true,
        activeIndex: 0,
        tabs: [
          EditorTab(
            filePath: 'diff:lib/main.dart',
            diffHunks: const [],
            workspacePath: Directory.current.path,
          ),
        ],
      );
      await tester.pumpWidget(_buildEditor(state));
      await tester.pump();

      expect(find.text('No diff available'), findsAtLeastNWidgets(1));
    });
  });

  // ── Loading / error states ────────────────────────────────────────────────
  group('FileEditorPanel — loading and error states', () {
    testWidgets('loading indicator shown while tab is loading', (tester) async {
      const state = FileEditorState(
        isVisible: true,
        tabs: [EditorTab(filePath: '/ws/loading.dart', isLoading: true)],
      );
      await tester.pumpWidget(_buildEditor(state));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    });

    testWidgets('error message shown when tab has error', (tester) async {
      const state = FileEditorState(
        isVisible: true,
        tabs: [EditorTab(filePath: '/ws/bad.dart', error: 'Cannot read file')],
      );
      await tester.pumpWidget(_buildEditor(state));
      await tester.pump();
      expect(find.textContaining('Cannot read file'), findsAtLeastNWidgets(1));
    });

    testWidgets('does not build a CodeField while content is still loading', (
      tester,
    ) async {
      final cubit =
          FileEditorCubit()..emit(
            const FileEditorState(
              isVisible: true,
              tabs: [EditorTab(filePath: '/ws/loading.dart', isLoading: true)],
            ),
          );
      addTearDown(cubit.close);

      await tester.pumpWidget(
        BlocProvider<FileEditorCubit>.value(
          value: cubit,
          child: MaterialApp(
            theme: AppThemePreset.neonPurple.theme,
            home: const Scaffold(body: FileEditorPanel()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
      expect(find.byType(CodeField), findsNothing);
    });

    testWidgets(
      'creates the CodeField with hydrated content after loading finishes',
      (tester) async {
        final cubit =
            FileEditorCubit()..emit(
              const FileEditorState(
                isVisible: true,
                tabs: [
                  EditorTab(
                    filePath: '/ws/analysis_options.yaml',
                    isLoading: true,
                  ),
                ],
              ),
            );
        addTearDown(cubit.close);

        await tester.pumpWidget(
          BlocProvider<FileEditorCubit>.value(
            value: cubit,
            child: MaterialApp(
              theme: AppThemePreset.neonPurple.theme,
              home: const Scaffold(body: FileEditorPanel()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        cubit.emit(
          const FileEditorState(
            isVisible: true,
            tabs: [
              EditorTab(
                filePath: '/ws/analysis_options.yaml',
                content: 'include: package:flutter_lints/flutter.yaml',
                originalContent: 'include: package:flutter_lints/flutter.yaml',
              ),
            ],
          ),
        );
        await tester.pump();

        final codeField = tester.widget<CodeField>(find.byType(CodeField));
        expect(
          codeField.controller.text,
          'include: package:flutter_lints/flutter.yaml',
        );
      },
    );
  });
}
