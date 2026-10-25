import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/file_tree_card.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(300, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 400,
          child: child,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders per-extension file icons and folder icons', (
    tester,
  ) async {
    const entries = [
      TreeEntry(
        name: 'lib',
        path: '/project/lib',
        isDir: true,
        depth: 0,
        isExpanded: true,
      ),
      TreeEntry(
        name: 'src',
        path: '/project/src',
        isDir: true,
        depth: 0,
        isExpanded: false,
      ),
      TreeEntry(
        name: 'main.dart',
        path: '/project/lib/main.dart',
        isDir: false,
        depth: 1,
      ),
      TreeEntry(
        name: 'app.ts',
        path: '/project/lib/app.ts',
        isDir: false,
        depth: 1,
      ),
      TreeEntry(
        name: 'data.json',
        path: '/project/lib/data.json',
        isDir: false,
        depth: 1,
      ),
      TreeEntry(
        name: 'config.yaml',
        path: '/project/lib/config.yaml',
        isDir: false,
        depth: 1,
      ),
      TreeEntry(
        name: 'README.md',
        path: '/project/lib/README.md',
        isDir: false,
        depth: 1,
      ),
      TreeEntry(
        name: 'logo.png',
        path: '/project/lib/logo.png',
        isDir: false,
        depth: 1,
      ),
      TreeEntry(
        name: 'Makefile',
        path: '/project/lib/Makefile',
        isDir: false,
        depth: 1,
      ),
    ];

    await _pump(tester, const FileTreeCard(props: FileTreeCardProps(entries: entries)));

    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
    expect(find.byIcon(Icons.code), findsOneWidget);
    expect(find.byIcon(Icons.javascript), findsOneWidget);
    expect(find.byIcon(Icons.data_object), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.description), findsOneWidget);
    expect(find.byIcon(Icons.image), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });
}
