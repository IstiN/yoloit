import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/editor_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildCard({
    required EditorCardProps props,
    void Function(String content)? onContentUpdate,
    void Function(int tabIndex)? onSwitchTab,
  }) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [AppColorScheme.fromAccent(const Color(0xFF7C6BFF))],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 480,
            height: 360,
            child: EditorCard(
              props: props,
              onContentUpdate: onContentUpdate,
              onSwitchTab: onSwitchTab,
            ),
          ),
        ),
      ),
    );
  }

  const markdownProps = EditorCardProps(
    filePath: '/docs/notes.md',
    language: 'markdown',
    content: '# Title\n\nSome **bold** text',
  );

  testWidgets('renders the code body with line numbers by default', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(props: markdownProps));

    expect(find.text('notes.md'), findsOneWidget);
    expect(find.text('markdown'), findsOneWidget);
    expect(find.text('# Title'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('preview button toggles between markdown and code views', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(props: markdownProps));

    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.byType(Markdown), findsOneWidget);

    await tester.tap(find.text('Code'));
    await tester.pump();
    expect(find.byType(Markdown), findsNothing);
    expect(find.text('# Title'), findsOneWidget);
  });

  testWidgets('edit button opens the editor and save commits the content', (
    tester,
  ) async {
    final updates = <String>[];
    await tester.pumpWidget(
      buildCard(props: markdownProps, onContentUpdate: updates.add),
    );

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'edited body');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(updates, ['edited body']);
    expect(find.byType(TextField), findsNothing);
    // The parent owns the content; until it pushes new props the card shows
    // the original text again.
    expect(find.text('# Title'), findsOneWidget);
  });

  testWidgets('switching to preview while editing commits pending changes', (
    tester,
  ) async {
    final updates = <String>[];
    await tester.pumpWidget(
      buildCard(props: markdownProps, onContentUpdate: updates.add),
    );

    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '# Changed');

    await tester.tap(find.text('Preview'));
    await tester.pump();

    expect(updates, ['# Changed']);
    expect(find.byType(Markdown), findsOneWidget);
  });

  testWidgets('tab bar taps forward the tab index', (tester) async {
    final switched = <int>[];
    const props = EditorCardProps(
      filePath: '/repo/a.md',
      language: 'markdown',
      content: 'a',
      tabs: [
        TabInfo(path: '/repo/a.md', isActive: true),
        TabInfo(path: '/repo/b.md'),
      ],
    );
    await tester.pumpWidget(buildCard(props: props, onSwitchTab: switched.add));

    expect(find.text('a.md'), findsWidgets);
    await tester.tap(find.text('b.md'));
    await tester.pump();

    expect(switched, [1]);
  });

  testWidgets('updates the displayed content when props change', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(props: markdownProps));
    expect(find.text('# Title'), findsOneWidget);

    await tester.pumpWidget(
      buildCard(
        props: const EditorCardProps(
          filePath: '/docs/notes.md',
          language: 'markdown',
          content: 'fresh content',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('fresh content'), findsOneWidget);
  });
}
