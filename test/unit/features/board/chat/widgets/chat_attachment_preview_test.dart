import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/widgets/chat_attachment_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPreview(
    WidgetTester tester, {
    required List<String> paths,
    bool onLight = true,
    void Function(String path)? onOpenFile,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChatAttachmentPreview(
              paths: paths,
              onLight: onLight,
              onOpenFile: onOpenFile,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders a chip per file and forwards taps', (tester) async {
    final opened = <String>[];
    await pumpPreview(
      tester,
      paths: const <String>['docs/notes.txt', 'README.md'],
      onOpenFile: opened.add,
    );

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));

    await tester.tap(find.text('notes.txt'));
    await tester.pump();
    expect(opened, <String>['docs/notes.txt']);
  });

  testWidgets('labels clipboard capture files as clipboard', (tester) async {
    final opened = <String>[];
    await pumpPreview(
      tester,
      paths: const <String>['/tmp/yoloit_clip/clip_42.txt'],
      onOpenFile: opened.add,
    );

    expect(find.text('clipboard'), findsOneWidget);

    await tester.tap(find.text('clipboard'));
    await tester.pump();
    expect(opened, <String>['/tmp/yoloit_clip/clip_42.txt']);
  });

  testWidgets('renders chips on a dark bubble background', (tester) async {
    final opened = <String>[];
    await pumpPreview(
      tester,
      paths: const <String>['logs/trace.log'],
      onLight: false,
      onOpenFile: opened.add,
    );

    expect(find.text('trace.log'), findsOneWidget);

    await tester.tap(find.text('trace.log'));
    await tester.pump();
    expect(opened, <String>['logs/trace.log']);
  });

  testWidgets('renders nothing for an empty path list', (tester) async {
    await pumpPreview(tester, paths: const <String>[]);

    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
  });
}
