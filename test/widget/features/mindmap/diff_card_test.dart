import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/diff_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildCard({
    required DiffCardProps props,
    void Function(String filePath)? onFileTap,
  }) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [AppColorScheme.fromAccent(const Color(0xFF7C6BFF))],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            height: 500,
            child: DiffCard(props: props, onFileTap: onFileTap),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the empty state when nothing changed', (tester) async {
    await tester.pumpWidget(buildCard(props: const DiffCardProps()));

    expect(find.text('Git Changes · Diff'), findsOneWidget);
    expect(find.text('No changes'), findsOneWidget);
  });

  testWidgets('renders changed files with status labels and line counts', (
    tester,
  ) async {
    const props = DiffCardProps(
      repoName: 'yoloit',
      changedFiles: [
        ChangedFileEntry(
          path: 'lib/added.dart',
          name: 'added.dart',
          status: 'added',
          addedLines: 12,
        ),
        ChangedFileEntry(
          path: 'lib/gone.dart',
          name: 'gone.dart',
          status: 'deleted',
          removedLines: 7,
        ),
        ChangedFileEntry(
          path: 'lib/moved.dart',
          name: 'moved.dart',
          status: 'renamed',
        ),
        ChangedFileEntry(
          path: 'lib/new/nested/untracked.dart',
          name: '',
          status: 'untracked',
        ),
        ChangedFileEntry(
          path: 'lib/edited.dart',
          name: 'edited.dart',
          status: 'modified',
          addedLines: 3,
          removedLines: 2,
        ),
      ],
    );
    await tester.pumpWidget(buildCard(props: props));

    expect(find.text('Diff · yoloit'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    expect(find.text('U'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('-7'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('-2'), findsOneWidget);
    // Empty name falls back to the last path segment.
    expect(find.text('untracked.dart'), findsOneWidget);
  });

  testWidgets('renders diff hunks with add/remove/context lines', (
    tester,
  ) async {
    const props = DiffCardProps(
      hunks: [
        DiffHunk(
          header: '@@ -1,3 +1,4 @@',
          lines: [
            DiffLine(text: ' context line', type: 'context'),
            DiffLine(text: '-old line', type: 'remove'),
            DiffLine(text: '+new line', type: 'add'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(buildCard(props: props));

    expect(find.text('@@ -1,3 +1,4 @@'), findsOneWidget);
    expect(find.text(' context line'), findsOneWidget);
    expect(find.text('-old line'), findsOneWidget);
    expect(find.text('+new line'), findsOneWidget);
  });

  testWidgets('file taps forward the tapped path', (tester) async {
    final tapped = <String>[];
    const props = DiffCardProps(
      changedFiles: [
        ChangedFileEntry(
          path: 'lib/one.dart',
          name: 'one.dart',
          status: 'modified',
        ),
        ChangedFileEntry(
          path: 'lib/two.dart',
          name: 'two.dart',
          status: 'modified',
        ),
      ],
      selectedFilePath: 'lib/two.dart',
    );
    await tester.pumpWidget(buildCard(props: props, onFileTap: tapped.add));

    await tester.tap(find.text('one.dart'));
    await tester.pump();

    expect(tapped, ['lib/one.dart']);
  });
}
