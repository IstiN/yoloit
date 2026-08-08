import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/file_preview_plugin.dart';

// 1x1 transparent PNG.
final Uint8List _kPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
  'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const String _kSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
    'height="10"><rect width="10" height="10" fill="red"/></svg>';

void main() {
  const plugin = FilePreviewPlugin();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yoloit_file_preview_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String writeTextFile(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file.path;
  }

  String writeByteFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  Finder textWidgetsContaining(String needle) {
    return find.byWidgetPredicate((widget) {
      if (widget is Text) {
        final plain = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return plain.contains(needle);
      }
      if (widget is SelectableText) {
        final plain = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return plain.contains(needle);
      }
      if (widget is RichText) {
        return widget.text.toPlainText().contains(needle);
      }
      return false;
    });
  }

  testWidgets('shows clear error for missing image path', (tester) async {
    final missingPath =
        '${Directory.systemTemp.path}/yoloit_missing_preview_image.png';

    await tester.pumpWidget(_previewHarness(plugin, missingPath));
    await tester.pump();

    expect(find.text('File not found'), findsOneWidget);
    expect(find.text(missingPath), findsOneWidget);
  });

  testWidgets('shows empty-state picker when no path is set', (tester) async {
    await tester.pumpWidget(_previewHarness(plugin, ''));
    await tester.pump();

    expect(find.text('No file selected'), findsOneWidget);
    expect(find.text('Pick File'), findsOneWidget);
    expect(find.byIcon(Icons.perm_media_outlined), findsOneWidget);
  });

  testWidgets('renders raster image bytes for png files', (tester) async {
    final path = writeByteFile('pixel.png', _kPngBytes);

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    // Small existing files are editable as text.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('pixel.png'), findsOneWidget);
  });

  testWidgets('shows decode error for corrupt image data', (tester) async {
    final path = writeByteFile('corrupt.png', [0, 1, 2, 3, 4, 5]);

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.text('Cannot decode image'), findsOneWidget);
    expect(find.text('Change file'), findsOneWidget);
  });

  testWidgets('refreshes image when its file is modified on the bus', (
    tester,
  ) async {
    final path = writeByteFile('watched.png', _kPngBytes);

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    // Unrelated path: ignored by the guard.
    BoardEventBus.instance.fileModified('${tempDir.path}/other.png');
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    // Matching path: bumps the refresh key and reloads the preview.
    BoardEventBus.instance.fileModified(path);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('renders svg files through SvgPicture', (tester) async {
    final path = writeTextFile('icon.svg', _kSvg);

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('shows broken-image icon for missing svg', (tester) async {
    final path = '${tempDir.path}/missing.svg';

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('pdf files show preview card and create linked web panel', (
    tester,
  ) async {
    final path = writeByteFile('report.pdf', [0x25, 0x50, 0x44, 0x46]);
    final linkedPanels = <List<Object?>>[];

    await tester.pumpWidget(
      _previewHarness(
        plugin,
        path,
        onCreateLinkedPanel: (typeId, state, title) async {
          linkedPanels.add([typeId, state, title]);
          return 'linked-1';
        },
      ),
    );
    await tester.pump();

    expect(find.text('report.pdf'), findsWidgets);
    expect(find.text('Preview PDF'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);

    await tester.tap(find.text('Preview PDF'));
    await tester.pump();

    expect(linkedPanels, hasLength(1));
    expect(linkedPanels.single[0], 'board.webpage');
    final state = linkedPanels.single[1] as Map<String, dynamic>;
    expect(state['url'] as String, startsWith('file://'));
    expect(state['title'], 'report.pdf');
    expect(linkedPanels.single[2], 'report.pdf');
  });

  testWidgets('html files offer open-as-webpage from the toolbar', (
    tester,
  ) async {
    final path = writeTextFile('page.html', '<html><body>hi</body></html>');
    final linkedPanels = <List<Object?>>[];

    await tester.pumpWidget(
      _previewHarness(
        plugin,
        path,
        onCreateLinkedPanel: (typeId, state, title) async {
          linkedPanels.add([typeId, state, title]);
          return 'linked-2';
        },
      ),
    );
    await tester.pump();

    // HTML is previewed as highlighted code.
    expect(textWidgetsContaining('<html>'), findsWidgets);

    await tester.tap(find.text('Web'));
    await tester.pump();

    expect(linkedPanels, hasLength(1));
    expect(linkedPanels.single[0], 'board.webpage');
    final state = linkedPanels.single[1] as Map<String, dynamic>;
    expect(state['url'] as String, startsWith('file://'));
    expect(state['title'], 'page.html');
  });

  testWidgets('unknown binary files fall back to open-in-editor card', (
    tester,
  ) async {
    final path = writeByteFile('firmware.bin', [0xDE, 0xAD, 0xBE, 0xEF]);

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(find.text('Open in Editor'), findsOneWidget);
    expect(find.text('firmware.bin'), findsWidgets);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  // Markdown previews spin up the shared MermaidRenderer, which creates a
  // flutter_js runtime with a periodic XHR poll timer. That timer must live
  // on the real event loop, so these tests run inside tester.runAsync.
  testWidgets('renders markdown file content', (tester) async {
    final path = writeTextFile(
      'notes.md',
      '# Title\n\nhello preview world\n',
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(_previewHarness(plugin, path));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump();

      expect(find.text('File not found'), findsNothing);
      expect(textWidgetsContaining('hello preview world'), findsWidgets);
    });
  });

  testWidgets('reloads markdown content on file-modified events', (
    tester,
  ) async {
    final path = writeTextFile('live.md', 'first markdown version\n');

    await tester.runAsync(() async {
      await tester.pumpWidget(_previewHarness(plugin, path));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump();
      expect(textWidgetsContaining('first markdown version'), findsWidgets);

      File(path).writeAsStringSync('second markdown version\n');
      BoardEventBus.instance.fileModified(path);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();

      expect(textWidgetsContaining('second markdown version'), findsWidgets);
    });
  });

  testWidgets('shows not-found for missing markdown file', (tester) async {
    final path = '${tempDir.path}/missing.md';

    await tester.runAsync(() async {
      await tester.pumpWidget(_previewHarness(plugin, path));
      await tester.pump();

      expect(find.text('File not found'), findsOneWidget);
    });
  });

  testWidgets('renders json code file with line numbers', (tester) async {
    final path = writeTextFile(
      'config.json',
      '{"name": "yolo", "active": true}\n{"count": 2}\n',
    );

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(textWidgetsContaining('"name"'), findsWidgets);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('treats dotenv files as editable text', (tester) async {
    final path = writeTextFile('.env', 'FOO=bar # local\n');

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(textWidgetsContaining('FOO'), findsWidgets);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('treats extensionless Makefile as text', (tester) async {
    final path = writeTextFile('Makefile', 'all:\n\techo hi\n');

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(textWidgetsContaining('echo hi'), findsWidgets);
  });

  testWidgets('warns when line count exceeds preview limit', (tester) async {
    final lines = List<String>.generate(5001, (i) => 'line $i');
    final path = writeTextFile('huge.txt', lines.join('\n'));

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(
      find.textContaining('Showing first 5000 of 5001 lines'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('truncates long lines with an ellipsis', (tester) async {
    final path = writeTextFile('longline.txt', 'x' * 2500);

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    // The over-long line is cut to 2000 chars and gets a trailing ellipsis.
    // (The info banner itself only shows for byte/line-count truncation.)
    expect(textWidgetsContaining('…'), findsWidgets);
  });

  testWidgets('warns when file bytes exceed preview limit', (tester) async {
    final bytes = Uint8List(2 * 1024 * 1024 + 100)
      ..fillRange(0, 2 * 1024 * 1024 + 100, 0x61);
    final path = writeByteFile('big.log', bytes);

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(find.textContaining('Showing first 2.0 MB'), findsOneWidget);
  });

  testWidgets('reloads code lines after debounced file-modified event', (
    tester,
  ) async {
    final path = writeTextFile('counter.txt', 'first content\n');

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();
    expect(textWidgetsContaining('first content'), findsWidgets);

    File(path).writeAsStringSync('second content\n');
    BoardEventBus.instance.fileModified(path);
    // Fire the 300ms debounce timer.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(textWidgetsContaining('second content'), findsWidgets);
  });

  testWidgets('shows not-found for missing code file', (tester) async {
    final path = '${tempDir.path}/missing_notes.txt';

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    expect(find.text('File not found'), findsOneWidget);
    // Text extensions stay editable even when the file does not exist yet.
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('missing file with unknown extension is not editable', (
    tester,
  ) async {
    final path = '${tempDir.path}/missing.xyz';

    await tester.pumpWidget(_previewHarness(plugin, path));
    await tester.pump();

    // Falls back to the generic file card without an edit action.
    expect(find.text('Open in Editor'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  test('highlights JSON keys, strings, numbers, booleans, and nulls', () {
    final colors = AppColorScheme.fromAccent(Colors.deepPurple);
    final spans = filePreviewCodeSyntaxSpans(
      '"name": "Teammate", "active": true, "score": 42, "meta": null',
      extension: 'json',
      colors: colors,
    );

    final styled = spans.where((span) => span.style?.color != null).toList();
    expect(
      styled.map((span) => span.text),
      containsAll(['"name"', '"Teammate"', 'true', '42', 'null']),
    );
    expect(
      styled.map((span) => span.style!.color).toSet().length,
      greaterThanOrEqualTo(4),
    );
  });

  test('highlights HTML/XML tags, attributes, and strings', () {
    final colors = AppColorScheme.fromAccent(Colors.deepPurple);
    final spans = filePreviewCodeSyntaxSpans(
      '<meta name="viewport" content="width=device-width">',
      extension: 'html',
      colors: colors,
    );

    final styled = spans.where((span) => span.style?.color != null).toList();
    expect(styled.map((span) => span.text), containsAll(['<meta', 'name']));
    expect(
      styled.map((span) => span.text),
      containsAll(['"viewport"', '"width=device-width"']),
    );
    expect(
      styled.map((span) => span.style!.color).toSet().length,
      greaterThanOrEqualTo(3),
    );
  });

  test('highlights dotenv keys, values, export, and comments', () {
    final colors = AppColorScheme.fromAccent(Colors.deepPurple);
    final spans = filePreviewCodeSyntaxSpans(
      'export OPENAI_API_KEY=test # local',
      extension: 'env',
      colors: colors,
    );

    final styled = spans.where((span) => span.style?.color != null).toList();
    expect(
      styled.map((span) => span.text),
      containsAll(['export ', 'OPENAI_API_KEY', 'test ', '# local']),
    );
    expect(
      styled.map((span) => span.style!.color).toSet().length,
      greaterThanOrEqualTo(4),
    );
  });
}

Widget _previewHarness(
  FilePreviewPlugin plugin,
  String path, {
  Future<String?> Function(String, Map<String, dynamic>, String)?
  onCreateLinkedPanel,
  ValueChanged<Map<String, dynamic>>? onUpdateState,
  bool isHeadlessPreview = false,
}) {
  final panel = BoardPanelInstance(
    id: 'preview',
    type: FilePreviewPlugin.kTypeId,
    title: 'Preview',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 480, height: 360),
    state: {'path': path, 'title': path.split(Platform.pathSeparator).last},
  );

  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 480,
        height: 360,
        child: Builder(
          builder:
              (context) => plugin.buildContent(
                context,
                panel,
                BoardPanelRenderContext(
                  isSelected: false,
                  onFocus: () {},
                  onDelete: () {},
                  onUpdateState: onUpdateState ?? (_) {},
                  onShowEditor: () {},
                  onCreateLinkedPanel: onCreateLinkedPanel,
                  isHeadlessPreview: isHeadlessPreview,
                ),
              ),
        ),
      ),
    ),
  );
}
