import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/git_init_prompt.dart';

void main() {
  testWidgets('shows dialog for folder without git repo', (tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('git_prompt_test_');
    addTearDown(() {
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {
        // ignore cleanup errors
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: [AppColorScheme.fromAccent(const Color(0xFF7C3AED))],
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => maybePromptGitInit(context, tmpDir.path),
            child: const Text('Tap'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tap'));
    await tester.pumpAndSettle();

    expect(find.text('No Git Repository'), findsOneWidget);
    expect(find.textContaining('Initialize one here?'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('No Git Repository'), findsNothing);
    expect(Directory('${tmpDir.path}/.git').existsSync(), isFalse);
  });

  testWidgets('initializes git when user confirms', (tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('git_prompt_test_');
    addTearDown(() {
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {
        // ignore cleanup errors
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: [AppColorScheme.fromAccent(const Color(0xFF7C3AED))],
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => maybePromptGitInit(context, tmpDir.path),
            child: const Text('Tap'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tap'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Initialize Git'));
    await tester.pumpAndSettle();

    expect(find.text('No Git Repository'), findsNothing);
  });

  testWidgets('does not show dialog when git repo exists', (tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('git_prompt_test_');
    addTearDown(() {
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {
        // ignore cleanup errors
      }
    });
    Directory('${tmpDir.path}/.git').createSync();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: [AppColorScheme.fromAccent(const Color(0xFF7C3AED))],
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => maybePromptGitInit(context, tmpDir.path),
            child: const Text('Tap'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tap'));
    await tester.pumpAndSettle();

    expect(find.text('No Git Repository'), findsNothing);
  });
}
