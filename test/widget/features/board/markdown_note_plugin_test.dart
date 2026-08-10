import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';

void main() {
  const plugin = MarkdownNotePlugin();

  test('metadata and initial state', () {
    expect(plugin.typeId, 'board.note.markdown');
    expect(plugin.hasEditor, isTrue);
    expect(plugin.showInCatalog, isFalse);
    expect(plugin.initialState['markdown'], '');
    expect(plugin.initialState['autoHeight'], isFalse);
    expect(plugin.initialState['autoScroll'], isFalse);
  });

  group('panel content', () {
    Future<GlobalKey<_NoteHostState>> pumpNote(
      WidgetTester tester,
      _NoteHarness harness,
    ) async {
      final key = GlobalKey<_NoteHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 220,
              child: _NoteHost(key: key, harness: harness),
            ),
          ),
        ),
      );
      await tester.pump();
      return key;
    }

    testWidgets('renders markdown and shows a hover copy button', (
      tester,
    ) async {
      // Clipboard.setData goes over a platform channel that never replies in
      // tests, so `_copyContent` would never reach its setState — stub it.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      final harness = _NoteHarness({'markdown': '# Hello'});
      await pumpNote(tester, harness);

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(SingleChildScrollView)));
      await tester.pump();

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(find.text('Copied'), findsOneWidget);

      // The copied state resets after a second.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('renders a placeholder for empty notes', (tester) async {
      await pumpNote(tester, _NoteHarness({'markdown': ''}));
      expect(find.text('Empty note'), findsOneWidget);
    });

    testWidgets('autoScroll jumps to the bottom when markdown changes', (
      tester,
    ) async {
      final tall = List.generate(30, (i) => '# H$i').join('\n');
      final harness = _NoteHarness({'markdown': tall, 'autoScroll': true});
      final key = await pumpNote(tester, harness);

      double offset() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      expect(offset(), 0);

      key.currentState!.updateState({
        ...harness.state,
        'markdown': '$tall\n# Extra',
      });
      // First pump rebuilds (didUpdateWidget schedules a post-frame scroll);
      // the post-frame callback runs on the next frame, then the 200ms
      // animation completes within the final pump.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(offset(), greaterThan(0));
    });

    testWidgets('autoHeight resizes the panel to fit rendered content', (
      tester,
    ) async {
      final harness = _NoteHarness({'markdown': '# Hello', 'autoHeight': true});
      final key = await pumpNote(tester, harness);
      await tester.pump();

      expect(harness.resizes, isNotEmpty);
      expect(harness.resizes.last.width, 360);
      expect(harness.resizes.last.height, lessThan(220));

      // Changing the markdown reschedules the resize (didUpdateWidget).
      final taller = List.generate(20, (i) => '# H$i').join('\n');
      key.currentState!.updateState({
        ...harness.state,
        'markdown': taller,
      });
      await tester.pump();
      await tester.pump();

      expect(harness.resizes.length, greaterThan(1));
      expect(harness.resizes.last.height, greaterThan(220));
    });
  });

  group('editor dialog', () {
    Future<TextEditingController> openEditor(
      WidgetTester tester,
      void Function(Map<String, dynamic>) onSave,
    ) async {
      const panel = BoardPanelInstance(
        id: 'note-1',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Note',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 360, height: 220),
        state: {'markdown': '', 'autoHeight': false, 'autoScroll': false},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () => plugin.showEditor(context, panel, onSave),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit markdown note'), findsOneWidget);
      return tester.widget<TextField>(find.byType(TextField).last).controller!;
    }

    testWidgets('toolbar inserts a placeholder when never focused', (
      tester,
    ) async {
      _useLargeSurface(tester);
      final controller = await openEditor(tester, (_) {});

      // The field was never focused, so the selection is invalid and the
      // placeholder is inserted at the end of the (empty) text.
      await tester.tap(find.byTooltip('Code block'));
      await tester.pump();
      expect(controller.text, '```\ncode\n```');
    });

    testWidgets('toolbar normalizes forward and reversed selections', (
      tester,
    ) async {
      _useLargeSurface(tester);
      Map<String, dynamic>? saved;
      final controller = await openEditor(tester, (state) => saved = state);

      final mdField = find.byType(TextField).last;
      await tester.enterText(mdField, 'hello');

      // Collapsed caret: wraps the placeholder.
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(controller.text, 'hello**bold**');

      // Forward selection wraps the selected text.
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.pump();
      await tester.tap(find.byTooltip('Italic'));
      await tester.pump();
      expect(controller.text, '*hello***bold**');

      // Reversed selection is normalized before the prefix is applied.
      controller.selection = const TextSelection(baseOffset: 5, extentOffset: 0);
      await tester.pump();
      await tester.tap(find.byTooltip('Bullet list'));
      await tester.pump();
      expect(controller.text, '- *hello***bold**');

      // Preview toggle renders the markdown instead of the field.
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['markdown'], '- *hello***bold**');
    });
  });
}

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _NoteHarness {
  _NoteHarness(this.state);

  Map<String, dynamic> state;
  final List<({double width, double height})> resizes = [];
}

class _NoteHost extends StatefulWidget {
  const _NoteHost({super.key, required this.harness});

  final _NoteHarness harness;

  @override
  State<_NoteHost> createState() => _NoteHostState();
}

class _NoteHostState extends State<_NoteHost> {
  void updateState(Map<String, dynamic> next) {
    setState(() => widget.harness.state = next);
  }

  @override
  Widget build(BuildContext context) {
    final panel = BoardPanelInstance(
      id: 'note-1',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Note',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 360, height: 220),
      state: widget.harness.state,
    );
    return const MarkdownNotePlugin().buildContent(
      context,
      panel,
      BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onShowEditor: () {},
        onUpdateState: updateState,
        onResize:
            (width, height) =>
                widget.harness.resizes.add((width: width, height: height)),
      ),
    );
  }
}
